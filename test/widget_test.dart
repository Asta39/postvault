import 'package:flutter_test/flutter_test.dart';
import 'package:postvault/services/categorizer.dart';
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
}
