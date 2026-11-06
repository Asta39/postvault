import 'package:flutter/material.dart';

import '../data/post_db.dart';
import 'cream.dart';

/// Grid of post tiles that adapts its column count to the screen.
class PostGrid extends StatelessWidget {
  const PostGrid({super.key, required this.posts, required this.onTap});
  final List<SavedPost> posts;
  final void Function(SavedPost) onTap;

  @override
  Widget build(BuildContext context) => SliverGrid.builder(
    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: context.columns,
      mainAxisSpacing: context.s(12),
      crossAxisSpacing: context.s(12),
      childAspectRatio: 0.72,
    ),
    itemCount: posts.length,
    itemBuilder: (_, i) =>
        PostTile(post: posts[i], onTap: () => onTap(posts[i])),
  );
}

class PostTile extends StatelessWidget {
  const PostTile({super.key, required this.post, required this.onTap});
  final SavedPost post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = post.summary?.isNotEmpty == true
        ? post.summary!
        : (post.caption ?? post.url);
    return RepaintBoundary(
      child: GestureDetector(
        onTap: onTap,
        child: ClipRSuperellipse(
          borderRadius: BorderRadius.circular(context.s(28)),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(color: const Color(0xFFEFE6C8)),
              if (post.imageUrl != null)
                Image.network(
                  post.imageUrl!,
                  fit: BoxFit.cover,
                  cacheWidth: 480,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const SizedBox(),
                ),
              Positioned(
                left: context.s(8),
                right: context.s(8),
                bottom: context.s(8),
                // Static frosted panel: same look as glass, far cheaper to scroll.
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xD9F6F1E4),
                    borderRadius: BorderRadius.circular(context.s(20)),
                    border: Border.all(color: const Color(0x99FFFFFF)),
                  ),
                  padding: EdgeInsets.fromLTRB(
                    context.s(12),
                    context.s(10),
                    context.s(12),
                    context.s(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        post.category.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Cream.label(context, size: 9, c: Cream.ink),
                      ),
                      SizedBox(height: context.s(4)),
                      Text(
                        text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Cream.body(
                          context,
                          size: 12,
                          w: FontWeight.w500,
                        ),
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
