import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/post_db.dart';
import '../services/image_store.dart';
import '../services/metadata.dart';
import 'cream.dart';

const _newCollection = '\u0000new';

Widget _row(
  BuildContext c, {
  required String label,
  required VoidCallback onTap,
  IconData? leading,
  bool bold = false,
  bool checked = false,
}) => InkWell(
  onTap: onTap,
  child: Container(
    padding: EdgeInsets.symmetric(vertical: c.s(15)),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: Cream.line)),
    ),
    child: Row(
      children: [
        if (leading != null) ...[
          Icon(leading, color: Cream.ink, size: c.s(20)),
          SizedBox(width: c.s(12)),
        ],
        Expanded(
          child: Text(
            label,
            style: Cream.body(
              c,
              size: 17,
              w: bold ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
        if (checked) Icon(Icons.check, color: Cream.ink, size: c.s(20)),
      ],
    ),
  ),
);

/// Lets the user pick a collection or create one. [current] gets a tick.
/// Returns the chosen name, or null if dismissed.
Future<String?> pickCollection(
  BuildContext context,
  PostDb db, {
  String? current,
}) async {
  final all = await db.categories();
  if (!context.mounted) return null;
  final cat = await showCreamSheet<String>(
    context,
    title: 'Move to',
    builder: (c) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * 0.6),
      child: ListView(
        padding: EdgeInsets.zero,
        shrinkWrap: true,
        children: [
          _row(
            c,
            label: 'New collection',
            leading: Icons.add,
            bold: true,
            onTap: () => Navigator.pop(c, _newCollection),
          ),
          for (final name in all)
            _row(
              c,
              label: name,
              bold: name == current,
              checked: name == current,
              onTap: () => Navigator.pop(c, name),
            ),
        ],
      ),
    ),
  );
  if (cat != _newCollection || !context.mounted) return cat;
  final name = (await showCreamInput(
    context,
    title: 'New collection',
    action: 'Create and move',
    hint: 'Collection name',
  ))?.trim();
  if (name == null || name.isEmpty) return null;
  await db.addCollection(name);
  return name;
}

/// Moves [post] to a collection the user picks.
/// Returns the updated post, or null if nothing changed.
Future<SavedPost?> movePost(
  BuildContext context,
  PostDb db,
  SavedPost post,
) async {
  final cat = await pickCollection(context, db, current: post.category);
  if (cat == null || cat == post.category) return null;
  final updated = post.copyWith(category: cat);
  await db.update(updated);
  return updated;
}

/// Moves several posts to one collection. Returns how many were moved.
Future<int> movePosts(
  BuildContext context,
  PostDb db,
  List<SavedPost> posts,
) async {
  final cat = await pickCollection(context, db);
  if (cat == null) return 0;
  var moved = 0;
  for (final post in posts) {
    if (post.category == cat) continue;
    await db.update(post.copyWith(category: cat));
    moved++;
  }
  if (context.mounted && moved > 0) {
    showToast(context, 'Moved $moved ${moved == 1 ? 'post' : 'posts'} to $cat');
  }
  return moved;
}

/// Deletes several posts at once and offers one Undo for all of them.
Future<void> deletePostsWithUndo(
  BuildContext context,
  PostDb db,
  List<SavedPost> posts, {
  VoidCallback? onChange,
}) async {
  if (posts.isEmpty) return;
  for (final post in posts) {
    await db.delete(post.id!);
  }
  onChange?.call();
  if (!context.mounted) return;
  final n = posts.length;
  showToast(
    context,
    n == 1 ? 'Post deleted' : '$n posts deleted',
    actionLabel: 'Undo',
    duration: const Duration(seconds: 6),
    onAction: () async {
      for (final post in posts) {
        await db.insert(post);
      }
      onChange?.call();
    },
    onClosed: () {
      for (final post in posts) {
        ImageStore.instance.remove(post.url);
      }
    },
  );
}

/// Deletes [post] straight away and offers Undo for a few seconds.
/// [onChange] runs after the delete and again if it is undone.
Future<void> deleteWithUndo(
  BuildContext context,
  PostDb db,
  SavedPost post, {
  VoidCallback? onChange,
}) async {
  await db.delete(post.id!);
  onChange?.call();
  if (!context.mounted) return;
  showToast(
    context,
    'Post deleted',
    actionLabel: 'Undo',
    duration: const Duration(seconds: 5),
    onAction: () async {
      await db.insert(post);
      onChange?.call();
    },
    // The stored picture is only removed once Undo is no longer possible.
    onClosed: () => ImageStore.instance.remove(post.url),
  );
}

/// Long-press menu for a post. [onChange] runs when the post was changed.
Future<void> showPostActions(
  BuildContext context,
  PostDb db,
  SavedPost post, {
  required VoidCallback onChange,
  VoidCallback? onSelect,
}) async {
  final action = await showCreamSheet<String>(
    context,
    title: post.summary?.isNotEmpty == true ? post.summary! : 'Saved post',
    builder: (c) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _row(
          c,
          label: 'Open in ${sourceName(post.url)}',
          leading: Icons.north_east,
          onTap: () => Navigator.pop(c, 'open'),
        ),
        _row(
          c,
          label: 'Move to another collection',
          leading: Icons.folder_outlined,
          onTap: () => Navigator.pop(c, 'move'),
        ),
        if (onSelect != null)
          _row(
            c,
            label: 'Select posts',
            leading: Icons.check_circle_outline,
            onTap: () => Navigator.pop(c, 'select'),
          ),
        _row(
          c,
          label: 'Delete',
          leading: Icons.delete_outline,
          onTap: () => Navigator.pop(c, 'delete'),
        ),
      ],
    ),
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case 'open':
      await launchUrl(
        Uri.parse(post.url),
        mode: LaunchMode.externalApplication,
      );
    case 'select':
      onSelect?.call();
    case 'move':
      if (await movePost(context, db, post) != null) onChange();
    case 'delete':
      await deleteWithUndo(context, db, post, onChange: onChange);
  }
}
