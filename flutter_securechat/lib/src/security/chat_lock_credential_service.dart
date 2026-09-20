import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import '../storage/secure_chat_database.dart';

abstract interface class ChatLockCredentialStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class DatabaseChatLockCredentialStore implements ChatLockCredentialStore {
  const DatabaseChatLockCredentialStore(this._dao);

  final CryptoStateDao _dao;

  @override
  Future<String?> read(String key) => _dao.get(key);

  @override
  Future<void> write(String key, String value) => _dao.put(key, value);

  @override
  Future<void> delete(String key) => _dao.delete(key);
}

class ChatLockCredentialService {
  ChatLockCredentialService({
    required ChatLockCredentialStore store,
    Random? random,
  }) : _store = store,
       _random = random ?? Random.secure();

  static const minPasswordLength = 8;
  static const maxPasswordLength = 128;
  static const _iterations = 120000;
  static const _saltLength = 32;
  static const _keyPrefix = 'chat-lock-credential:v1:';

  final ChatLockCredentialStore _store;
  final Random _random;
  final Pbkdf2 _kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: _iterations,
    bits: 256,
  );

  Future<bool> hasCredential(String conversationId) async =>
      await _store.read(await _key(conversationId)) != null;

  Future<void> setPassword(String conversationId, String password) async {
    _validatePassword(password);
    final salt = List<int>.generate(
      _saltLength,
      (_) => _random.nextInt(256),
      growable: false,
    );
    final verifier = await _derive(password, salt);
    await _store.write(
      await _key(conversationId),
      jsonEncode({
        'version': 1,
        'iterations': _iterations,
        'salt': base64UrlEncode(salt),
        'verifier': base64UrlEncode(verifier),
      }),
    );
  }

  Future<bool> verifyPassword(String conversationId, String password) async {
    if (password.length > maxPasswordLength) return false;
    final encoded = await _store.read(await _key(conversationId));
    if (encoded == null) return false;
    try {
      final json = (jsonDecode(encoded) as Map).cast<String, Object?>();
      if (json['version'] != 1 || json['iterations'] != _iterations) {
        return false;
      }
      final salt = base64Url.decode(json['salt'] as String);
      final expected = base64Url.decode(json['verifier'] as String);
      if (salt.length != _saltLength || expected.length != 32) return false;
      final actual = await _derive(password, salt);
      return _constantTimeEquals(expected, actual);
    } catch (_) {
      return false;
    }
  }

  Future<void> clear(String conversationId) async {
    await _store.delete(await _key(conversationId));
  }

  Future<String> _key(String conversationId) async {
    final digest = await Sha256().hash(utf8.encode(conversationId));
    return '$_keyPrefix${base64UrlEncode(digest.bytes)}';
  }

  Future<List<int>> _derive(String password, List<int> salt) async =>
      (await _kdf.deriveKey(
        secretKey: SecretKey(utf8.encode(password)),
        nonce: salt,
      )).extractBytes();

  static bool _constantTimeEquals(List<int> expected, List<int> actual) {
    if (expected.length != actual.length) return false;
    var difference = 0;
    for (var index = 0; index < expected.length; index++) {
      difference |= expected[index] ^ actual[index];
    }
    return difference == 0;
  }

  static void _validatePassword(String password) {
    if (password.length < minPasswordLength ||
        password.length > maxPasswordLength) {
      throw ArgumentError.value(password.length, 'password', 'Invalid length');
    }
  }
}
