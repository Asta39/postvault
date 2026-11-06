import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/post_db.dart';
import '../services/ai_key.dart';
import '../services/categorizer.dart';
import 'cream.dart';

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
    final c = await categorize(text, apiKey: await resolveGroqKey());
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

  Future<void> _move() async {
    final cat = await showCreamSheet<String>(
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
            for (final cat in categories)
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
    if (cat == null) return;
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
                                      style: Cream.label(context, c: Cream.ink),
                                    ),
                                  ),
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
                                      if (post.imageUrl != null)
                                        Image.network(
                                          post.imageUrl!,
                                          fit: BoxFit.cover,
                                          cacheWidth: 1080,
                                          errorBuilder: (_, _, _) =>
                                              const SizedBox(),
                                        ),
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
                                      Frost(
                                        radius: 16,
                                        padding: EdgeInsets.symmetric(
                                          horizontal: context.s(14),
                                          vertical: context.s(8),
                                        ),
                                        child: Text(
                                          t,
                                          style: Cream.body(context, size: 13),
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
                            label: 'Open in Instagram',
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
