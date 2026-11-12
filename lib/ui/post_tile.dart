import 'package:flutter/material.dart';

import '../data/post_db.dart';
import '../services/image_store.dart';
import 'cream.dart';

/// Grid of post tiles that adapts its column count to the screen.
class PostGrid extends StatelessWidget {
  const PostGrid({
    super.key,
    required this.posts,
    required this.onTap,
    this.onLongPress,
    this.selected,
  });
  final List<SavedPost> posts;
  final void Function(SavedPost) onTap;
  final void Function(SavedPost)? onLongPress;

  /// Ids of the selected posts while selecting; null when not selecting.
  final Set<int>? selected;

  @override
  Widget build(BuildContext context) => SliverGrid.builder(
    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: context.columns,
      mainAxisSpacing: context.s(12),
      crossAxisSpacing: context.s(12),
      childAspectRatio: 0.72,
    ),
    itemCount: posts.length,
    itemBuilder: (_, i) => PostTile(
      post: posts[i],
      onTap: () => onTap(posts[i]),
      selected: selected?.contains(posts[i].id),
      onLongPress: onLongPress == null ? null : () => onLongPress!(posts[i]),
    ),
  );
}

class PostTile extends StatelessWidget {
  const PostTile({
    super.key,
    required this.post,
    required this.onTap,
    this.onLongPress,
    this.heroPrefix = '',
    this.selected,
  });
  final SavedPost post;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Whether this post is ticked; null hides the tick circle.
  final bool? selected;

  /// Makes the open animation tag unique when a post shows twice on a screen.
  final String heroPrefix;

  @override
  Widget build(BuildContext context) {
    final text = post.summary?.isNotEmpty == true
        ? post.summary!
        : (post.caption ?? post.url);
    return RepaintBoundary(
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: ClipRSuperellipse(
          borderRadius: BorderRadius.circular(context.s(28)),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(color: Cream.placeholder),
              // The picture grows into the post screen when opened.
              Hero(
                tag: 'post-$heroPrefix${post.url}',
                child: PostImage(post: post, cacheWidth: 480),
              ),
              if (selected == true) Container(color: const Color(0x66000000)),
              if (selected != null)
                Positioned(
                  top: context.s(10),
                  right: context.s(10),
                  child: Container(
                    width: context.s(28),
                    height: context.s(28),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected! ? Cream.ink : const Color(0x66000000),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: selected!
                        ? Icon(
                            Icons.check,
                            size: context.s(18),
                            color: Cream.bg,
                          )
                        : null,
                  ),
                ),
              Positioned(
                left: context.s(8),
                right: context.s(8),
                bottom: context.s(8),
                // Static frosted panel: same look as glass, far cheaper to scroll.
                child: Container(
                  decoration: BoxDecoration(
                    color: Cream.captionFill,
                    borderRadius: BorderRadius.circular(context.s(20)),
                    border: Border.all(color: Cream.frostEdge),
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

/// A post's picture: the copy stored on the phone when there is one,
/// otherwise the Instagram link (which can expire).
class PostImage extends StatelessWidget {
  const PostImage({super.key, required this.post, required this.cacheWidth});
  final SavedPost post;
  final int cacheWidth;

  @override
  Widget build(BuildContext context) {
    final file = ImageStore.instance.fileFor(post.url);
    if (file != null) {
      return Image.file(
        file,
        fit: BoxFit.cover,
        cacheWidth: cacheWidth,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => const SizedBox(),
      );
    }
    if (post.imageUrl == null) return const SizedBox();
    return Image.network(
      post.imageUrl!,
      fit: BoxFit.cover,
      cacheWidth: cacheWidth,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => const SizedBox(),
    );
  }
}

/// Placeholder shown while a newly shared post is fetched and sorted.
class SavingCard extends StatefulWidget {
  const SavingCard({super.key});

  @override
  State<SavingCard> createState() => _SavingCardState();
}

class _SavingCardState extends State<SavingCard>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween(begin: 0.45, end: 1.0).animate(_pulse),
    child: Container(
      decoration: BoxDecoration(
        color: Cream.placeholder,
        borderRadius: BorderRadius.circular(context.s(28)),
        border: Border.all(color: Cream.frostEdge),
      ),
      padding: EdgeInsets.all(context.s(16)),
      alignment: Alignment.bottomLeft,
      child: Text(
        'SAVING AND\nSORTING…',
        style: Cream.label(context, size: 10, c: Cream.ink),
      ),
    ),
  );
}
