import 'dart:convert';

import '../storage/secure_chat_database.dart';
import 'private_contact_discovery.dart';

/// Dizin belirteclerini sifreli yerel veritabaninda tek kayit olarak tutar.
///
/// Yalniz son dizin anahtarinin belirtecleri saklanir; anahtar degisince
/// kayit gecersiz sayilir ve ilk eslemede yenisiyle degisir.
class StoredDirectoryTokenCache implements DirectoryTokenCache {
  StoredDirectoryTokenCache(this._state);

  static const _key = 'directory-tokens:v1';
  static final _hash = RegExp(r'^[0-9a-f]{64}$');
  static final _token = RegExp(r'^[A-Za-z0-9_-]{43}$');

  final CryptoStateDao _state;

  @override
  Future<Map<String, String>> load(String keyId) async {
    final encoded = await _state.get(_key);
    if (encoded == null) return {};
    try {
      final json = (jsonDecode(encoded) as Map).cast<String, Object?>();
      if (json['keyId'] != keyId) return {};
      return {
        for (final entry in (json['tokens'] as Map).entries)
          if (entry.key is String &&
              entry.value is String &&
              _hash.hasMatch(entry.key as String) &&
              _token.hasMatch(entry.value as String))
            entry.key as String: entry.value as String,
      };
    } catch (_) {
      // Bozuk kayit yok sayilir; sonraki esleme yeniden yazar.
      return {};
    }
  }

  @override
  Future<void> save(String keyId, Map<String, String> tokens) =>
      _state.put(_key, jsonEncode({'keyId': keyId, 'tokens': tokens}));
}
