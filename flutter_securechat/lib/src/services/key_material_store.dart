import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'crypto_service.dart';

abstract interface class KeyMaterialStore {
  Future<List<int>> readOrCreateMasterKey();
}

/// Keeps the database/session wrapping key in Android Keystore-backed storage
/// and the iOS Keychain. The key is intentionally separate from the encrypted
/// snapshot files so copying app data alone is insufficient to decrypt them.
class PlatformKeyMaterialStore implements KeyMaterialStore {
  PlatformKeyMaterialStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _masterKeyName = 'securechat.master-key.v1';
  final FlutterSecureStorage _storage;

  @override
  Future<List<int>> readOrCreateMasterKey() async {
    final stored = await _storage.read(
      key: _masterKeyName,
      aOptions: _androidOptions,
      iOptions: _iosOptions,
    );
    if (stored != null) {
      final bytes = base64Decode(stored);
      if (bytes.length != 32) {
        throw const FormatException('Invalid SecureChat master key length');
      }
      return bytes;
    }

    final bytes = LocalAeadCryptoService.newMasterKeyBytes();
    await _storage.write(
      key: _masterKeyName,
      value: base64Encode(bytes),
      aOptions: _androidOptions,
      iOptions: _iosOptions,
    );
    return bytes;
  }

  static const _androidOptions = AndroidOptions(
    storageNamespace: 'securechat_key_material',
  );
  static const _iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  );
}

/// Deterministic in-memory implementation used only by unit/widget tests.
class MemoryKeyMaterialStore implements KeyMaterialStore {
  MemoryKeyMaterialStore([List<int>? seed])
    : _key = List<int>.from(
        seed ?? List<int>.generate(32, (index) => index + 1),
      );

  final List<int> _key;

  @override
  Future<List<int>> readOrCreateMasterKey() async => List<int>.from(_key);
}
