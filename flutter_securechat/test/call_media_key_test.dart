import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_securechat/src/media/call_media_key.dart';

/// Cagri medya anahtarinin uretimi, wire bicimi ve kusak semantigi.
///
/// Anahtar sunucudan gecmez; her katilimciya direct Signal zarfi icinde
/// gider. Bu testler bicimi ve fail-closed ayristirmayi sabitler.
void main() {
  group('CallMediaKey', () {
    test('generates a 32 byte key that differs every time', () {
      final first = CallMediaKey.generate(callId: 'call-1');
      final second = CallMediaKey.generate(callId: 'call-1');

      expect(first.key.length, CallMediaKey.keyLengthBytes);
      expect(second.key.length, CallMediaKey.keyLengthBytes);
      expect(base64Encode(first.key), isNot(base64Encode(second.key)));
      expect(first.epoch, 0);
    });

    test('round trips through the wire format', () {
      final key = CallMediaKey.generate(callId: 'call-42', epoch: 3);

      final parsed = CallMediaKey.tryParse(key.encode());

      expect(parsed, isNotNull);
      expect(parsed, key);
      expect(parsed!.epoch, 3);
      expect(parsed.callId, 'call-42');
    });

    test('rotation produces a new key on the next epoch', () {
      final first = CallMediaKey.generate(callId: 'call-1');
      final second = first.rotate();

      expect(second.epoch, first.epoch + 1);
      expect(second.callId, first.callId);
      // Yeni uye onceki frame'leri, ayrilan uye sonraki frame'leri
      // cozememeli: kusak artarken anahtar da degismeli.
      expect(base64Encode(second.key), isNot(base64Encode(first.key)));
    });

    test('the key index wraps inside the frame cryptor key ring', () {
      final key = CallMediaKey(
        callId: 'call-1',
        epoch: CallMediaKey.keyRingSize + 2,
        key: Uint8List(CallMediaKey.keyLengthBytes),
      );

      expect(key.keyIndex, 2);
      expect(key.keyIndex, lessThan(CallMediaKey.keyRingSize));
    });

    test('a key minted for another call is refused', () {
      final key = CallMediaKey.generate(callId: 'other-call');

      expect(
        CallMediaKey.tryParse(key.encode(), expectedCallId: 'my-call'),
        isNull,
      );
      expect(
        CallMediaKey.tryParse(key.encode(), expectedCallId: 'other-call'),
        isNotNull,
      );
    });

    test('a call id containing separators still round trips', () {
      final key = CallMediaKey.generate(callId: 'group:abc:123', epoch: 7);

      final parsed = CallMediaKey.tryParse(key.encode());

      expect(parsed?.callId, 'group:abc:123');
      expect(parsed?.epoch, 7);
    });

    test('malformed payloads are refused instead of throwing', () {
      final candidates = <String>[
        '',
        'CALLKEY:v1',
        'CALLKEY:v1:call:notanumber:${base64Encode(Uint8List(32))}',
        'CALLKEY:v1:call:0:!!!not-base64!!!',
        // Yanlis uzunlukta anahtar sessizce kabul edilmemeli.
        'CALLKEY:v1:call:0:${base64Encode(Uint8List(16))}',
        'CALLKEY:v2:call:0:${base64Encode(Uint8List(32))}',
        'MSGID:something-else',
      ];

      for (final candidate in candidates) {
        expect(
          CallMediaKey.tryParse(candidate),
          isNull,
          reason: 'kabul edilmemeliydi: $candidate',
        );
      }
    });

    test('a negative epoch is refused', () {
      expect(
        CallMediaKey.tryParse(
          'CALLKEY:v1:call:-1:${base64Encode(Uint8List(32))}',
        ),
        isNull,
      );
    });
  });
}
