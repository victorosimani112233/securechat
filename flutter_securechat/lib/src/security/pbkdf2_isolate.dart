import 'dart:convert';
import 'dart:isolate';

import 'package:cryptography/cryptography.dart';

/// PBKDF2-HMAC-SHA256 ayri bir isolate'te.
///
/// Sohbet kilidi ve yedek 120 000 tur kullanir; saf Dart'ta bu arayuz
/// isolate'inde calisinca ekran parola dogrulanana kadar donuyordu.
/// Cikti ana isolate'teki hesapla birebir aynidir.
Future<List<int>> pbkdf2Sha256({
  required String password,
  required List<int> salt,
  required int iterations,
  int bits = 256,
}) {
  final saltCopy = List<int>.of(salt, growable: false);
  return Isolate.run(() async {
    final kdf = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: bits,
    );
    final key = await kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: saltCopy,
    );
    return key.extractBytes();
  }, debugName: 'pbkdf2');
}
