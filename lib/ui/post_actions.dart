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

/// Lets the user pick a collection (or create one) and moves [post] there.
/// Returns the updated post, or null if nothing changed.
Future<SavedPost?> movePost(
  BuildContext context,
  PostDb db,
  SavedPost post,
) async {
  final all = await db.categories();
  if (!context.mounted) return null;
  var cat = await showCreamSheet<String>(
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
              bold: name == post.category,
              checked: name == post.category,
              onTap: () => Navigator.pop(c, name),
            ),
        ],
      ),
    ),
  );
  if (cat == null || !context.mounted) return null;
  if (cat == _newCollection) {
    final name = (await showCreamInput(
      context,
      title: 'New collection',
      action: 'Create and move',
      hint: 'Collection name',
    ))?.trim();
    if (name == null || name.isEmpty) return null;
    await db.addCollection(name);
    cat = name;
  }
  if (cat == post.category) return null;
  final updated = post.copyWith(category: cat);
  await db.update(updated);
  return updated;
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
    case 'move':
      if (await movePost(context, db, post) != null) onChange();
    case 'delete':
      await deleteWithUndo(context, db, post, onChange: onChange);
  }
}
