import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/auth/phone_privacy.dart';
import 'package:flutter_securechat/src/contacts/private_contact_discovery.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'blind OPRF discovery sends fixed cover batch and opens only local matches',
    () async {
      final fixture = await _PrivateDirectoryFixture.start();
      addTearDown(fixture.close);
      final api = PrivateContactDiscoveryApi(
        baseUrl: fixture.baseUrl,
        client: HttpClient(),
        random: Random(9173),
      );
      final aliceHash = await hashPhoneNumber('+905551234567');
      final unknownHash = await hashPhoneNumber('+905550000000');
      final ownHash = await hashPhoneNumber('+905559999999');

      final matches = await api.checkUsers(
        [aliceHash, unknownHash],
        'access-token',
        ownPhoneHash: ownHash,
        ownUserId: _ownUserId,
      );

      expect(matches, hasLength(1));
      expect(matches.single.userId, _aliceUserId);
      expect(matches.single.phoneHash, aliceHash);
      expect(fixture.evaluateRequests, 1);
      expect(fixture.lastBlindedBatch, hasLength(256));
      expect(fixture.lastEvaluateAuthorization, 'Bearer access-token');
      expect(fixture.directoryUpdateBody, {'phoneHash': ownHash});
      expect(fixture.snapshotRequests, 2);
      expect(
        jsonEncode(fixture.lastBlindedBatch),
        isNot(
          anyOf(contains(aliceHash), contains(unknownHash), contains(ownHash)),
        ),
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'invalid directory key identifier fails closed before evaluation',
    () async {
      final fixture = await _PrivateDirectoryFixture.start(
        overrideKeyId: 'tampered-key-id',
      );
      addTearDown(fixture.close);
      final api = PrivateContactDiscoveryApi(
        baseUrl: fixture.baseUrl,
        client: HttpClient(),
        random: Random(4),
      );

      final phoneHash = await hashPhoneNumber('+905551234567');
      await expectLater(
        api.checkUsers([phoneHash], 'access-token'),
        throwsA(isA<PrivateDirectoryException>()),
      );
      expect(fixture.evaluateRequests, 0);
    },
  );

  test(
    'missing private-directory route is classified without fallback',
    () async {
      final fixture = await _PrivateDirectoryFixture.start(configMissing: true);
      addTearDown(fixture.close);
      final api = PrivateContactDiscoveryApi(
        baseUrl: fixture.baseUrl,
        client: HttpClient(),
        random: Random(9),
      );

      final phoneHash = await hashPhoneNumber('+905551234567');
      await expectLater(
        api.checkUsers([phoneHash], 'access-token'),
        throwsA(
          isA<DirectoryServiceUnavailableException>()
              .having((error) => error.statusCode, 'statusCode', 404)
              .having(
                (error) => error.protocolRouteMissing,
                'protocolRouteMissing',
                isTrue,
              ),
        ),
      );
      expect(fixture.evaluateRequests, 0);
      expect(fixture.snapshotRequests, 0);
    },
  );
}

const _aliceUserId = '123e4567-e89b-42d3-a456-426614174000';
const _ownUserId = '123e4567-e89b-42d3-a456-426614174001';
const _keyId = 'pAQTBRUi6bA5OuUPgZTrhWj6E0WI5AcjUXe5StNKSXo';
const _modulusHex =
    'abc4d4aadcc4d22e9f1b2064015439d849c212a7278529944feee70764d09f23914af5c3d825db6694fc0f19f8d13924fe1337f8b0c079ce52bea2c0ff560733da8d284dd06fe6ab473df07118dce68c521707d9ffa03a2da8d7c76d378805897be15bdad3a43e10342685fa64b64d19f563ae2979c9a4e818228be79cdf7bba4eca3fe7eb53b2297957a20b79106107eebc81ae98f8f19f21785ee78cb004d6414c335c9d99dcda6b8288889cbb61e8c8d3062c1f4a86282838b3c836898690cf7564b1964a6c735e2c17b70b073a4a40065a25008c48b730b20a1b9134857404036ff8511de60fdfd294d496bb4e77b00817ca8179b2146a3123fbc95740194e9f96579496d73fafe1532146f202f052c789eb8c6b867f3a809be8dfc0061ce46504796205abd543e8be279cc566823eb2a27e1efc2ee59ea5eb9863e93c7ba6c1eb87cd8fa5bbc2e1b40f83baf572a0305fa4eaa794c6636ab960fe6bab811592b94d07689a08c6458418cc25c815d34af1d3629904a3958e93b06e74a533';
