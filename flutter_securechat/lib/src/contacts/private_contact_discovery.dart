import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

import 'contact_discovery_api.dart';

const _protocolVersion = 'elcim-directory-oprf-v1';
const _authenticatedBatchSize = 256;
const _maximumCandidatesPerDiscovery = 8192;
const _minimumRsaBits = 3072;
const _gcmNonceBytes = 12;
const _gcmTagBytes = 16;
const _maximumConfigBytes = 16 * 1024;
const _maximumEvaluateBytes = 512 * 1024;
const _maximumSnapshotBytes = 32 * 1024 * 1024;

final _phoneHashPattern = RegExp(r'^[0-9a-f]{64}$');
final _userIdPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);
final _phoneInputDomain = ascii.encode('elcim-directory-phone-v1\x00');
final _tokenDomain = ascii.encode('elcim-directory-token-v1\x00');
final _labelDomain = ascii.encode('elcim-directory-label-v1\x00');
final _entryKeyDomain = ascii.encode('elcim-directory-entry-key-v1\x00');
final _entryAadDomain = ascii.encode('elcim-directory-entry-aad-v1\x00');

class PrivateDirectoryException implements Exception {
  const PrivateDirectoryException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'PrivateDirectoryException: $message';
}

/// The configured server cannot currently provide the private-directory
/// protocol. Callers must keep cached local matches and must never fall back to
/// sending phone numbers or deterministic phone hashes to a legacy endpoint.
class DirectoryServiceUnavailableException extends PrivateDirectoryException {
  const DirectoryServiceUnavailableException({int? statusCode})
    : super(
        'The private directory service is unavailable; insecure fallback was not used.',
        statusCode: statusCode,
      );

  bool get protocolRouteMissing =>
      statusCode == HttpStatus.notFound ||
      statusCode == HttpStatus.notImplemented;
}

class DirectoryKeyChangedException extends PrivateDirectoryException {
  const DirectoryKeyChangedException()
    : super('Private directory key changed; retry with the new key.');
}

class DirectoryOwnershipException extends PrivateDirectoryException {
  const DirectoryOwnershipException()
    : super('The local phone identity is assigned to another account.');
}

class PrivateDirectoryConfig {
  PrivateDirectoryConfig._({
    required this.version,
    required this.keyId,
    required this.modulus,
    required this.exponent,
    required this.modulusBytes,
    required this.batchSize,
  });

  final String version;
  final String keyId;
  final BigInt modulus;
  final BigInt exponent;
  final int modulusBytes;
  final int batchSize;

  static PrivateDirectoryConfig parse(Map<String, Object?> json) {
    final version = json['version'] as String? ?? '';
    final keyId = json['keyId'] as String? ?? '';
    final modulusEncoded = json['modulus'] as String? ?? '';
    final exponentEncoded = json['exponent'] as String? ?? '';
    final batchSize = (json['batchSize'] as num?)?.toInt() ?? 0;
    if (version != _protocolVersion || batchSize != _authenticatedBatchSize) {
      throw const PrivateDirectoryException(
        'Unsupported private directory protocol configuration.',
      );
    }
    final modulusBytes = _decodeBase64Url(modulusEncoded);
    final exponentBytes = _decodeBase64Url(exponentEncoded);
    final modulus = _bytesToBigInt(modulusBytes);
    final exponent = _bytesToBigInt(exponentBytes);
    if (modulus.bitLength < _minimumRsaBits ||
        modulus.isEven ||
        exponent != BigInt.from(65537)) {
      throw const PrivateDirectoryException(
        'Private directory RSA parameters do not meet the security policy.',
      );
    }
    final expectedKeyId = _base64UrlNoPadding(
      crypto.sha256
          .convert(_rsaSubjectPublicKeyInfo(modulusBytes, exponentBytes))
          .bytes,
    );
    if (keyId.isEmpty || !_constantTimeStringEquals(expectedKeyId, keyId)) {
      throw const PrivateDirectoryException(
        'Private directory public key identifier is invalid.',
      );
    }
    return PrivateDirectoryConfig._(
      version: version,
      keyId: keyId,
      modulus: modulus,
      exponent: exponent,
      modulusBytes: modulusBytes.length,
      batchSize: batchSize,
    );
  }
}

