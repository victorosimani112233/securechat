import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/auth/auth_api.dart';
import 'package:flutter_securechat/src/auth/auth_coordinator.dart';
import 'package:flutter_securechat/src/auth/phone_privacy.dart';
import 'package:flutter_securechat/src/contacts/contact_discovery_api.dart';
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
                'userId': requests[path]!['userId'],
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
      final directoryApi = _RecordingDirectoryApi();
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
        privateDirectory: directoryApi,
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

      final registeredId = requests['/api/v1/users/register']!['userId'];
      expect(session.userId, registeredId);
      expect(session.accessToken, 'access-1');
      expect(signaling.currentStatus.isConnected, isTrue);
      expect(requests['/api/v1/otp/request']?['email'], 'user@example.com');
      expect(requests['/api/v1/users/register']?['registrationToken'], 'reg-1');
      expect(requests['/api/v1/users/register'], isNot(contains('phoneHash')));
      expect(directoryApi.phoneHashes, isEmpty);
      expect(directoryApi.accessToken, 'access-1');
      expect(directoryApi.ownUserId, registeredId);
      expect(directoryApi.ownPhoneHash, await hashPhoneNumber('905551234567'));
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

      final protocolStore = DatabaseCryptoProtocolStore(fixture.database);
      expect(await protocolStore.getIdentityKeyPair(), isNotNull);
      expect(await protocolStore.getAvailablePreKeyCount(), greaterThan(0));
      await coordinator.logout();
      expect(session.userId, isNull);
      expect(await protocolStore.getIdentityKeyPair(), isNull);
      expect(await protocolStore.getAvailablePreKeyCount(), 0);
    },
  );

  test('initial prekey upload failure is not ignored', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      await request.drain<void>();
      request.response
        ..statusCode = HttpStatus.serviceUnavailable
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'error': 'prekey_store_unavailable'}));
      await request.response.close();
    });
    final api = AuthApi(
      baseUrl: 'http://${server.address.address}:${server.port}',
    );
    const bundle = SerializedPreKeyBundle(
      identityPublicKey: [1],
      registrationId: 1,
      signedPreKeyId: 1,
      signedPreKey: [2],
      signedPreKeySignature: [3],
      oneTimePreKeys: [],
    );

    await expectLater(
      api.uploadPreKeys(bundle, 'access-token'),
      throwsA(isA<AuthApiException>()),
    );
  });

  for (final scenario in [
    'restored identity',
    'existing account response',
    'different account response',
    'directory rejection',
  ]) {
    test('$scenario cannot establish or replace a local session', () async {
      final fixture = await _openFixture();
      addTearDown(fixture.close);
      final store = DatabaseCryptoProtocolStore(fixture.database);
      final preKeys = PreKeyManager(store, batchSize: 2);
      await preKeys.generateAndSerializeInitialBundle();
      final identityBefore = await store.getIdentityKeyPair();
      final session = SessionStore(
        userId: scenario == 'restored identity' ? 'restored-user' : null,
        displayName: 'Existing profile',
        phoneNumber: '+905551234567',
      );
      final sessionBefore = session.toJson();
      final api = _RegistrationApi(scenario);
      final directory = _RecordingDirectoryApi(
        reject: scenario == 'directory rejection',
      );
      final signaling = InMemorySignalingService();
      final coordinator = AuthCoordinator(
        api: api,
        session: session,
        preKeys: preKeys,
        signaling: signaling,
        signalingUrl: 'ws://local',
        privateDirectory: directory,
      );
      await expectLater(
        coordinator.registerAndLogin(
          displayName: 'Replacement profile',
          phoneNumber: '+905559876543',
          registrationToken: 'otp-grant',
        ),
        throwsA(
          scenario == 'restored identity' ||
                  scenario == 'existing account response'
              ? isA<ExistingAccountLoginRequired>()
              : isA<AuthApiException>(),
        ),
      );
      expect(session.toJson(), sessionBefore);
      expect(session.isLoggedIn, isFalse);
      expect(signaling.currentStatus.isConnected, isFalse);
      expect(await store.getIdentityKeyPair(), identityBefore);
      if (scenario == 'restored identity') expect(api.registerCalls, 0);
      expect(api.uploadCalls, 0);
      if (scenario.contains('response') || scenario == 'restored identity') {
        expect(directory.accessToken, isNull);
      }
    });
  }

  test(
    'prekey upload failure retains durable credentials and identity',
    () async {
      final fixture = await _openFixture();
      addTearDown(fixture.close);
      final store = DatabaseCryptoProtocolStore(fixture.database);
      final preKeys = PreKeyManager(store, batchSize: 2);
      await preKeys.generateAndSerializeInitialBundle();
      final identityBefore = await store.getIdentityKeyPair();
      final sessionFile = File('${fixture.directory.path}/session.securejson');
      final storageCrypto = LocalAeadCryptoService(
        SecretKey(List<int>.generate(32, (index) => index + 1)),
      );
      final session = await PersistentSessionStore.open(
        file: sessionFile,
        crypto: storageCrypto,
      );
      addTearDown(session.close);
      final api = _RegistrationApi('prekey rejection');
      final directory = _RecordingDirectoryApi();
      final signaling = InMemorySignalingService();
      final coordinator = AuthCoordinator(
        api: api,
        session: session,
        preKeys: preKeys,
        signaling: signaling,
        signalingUrl: 'ws://local',
        privateDirectory: directory,
      );

      await expectLater(
        coordinator.registerAndLogin(
          displayName: 'Alice',
          phoneNumber: '+905551234567',
          registrationToken: 'otp-grant',
        ),
        throwsA(isA<AuthApiException>()),
      );
      expect(directory.ownUserId, session.userId);
      expect(api.uploadCalls, 1);
      expect(signaling.currentStatus.isConnected, isFalse);
      expect(await store.getIdentityKeyPair(), identityBefore);

      final reopened = await PersistentSessionStore.open(
        file: sessionFile,
        crypto: storageCrypto,
      );
      addTearDown(reopened.close);
      expect(reopened.userId, directory.ownUserId);
      expect(reopened.accessToken, 'access');
      expect(reopened.refreshToken, 'refresh');
      expect(reopened.isLoggedIn, isTrue);
      expect(reopened.displayName, 'Alice');

      // A retry must not register another UUID or discard the retained identity.
      await expectLater(
        coordinator.registerAndLogin(
          displayName: 'Alice',
          phoneNumber: '+905551234567',
          registrationToken: 'another-grant',
        ),
        throwsA(isA<ExistingAccountLoginRequired>()),
      );
      expect(api.registerCalls, 1);
      expect(await store.getIdentityKeyPair(), identityBefore);
    },
  );
}