const _privateExponentHex =
    '17f27797209df212f237551de17a381c4ee02c90904d1b8864027c6ec69fe2929206df84ffcffb556dba471d5f029afdc221b4cbca51f3496560d2e3a70026933f4a2f0f20dafba4efbd936ace7011abb37ad1809387bcef5bb045a094e834f96a18ccf6664b94ced683c91453d129fba4a9fd2b26cc60336ec0a0e7ad5d1242085fb5bc24235adde1b46ad0eafe726b54332f6898f1700ce2f230ad05d60e693e839ca4dcb6099936a43ab117c4ca0d805e11e8b9d8be7915191ea61af05e74516857791918ad92f5176006ebfdbdf365f2c38b2564a2dbfb1bf4782231da5072bfb9402c5bef6bd9017020819589696cc9c9cb9f492aca4b2f66f77debad0f2644523933e386e853c15cceff8f91dac9639142789351738134b3038bb0b192bd02f501db14dbc66f91792237c5b6e632fba98c64c6f8b9c9c2715ed8e3d6b677aa4315245ff3948c62eb29978ab3c85cfac614da2bb3c6caa3139a5b7d79215f0a994841bdf7d018409e4b89744c9729d3aa0e064318d890d53bb51b95f701';

class _PrivateDirectoryFixture {
  _PrivateDirectoryFixture._(
    this.server,
    this.overrideKeyId,
    this.configMissing,
  );

  final HttpServer server;
  final String? overrideKeyId;
  final bool configMissing;
  final BigInt modulus = BigInt.parse(_modulusHex, radix: 16);
  final BigInt privateExponent = BigInt.parse(_privateExponentHex, radix: 16);
  int evaluateRequests = 0;
  int snapshotRequests = 0;
  List<String> lastBlindedBatch = const [];
  String? lastEvaluateAuthorization;
  Map<String, Object?>? directoryUpdateBody;
  bool ownEnrolled = false;

  String get baseUrl => 'http://${server.address.address}:${server.port}';

  static Future<_PrivateDirectoryFixture> start({
    String? overrideKeyId,
    bool configMissing = false,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fixture = _PrivateDirectoryFixture._(
      server,
      overrideKeyId,
      configMissing,
    );
    server.listen(fixture._handle);
    return fixture;
  }

  Future<void> close() => server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    try {
      switch ('${request.method} ${request.uri.path}') {
        case 'GET /api/v1/directory/config':
          if (configMissing) {
            request.response.statusCode = HttpStatus.notFound;
            request.response.write(jsonEncode({'error': 'not_found'}));
            break;
          }
          request.response.write(
            jsonEncode({
              'version': 'elcim-directory-oprf-v1',
              'keyId': overrideKeyId ?? _keyId,
              'modulus': _encode(_toBytes(modulus, 384)),
              'exponent': 'AQAB',
              'batchSize': 256,
            }),
          );
          break;
        case 'POST /api/v1/directory/evaluate':
          evaluateRequests++;
          lastEvaluateAuthorization = request.headers.value(
            HttpHeaders.authorizationHeader,
          );
          final body =
              (jsonDecode(await utf8.decoder.bind(request).join()) as Map)
                  .cast<String, Object?>();
          lastBlindedBatch = (body['blinded'] as List).cast<String>();
          final evaluated = lastBlindedBatch
              .map(
                (value) => _encode(
                  _toBytes(
                    _fromBytes(_decode(value)).modPow(privateExponent, modulus),
                    384,
                  ),
                ),
              )
              .toList(growable: false);
          request.response.write(
            jsonEncode({'keyId': _keyId, 'evaluated': evaluated}),
          );
          break;
        case 'GET /api/v1/directory/snapshot':
          snapshotRequests++;
          final entries = <Map<String, String>>[
            await _entry(await hashPhoneNumber('+905551234567'), _aliceUserId),
            if (ownEnrolled)
              await _entry(await hashPhoneNumber('+905559999999'), _ownUserId),
          ];
          request.response.write(
            jsonEncode({'keyId': _keyId, 'entries': entries}),
          );
          break;
        case 'POST /api/v1/users/directory-token':
          directoryUpdateBody =
              (jsonDecode(await utf8.decoder.bind(request).join()) as Map)
                  .cast<String, Object?>();
          ownEnrolled = true;
          request.response.write(jsonEncode({'status': 'ok', 'keyId': _keyId}));
          break;
        default:
          request.response.statusCode = HttpStatus.notFound;
          request.response.write(jsonEncode({'error': 'not_found'}));
      }
    } catch (error, stackTrace) {
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write(
        jsonEncode({'error': '$error', 'trace': '$stackTrace'}),
      );
    } finally {
      await request.response.close();
    }
  }

