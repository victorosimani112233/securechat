import 'dart:math';

import 'package:cryptography/cryptography.dart';

class CallEncryptionKeys {
  CallEncryptionKeys({required this.masterKey, required this.masterSalt});

  final List<int> masterKey;
  final List<int> masterSalt;

  void clear() {
    masterKey.fillRange(0, masterKey.length, 0);
    masterSalt.fillRange(0, masterSalt.length, 0);
  }
}

class CallCryptoManager {
  CallCryptoManager({Random? random}) : _random = random ?? Random.secure();

  final Random _random;
  final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 64);

  Future<CallEncryptionKeys> deriveCallEncryptionKey(String peerId) async {
    final nonce = List<int>.generate(32, (_) => _random.nextInt(256));
    final derived = await _hkdf.deriveKey(
      secretKey: SecretKey(nonce),
      nonce: const [],
      info: 'SecureChat-SRTP-Key:$peerId'.codeUnits,
    );
    final bytes = await derived.extractBytes();
    nonce.fillRange(0, nonce.length, 0);
    return CallEncryptionKeys(
      masterKey: bytes.sublist(0, 32),
      masterSalt: bytes.sublist(32, 64),
    );
  }
}
