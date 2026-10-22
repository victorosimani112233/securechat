import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/security/pbkdf2_isolate.dart';
import 'package:flutter_test/flutter_test.dart';

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

void main() {
  test('matches the published PBKDF2-HMAC-SHA256 vector', () async {
    final key = await pbkdf2Sha256(
      password: 'password',
      salt: utf8.encode('salt'),
      iterations: 1,
    );
    expect(
      _hex(key),
      '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
    );
  });

  test('derives exactly what the in-isolate derivation produced', () async {
    // Mevcut sohbet kilidi dogrulayicilari ve yedekler gecerli kalmali.
    final salt = List<int>.generate(32, (index) => index * 7 % 256);
    final expected =
        await (await Pbkdf2(
              macAlgorithm: Hmac.sha256(),
              iterations: 2000,
              bits: 256,
            ).deriveKey(
              secretKey: SecretKey(utf8.encode('çok gizli şifre')),
              nonce: salt,
            ))
            .extractBytes();

    final actual = await pbkdf2Sha256(
      password: 'çok gizli şifre',
      salt: salt,
      iterations: 2000,
    );

    expect(actual, expected);
  });
}