  Future<Map<String, String>> _entry(String phoneHash, String userId) async {
    final point = _fullDomainPoint(phoneHash);
    final evaluated = point.modPow(privateExponent, modulus);
    final token = crypto.sha256.convert([
      ...ascii.encode('elcim-directory-token-v1\x00'),
      ..._toBytes(evaluated, 384),
    ]).bytes;
    final label = _encode(
      crypto.sha256.convert([
        ...ascii.encode('elcim-directory-label-v1\x00'),
        ...token,
      ]).bytes,
    );
    final key = crypto.sha256.convert([
      ...ascii.encode('elcim-directory-entry-key-v1\x00'),
      ...token,
    ]).bytes;
    final nonce = List<int>.generate(
      12,
      (index) => index + userId.codeUnitAt(0),
    );
    final aad = [
      ...ascii.encode('elcim-directory-entry-aad-v1\x00'),
      ...ascii.encode(_keyId),
      0,
      ...ascii.encode(label),
    ];
    final box = await AesGcm.with256bits().encrypt(
      utf8.encode(userId),
      secretKey: SecretKey(key),
      nonce: nonce,
      aad: aad,
    );
    return {
      'label': label,
      'sealedUserId': _encode([
        ...box.nonce,
        ...box.cipherText,
        ...box.mac.bytes,
      ]),
    };
  }

  BigInt _fullDomainPoint(String phoneHash) {
    final phoneDomain = ascii.encode('elcim-directory-phone-v1\x00');
    for (var attempt = 0; attempt <= 255; attempt++) {
      final seed = crypto.sha256.convert([
        ...phoneDomain,
        ...ascii.encode(phoneHash),
        ..._int32(attempt),
      ]).bytes;
      final expanded = <int>[];
      var counter = 0;
      while (expanded.length < 400) {
        expanded.addAll(
          crypto.sha256.convert([...seed, ..._int32(counter++)]).bytes,
        );
      }
      final candidate =
          (_fromBytes(expanded) % (modulus - BigInt.one)) + BigInt.one;
      if (candidate > BigInt.one && candidate.gcd(modulus) == BigInt.one) {
        return candidate;
      }
    }
    throw StateError('test point mapping failed');
  }
}

BigInt _fromBytes(List<int> bytes) {
  var result = BigInt.zero;
  for (final byte in bytes) {
    result = (result << 8) | BigInt.from(byte);
  }
  return result;
}

Uint8List _toBytes(BigInt value, int width) {
  final result = Uint8List(width);
  var remaining = value;
  for (var index = width - 1; index >= 0; index--) {
    result[index] = (remaining & BigInt.from(255)).toInt();
    remaining >>= 8;
  }
  return result;
}

Uint8List _int32(int value) {
  final bytes = ByteData(4)..setUint32(0, value, Endian.big);
  return bytes.buffer.asUint8List();
}

String _encode(List<int> bytes) => base64UrlEncode(bytes).replaceAll('=', '');

List<int> _decode(String value) => base64Url.decode(base64Url.normalize(value));