/// Authenticated blind-RSA private-set discovery client.
///
/// Phone hashes remain local. Each request contains exactly 256 randomized RSA
/// group values and the downloaded snapshot contains only token-derived labels
/// plus token-bound AEAD envelopes. The server can observe request timing and
/// the number of 256-entry batches, but cannot read the address-book inputs or
/// persist a caller-to-contact social graph through this protocol.
class PrivateContactDiscoveryApi implements ContactDiscoveryApi {
  PrivateContactDiscoveryApi({
    required String baseUrl,
    required HttpClient client,
    Random? random,
  }) : _base = Uri.parse(baseUrl),
       _client = client,
       _random = random ?? Random.secure();

  final Uri _base;
  final HttpClient _client;
  final Random _random;
  final AesGcm _aead = AesGcm.with256bits();
  PrivateDirectoryConfig? _cachedConfig;

  @override
  Future<List<RegisteredUserMatch>> checkUsers(
    List<String> phoneHashes,
    String accessToken, {
    String? ownPhoneHash,
    String? ownUserId,
  }) async {
    if (accessToken.isEmpty) {
      throw const PrivateDirectoryException('Authentication is required.');
    }
    final requested = _validatedUniqueHashes(phoneHashes);
    final normalizedOwnHash = ownPhoneHash?.toLowerCase();
    if (normalizedOwnHash != null &&
        !_phoneHashPattern.hasMatch(normalizedOwnHash)) {
      throw const PrivateDirectoryException('Invalid own phone hash.');
    }
    if (ownUserId != null && !_userIdPattern.hasMatch(ownUserId)) {
      throw const PrivateDirectoryException('Invalid authenticated user id.');
    }
    final candidates = <String>{...requested};
    if (normalizedOwnHash != null && ownUserId != null) {
      candidates.add(normalizedOwnHash);
    }
    if (candidates.isEmpty) return const [];
    if (candidates.length > _maximumCandidatesPerDiscovery) {
      throw const PrivateDirectoryException(
        'Private discovery candidate limit exceeded.',
      );
    }

    var config = await _loadConfig();
    late Map<String, String> tokensByHash;
    try {
      tokensByHash = await _evaluateCandidates(
        candidates.toList(growable: false),
        accessToken,
        config,
      );
    } on DirectoryKeyChangedException {
      _cachedConfig = null;
      config = await _loadConfig();
      tokensByHash = await _evaluateCandidates(
        candidates.toList(growable: false),
        accessToken,
        config,
      );
    }

    var snapshot = await _loadSnapshot(accessToken, config);
    var resolved = await _resolveSnapshot(tokensByHash, snapshot, config);
    if (normalizedOwnHash != null && ownUserId != null) {
      final currentOwner = resolved[normalizedOwnHash];
      if (currentOwner != null && currentOwner != ownUserId) {
        throw const DirectoryOwnershipException();
      }
      if (currentOwner == null) {
        await _updateOwnDirectory(
          phoneHash: normalizedOwnHash,
          accessToken: accessToken,
          expectedKeyId: config.keyId,
        );
        snapshot = await _loadSnapshot(accessToken, config);
        resolved = await _resolveSnapshot(tokensByHash, snapshot, config);
        if (resolved[normalizedOwnHash] != ownUserId) {
          throw const DirectoryOwnershipException();
        }
      }
    }

    return requested
        .map(
          (hash) => resolved[hash] == null
              ? null
              : RegisteredUserMatch(userId: resolved[hash]!, phoneHash: hash),
        )
        .whereType<RegisteredUserMatch>()
        .toList(growable: false);
  }

