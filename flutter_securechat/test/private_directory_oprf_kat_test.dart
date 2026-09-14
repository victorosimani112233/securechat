import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_securechat/src/contacts/private_contact_discovery.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Flutter blind and unblind match the independent RSA-OPRF KAT',
    () async {
      final file = File(
        'server_hardened/tools/crypto-audit/vectors/'
        'oprf_cross_language_kat.json',
      );
      final bytes = await file.readAsBytes();
      expect(
        crypto.sha256.convert(bytes).toString(),
        '60a70404b766535c81f421c8528026ebd6a464168cdf0a7939b28a79ef7cdac9',
      );
      final vector = (jsonDecode(utf8.decode(bytes)) as Map)
          .cast<String, Object?>();
      String value(String name) => vector[name]! as String;

      final config = PrivateDirectoryConfig.parse({
        'version': value('protocolVersion'),
        'keyId': value('keyId'),
        'modulus': value('modulus'),
        'exponent': value('exponent'),
        'batchSize': 256,
      });
      final point = DirectoryOprfMath.fullDomainPoint(
        value('phoneHash'),
        config,
      );
      expect(_encode(point, config.modulusBytes), value('point'));

      final blind = DirectoryOprfMath.blindWithFactor(
        phoneHash: value('phoneHash'),
        config: config,
        factor: _decode(value('factor')),
      );
      expect(blind.encoded, value('blinded'));
      expect(
        DirectoryOprfMath.unblind(
          encoded: value('evaluated'),
          inverse: blind.inverse,
          config: config,
        ),
        value('token'),
      );
    },
  );

  test(
    'RSA blinding factors reject out-of-range samples without modulo bias',
    () async {
      final vector =
          (jsonDecode(
                    await File(
                      'server_hardened/tools/crypto-audit/vectors/'
                      'oprf_cross_language_kat.json',
                    ).readAsString(),
                  )
                  as Map)
              .cast<String, Object?>();
      final config = PrivateDirectoryConfig.parse({
        'version': vector['protocolVersion'],
        'keyId': vector['keyId'],
        'modulus': vector['modulus'],
        'exponent': vector['exponent'],
        'batchSize': 256,
      });
      expect(config.modulus.bitLength % 8, 0);
      var valid = BigInt.two;
      while (valid.gcd(config.modulus) != BigInt.one) {
        valid += BigInt.one;
      }
      final random = _ScriptedByteRandom([
        ..._toBytes(config.modulus, config.modulusBytes),
        ..._toBytes(valid, config.modulusBytes),
      ]);

      expect(
        DirectoryOprfMath.sampleGroupElement(config.modulus, random),
        valid,
      );
      expect(random.bytesRead, config.modulusBytes * 2);
    },
  );
}

BigInt _decode(String encoded) {
  final bytes = base64Url.decode(base64Url.normalize(encoded));
  var value = BigInt.zero;
  for (final byte in bytes) {
    value = (value << 8) | BigInt.from(byte);
  }
  return value;
}

String _encode(BigInt value, int width) {
  return base64UrlEncode(_toBytes(value, width)).replaceAll('=', '');
}

List<int> _toBytes(BigInt value, int width) {
  final bytes = List<int>.filled(width, 0);
  var remaining = value;
  for (var index = width - 1; index >= 0; index--) {
    bytes[index] = (remaining & BigInt.from(255)).toInt();
    remaining >>= 8;
  }
  expect(remaining, BigInt.zero);
  return bytes;
}

class _ScriptedByteRandom implements Random {
  _ScriptedByteRandom(this._bytes);

  final List<int> _bytes;
  int bytesRead = 0;

  @override
  int nextInt(int max) {
    expect(max, 256);
    if (bytesRead >= _bytes.length) {
      throw StateError('Scripted random input exhausted');
    }
    return _bytes[bytesRead++];
  }

  @override
  bool nextBool() => nextInt(256).isOdd;

  @override
  double nextDouble() => nextInt(256) / 256;
}
