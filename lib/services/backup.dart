import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/post_db.dart';
import 'image_store.dart';

/// Backup format: a zip holding `posts.json` plus `images/<name>.jpg`.
const backupFormat = 1;

/// Turns posts into the JSON stored in a backup (ids are left out; the post
/// URL identifies a post).
String encodePosts(List<SavedPost> posts) => jsonEncode({
  'format': backupFormat,
  'posts': [for (final post in posts) post.toMap()..remove('id')],
});

List<SavedPost> decodePosts(String json) {
  final data = jsonDecode(json) as Map<String, dynamic>;
  return [
    for (final m in data['posts'] as List)
      SavedPost.fromMap(Map<String, Object?>.from(m as Map)),
  ];
}

/// Writes a backup zip to a temporary file and returns it.
Future<File> exportBackup(PostDb db) async {
  final posts = await db.search();
  final archive = Archive();
  final json = utf8.encode(encodePosts(posts));
  archive.addFile(ArchiveFile('posts.json', json.length, json));
  for (final post in posts) {
    final img = ImageStore.instance.fileFor(post.url);
    if (img == null) continue;
    final bytes = await img.readAsBytes();
    archive.addFile(
      ArchiveFile('images/${p.basename(img.path)}', bytes.length, bytes),
    );
  }
  final stamp = DateTime.now().toIso8601String().substring(0, 10);
  final out = File(
    p.join((await getTemporaryDirectory()).path, 'postvault-backup-$stamp.zip'),
  );
  await out.writeAsBytes(ZipEncoder().encode(archive), flush: true);
  return out;
}

/// Adds posts from a backup. Posts already on the phone are never changed
/// or removed. Returns how many posts were added.
Future<int> importBackup(PostDb db, File zip) async {
  final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
  final entry = archive.findFile('posts.json');
  if (entry == null) throw const FormatException('Not a PostVault backup');
  final posts = decodePosts(utf8.decode(entry.content as List<int>));
  var added = 0;
  for (final post in posts) {
    if (await db.exists(post.url)) continue;
    await db.insert(post);
    added++;
  }
  for (final f in archive.files) {
    if (!f.isFile || !f.name.startsWith('images/')) continue;
    final name = p.basename(f.name);
    for (final post in posts) {
      if (ImageStore.nameFor(post.url) == name &&
          ImageStore.instance.fileFor(post.url) == null) {
        await ImageStore.instance.writeBytes(post.url, f.content as List<int>);
      }
    }
  }
  return added;
}
