import 'dart:async';

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:share_plus/share_plus.dart';

import 'data/post_db.dart';
import 'services/ai_key.dart';
import 'services/backup.dart';
import 'services/categorizer.dart';
import 'services/image_store.dart';
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
  await ImageStore.instance.init();
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
  Timer? _debounce;
  List<SavedPost> _results = [];
  Map<String, int> _counts = {};
  int _processing = 0;

  bool get _searching => _search.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _refresh();
    // Store pictures for posts saved before images were kept on the phone.
    ImageStore.instance.backfill(widget.db).then((n) {
      if (n > 0 && mounted) setState(() {});
    });
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
    _debounce?.cancel();
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

  /// Saves posts shared from another app, then hands the screen back to
  /// that app so saving doesn't interrupt scrolling.
  Future<void> _onShared(List<SharedMediaFile> files) async {
    final urls = [
      for (final f in files) extractUrl('${f.path} ${f.message ?? ''}'),
    ].whereType<String>().toList();
    if (urls.isEmpty) return;
    await Future.wait(urls.map(_savePost));
    // Leave the confirmation up long enough to read, then go back.
    await Future<void>.delayed(const Duration(milliseconds: 1300));
    if (mounted && ModalRoute.of(context)?.isCurrent == true) {
      await SystemNavigator.pop();
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
      final c = await categorize(
        text,
        apiKey: await resolveGroqKey(),
        categories: await widget.db.categories(),
      );
      final post = SavedPost(
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
      );
      await widget.db.insert(post);
      await ImageStore.instance.ensure(post, widget.db);
      _toast('Saved to ${c.category}');
    } finally {
      if (mounted) setState(() => _processing--);
      await _refresh();
    }
  }

  static const _exportAction = '\u0000export';
  static const _importAction = '\u0000import';

  Future<void> _export() async {
    try {
      final file = await exportBackup(widget.db);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], subject: 'PostVault backup'),
      );
    } catch (_) {
      _toast('Could not create the backup');
    }
  }

  Future<void> _import() async {
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      final path = picked.isEmpty ? null : picked.first.path;
      if (path == null) return;
      final added = await importBackup(widget.db, File(path));
      _toast(added == 0 ? 'Nothing new in that backup' : 'Added $added posts');
      await _refresh();
    } on FormatException {
      _toast('That file is not a PostVault backup');
    } catch (_) {
      _toast('Could not read that backup');
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
          SizedBox(height: c.s(20)),
          Text('BACKUP', style: Cream.label(c, size: 14, c: Cream.ink)),
          SizedBox(height: c.s(8)),
          Text(
            'Export saves all your posts and pictures to one file. Keep it '
            'somewhere off this phone, like Google Drive.',
            style: Cream.body(c, size: 14, c: Cream.muted),
          ),
          SizedBox(height: c.s(8)),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(c, _exportAction),
                  child: Text('Export', style: Cream.body(c, size: 15)),
                ),
              ),
              SizedBox(width: c.s(10)),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(c, _importAction),
                  child: Text('Import', style: Cream.body(c, size: 15)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (result == null) return;
    if (result == _exportAction) return _export();
    if (result == _importAction) return _import();
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
              hintText: 'Instagram, TikTok, YouTube or X link',
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
                        // Wait for a pause in typing before searching.
                        onChanged: (_) {
                          _debounce?.cancel();
                          _debounce = Timer(
                            const Duration(milliseconds: 220),
                            _refresh,
                          );
                        },
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
