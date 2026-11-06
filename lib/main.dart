import 'dart:async';

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'data/post_db.dart';
import 'services/ai_key.dart';
import 'services/categorizer.dart';
import 'services/metadata.dart';
import 'ui/category_page.dart';
import 'ui/cream.dart';
import 'ui/post_detail.dart';
import 'ui/post_tile.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LiquidGlassWidgets.initialize(enablePerformanceMonitor: false);
  if (const bool.fromEnvironment('PERF_LOG')) _logFrames();
  final db = await PostDb.open();
  runApp(
    LiquidGlassWidgets.wrap(
      child: PostVaultApp(db: db),
      brightnessResolver: Theme.maybeBrightnessOf,
      // Drops glass quality automatically if the phone can't keep 60fps.
      adaptiveQuality: true,
    ),
  );
}

class PostVaultApp extends StatelessWidget {
  const PostVaultApp({super.key, required this.db});
  final PostDb db;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'PostVault',
    debugShowCheckedModeBanner: false,
    themeMode: ThemeMode.light,
    theme: ThemeData(
      colorSchemeSeed: Cream.glow,
      scaffoldBackgroundColor: Cream.bg,
      useMaterial3: true,
    ),
    home: HomePage(db: db),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.db});
  final PostDb db;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _search = TextEditingController();
  StreamSubscription<List<SharedMediaFile>>? _shareSub;
  List<SavedPost> _results = [];
  Map<String, int> _counts = {};
  int _processing = 0;

  bool get _searching => _search.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _refresh();
    _shareSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      _onShared,
    );
    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      _onShared(files);
      ReceiveSharingIntent.instance.reset();
    });
  }

  @override
  void dispose() {
    _shareSub?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final counts = await widget.db.categoryCounts();
    final results = _searching
        ? await widget.db.search(query: _search.text)
        : <SavedPost>[];
    if (!mounted) return;
    setState(() {
      _counts = counts;
      _results = results;
    });
  }

  void _onShared(List<SharedMediaFile> files) {
    for (final f in files) {
      final url = extractUrl('${f.path} ${f.message ?? ''}');
      if (url != null) _savePost(url);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: Cream.body(context, size: 14, c: Cream.bg)),
        backgroundColor: Cream.ink,
        behavior: SnackBarBehavior.floating,
        shape: const StadiumBorder(),
        margin: EdgeInsets.fromLTRB(
          context.gutter,
          0,
          context.gutter,
          context.s(100),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _savePost(String rawUrl) async {
    final url = normaliseUrl(rawUrl);
    if (await widget.db.exists(url)) {
      _toast('Already saved');
      return;
    }
    setState(() => _processing++);
    try {
      final meta = await fetchMetadata(url);
      final text = [meta.author, meta.caption].whereType<String>().join('\n');
      final c = await categorize(text, apiKey: await resolveGroqKey());
      await widget.db.insert(
        SavedPost(
          url: url,
          author: meta.author,
          caption: meta.caption,
          imageUrl: meta.imageUrl,
          category: c.category,
          tags: c.tags,
          summary: c.summary,
          description: c.description,
          links: c.links,
          savedAt: DateTime.now(),
        ),
      );
      _toast('Saved to ${c.category}');
    } finally {
      if (mounted) setState(() => _processing--);
      await _refresh();
    }
  }

  Future<void> _openSettings() async {
    final hasOwn = await hasUserGroqKey();
    if (!mounted) return;
    final ctrl = TextEditingController();
    final status = hasOwn
        ? 'Using your own Groq key.'
        : builtInGroqKey.isNotEmpty
        ? 'Using the built-in Groq key.'
        : 'No AI key yet: posts are sorted by keywords only.';
    final result = await showCreamSheet<String>(
      context,
      title: 'AI sorting',
      builder: (c) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(status, style: Cream.body(c, w: FontWeight.w600)),
          SizedBox(height: c.s(8)),
          Text(
            'Paste a free Groq API key from console.groq.com to get smart '
            'categories, descriptions and links. It stays on this phone.',
            style: Cream.body(c, size: 14, c: Cream.muted),
          ),
          SizedBox(height: c.s(16)),
          TextField(
            controller: ctrl,
            obscureText: true,
            style: Cream.body(c, size: 16),
            decoration: InputDecoration(
              hintText: hasOwn ? 'Paste a new key to replace it' : 'gsk_…',
              hintStyle: Cream.body(c, size: 16, c: Cream.muted),
              filled: true,
              fillColor: const Color(0x80FFFFFF),
              contentPadding: EdgeInsets.symmetric(
                horizontal: c.s(18),
                vertical: c.s(18),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(c.s(20)),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          SizedBox(height: c.s(16)),
          InkPill(label: 'Save key', onTap: () => Navigator.pop(c, ctrl.text)),
          if (hasOwn) ...[
            SizedBox(height: c.s(8)),
            TextButton(
              onPressed: () => Navigator.pop(c, ''),
              child: Text(
                'Remove my key',
                style: Cream.body(c, size: 14, c: Cream.muted),
              ),
            ),
          ],
        ],
      ),
    );
    if (result == null) return;
    if (result.trim().isEmpty && !hasOwn) return;
    await setUserGroqKey(result);
    _toast(result.trim().isEmpty ? 'Key removed' : 'Key saved');
  }

  Future<void> _addManually() async {
    final ctrl = TextEditingController();
    final text = await showCreamSheet<String>(
      context,
      title: 'Add a post link',
      builder: (c) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: ctrl,
            autofocus: true,
            style: Cream.body(c, size: 16),
            decoration: InputDecoration(
              hintText: 'https://www.instagram.com/p/…',
              hintStyle: Cream.body(c, size: 16, c: Cream.muted),
              filled: true,
              fillColor: const Color(0x80FFFFFF),
              contentPadding: EdgeInsets.symmetric(
                horizontal: c.s(18),
                vertical: c.s(18),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(c.s(20)),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          SizedBox(height: c.s(16)),
          InkPill(label: 'Save', onTap: () => Navigator.pop(c, ctrl.text)),
        ],
      ),
    );
    final url = text == null ? null : extractUrl(text);
    if (url != null) _savePost(url);
  }

  Future<void> _push(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final g = context.gutter;
    final total = _counts.values.fold(0, (a, b) => a + b);
    return Material(
      type: MaterialType.transparency,
      child: GlassScaffold(
        // Edge fades re-blur the content every scroll frame; skip them.
        edgeFade: false,
        background: const CreamBackground(),
        body: Stack(
          children: [
            CustomScrollView(
              slivers: [
                SliverSafeArea(
                  bottom: false,
                  sliver: SliverPadding(
                    padding: EdgeInsets.fromLTRB(g, context.s(14), g, 0),
                    sliver: SliverList.list(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'POSTVAULT',
                                style: Cream.label(
                                  context,
                                  size: 15,
                                  c: Cream.ink,
                                ),
                              ),
                            ),
                            GlassIcon(
                              icon: Icons.tune,
                              label: 'AI settings',
                              onTap: _openSettings,
                            ),
                          ],
                        ),
                        SizedBox(height: context.s(36)),
                        Text(
                          _searching ? 'RESULTS' : 'SAVED POSTS',
                          style: Cream.label(context),
                        ),
                        SizedBox(height: context.s(6)),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${_searching ? _results.length : total}',
                              style: Cream.display(context),
                            ),
                            const Spacer(),
                            if (_processing > 0)
                              Padding(
                                padding: EdgeInsets.only(bottom: context.s(8)),
                                child: Text(
                                  'SORTING…',
                                  style: Cream.label(context, size: 11),
                                ),
                              ),
                          ],
                        ),
                        SizedBox(
                          height: _searching
                              ? context.s(28)
                              : MediaQuery.sizeOf(context).height * 0.14,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_searching)
                  _results.isEmpty
                      ? SliverToBoxAdapter(
                          child: _message('Nothing matches that search.'),
                        )
                      : SliverPadding(
                          padding: EdgeInsets.fromLTRB(g, 0, g, context.s(120)),
                          sliver: PostGrid(
                            posts: _results,
                            onTap: (p) =>
                                _push(PostDetailPage(db: widget.db, post: p)),
                          ),
                        )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(g, 0, g, context.s(120)),
                    sliver: SliverToBoxAdapter(
                      child: _counts.isEmpty
                          ? _message(
                              'In Instagram tap Share, then PostVault, on any post. '
                              'Or tap + to paste a link.',
                            )
                          : _collections(),
                    ),
                  ),
              ],
            ),
            Positioned(
              left: g,
              right: g,
              bottom: context.s(16),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    Expanded(
                      child: GlassSearchBar(
                        controller: _search,
                        settings: Cream.bar,
                        placeholder: 'Search your saves',
                        height: context.s(58),
                        textStyle: Cream.body(context, size: 16),
                        placeholderStyle: Cream.body(
                          context,
                          size: 16,
                          c: Cream.muted,
                        ),
                        searchIconColor: Cream.ink,
                        onChanged: (_) => _refresh(),
                      ),
                    ),
                    SizedBox(width: context.s(10)),
                    SizedBox(
                      width: context.s(58),
                      height: context.s(58),
                      child: FloatingActionButton(
                        heroTag: 'add',
                        elevation: 4,
                        backgroundColor: Cream.ink,
                        foregroundColor: Cream.bg,
                        shape: const CircleBorder(),
                        tooltip: 'Add a post link',
                        onPressed: _addManually,
                        child: Icon(Icons.add, size: context.s(26)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _message(String text) => Padding(
    padding: EdgeInsets.symmetric(
      horizontal: context.s(32),
      vertical: context.s(24),
    ),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: Cream.body(context, c: Cream.muted),
    ),
  );

  Widget _collections() {
    final entries = _counts.entries.toList();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: GlassContainer(
          settings: Cream.panel,
          shape: LiquidRoundedSuperellipse(borderRadius: context.s(36)),
          padding: EdgeInsets.fromLTRB(
            context.s(24),
            context.s(22),
            context.s(24),
            context.s(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'COLLECTIONS',
                style: Cream.label(context, size: 13, c: Cream.ink),
              ),
              SizedBox(height: context.s(8)),
              for (var i = 0; i < entries.length; i++)
                InkWell(
                  onTap: () => _push(
                    CategoryPage(db: widget.db, category: entries[i].key),
                  ),
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: context.s(16)),
                    decoration: BoxDecoration(
                      border: i == entries.length - 1
                          ? null
                          : const Border(bottom: BorderSide(color: Cream.line)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            entries[i].key,
                            style: Cream.body(context, size: 18),
                          ),
                        ),
                        Text(
                          '${entries[i].value}',
                          style:
                              Cream.body(
                                context,
                                size: 18,
                                w: FontWeight.w300,
                              ).copyWith(
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                        ),
                        SizedBox(width: context.s(10)),
                        Icon(
                          Icons.chevron_right,
                          size: context.s(20),
                          color: Cream.muted,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Build with --dart-define=PERF_LOG=true to print frame-time stats to logcat.
void _logFrames() {
  final build = <int>[], raster = <int>[];
  WidgetsBinding.instance.addTimingsCallback((timings) {
    for (final t in timings) {
      build.add(t.buildDuration.inMicroseconds);
      raster.add(t.rasterDuration.inMicroseconds);
    }
    if (build.length < 120) return;
    String stat(List<int> v) {
      v.sort();
      final p90 = v[(v.length * .9).floor()] / 1000;
      final slow = v.where((x) => x > 16600).length;
      return 'p90=${p90.toStringAsFixed(1)}ms slow=$slow/${v.length}';
    }

    // ignore: avoid_print
    print('PERF build ${stat(build)} | raster ${stat(raster)}');
    build.clear();
    raster.clear();
  });
}
