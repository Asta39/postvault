import 'dart:async';

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../data/post_db.dart';
import 'cream.dart';
import 'post_detail.dart';
import 'post_tile.dart';

/// A list of posts with its own search bar: one collection when [category]
/// is given, otherwise every save (used when a tag is tapped).
class CategoryPage extends StatefulWidget {
  const CategoryPage({
    super.key,
    required this.db,
    this.category,
    this.initialQuery = '',
  });
  final PostDb db;
  final String? category;
  final String initialQuery;

  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<CategoryPage> {
  late final _search = TextEditingController(text: widget.initialQuery);
  late String? _category = widget.category;
  List<SavedPost> _posts = [];
  bool _oldestFirst = false;
  Timer? _debounce;

  bool get _searching => _search.text.trim().isNotEmpty;
  String get _name => _category ?? 'All saves';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final posts = await widget.db.search(
      query: _search.text,
      category: _category,
      oldestFirst: _oldestFirst,
    );
    if (mounted) setState(() => _posts = posts);
  }

  /// Waits for a pause in typing before searching.
  void _onQuery(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), _load);
  }

  Future<void> _open(SavedPost p) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PostDetailPage(db: widget.db, post: p),
      ),
    );
    _load();
  }

  Future<void> _rename() async {
    final from = _category;
    if (from == null) return;
    final to = (await showCreamInput(
      context,
      title: 'Rename collection',
      action: 'Rename',
      initial: from,
    ))?.trim();
    if (to == null || to.isEmpty || to == from) return;
    await widget.db.renameCollection(from, to);
    if (!mounted) return;
    setState(() => _category = to);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final g = context.gutter;
    return Material(
      type: MaterialType.transparency,
      child: GlassScaffold(
        // Edge fades re-blur the content every scroll frame; skip them.
        edgeFade: false,
        background: const CreamBackground(alignment: Alignment(-0.3, -0.6)),
        body: Stack(
          children: [
            CustomScrollView(
              slivers: [
                SliverSafeArea(
                  bottom: false,
                  sliver: SliverPadding(
                    padding: EdgeInsets.fromLTRB(g, context.s(8), g, 0),
                    sliver: SliverList.list(
                      children: [
                        Row(
                          children: [
                            GlassIcon(
                              icon: Icons.chevron_left,
                              label: 'Back',
                              onTap: () => Navigator.pop(context),
                            ),
                            const Spacer(),
                            GlassIcon(
                              icon: _oldestFirst
                                  ? Icons.arrow_upward
                                  : Icons.arrow_downward,
                              label: _oldestFirst
                                  ? 'Showing oldest first'
                                  : 'Showing newest first',
                              onTap: () {
                                setState(() => _oldestFirst = !_oldestFirst);
                                _load();
                              },
                            ),
                            if (_category != null) ...[
                              SizedBox(width: context.s(8)),
                              GlassIcon(
                                icon: Icons.edit_outlined,
                                label: 'Rename collection',
                                onTap: _rename,
                              ),
                            ],
                          ],
                        ),
                        SizedBox(height: context.s(28)),
                        Text(
                          _searching
                              ? 'RESULTS IN ${_name.toUpperCase()}'
                              : _name.toUpperCase(),
                          style: Cream.label(context, size: 13),
                        ),
                        SizedBox(height: context.s(6)),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${_posts.length}',
                              style: Cream.display(context),
                            ),
                            const Spacer(),
                            Padding(
                              padding: EdgeInsets.only(bottom: context.s(8)),
                              child: Text(
                                _oldestFirst ? 'OLDEST FIRST' : 'NEWEST FIRST',
                                style: Cream.label(context, size: 11),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: context.s(28)),
                      ],
                    ),
                  ),
                ),
                if (_posts.isEmpty && _searching)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(context.s(32)),
                      child: Text(
                        'Nothing in $_name matches that search.',
                        textAlign: TextAlign.center,
                        style: Cream.body(context, c: Cream.muted),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    // Room at the bottom so the last row clears the search bar.
                    padding: EdgeInsets.fromLTRB(g, 0, g, context.s(120)),
                    sliver: PostGrid(posts: _posts, onTap: _open),
                  ),
              ],
            ),
            Positioned(
              left: g,
              right: g,
              bottom: context.s(16),
              child: SafeArea(
                top: false,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: GlassSearchBar(
                      controller: _search,
                      settings: Cream.bar,
                      placeholder: 'Search in $_name',
                      height: context.s(58),
                      textStyle: Cream.body(context, size: 16),
                      placeholderStyle: Cream.body(
                        context,
                        size: 16,
                        c: Cream.muted,
                      ),
                      searchIconColor: Cream.ink,
                      onChanged: _onQuery,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
