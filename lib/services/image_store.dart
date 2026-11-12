import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/post_db.dart';
import 'metadata.dart';

/// Keeps a copy of every post image on the phone.
///
/// Instagram image links expire, so relying on them means thumbnails go blank
/// after a while. Files are named after the post URL, so no database change
/// is needed and existing posts are untouched.
class ImageStore {
  ImageStore._();
  static final instance = ImageStore._();

  late final Directory dir;
  final _have = <String>{};

  Future<void> init() async {
    final docs = await getApplicationDocumentsDirectory();
    dir = Directory(p.join(docs.path, 'images'));
    await dir.create(recursive: true);
    await for (final f in dir.list()) {
      _have.add(p.basename(f.path));
    }
  }

  /// File name for a post, derived from its (already normalised) URL.
  static String nameFor(String postUrl) =>
      '${base64Url.encode(utf8.encode(postUrl)).replaceAll('=', '')}.jpg';

  /// The local image for a post, or null if it has not been stored yet.
  File? fileFor(String postUrl) {
    final name = nameFor(postUrl);
    return _have.contains(name) ? File(p.join(dir.path, name)) : null;
  }

  Future<bool> _download(String postUrl, String imageUrl) async {
    try {
      final res = await http
          .get(Uri.parse(imageUrl))
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200 || res.bodyBytes.length < 500) return false;
      await writeBytes(postUrl, res.bodyBytes);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> writeBytes(String postUrl, List<int> bytes) async {
    final name = nameFor(postUrl);
    // Write to a temp file first so a crash never leaves a half image.
    final tmp = File(p.join(dir.path, '$name.part'));
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(p.join(dir.path, name));
    _have.add(name);
  }

  /// Stores the image for [post]. If its saved link has expired, asks
  /// Instagram for a fresh one and remembers it.
  Future<bool> ensure(SavedPost post, PostDb db) async {
    if (fileFor(post.url) != null) return true;
    final link = post.imageUrl;
    if (link != null && await _download(post.url, link)) return true;
    final fresh = (await fetchMetadata(post.url)).imageUrl;
    if (fresh == null || fresh == link) return false;
    if (!await _download(post.url, fresh)) return false;
    if (post.id != null) await db.setImageUrl(post.id!, fresh);
    return true;
  }

  /// Stores images for every post that doesn't have one yet.
  /// Returns how many were newly stored.
  Future<int> backfill(PostDb db) async {
    var added = 0;
    for (final post in await db.search()) {
      if (fileFor(post.url) == null && await ensure(post, db)) added++;
    }
    return added;
  }

  Future<void> remove(String postUrl) async {
    final name = nameFor(postUrl);
    _have.remove(name);
    final f = File(p.join(dir.path, name));
    if (await f.exists()) await f.delete();
  }
}
