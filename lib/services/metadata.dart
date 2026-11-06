import 'package:http/http.dart' as http;

/// Basic info scraped from a shared post link.
class PostMetadata {
  final String url;
  final String? title;
  final String? caption;
  final String? author;
  final String? imageUrl;

  const PostMetadata({
    required this.url,
    this.title,
    this.caption,
    this.author,
    this.imageUrl,
  });
}

final _urlRe = RegExp(r'https?://\S+');

/// Pull the first URL out of shared text (Instagram shares "text + link").
String? extractUrl(String shared) => _urlRe.firstMatch(shared)?.group(0);

/// Normalise an Instagram link so the same post is not saved twice.
String normaliseUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return url;
  final path = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
  final host = uri.host.startsWith('m.')
      ? 'www.${uri.host.substring(2)}'
      : uri.host;
  return Uri(scheme: 'https', host: host, path: path).toString();
}

String _decode(String s) => s
    .replaceAll('&quot;', '"')
    .replaceAll('&#039;', "'")
    .replaceAll('&#39;', "'")
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAllMapped(
      RegExp(r'&#x([0-9a-fA-F]+);'),
      (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)),
    )
    .replaceAllMapped(
      RegExp(r'&#(\d+);'),
      (m) => String.fromCharCode(int.parse(m[1]!)),
    );

String? _meta(String html, String prop) {
  final re = RegExp(
    '<meta[^>]+(?:property|name)=["\']$prop["\'][^>]+content=["\']([^"\']*)["\']',
    caseSensitive: false,
  );
  final m = re.firstMatch(html);
  return m == null ? null : _decode(m.group(1)!);
}

/// Fetch Open Graph tags. Instagram serves OG tags to link-preview crawlers,
/// so we identify as one. If Instagram blocks it, we still save the link.
Future<PostMetadata> fetchMetadata(String url) async {
  try {
    final res = await http
        .get(
          Uri.parse(url),
          headers: {
            'User-Agent': 'facebookexternalhit/1.1',
            'Accept-Language': 'en',
          },
        )
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return PostMetadata(url: url);
    final html = res.body;
    final title = _meta(html, 'og:title');
    final desc = _meta(html, 'og:description') ?? _meta(html, 'description');
    // og:title looks like: `Name on Instagram: "caption..."`
    String? author;
    String? caption = desc;
    if (title != null) {
      final m = RegExp(
        r'^(.*?) on Instagram: "(.*)"$',
        dotAll: true,
      ).firstMatch(title);
      if (m != null) {
        author = m.group(1);
        caption = m.group(2);
      }
    }
    return PostMetadata(
      url: url,
      title: title,
      caption: caption,
      author: author,
      imageUrl: _meta(html, 'og:image'),
    );
  } catch (_) {
    return PostMetadata(url: url);
  }
}