  Future<PrivateDirectoryConfig> _loadConfig() async {
    final cached = _cachedConfig;
    if (cached != null) return cached;
    late final _JsonResponse response;
    try {
      response = await _requestJson(
        method: 'GET',
        path: '/api/v1/directory/config',
        maximumBytes: _maximumConfigBytes,
      );
    } on SocketException {
      throw const DirectoryServiceUnavailableException();
    } on HandshakeException {
      throw const DirectoryServiceUnavailableException();
    } on TimeoutException {
      throw const DirectoryServiceUnavailableException();
    }
    if (response.statusCode == HttpStatus.notFound ||
        response.statusCode == HttpStatus.notImplemented ||
        response.statusCode == HttpStatus.badGateway ||
        response.statusCode == HttpStatus.serviceUnavailable ||
        response.statusCode == HttpStatus.gatewayTimeout) {
      throw DirectoryServiceUnavailableException(
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode != HttpStatus.ok) {
      throw PrivateDirectoryException(
        'Private directory configuration failed.',
        statusCode: response.statusCode,
      );
    }
    final config = PrivateDirectoryConfig.parse(response.json);
    _cachedConfig = config;
    return config;
  }

  Future<Map<String, String>> _evaluateCandidates(
    List<String> hashes,
    String accessToken,
    PrivateDirectoryConfig config,
  ) async {
    final result = <String, String>{};
    for (var offset = 0; offset < hashes.length; offset += config.batchSize) {
      final end = min(offset + config.batchSize, hashes.length);
      final records = <_BlindRecord>[
        for (final hash in hashes.sublist(offset, end)) _blind(hash, config),
      ];
      while (records.length < config.batchSize) {
        records.add(
          _BlindRecord(
            phoneHash: null,
            encoded: _base64UrlNoPadding(
              _bigIntToBytes(
                _randomGroupElement(config.modulus),
                config.modulusBytes,
              ),
            ),
            inverse: null,
          ),
        );
      }
      records.shuffle(_random);
      final response = await _requestJson(
        method: 'POST',
        path: '/api/v1/directory/evaluate',
        bearerToken: accessToken,
        body: {
          'keyId': config.keyId,
          'blinded': records.map((record) => record.encoded).toList(),
        },
        maximumBytes: _maximumEvaluateBytes,
      );
      if (response.statusCode == HttpStatus.conflict) {
        throw const DirectoryKeyChangedException();
      }
      if (response.statusCode != HttpStatus.ok) {
        throw PrivateDirectoryException(
          'Private directory evaluation failed.',
          statusCode: response.statusCode,
        );
      }
      if (response.json['keyId'] != config.keyId) {
        throw const PrivateDirectoryException(
          'Private directory evaluation key mismatch.',
        );
      }
      final evaluated = response.json['evaluated'];
      if (evaluated is! List || evaluated.length != config.batchSize) {
        throw const PrivateDirectoryException(
          'Private directory returned an invalid batch.',
        );
      }
      for (var index = 0; index < records.length; index++) {
        final record = records[index];
        if (record.phoneHash == null) continue;
        final encoded = evaluated[index];
        if (encoded is! String) {
          throw const PrivateDirectoryException(
            'Private directory returned a malformed group value.',
          );
        }
        result[record.phoneHash!] = _unblind(encoded, record.inverse!, config);
      }
    }
    return result;
  }

  _BlindRecord _blind(String phoneHash, PrivateDirectoryConfig config) {
    final point = _fullDomainPoint(phoneHash, config);
    final factor = _randomGroupElement(config.modulus);
    final blinded =
        (point * factor.modPow(config.exponent, config.modulus)) %
        config.modulus;
    return _BlindRecord(
      phoneHash: phoneHash,
      encoded: _base64UrlNoPadding(
        _bigIntToBytes(blinded, config.modulusBytes),
      ),
      inverse: factor.modInverse(config.modulus),
    );
  }

  String _unblind(
    String encoded,
    BigInt inverse,
    PrivateDirectoryConfig config,
  ) {
    final bytes = _decodeBase64Url(encoded);
    if (bytes.length != config.modulusBytes) {
      throw const PrivateDirectoryException(
        'Private directory group value has an invalid width.',
      );
    }
    final evaluated = _bytesToBigInt(bytes);
    if (evaluated <= BigInt.one ||
        evaluated >= config.modulus ||
        evaluated.gcd(config.modulus) != BigInt.one) {
      throw const PrivateDirectoryException(
        'Private directory group value is outside the RSA group.',
      );
    }
    final unblinded = (evaluated * inverse) % config.modulus;
    return _base64UrlNoPadding(
      crypto.sha256.convert([
        ..._tokenDomain,
        ..._bigIntToBytes(unblinded, config.modulusBytes),
      ]).bytes,
    );
  }

  Future<List<_SnapshotEntry>> _loadSnapshot(
    String accessToken,
    PrivateDirectoryConfig config,
  ) async {
    final response = await _requestJson(
      method: 'GET',
      path: '/api/v1/directory/snapshot',
      bearerToken: accessToken,
      maximumBytes: _maximumSnapshotBytes,
    );
    if (response.statusCode != HttpStatus.ok) {
      throw PrivateDirectoryException(
        'Private directory snapshot failed.',
        statusCode: response.statusCode,
      );
    }
    if (response.json['keyId'] != config.keyId) {
      _cachedConfig = null;
      throw const DirectoryKeyChangedException();
    }
    final rawEntries = response.json['entries'];
    if (rawEntries is! List) {
      throw const PrivateDirectoryException('Invalid directory snapshot.');
    }
    final labels = <String>{};
    final entries = <_SnapshotEntry>[];
    for (final item in rawEntries) {
      if (item is! Map) {
        throw const PrivateDirectoryException('Invalid directory entry.');
      }
      final entry = item.cast<String, Object?>();
      final label = entry['label'] as String? ?? '';
      final sealedUserId = entry['sealedUserId'] as String? ?? '';
      final labelBytes = _decodeBase64Url(label);
      final envelopeBytes = _decodeBase64Url(sealedUserId);
      if (labelBytes.length != 32 ||
          envelopeBytes.length < _gcmNonceBytes + _gcmTagBytes ||
          !labels.add(label)) {
        throw const PrivateDirectoryException(
          'Directory snapshot contains a malformed or duplicate entry.',
        );
      }
      entries.add(_SnapshotEntry(label, sealedUserId));
    }
    return entries;
  }

  Future<Map<String, String>> _resolveSnapshot(
    Map<String, String> tokensByHash,
    List<_SnapshotEntry> snapshot,
    PrivateDirectoryConfig config,
  ) async {
    final byLabel = {for (final entry in snapshot) entry.label: entry};
    final resolved = <String, String>{};
    for (final tokenEntry in tokensByHash.entries) {
      final token = _decodeBase64Url(tokenEntry.value);
      if (token.length != 32) {
        throw const PrivateDirectoryException('Invalid directory token.');
      }
      final label = _base64UrlNoPadding(
        crypto.sha256.convert([..._labelDomain, ...token]).bytes,
      );
      final entry = byLabel[label];
      if (entry == null) continue;
      final key = crypto.sha256.convert([..._entryKeyDomain, ...token]).bytes;
      final envelope = _decodeBase64Url(entry.sealedUserId);
      final nonce = envelope.sublist(0, _gcmNonceBytes);
      final cipherAndTag = envelope.sublist(_gcmNonceBytes);
      final cipherText = cipherAndTag.sublist(
        0,
        cipherAndTag.length - _gcmTagBytes,
      );
      final mac = cipherAndTag.sublist(cipherAndTag.length - _gcmTagBytes);
      final aad = [
        ..._entryAadDomain,
        ...ascii.encode(config.keyId),
        0,
        ...ascii.encode(label),
      ];
      late final List<int> plaintext;
      try {
        plaintext = await _aead.decrypt(
          SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
          secretKey: SecretKey(key),
          aad: aad,
        );
      } on SecretBoxAuthenticationError {
        throw const PrivateDirectoryException(
          'Directory snapshot authentication failed.',
        );
      }
      final userId = utf8.decode(plaintext, allowMalformed: false);
      if (!_userIdPattern.hasMatch(userId)) {
        throw const PrivateDirectoryException(
          'Directory snapshot contains an invalid user id.',
        );
      }
      resolved[tokenEntry.key] = userId;
    }
    return resolved;
  }

  Future<void> _updateOwnDirectory({
    required String phoneHash,
    required String accessToken,
    required String expectedKeyId,
  }) async {
    final response = await _requestJson(
      method: 'POST',
      path: '/api/v1/users/directory-token',
      bearerToken: accessToken,
      body: {'phoneHash': phoneHash},
      maximumBytes: _maximumConfigBytes,
    );
    if (response.statusCode != HttpStatus.ok) {
      throw PrivateDirectoryException(
        'Private directory enrollment failed.',
        statusCode: response.statusCode,
      );
    }
    if (response.json['keyId'] != expectedKeyId) {
      _cachedConfig = null;
      throw const DirectoryKeyChangedException();
    }
  }

  Future<_JsonResponse> _requestJson({
    required String method,
    required String path,
    required int maximumBytes,
    String? bearerToken,
    Object? body,
  }) async {
    final request = await _client
        .openUrl(method, _base.resolve(path))
        .timeout(const Duration(seconds: 15));
    request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
    if (bearerToken != null) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $bearerToken',
      );
    }
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close().timeout(const Duration(seconds: 30));
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 30))) {
      bytes.addAll(chunk);
      if (bytes.length > maximumBytes) {
        throw const PrivateDirectoryException(
          'Private directory response exceeds the local safety limit.',
        );
      }
    }
    Map<String, Object?> json = const {};
    if (bytes.isNotEmpty) {
      final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
      if (decoded is! Map) {
        throw const PrivateDirectoryException(
          'Private directory response is not a JSON object.',
        );
      }
      json = decoded.cast<String, Object?>();
    }
    return _JsonResponse(response.statusCode, json);
  }

  List<String> _validatedUniqueHashes(List<String> hashes) {
    final result = <String>{};
    for (final value in hashes) {
      final normalized = value.toLowerCase();
      if (!_phoneHashPattern.hasMatch(normalized)) {
        throw const PrivateDirectoryException('Invalid contact phone hash.');
      }
      result.add(normalized);
    }
    return result.toList(growable: false);
  }

  BigInt _fullDomainPoint(String phoneHash, PrivateDirectoryConfig config) {
    for (var attempt = 0; attempt <= 255; attempt++) {
      final seed = crypto.sha256.convert([
        ..._phoneInputDomain,
        ...ascii.encode(phoneHash),
        ..._int32(attempt),
      ]).bytes;
      final expanded = <int>[];
      var counter = 0;
      while (expanded.length < config.modulusBytes + 16) {
        expanded.addAll(
          crypto.sha256.convert([...seed, ..._int32(counter++)]).bytes,
        );
      }
      final candidate =
          (_bytesToBigInt(expanded) % (config.modulus - BigInt.one)) +
          BigInt.one;
      if (candidate > BigInt.one &&
          candidate.gcd(config.modulus) == BigInt.one) {
        return candidate;
      }
    }
    throw const PrivateDirectoryException(
      'Could not map contact identity into the RSA group.',
    );
  }

  BigInt _randomGroupElement(BigInt modulus) {
    final width = (modulus.bitLength + 7) ~/ 8;
    while (true) {
      final bytes = List<int>.generate(width, (_) => _random.nextInt(256));
      final candidate =
          (_bytesToBigInt(bytes) % (modulus - BigInt.from(3))) + BigInt.two;
      if (candidate < modulus && candidate.gcd(modulus) == BigInt.one) {
        return candidate;
      }
    }
  }
}

