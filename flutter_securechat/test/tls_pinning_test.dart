import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_securechat/src/config/app_config.dart';
import 'package:flutter_securechat/src/network/tls_pinning.dart';

void main() {
  test('SPKI extraction pins public key rather than full certificate', () {
    final first = _certificate([1, 2, 3, 4], serial: 1);
    final renewed = _certificate([1, 2, 3, 4], serial: 2);
    final otherKey = _certificate([9, 8, 7], serial: 3);
    final pin = base64Encode(
      sha256.convert(extractSubjectPublicKeyInfo(first)).bytes,
    );
    final backup = base64Encode(
      sha256.convert(extractSubjectPublicKeyInfo(otherKey)).bytes,
    );
    final policy = TlsPinPolicy({
      'secure.example': [pin, backup],
    });

    expect(policy.verifyDer('secure.example', first), isTrue);
    expect(policy.verifyDer('secure.example', renewed), isTrue);
    expect(policy.verifyDer('secure.example', otherKey), isTrue);
    expect(
      policy.verifyDer('secure.example', _certificate([5], serial: 4)),
      isFalse,
    );
    expect(policy.verifyDer('unrelated.example', otherKey), isTrue);
  });

  test('TLS configuration fails fast without host and backup pin', () {
    expect(
      () => const AppConfig(
        apiBaseUrl: 'https://api.example',
        signalingUrl: 'wss://api.example',
        certificatePinHost: '',
        certificatePins: [],
      ).validateNetworkSecurity(),
      throwsStateError,
    );
    expect(
      () => const AppConfig(
        apiBaseUrl: 'https://api.example',
        signalingUrl: 'wss://api.example',
        certificatePinHost: 'api.example',
        certificatePins: ['primary-only'],
      ).validateNetworkSecurity(),
      throwsStateError,
    );
    expect(
      () => const AppConfig(
        apiBaseUrl: 'https://api.example',
        signalingUrl: 'wss://socket.example',
        certificatePinHost: 'api.example',
        certificatePins: ['primary', 'backup'],
      ).validateNetworkSecurity(),
      throwsStateError,
    );
  });

  test('malformed certificate DER is rejected', () {
    expect(
      () => extractSubjectPublicKeyInfo(Uint8List.fromList([0x30, 0x7f])),
      throwsFormatException,
    );
  });

  test('secure HTTP client factory owns and closes every created client', () {
    final factory = SecureHttpClientFactory(
      TlsPinPolicy({
        'secure.example': ['primary', 'backup'],
      }),
    );

    factory.create();
    factory.create();
    expect(factory.activeClientCount, 2);

    factory.close();
    factory.close();
    expect(factory.isClosed, isTrue);
    expect(factory.activeClientCount, 0);
    expect(factory.create, throwsStateError);
  });
}

Uint8List _certificate(List<int> key, {required int serial}) {
  final spki = _sequence([
    _sequence([
      _element(0x06, [0x2a, 0x03]),
    ]),
    _element(0x03, [0, ...key]),
  ]);
  final tbs = _sequence([
    _element(0xa0, _element(0x02, [2])),
    _element(0x02, [serial]),
    _sequence(const []),
    _sequence(const []),
    _sequence(const []),
    _sequence(const []),
    spki,
  ]);
  return Uint8List.fromList(
    _sequence([
      tbs,
      _sequence(const []),
      _element(0x03, const [0]),
    ]),
  );
}

List<int> _sequence(List<List<int>> children) =>
    _element(0x30, children.expand((value) => value).toList());

List<int> _element(int tag, List<int> content) {
  if (content.length >= 128) throw ArgumentError('test DER is too large');
  return [tag, content.length, ...content];
}
