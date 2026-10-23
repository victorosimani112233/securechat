import 'dart:convert';
import 'dart:isolate';

import 'package:cryptography/cryptography.dart';

/// Kayit kilidi PIN'i: 6-12 rakam.
bool validRegistrationLockPin(String pin) =>
    RegExp(r'^[0-9]{6,12}$').hasMatch(pin);

/// PIN'den sunucuya giden 32 baytlik kanit.
///
/// PIN sunucuya gitmez. Argon2id (64 MiB, 3 tur) hesap kimligiyle tuzlanir;
/// ayni PIN farkli hesaplarda farkli kanit verir. Sunucu kanitin yalniz
/// kendi anahtariyla HMAC'ini saklar ve yanlis denemeleri sayar.
Future<String> registrationLockProof({
  required String pin,
  required String userId,
}) async {
  if (!validRegistrationLockPin(pin)) {
    throw ArgumentError.value('***', 'pin', 'Invalid registration lock PIN');
  }
  final bytes = await Isolate.run(() async {
    final key =
        await Argon2id(
          parallelism: 1,
          memory: 64 * 1024,
          iterations: 3,
          hashLength: 32,
        ).deriveKey(
          secretKey: SecretKey(utf8.encode(pin)),
          nonce: utf8.encode('elcim-registration-lock-v1\u0000$userId'),
        );
    return key.extractBytes();
  }, debugName: 'registration-lock');
  return base64Encode(bytes);
}