class _BlindRecord {
  const _BlindRecord({
    required this.phoneHash,
    required this.encoded,
    required this.inverse,
  });

  final String? phoneHash;
  final String encoded;
  final BigInt? inverse;
}

class _SnapshotEntry {
  const _SnapshotEntry(this.label, this.sealedUserId);

  final String label;
  final String sealedUserId;
}

class _JsonResponse {
  const _JsonResponse(this.statusCode, this.json);

  final int statusCode;
  final Map<String, Object?> json;
}

BigInt _bytesToBigInt(List<int> bytes) {
  var value = BigInt.zero;
  for (final byte in bytes) {
    value = (value << 8) | BigInt.from(byte);
  }
  return value;
}

Uint8List _bigIntToBytes(BigInt value, int width) {
  if (value.isNegative) {
    throw const PrivateDirectoryException('Negative RSA group value.');
  }
  final output = Uint8List(width);
  var remaining = value;
  for (var index = width - 1; index >= 0; index--) {
    output[index] = (remaining & BigInt.from(255)).toInt();
    remaining >>= 8;
  }
  if (remaining != BigInt.zero) {
    throw const PrivateDirectoryException('RSA group value exceeds its width.');
  }
  return output;
}

Uint8List _decodeBase64Url(String value) {
  try {
    return Uint8List.fromList(base64Url.decode(base64Url.normalize(value)));
  } on FormatException {
    throw const PrivateDirectoryException('Invalid base64url value.');
  }
}

