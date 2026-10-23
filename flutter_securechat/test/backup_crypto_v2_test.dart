import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/backup/backup_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final plaintext = utf8.encode('{"yedek":"icerik"}');

  test('new backups use the Argon2id v2 container', () async {
    final crypto = BackupCrypto(random: Random(7));
    final sealed = await crypto.encrypt(plaintext, 'parola-12345');
    expect(ascii.decode(sealed.sublist(0, 4)), 'ELCB');
    expect(sealed[4], 2);
    expect(sealed[5], 1);
    final header = ByteData.sublistView(sealed);
    expect(header.getUint32(6), BackupCrypto.defaultMemoryKiB);
    expect(header.getUint32(10), BackupCrypto.defaultIterations);
    expect(await crypto.decrypt(sealed, 'parola-12345'), plaintext);
    expect(await crypto.decrypt(sealed, 'yanlis-parola'), isNull);
  });

  test('the header is authenticated', () async {
    final crypto = BackupCrypto(random: Random(8));
    final sealed = await crypto.encrypt(plaintext, 'parola-12345');
    // Daha zayif bir tur sayisina indirmek dosyayi gecersiz kilar.
    final weakened = Uint8List.fromList(sealed)..[13] = 1;
    expect(await crypto.decrypt(weakened, 'parola-12345'), isNull);
    // Asiri bellek isteyen bicim acilmaya calisilmaz.
    final greedy = Uint8List.fromList(sealed);
    ByteData.sublistView(greedy).setUint32(6, 1 << 30);
    expect(await crypto.decrypt(greedy, 'parola-12345'), isNull);
  });

  test('old PBKDF2 backups still open', () async {
    // Eski bicim: tuz(32) + IV(12) + sifreli metin + etiket(16).
    final salt = List<int>.generate(32, (i) => i);
    final nonce = List<int>.generate(12, (i) => 100 + i);
    final key = await Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: BackupCrypto.legacyIterations,
      bits: 256,
    ).deriveKey(secretKey: SecretKey(utf8.encode('eski-parola')), nonce: salt);
    final box = await AesGcm.with256bits().encrypt(
      plaintext,
      secretKey: key,
      nonce: nonce,
    );
    final legacy = [...salt, ...nonce, ...box.cipherText, ...box.mac.bytes];
    expect(await BackupCrypto().decrypt(legacy, 'eski-parola'), plaintext);
    expect(await BackupCrypto().decrypt(legacy, 'baska'), isNull);
  });
}