class _RegistrationApi extends AuthApi {
  _RegistrationApi(this.scenario) : super(baseUrl: 'http://unused.invalid');

  final String scenario;
  int registerCalls = 0;
  int uploadCalls = 0;

  @override
  Future<RegisterResult> register({
    required String userId,
    required String registrationToken,
  }) async {
    registerCalls++;
    return RegisterResult(
      userId: scenario == 'different account response' ? 'other-user' : userId,
      isNew: scenario != 'existing account response',
      accessToken: 'access',
      refreshToken: 'refresh',
    );
  }

  @override
  Future<void> uploadPreKeys(
    SerializedPreKeyBundle bundle,
    String accessToken,
  ) async {
    uploadCalls++;
    if (scenario == 'prekey rejection') {
      throw const AuthApiException('unavailable', statusCode: 503);
    }
  }
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

class _RecordingDirectoryApi implements ContactDiscoveryApi {
  _RecordingDirectoryApi({this.reject = false});

  final bool reject;
  List<String>? phoneHashes;
  String? accessToken;
  String? ownPhoneHash;
  String? ownUserId;

  @override
  Future<List<RegisteredUserMatch>> checkUsers(
    List<String> phoneHashes,
    String accessToken, {
    String? ownPhoneHash,
    String? ownUserId,
  }) async {
    if (reject) {
      // The hardened route deliberately conflates malformed and already-owned
      // directory tokens. It does not disclose a recoverable account/email.
      throw const AuthApiException('invalid_directory_token', statusCode: 400);
    }
    this.phoneHashes = List<String>.of(phoneHashes);
    this.accessToken = accessToken;
    this.ownPhoneHash = ownPhoneHash;
    this.ownUserId = ownUserId;
    return const [];
  }
}