String _base64UrlNoPadding(List<int> value) =>
    base64UrlEncode(value).replaceAll('=', '');

Uint8List _int32(int value) {
  final bytes = ByteData(4)..setUint32(0, value, Endian.big);
  return bytes.buffer.asUint8List();
}

bool _constantTimeStringEquals(String left, String right) {
  final leftBytes = ascii.encode(left);
  final rightBytes = ascii.encode(right);
  var difference = leftBytes.length ^ rightBytes.length;
  final length = max(leftBytes.length, rightBytes.length);
  for (var index = 0; index < length; index++) {
    final a = index < leftBytes.length ? leftBytes[index] : 0;
    final b = index < rightBytes.length ? rightBytes[index] : 0;
    difference |= a ^ b;
  }
  return difference == 0;
}

List<int> _rsaSubjectPublicKeyInfo(
  List<int> modulusBytes,
  List<int> exponentBytes,
) {
  final rsaPublicKey = _derSequence([
    ..._derInteger(modulusBytes),
    ..._derInteger(exponentBytes),
  ]);
  const rsaEncryptionAlgorithm = <int>[
    0x30,
    0x0d,
    0x06,
    0x09,
    0x2a,
    0x86,
    0x48,
    0x86,
    0xf7,
    0x0d,
    0x01,
    0x01,
    0x01,
    0x05,
    0x00,
  ];
  return _derSequence([
    ...rsaEncryptionAlgorithm,
    ..._derElement(0x03, [0, ...rsaPublicKey]),
  ]);
}

List<int> _derInteger(List<int> bytes) {
  var firstNonZero = 0;
  while (firstNonZero < bytes.length - 1 && bytes[firstNonZero] == 0) {
    firstNonZero++;
  }
  final unsigned = bytes.sublist(firstNonZero);
  final content = unsigned.first & 0x80 == 0 ? unsigned : [0, ...unsigned];
  return _derElement(0x02, content);
}

List<int> _derSequence(List<int> content) => _derElement(0x30, content);

List<int> _derElement(int tag, List<int> content) => [
  tag,
  ..._derLength(content.length),
  ...content,
];

List<int> _derLength(int length) {
  if (length < 0x80) return [length];
  final bytes = <int>[];
  var remaining = length;
  while (remaining > 0) {
    bytes.insert(0, remaining & 0xff);
    remaining >>= 8;
  }
  return [0x80 | bytes.length, ...bytes];
}
