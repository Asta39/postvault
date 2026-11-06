import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Optional Groq key baked in at build time from the git-ignored secrets.json:
///   flutter build apk --dart-define-from-file=secrets.json
/// Public release builds ship without one.
const builtInGroqKey = String.fromEnvironment('GROQ_API_KEY');

const _storage = FlutterSecureStorage();
const _storageKey = 'groq_api_key';

/// The user's own key (Settings) wins over the built-in one.
Future<String> resolveGroqKey() async =>
    (await _storage.read(key: _storageKey)) ?? builtInGroqKey;

Future<bool> hasUserGroqKey() async =>
    (await _storage.read(key: _storageKey))?.isNotEmpty ?? false;

Future<void> setUserGroqKey(String? key) => key == null || key.trim().isEmpty
    ? _storage.delete(key: _storageKey)
    : _storage.write(key: _storageKey, value: key.trim());
