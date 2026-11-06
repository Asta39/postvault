import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class SavedPost {
  final int? id;
  final String url;
  final String? author;
  final String? caption;
  final String? imageUrl;
  final String category;
  final List<String> tags;
  final String? summary;
  final String? note;
  final String? description;
  final List<String> links;
  final DateTime savedAt;

  SavedPost({
    this.id,
    required this.url,
    this.author,
    this.caption,
    this.imageUrl,
    required this.category,
    required this.tags,
    this.summary,
    this.note,
    this.description,
    this.links = const [],
    required this.savedAt,
  });

  Map<String, Object?> toMap() => {
    'id': id,
    'url': url,
    'author': author,
    'caption': caption,
    'image_url': imageUrl,
    'category': category,
    'tags': tags.join(','),
    'summary': summary,
    'note': note,
    'description': description,
    'links': links.join('\n'),
    'saved_at': savedAt.millisecondsSinceEpoch,
  };

  static SavedPost fromMap(Map<String, Object?> m) => SavedPost(
    id: m['id'] as int?,
    url: m['url'] as String,
    author: m['author'] as String?,
    caption: m['caption'] as String?,
    imageUrl: m['image_url'] as String?,
    category: m['category'] as String,
    tags: ((m['tags'] as String?) ?? '')
        .split(',')
        .where((t) => t.isNotEmpty)
        .toList(),
    summary: m['summary'] as String?,
    note: m['note'] as String?,
    description: m['description'] as String?,
    links: ((m['links'] as String?) ?? '')
        .split('\n')
        .where((l) => l.isNotEmpty)
        .toList(),
    savedAt: DateTime.fromMillisecondsSinceEpoch(m['saved_at'] as int),
  );

  SavedPost copyWith({
    String? category,
    String? note,
    String? description,
    List<String>? links,
  }) => SavedPost(
    id: id,
    url: url,
    author: author,
    caption: caption,
    imageUrl: imageUrl,
    category: category ?? this.category,
    tags: tags,
    summary: summary,
    note: note ?? this.note,
    description: description ?? this.description,
    links: links ?? this.links,
    savedAt: savedAt,
  );
}

class PostDb {
  PostDb._(this._db);
  final Database _db;

  static Future<PostDb> open() async {
    final db = await openDatabase(
      p.join(await getDatabasesPath(), 'postvault.db'),
      version: 2,
      onUpgrade: (db, from, _) async {
        if (from < 2) {
          await db.execute('ALTER TABLE posts ADD COLUMN description TEXT');
          await db.execute('ALTER TABLE posts ADD COLUMN links TEXT');
        }
      },
      onCreate: (db, _) => db.execute('''
        CREATE TABLE posts(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          url TEXT UNIQUE NOT NULL,
          author TEXT, caption TEXT, image_url TEXT,
          category TEXT NOT NULL, tags TEXT, summary TEXT, note TEXT,
          description TEXT, links TEXT,
          saved_at INTEGER NOT NULL
        )'''),
    );
    return PostDb._(db);
  }

  Future<bool> exists(String url) async => (await _db.query(
    'posts',
    where: 'url = ?',
    whereArgs: [url],
    limit: 1,
  )).isNotEmpty;

  Future<void> insert(SavedPost post) => _db.insert(
    'posts',
    post.toMap(),
    conflictAlgorithm: ConflictAlgorithm.ignore,
  );

  Future<void> update(SavedPost post) =>
      _db.update('posts', post.toMap(), where: 'id = ?', whereArgs: [post.id]);

  Future<void> delete(int id) =>
      _db.delete('posts', where: 'id = ?', whereArgs: [id]);

  /// Every word in [query] must appear in some searchable field.
  Future<List<SavedPost>> search({String query = '', String? category}) async {
    final where = <String>[];
    final args = <Object?>[];
    if (category != null) {
      where.add('category = ?');
      args.add(category);
    }
    for (final word in query.trim().toLowerCase().split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;
      where.add(
        "(lower(coalesce(caption,'') || ' ' || coalesce(author,'') || ' ' || "
        "coalesce(tags,'') || ' ' || coalesce(summary,'') || ' ' || "
        "coalesce(note,'') || ' ' || coalesce(description,'') || ' ' || category) LIKE ?)",
      );
      args.add('%$word%');
    }
    final rows = await _db.query(
      'posts',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: 'saved_at DESC',
    );
    return rows.map(SavedPost.fromMap).toList();
  }

  Future<Map<String, int>> categoryCounts() async {
    final rows = await _db.rawQuery(
      'SELECT category, COUNT(*) c FROM posts GROUP BY category ORDER BY c DESC',
    );
    return {for (final r in rows) r['category'] as String: r['c'] as int};
  }
}
