import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/auth/auth_api.dart';
import 'package:flutter_securechat/src/auth/auth_coordinator.dart';
import 'package:flutter_securechat/src/auth/phone_privacy.dart';
import 'package:flutter_securechat/src/crypto/crypto_protocol_store.dart';
import 'package:flutter_securechat/src/crypto/pre_key_manager.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'phone normalization and local discovery hash match privacy contract',
    () async {
      expect(normalizePhoneDigits('0555 123 45 67'), '905551234567');
      expect(normalizePhoneDigits('+90 555 123 45 67'), '905551234567');
      expect(await hashPhoneNumber('5551234567'), hasLength(64));
    },
  );

  test(
    'OTP registration persists tokens, uploads prekeys and connects',
    () async {
      final requests = <String, Map<String, Object?>>{};
      final authHeaders = <String, String?>{};
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        final path = request.uri.path;
        final raw = await utf8.decoder.bind(request).join();
        requests[path] = raw.isEmpty
            ? <String, Object?>{}
            : (jsonDecode(raw) as Map).cast<String, Object?>();
        authHeaders[path] = request.headers.value(
          HttpHeaders.authorizationHeader,
        );
        request.response.headers.contentType = ContentType.json;
        switch (path) {
          case '/api/v1/otp/request':
            request.response.write(jsonEncode({'sent': true}));
          case '/api/v1/otp/verify':
            request.response.write(
              jsonEncode({'verified': true, 'registrationToken': 'reg-1'}),
            );
          case '/api/v1/users/register':
            request.response.write(
              jsonEncode({
                'userId': 'server-user',
                'isNew': true,
                'accessToken': 'access-1',
                'refreshToken': 'refresh-1',
              }),
            );
          case '/api/v1/prekeys/upload':
            request.response.write(jsonEncode({'status': 'ok'}));
          case '/api/v1/auth/refresh':
            request.response.write(
              jsonEncode({
                'accessToken': 'access-2',
                'refreshToken': 'refresh-2',
              }),
            );
          default:
            request.response.statusCode = 404;
            request.response.write(jsonEncode({'error': 'not found'}));
        }
        await request.response.close();
      });

      final fixture = await _openFixture();
      addTearDown(fixture.close);
      final api = AuthApi(
        baseUrl: 'http://${server.address.address}:${server.port}',
      );
      final signaling = InMemorySignalingService();
      final session = SessionStore();
      final coordinator = AuthCoordinator(
        api: api,
        session: session,
        preKeys: PreKeyManager(
          DatabaseCryptoProtocolStore(fixture.database),
          batchSize: 3,
          refreshThreshold: 1,
        ),
        signaling: signaling,
        signalingUrl: 'ws://local',
      );

      expect(
        (await coordinator.requestOtp('User@Example.com')).status,
        OtpRequestStatus.sent,
      );
      final registrationToken = await coordinator.verifyOtp(
        'User@Example.com',
        '123456',
      );
      await coordinator.registerAndLogin(
        displayName: 'Alice Example',
        phoneNumber: '0555 123 45 67',
        registrationToken: registrationToken,
      );

      expect(session.userId, 'server-user');
      expect(session.accessToken, 'access-1');
      expect(signaling.currentStatus.isConnected, isTrue);
      expect(requests['/api/v1/otp/request']?['email'], 'user@example.com');
      expect(requests['/api/v1/users/register']?['registrationToken'], 'reg-1');
      expect(
        requests['/api/v1/users/register'],
        isNot(contains('encryptedPhone')),
      );
      expect(
        (requests['/api/v1/prekeys/upload']?['oneTimePreKeys'] as List),
        hasLength(3),
      );
      expect(authHeaders['/api/v1/prekeys/upload'], 'Bearer access-1');

      expect(await coordinator.refreshAccessToken(), 'access-2');
      expect(session.refreshToken, 'refresh-2');
    },
  );
}

Future<_Fixture> _openFixture() async {
  final directory = await Directory.systemTemp.createTemp('securechat_auth_');
  final database = await SecureChatDatabase.open(
    file: File('${directory.path}/storage.securejson'),
    crypto: LocalAeadCryptoService(
      SecretKey(List<int>.generate(32, (index) => 100 + index)),
    ),
  );
  return _Fixture(directory, database);
}

class _Fixture {
  const _Fixture(this.directory, this.database);

  final Directory directory;
  final SecureChatDatabase database;

  Future<void> close() async {
    await database.close();
    await directory.delete(recursive: true);
  }
}
