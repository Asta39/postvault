import 'package:flutter_test/flutter_test.dart';
import 'package:postvault/data/post_db.dart';
import 'package:postvault/services/backup.dart';
import 'package:postvault/services/categorizer.dart';
import 'package:postvault/services/image_store.dart';
import 'package:postvault/services/metadata.dart';

void main() {
  test('extracts url from shared Instagram text', () {
    expect(extractUrl('Check this https://www.instagram.com/reel/abc123/?igsh=xyz'),
        'https://www.instagram.com/reel/abc123/?igsh=xyz');
  });

  test('normalises url, drops tracking query', () {
    expect(normaliseUrl('https://www.instagram.com/reel/abc123?igsh=xyz'),
        'https://www.instagram.com/reel/abc123/');
  });

  test('keyword fallback picks category and hashtags', () {
    final c = keywordCategorize('Easy pasta recipe for dinner #food #pasta');
    expect(c.category, 'Food & Recipes');
    expect(c.tags, containsAll(['food', 'pasta']));
  });

  test('extracts links and handles from caption', () {
    final l = extractLinks('Try it at github.com/foo/bar and https://x.ai/docs. Follow @ai_luke!');
    expect(l, containsAll(['github.com/foo/bar', 'https://x.ai/docs', '@ai_luke']));
  });

  test('backup JSON round-trips a post without losing fields', () {
    final post = SavedPost(
      url: 'https://www.instagram.com/p/abc/',
      author: 'Ada',
      caption: 'Hello, "world"\nline two',
      imageUrl: 'https://img/x.jpg',
      category: 'Tech',
      tags: ['ai', 'tools'],
      summary: 'A title',
      note: 'my note',
      description: 'About it.',
      links: ['github.com/a/b', '@ada'],
      savedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );
    final back = decodePosts(encodePosts([post])).single;
    expect(back.toMap()..remove('id'), post.toMap()..remove('id'));
  });

  test('image file names are stable and filesystem safe', () {
    final a = ImageStore.nameFor('https://www.instagram.com/reel/abc_-1/');
    expect(a, ImageStore.nameFor('https://www.instagram.com/reel/abc_-1/'));
    expect(RegExp(r'^[A-Za-z0-9_-]+\.jpg$').hasMatch(a), isTrue);
  });
}
