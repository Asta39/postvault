import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/post_db.dart';
import '../services/ai_key.dart';
import '../services/categorizer.dart';
import '../services/image_store.dart';
import '../services/metadata.dart';
import 'category_page.dart';
import 'cream.dart';
import 'post_tile.dart';

/// Turns a mentioned link, domain, @handle or product name into a URL.
Uri linkTarget(String link) {
  if (link.startsWith('http')) return Uri.parse(link);
  if (link.startsWith('@')) {
    return Uri.parse('https://www.instagram.com/${link.substring(1)}/');
  }
  if (RegExp(r'^[\w-]+(\.[\w-]+)+(/\S*)?$').hasMatch(link)) {
    return Uri.parse('https://$link');
  }
  return Uri.https('www.google.com', '/search', {'q': link});
}

class PostDetailPage extends StatefulWidget {
  const PostDetailPage({super.key, required this.db, required this.post});
  final PostDb db;
  final SavedPost post;

  @override
  State<PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends State<PostDetailPage> {
  late SavedPost post = widget.post;
  bool _describing = false;
  bool _reanalysing = false;

  @override
  void initState() {
    super.initState();
    if ((post.description ?? '').isEmpty) _describe();
  }

  /// Posts saved before descriptions existed get one the first time they open.
  Future<void> _describe() async {
    final text = [post.author, post.caption].whereType<String>().join('\n');
    if (text.trim().isEmpty) return;
    setState(() => _describing = true);
    final c = await categorize(
      text,
      apiKey: await resolveGroqKey(),
      categories: await widget.db.categories(),
    );
    final updated = post.copyWith(
      description: c.description.isNotEmpty ? c.description : c.summary,
      links: c.links,
    );
    await widget.db.update(updated);
    if (mounted) {
      setState(() {
        post = updated;
        _describing = false;
      });
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

  /// Fetches the post again and redoes the AI work. Keeps the collection
  /// unless the post was never sorted, and keeps the user's note.
  Future<void> _reanalyse() async {
    if (_reanalysing) return;
    setState(() => _reanalysing = true);
    try {
      final meta = await fetchMetadata(post.url);
      final author = meta.author ?? post.author;
      final caption = meta.caption ?? post.caption;
      final text = [author, caption].whereType<String>().join('\n');
      if (text.trim().isEmpty) {
        _toast('Could not read this post right now');
        return;
      }
      final c = await categorize(
        text,
        apiKey: await resolveGroqKey(),
        categories: await widget.db.categories(),
      );
      final updated = post.copyWith(
        author: author,
        caption: caption,
        imageUrl: meta.imageUrl,
        category: post.category == 'Other' ? c.category : null,
        tags: c.tags.isEmpty ? null : c.tags,
        summary: c.summary.isEmpty ? null : c.summary,
        description: c.description.isEmpty ? null : c.description,
        links: c.links.isEmpty ? null : c.links,
      );
      await widget.db.update(updated);
      await ImageStore.instance.ensure(updated, widget.db);
      if (mounted) setState(() => post = updated);
      _toast('Post refreshed');
    } finally {
      if (mounted) setState(() => _reanalysing = false);
    }
  }

  Future<void> _editNote() async {
    final text = await showCreamInput(
      context,
      title: 'Your note',
      action: 'Save note',
      hint: 'Why you saved this, what to try…',
      initial: post.note ?? '',
      maxLines: 5,
    );
    if (text == null) return;
    final updated = post.copyWith(note: text.trim());
    await widget.db.update(updated);
    if (mounted) setState(() => post = updated);
  }

  static const _newCollection = '\u0000new';

  Future<void> _move() async {
    final all = await widget.db.categories();
    if (!mounted) return;
    var cat = await showCreamSheet<String>(
      context,
      title: 'Move to',
      builder: (c) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(c).height * 0.6,
        ),
        child: ListView(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          children: [
            InkWell(
              onTap: () => Navigator.pop(c, _newCollection),
              child: Container(
                padding: EdgeInsets.symmetric(vertical: c.s(15)),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Cream.line)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.add, color: Cream.ink, size: c.s(20)),
                    SizedBox(width: c.s(10)),
                    Text(
                      'New collection',
                      style: Cream.body(c, size: 17, w: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
            for (final cat in all)
              InkWell(
                onTap: () => Navigator.pop(c, cat),
                child: Container(
                  padding: EdgeInsets.symmetric(vertical: c.s(15)),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: Cream.line)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          cat,
                          style: Cream.body(
                            c,
                            size: 17,
                            w: cat == post.category
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (cat == post.category)
                        Icon(Icons.check, color: Cream.ink, size: c.s(20)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (cat == null || !mounted) return;
    if (cat == _newCollection) {
      final name = (await showCreamInput(
        context,
        title: 'New collection',
        action: 'Create and move',
        hint: 'Collection name',
      ))?.trim();
      if (name == null || name.isEmpty) return;
      await widget.db.addCollection(name);
      cat = name;
    }
    final updated = post.copyWith(category: cat);
    await widget.db.update(updated);
    setState(() => post = updated);
  }

  Future<void> _delete() async {
    final ok = await showCreamSheet<bool>(
      context,
      title: 'Delete this post?',
      builder: (c) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'It is removed from PostVault only, not from Instagram.',
            style: Cream.body(c, c: Cream.muted),
          ),
          SizedBox(height: c.s(20)),
          InkPill(label: 'Delete', onTap: () => Navigator.pop(c, true)),
        ],
      ),
    );
    if (ok != true) return;
    await widget.db.delete(post.id!);
    await ImageStore.instance.remove(post.url);
    if (mounted) Navigator.pop(context);
  }

  Widget _section(String title, Widget child) => Frost(
    padding: EdgeInsets.all(context.s(20)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Cream.label(context, size: 12, c: Cream.ink)),
        SizedBox(height: context.s(12)),
        child,
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final g = context.gutter;
    final title = post.summary?.isNotEmpty == true
        ? post.summary!
        : (post.caption ?? 'Saved post');
    final maxW = 640.0;
    return Material(
      type: MaterialType.transparency,
      child: GlassScaffold(
        // Edge fades re-blur the content every scroll frame; skip them.
        edgeFade: false,
        background: const CreamBackground(alignment: Alignment(0, -0.5)),
        body: Stack(
          children: [
            CustomScrollView(
              slivers: [
                SliverSafeArea(
                  sliver: SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      g,
                      context.s(8),
                      g,
                      context.s(110),
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: maxW),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  GlassIcon(
                                    icon: Icons.chevron_left,
                                    label: 'Back',
                                    onTap: () => Navigator.pop(context),
                                  ),
                                  Expanded(
                                    child: Text(
                                      post.category.toUpperCase(),
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Cream.label(context, c: Cream.ink),
                                    ),
                                  ),
                                  GlassIcon(
                                    icon: _reanalysing
                                        ? Icons.hourglass_empty
                                        : Icons.refresh,
                                    label: 'Refresh this post',
                                    onTap: _reanalyse,
                                  ),
                                  SizedBox(width: context.s(8)),
                                  GlassIcon(
                                    icon: Icons.delete_outline,
                                    label: 'Delete',
                                    onTap: _delete,
                                  ),
                                ],
                              ),
                              SizedBox(height: context.s(16)),
                              AspectRatio(
                                aspectRatio: 4 / 5,
                                child: ClipRSuperellipse(
                                  borderRadius: BorderRadius.circular(
                                    context.s(36),
                                  ),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Container(color: const Color(0xFFEFE6C8)),
                                      PostImage(post: post, cacheWidth: 1080),
                                      Positioned(
                                        left: context.s(14),
                                        right: context.s(14),
                                        bottom: context.s(14),
                                        child: Frost(
                                          radius: 26,
                                          color: const Color(0xD9F6F1E4),
                                          padding: EdgeInsets.all(
                                            context.s(18),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                title.toUpperCase(),
                                                maxLines: 3,
                                                overflow: TextOverflow.ellipsis,
                                                style: Cream.label(
                                                  context,
                                                  size: 16,
                                                  w: FontWeight.w400,
                                                  c: Cream.ink,
                                                ),
                                              ),
                                              if (post.author != null) ...[
                                                SizedBox(height: context.s(8)),
                                                Text(
                                                  '@${post.author}',
                                                  style: Cream.body(
                                                    context,
                                                    size: 12,
                                                    c: Cream.muted,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              SizedBox(height: context.s(16)),
                              _section(
                                'ABOUT THIS POST',
                                _describing
                                    ? Text(
                                        'Reading the post…',
                                        style: Cream.body(
                                          context,
                                          c: Cream.muted,
                                        ),
                                      )
                                    : Text(
                                        (post.description ?? '').isNotEmpty
                                            ? post.description!
                                            : 'No description available.',
                                        style: Cream.body(context, size: 16),
                                      ),
                              ),
                              SizedBox(height: context.s(12)),
                              InkWell(
                                onTap: _editNote,
                                borderRadius: BorderRadius.circular(
                                  context.s(28),
                                ),
                                child: _section(
                                  'YOUR NOTE',
                                  Text(
                                    (post.note ?? '').isNotEmpty
                                        ? post.note!
                                        : 'Tap to add a note',
                                    style: Cream.body(
                                      context,
                                      size: 16,
                                      c: (post.note ?? '').isNotEmpty
                                          ? Cream.ink
                                          : Cream.muted,
                                    ),
                                  ),
                                ),
                              ),
                              if (post.links.isNotEmpty) ...[
                                SizedBox(height: context.s(12)),
                                _section(
                                  'LINKS MENTIONED',
                                  Column(
                                    children: [
                                      for (
                                        var i = 0;
                                        i < post.links.length;
                                        i++
                                      )
                                        InkWell(
                                          onTap: () => launchUrl(
                                            linkTarget(post.links[i]),
                                            mode:
                                                LaunchMode.externalApplication,
                                          ),
                                          child: Container(
                                            padding: EdgeInsets.symmetric(
                                              vertical: context.s(13),
                                            ),
                                            decoration: BoxDecoration(
                                              border: i == post.links.length - 1
                                                  ? null
                                                  : const Border(
                                                      bottom: BorderSide(
                                                        color: Cream.line,
                                                      ),
                                                    ),
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  post.links[i].startsWith('@')
                                                      ? Icons.alternate_email
                                                      : Icons.link,
                                                  size: context.s(18),
                                                  color: Cream.muted,
                                                ),
                                                SizedBox(width: context.s(12)),
                                                Expanded(
                                                  child: Text(
                                                    post.links[i],
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: Cream.body(
                                                      context,
                                                      w: FontWeight.w500,
                                                    ),
                                                  ),
                                                ),
                                                Icon(
                                                  Icons.north_east,
                                                  size: context.s(16),
                                                  color: Cream.ink,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                              if (post.tags.isNotEmpty) ...[
                                SizedBox(height: context.s(16)),
                                Wrap(
                                  spacing: context.s(8),
                                  runSpacing: context.s(8),
                                  children: [
                                    for (final t in post.tags)
                                      InkWell(
                                        // Tapping a tag searches all saves.
                                        onTap: () => Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => CategoryPage(
                                              db: widget.db,
                                              initialQuery: t,
                                            ),
                                          ),
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          context.s(16),
                                        ),
                                        child: Frost(
                                          radius: 16,
                                          padding: EdgeInsets.symmetric(
                                            horizontal: context.s(14),
                                            vertical: context.s(10),
                                          ),
                                          child: Text(
                                            t,
                                            style: Cream.body(
                                              context,
                                              size: 13,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
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
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxW),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkPill(
                            label: 'Open in ${sourceName(post.url)}',
                            onTap: () => launchUrl(
                              Uri.parse(post.url),
                              mode: LaunchMode.externalApplication,
                            ),
                          ),
                        ),
                        SizedBox(width: context.s(10)),
                        GlassIcon(
                          icon: Icons.folder_outlined,
                          label: 'Move category',
                          size: 58,
                          live: true,
                          onTap: _move,
                        ),
                      ],
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
