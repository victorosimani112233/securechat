import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Kotlin BackupCrypto-compatible AES-256-GCM container:
/// [32-byte salt][12-byte IV][ciphertext][16-byte GCM tag].
class BackupCrypto {
  BackupCrypto({Random? random}) : _random = random ?? Random.secure();

  static const saltLength = 32;
  static const nonceLength = 12;
  static const macLength = 16;
  static const iterations = 120000;

  final Random _random;
  final AesGcm _cipher = AesGcm.with256bits();
  final Pbkdf2 _kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: iterations,
    bits: 256,
  );

  Future<Uint8List> encrypt(List<int> plaintext, String password) async {
    final salt = _bytes(saltLength);
    final nonce = _bytes(nonceLength);
    final key = await _derive(password, salt);
    final box = await _cipher.encrypt(plaintext, secretKey: key, nonce: nonce);
    return Uint8List.fromList([
      ...salt,
      ...nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
  }

  Future<Uint8List?> decrypt(List<int> encrypted, String password) async {
    if (encrypted.length < saltLength + nonceLength + macLength + 1) {
      return null;
    }
    try {
      final salt = encrypted.sublist(0, saltLength);
      final nonce = encrypted.sublist(saltLength, saltLength + nonceLength);
      final body = encrypted.sublist(saltLength + nonceLength);
      final cipherText = body.sublist(0, body.length - macLength);
      final mac = body.sublist(body.length - macLength);
      final clear = await _cipher.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: await _derive(password, salt),
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  Future<SecretKey> _derive(String password, List<int> salt) =>
      _kdf.deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);

  List<int> _bytes(int length) =>
      List<int>.generate(length, (_) => _random.nextInt(256));
}
