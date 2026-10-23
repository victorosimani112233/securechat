import 'dart:convert';

import 'package:flutter_securechat/src/crypto/plaintext_padding.dart';
import 'package:flutter_securechat/src/media/peer_capabilities.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sifreli mesaj uzunlugu duz metnin boyutunu ele vermemeli.
void main() {
  int bytes(String value) => utf8.encode(value).length;

  test('short messages of different length share one bucket', () {
    final sizes = {
      for (final text in ['evet', 'tamam, aksam gorusuruz', 'x' * 200])
        bytes(padPlaintext(text)),
    };
    expect(sizes, {256});
  });

  test('buckets grow in 256 then 4096 byte steps', () {
    expect(bytes(padPlaintext('a' * 300)), 512);
    expect(bytes(padPlaintext('a' * 5000)), 8192);
    // Cok buyuk govdeler yalniz baslik alir.
    final large = 'a' * 70000;
    expect(bytes(padPlaintext(large)), lessThan(70000 + 32));
  });

  test('round trip keeps the exact text including multibyte characters', () {
    for (final text in [
      '',
      'Çağrı şifreli 🔐',
      'BLOBPTR:v1:{"id":"x"}',
      'a' * 4090,
      'ğ' * 3000,
    ]) {
      expect(unpadPlaintext(padPlaintext(text)), text);
    }
  });

  test('unpadded plaintext from an old sender passes through', () {
    expect(unpadPlaintext('CHATCTRL:v2:abc'), 'CHATCTRL:v2:abc');
  });

  test('tampered padding or header is refused', () {
    final padded = padPlaintext('merhaba');
    expect(
      () => unpadPlaintext('${padded.substring(0, padded.length - 1)}x'),
      throwsFormatException,
    );
    expect(() => unpadPlaintext('\u0000P1:999:kisa'), throwsFormatException);
    expect(() => unpadPlaintext('\u0000P1:abc:'), throwsFormatException);
    expect(() => unpadPlaintext('\u0000P1:-1:'), throwsFormatException);
  });

  test('this version advertises that it can read padded messages', () {
    expect(localPeerCapabilities, contains(plaintextPaddingCapability));
  });
}
