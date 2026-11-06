import 'dart:convert';

import 'package:http/http.dart' as http;

class Categorization {
  final String category;
  final List<String> tags;
  final String summary;
  final String description;
  final List<String> links;

  const Categorization(
    this.category,
    this.tags,
    this.summary, {
    this.description = '',
    this.links = const [],
  });
}

final _linkRe = RegExp(
  r'(https?://[^\s)"]+)|\b((?:[a-z0-9-]+\.)+(?:com|io|ai|dev|app|co|org|net|so|xyz|me|gg|tv|ly|sh)(?:/[^\s)"]*)?)|(@[A-Za-z0-9_.]{2,30})',
  caseSensitive: false,
);

/// URLs, bare domains and @handles mentioned in the caption.
List<String> extractLinks(String text) {
  final out = <String>{};
  for (final m in _linkRe.allMatches(text)) {
    final v = m.group(0)!.replaceAll(RegExp(r'[.,!?:;]+$'), '');
    if (!v.contains('instagram.com/p/') && !v.contains('instagram.com/reel/')) {
      out.add(v);
    }
  }
  return out.take(10).toList();
}

const categories = [
  'Food & Recipes',
  'Fitness & Health',
  'Travel',
  'Fashion & Beauty',
  'Home & Decor',
  'Tech',
  'Business & Money',
  'Learning & Tips',
  'Art & Design',
  'Funny & Memes',
  'Music',
  'Shopping',
  'Other',
];

const _keywords = <String, List<String>>{
  'Food & Recipes': [
    'recipe',
    'food',
    'cook',
    'bake',
    'meal',
    'dinner',
    'lunch',
    'breakfast',
    'restaurant',
    'eat',
    'chef',
    'dessert',
    'pasta',
    'chicken',
  ],
  'Fitness & Health': [
    'workout',
    'gym',
    'fitness',
    'exercise',
    'protein',
    'health',
    'yoga',
    'run',
    'abs',
    'muscle',
    'diet',
    'wellness',
  ],
  'Travel': [
    'travel',
    'trip',
    'beach',
    'hotel',
    'flight',
    'island',
    'vacation',
    'explore',
    'city',
    'hike',
    'destination',
  ],
  'Fashion & Beauty': [
    'outfit',
    'fashion',
    'style',
    'makeup',
    'skincare',
    'hair',
    'beauty',
    'wear',
    'ootd',
    'nails',
  ],
  'Home & Decor': [
    'home',
    'decor',
    'interior',
    'room',
    'kitchen',
    'diy',
    'furniture',
    'apartment',
    'garden',
  ],
  'Tech': [
    'tech',
    'app',
    'ai',
    'code',
    'coding',
    'iphone',
    'android',
    'software',
    'gadget',
    'programming',
    'developer',
  ],
  'Business & Money': [
    'business',
    'money',
    'invest',
    'startup',
    'finance',
    'marketing',
    'entrepreneur',
    'sales',
    'income',
    'budget',
  ],
  'Learning & Tips': [
    'tip',
    'tips',
    'learn',
    'hack',
    'how to',
    'guide',
    'tutorial',
    'lesson',
    'advice',
    'productivity',
  ],
  'Art & Design': [
    'art',
    'design',
    'draw',
    'paint',
    'illustration',
    'photography',
    'creative',
    'sketch',
  ],
  'Funny & Memes': ['funny', 'meme', 'lol', 'joke', 'comedy', '😂', 'humor'],
  'Music': [
    'music',
    'song',
    'album',
    'concert',
    'guitar',
    'piano',
    'dj',
    'beat',
  ],
  'Shopping': [
    'buy',
    'shop',
    'sale',
    'discount',
    'link in bio',
    'deal',
    'product',
    'amazon',
  ],
};

/// Offline fallback: keyword matching + hashtags as tags.
Categorization keywordCategorize(String text) {
  final lower = text.toLowerCase();
  var best = 'Other';
  var bestScore = 0;
  _keywords.forEach((cat, words) {
    final score = words.where(lower.contains).length;
    if (score > bestScore) {
      bestScore = score;
      best = cat;
    }
  });
  final tags = RegExp(r'#(\w+)')
      .allMatches(text)
      .map((m) => m.group(1)!.toLowerCase())
      .toSet()
      .take(8)
      .toList();
  final summary = text.length > 120 ? '${text.substring(0, 117)}...' : text;
  return Categorization(best, tags, summary, links: extractLinks(text));
}

/// AI categorisation via the Groq API. Falls back to keywords on any error.
Future<Categorization> categorize(String text, {String? apiKey}) async {
  if (text.trim().isEmpty) return const Categorization('Other', [], '');
  if (apiKey == null || apiKey.isEmpty) return keywordCategorize(text);
  try {
    final prompt =
        '''
You organise someone's saved Instagram posts. Read the post text and reply with JSON only:
{"category": one of ${jsonEncode(categories)},
 "tags": [3-8 short lowercase search keywords],
 "summary": "one short sentence title for the post",
 "description": "2-3 plain sentences: what the post is about and the key takeaway or how-to",
 "links": [every website, URL, app, tool, product or @account mentioned, exactly as written]}

Post text:
"""$text"""''';
    final res = await http
        .post(
          Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'content-type': 'application/json',
          },
          body: jsonEncode({
            'model': 'openai/gpt-oss-20b',
            'max_tokens': 1000,
            'temperature': 0.2,
            'messages': [
              {'role': 'user', 'content': prompt},
            ],
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) return keywordCategorize(text);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final reply =
        (body['choices'] as List).first['message']['content'] as String? ?? '';
    final json = RegExp(r'\{[\s\S]*\}').firstMatch(reply)?.group(0);
    if (json == null) return keywordCategorize(text);
    final data = jsonDecode(json) as Map<String, dynamic>;
    var cat = data['category'] as String? ?? 'Other';
    if (!categories.contains(cat)) cat = 'Other';
    final tags = (data['tags'] as List? ?? [])
        .map((t) => t.toString().toLowerCase())
        .toList();
    final links = <String>{
      ...extractLinks(text),
      ...(data['links'] as List? ?? []).map((l) => l.toString().trim()),
    }.where((l) => l.isNotEmpty).take(10).toList();
    return Categorization(
      cat,
      tags,
      data['summary'] as String? ?? '',
      description: data['description'] as String? ?? '',
      links: links,
    );
  } catch (_) {
    return keywordCategorize(text);
  }
}
