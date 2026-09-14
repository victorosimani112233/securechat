// Private contact discovery (blind-RSA OPRF) mock modülü.
//
// Uygulamanın `lib/src/contacts/private_contact_discovery.dart` içindeki
// istemci tarafıyla bire bir uyumludur: aynı domain separator'lar, aynı
// full-domain hash, aynı token/label/AEAD türetimi.

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

const protocolVersion = 'elcim-directory-oprf-v1';
const authenticatedBatchSize = 256;

final _phoneInputDomain = ascii.encode('elcim-directory-phone-v1\x00');
final _tokenDomain = ascii.encode('elcim-directory-token-v1\x00');
final _labelDomain = ascii.encode('elcim-directory-label-v1\x00');
final _entryKeyDomain = ascii.encode('elcim-directory-entry-key-v1\x00');
final _entryAadDomain = ascii.encode('elcim-directory-entry-aad-v1\x00');

/// Dizinde kayıtlı bir kullanıcı: telefon hash'i -> UUID.
class DirectoryUser {
  const DirectoryUser({required this.userId, required this.phoneHash});
  final String userId;
  final String phoneHash;
}

class DirectoryModule {
  DirectoryModule._({
    required this.modulus,
    required this.privateExponent,
    required this.modulusBytes,
    required this.keyId,
    required this.modulusEncoded,
    required this.exponentEncoded,
  });

  final BigInt modulus;
  final BigInt privateExponent;
  final int modulusBytes;
  final String keyId;
  final String modulusEncoded;
  final String exponentEncoded;

  static final publicExponent = BigInt.from(65537);
  final AesGcm _aead = AesGcm.with256bits();
  final Map<String, DirectoryUser> users = {};

  static DirectoryModule load(String jsonPath) {
    final json =
        (jsonDecode(File(jsonPath).readAsStringSync()) as Map)
            .cast<String, Object?>();
    final modulusBytes = _hexToBytes(json['n'] as String);
    final exponentBytes = _bigIntToBytes(publicExponent, 3);
    final modulus = _bytesToBigInt(modulusBytes);
    final keyId = _b64url(
      crypto.sha256
          .convert(_rsaSubjectPublicKeyInfo(modulusBytes, exponentBytes))
          .bytes,
    );
    return DirectoryModule._(
      modulus: modulus,
      privateExponent: _bytesToBigInt(_hexToBytes(json['d'] as String)),
      modulusBytes: modulusBytes.length,
      keyId: keyId,
      modulusEncoded: _b64url(modulusBytes),
      exponentEncoded: _b64url(exponentBytes),
    );
  }

  Map<String, Object?> configJson() => {
    'version': protocolVersion,
    'keyId': keyId,
    'modulus': modulusEncoded,
    'exponent': exponentEncoded,
    'batchSize': authenticatedBatchSize,
  };

  /// Kör imza: her grup elemanını özel üsle değerlendirir.
  Map<String, Object?> evaluate(Map<String, Object?> body) {
    if (body['keyId'] != keyId) {
      return {'__status': HttpStatus.conflict, 'error': 'key changed'};
    }
    final blinded = body['blinded'];
    if (blinded is! List || blinded.length != authenticatedBatchSize) {
      return {'__status': HttpStatus.badRequest, 'error': 'bad batch'};
    }
    final evaluated = <String>[];
    for (final item in blinded) {
      final value = _bytesToBigInt(_b64urlDecode('$item'));
      final signed = value.modPow(privateExponent, modulus);
      evaluated.add(_b64url(_bigIntToBytes(signed, modulusBytes)));
    }
    return {'keyId': keyId, 'evaluated': evaluated};
  }

  /// Kayıtlı her kullanıcı için token'a bağlı etiket + AEAD zarfı üretir.
  Future<Map<String, Object?>> snapshot() async {
    final entries = <Map<String, Object?>>[];
    for (final user in users.values) {
      final token = _tokenFor(user.phoneHash);
      final label = _b64url(
        crypto.sha256.convert([..._labelDomain, ...token]).bytes,
      );
      final key = crypto.sha256.convert([..._entryKeyDomain, ...token]).bytes;
      final aad = <int>[
        ..._entryAadDomain,
        ...ascii.encode(keyId),
        0,
        ...ascii.encode(label),
      ];
      final nonce = List<int>.generate(12, (_) => _random.nextInt(256));
      final box = await _aead.encrypt(
        utf8.encode(user.userId),
        secretKey: SecretKey(key),
        nonce: nonce,
        aad: aad,
      );
      entries.add({
        'label': label,
        'sealedUserId': _b64url([...nonce, ...box.cipherText, ...box.mac.bytes]),
      });
    }
    return {'keyId': keyId, 'entries': entries};
  }

