import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../data/post_db.dart';
import 'cream.dart';
import 'post_detail.dart';
import 'post_tile.dart';

/// One collection: every post saved in [category].
class CategoryPage extends StatefulWidget {
  const CategoryPage({super.key, required this.db, required this.category});
  final PostDb db;
  final String category;

  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<CategoryPage> {
  final _search = TextEditingController();
  List<SavedPost> _posts = [];

  bool get _searching => _search.text.trim().isNotEmpty;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final posts = await widget.db.search(
      query: _search.text,
      category: widget.category,
    );
    if (mounted) setState(() => _posts = posts);
  }

  Future<void> _open(SavedPost p) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PostDetailPage(db: widget.db, post: p),
      ),
    );
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
                          ],
                        ),
                        SizedBox(height: context.s(28)),
                        Text(
                          _searching
                              ? 'RESULTS IN ${widget.category.toUpperCase()}'
                              : widget.category.toUpperCase(),
                          style: Cream.label(context, size: 13),
                        ),
                        SizedBox(height: context.s(6)),
                        Text('${_posts.length}', style: Cream.display(context)),
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
                        'Nothing in ${widget.category} matches that search.',
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
                      placeholder: 'Search in ${widget.category}',
                      height: context.s(58),
                      textStyle: Cream.body(context, size: 16),
                      placeholderStyle: Cream.body(
                        context,
                        size: 16,
                        c: Cream.muted,
                      ),
                      searchIconColor: Cream.ink,
                      onChanged: (_) => _load(),
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