  /// Sunucu tarafı OPRF: point(phoneHash)^d mod n -> token.
  List<int> _tokenFor(String phoneHash) {
    final point = fullDomainPoint(phoneHash);
    final signed = point.modPow(privateExponent, modulus);
    return crypto.sha256
        .convert([..._tokenDomain, ..._bigIntToBytes(signed, modulusBytes)])
        .bytes;
  }

  /// İstemcideki `_fullDomainPoint` ile birebir aynı olmak zorunda.
  BigInt fullDomainPoint(String phoneHash) {
    for (var attempt = 0; attempt <= 255; attempt++) {
      final seed = crypto.sha256.convert([
        ..._phoneInputDomain,
        ...ascii.encode(phoneHash),
        ..._int32(attempt),
      ]).bytes;
      final expanded = <int>[];
      var counter = 0;
      while (expanded.length < modulusBytes + 16) {
        expanded.addAll(
          crypto.sha256.convert([...seed, ..._int32(counter++)]).bytes,
        );
      }
      final candidate =
          (_bytesToBigInt(Uint8List.fromList(expanded)) %
              (modulus - BigInt.one)) +
          BigInt.one;
      if (candidate > BigInt.one && candidate.gcd(modulus) == BigInt.one) {
        return candidate;
      }
    }
    throw StateError('could not map phone hash into RSA group');
  }
}

final _random = Random.secure();

// --- kodlama yardımcıları (istemciyle aynı davranış) ---

String _b64url(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

Uint8List _b64urlDecode(String value) {
  final padded = value.padRight((value.length + 3) ~/ 4 * 4, '=');
  return Uint8List.fromList(base64Url.decode(padded));
}

Uint8List _hexToBytes(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

BigInt _bytesToBigInt(Uint8List bytes) {
  var result = BigInt.zero;
  for (final byte in bytes) {
    result = (result << 8) | BigInt.from(byte);
  }
  return result;
}

Uint8List _bigIntToBytes(BigInt value, int width) {
  final out = Uint8List(width);
  var current = value;
  for (var i = width - 1; i >= 0; i--) {
    out[i] = (current & BigInt.from(0xff)).toInt();
    current = current >> 8;
  }
  return out;
}

List<int> _int32(int value) => [
  (value >> 24) & 0xff,
  (value >> 16) & 0xff,
  (value >> 8) & 0xff,
  value & 0xff,
];

List<int> _derLength(int length) {
  if (length < 0x80) return [length];
  final bytes = <int>[];
  var current = length;
  while (current > 0) {
    bytes.insert(0, current & 0xff);
    current >>= 8;
  }
  return [0x80 | bytes.length, ...bytes];
}

List<int> _derInteger(List<int> value) {
  var content = value;
  var index = 0;
  while (index < content.length - 1 && content[index] == 0) {
    index++;
  }
  content = content.sublist(index);
  if (content.isNotEmpty && (content.first & 0x80) != 0) {
    content = [0, ...content];
  }
  return [0x02, ..._derLength(content.length), ...content];
}

List<int> _derSequence(List<int> content) => [
  0x30,
  ..._derLength(content.length),
  ...content,
];

List<int> _derBitString(List<int> content) => [
  0x03,
  ..._derLength(content.length + 1),
  0,
  ...content,
];

List<int> _rsaSubjectPublicKeyInfo(
  List<int> modulusBytes,
  List<int> exponentBytes,
) {
  final rsaPublicKey = _derSequence([
    ..._derInteger(modulusBytes),
    ..._derInteger(exponentBytes),
  ]);
  const rsaEncryptionOid = [
    0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01,
  ];
  final algorithm = _derSequence([...rsaEncryptionOid, 0x05, 0x00]);
  return _derSequence([...algorithm, ..._derBitString(rsaPublicKey)]);
}
