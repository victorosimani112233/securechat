import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/auth/account_recovery_coordinator.dart';
import 'package:flutter_securechat/src/auth/auth_api.dart';
import 'package:flutter_securechat/src/auth/secure_account_recovery_coordinator.dart';
import 'package:flutter_securechat/src/crypto/crypto_protocol_store.dart';
import 'package:flutter_securechat/src/crypto/pre_key_manager.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart' as signal;

const account = '12345678-1234-4234-8234-123456789abc';
const other = '87654321-1234-4234-8234-123456789abc';
final challengeId = base64UrlEncode(List.filled(32, 1)).replaceAll('=', '');
final capability = base64UrlEncode(List.filled(32, 2)).replaceAll('=', '');
final nonce = base64UrlEncode(List.filled(32, 3)).replaceAll('=', '');

void main() {
  late Directory directory;
  late SecureChatDatabase database;
  late PreKeyManager keys;
  late SessionStore session;
  late InMemorySignalingService signaling;
  late _Api api;
  late SecureAccountRecoveryCoordinator recovery;
  var now = DateTime.utc(2026, 9, 23);
  void coordinator() {
    recovery = SecureAccountRecoveryCoordinator(
      api: api,
      session: session,
      preKeys: keys,
      signaling: signaling,
      signalingUrl: 'ws://test',
      refreshAccessToken: () async => null,
      now: () => now,
    );
  }

  setUp(() async {
    now = DateTime.utc(2026, 9, 23);
    directory = await Directory.systemTemp.createTemp('recovery_flow_');
    database = await SecureChatDatabase.open(
      file: File('${directory.path}/db'),
      crypto: LocalAeadCryptoService(SecretKey(List.filled(32, 27))),
    );
    keys = PreKeyManager(DatabaseCryptoProtocolStore(database), batchSize: 3);
    session = SessionStore();
    signaling = InMemorySignalingService();
    api = _Api(keys.createRecoveryKeyMaterial().bundle);
    coordinator();
  });
  tearDown(() async {
    await signaling.dispose();
    await database.close();
    await directory.delete(recursive: true);
  });

  Future<RecoveryLoginApproval> approval() async => recovery.verifyLogin(
    await recovery.requestLogin('User@Example.com'),
    '123456',
  );

  test(
    'trusted enrollment signs exact purpose nonce account epoch email',
    () async {
      await keys.generateAndSerializeInitialBundle();
      session.login(
        userId: account,
        displayName: 'A',
        phoneNumber: '',
        accessToken: 'trusted',
        refreshToken: 'refresh',
      );
      expect(await recovery.getEnrollmentStatus(), isFalse);
      final challenge = await recovery.requestEnrollment(' User@Example.com ');
      await recovery.verifyEnrollment(challenge, '123456');
      final request = api.calls.last;
      expect(request.$1, endsWith('/recovery-email/verify'));
      expect(request.$3, 'trusted');
      final preimage = [
        'securechat/recovery-enroll/v1',
        challengeId,
        nonce,
        account,
        'epoch',
        'user@example.com',
        'v1',
      ].join('\n');
      expect(
        signal.Curve.verifySignature(
          signal.IdentityKey.fromBytes(
            base64Decode((await keys.localIdentityPublicKey())!),
            0,
          ).publicKey,
          Uint8List.fromList(utf8.encode(preimage)),
          base64Decode(request.$2['signature'] as String),
        ),
        isTrue,
      );
    },
  );

  test(
    'fresh recovery requires explicit identity approval and preserves UUID',
    () async {
      final grant = await approval();
      expect(grant.requiresIdentityReplacement, isTrue);
      await expectLater(
        recovery.completeLogin(grant, acceptIdentityReplacement: false),
        throwsA(isA<AuthApiException>()),
      );
      expect(await recovery.hasPendingLogin(), isFalse);
      await recovery.completeLogin(grant, acceptIdentityReplacement: true);
      expect(session.userId, account);
      expect(session.isLoggedIn, isTrue);
      expect(session.sharePhoneNumber, isFalse);
      expect(api.uploads, 1);
      expect(await recovery.hasPendingLogin(), isFalse);
      expect(signaling.currentStatus.isConnected, isTrue);
      final sent = api.calls
          .where((call) => call.$1.endsWith('/complete'))
          .single
          .$2;
      expect(sent['mode'], 'replace');
      expect(await keys.localIdentityPublicKey(), sent['identityPublicKey']);
    },
  );

  test(
    'same retained identity preserves key and requires correct registration id',
    () async {
      api.bundle = await keys.generateAndSerializeInitialBundle();
      final before = await keys.localIdentityPublicKey();
      session.userId = account;
      final grant = await approval();
      expect(grant.requiresIdentityReplacement, isFalse);
      await recovery.completeLogin(grant, acceptIdentityReplacement: false);
      expect(await keys.localIdentityPublicKey(), before);
      expect(
        api.calls
            .where((call) => call.$1.endsWith('/complete'))
            .single
            .$2['mode'],
        'preserve',
      );
    },
  );

  test(
    'lost completion response retries exact saved signature and key',
    () async {
      api.loseResponse = true;
      await expectLater(
        recovery.completeLogin(
          await approval(),
          acceptIdentityReplacement: true,
        ),
        throwsA(isA<AuthApiException>()),
      );
      expect(session.isLoggedIn, isFalse);
      expect(await keys.localIdentityPublicKey(), isNull);
      final first = jsonEncode(api.calls.last.$2);
      coordinator();
      expect(await recovery.resumePendingLogin(), isTrue);
      final requests = api.calls
          .where((call) => call.$1.endsWith('/complete'))
          .toList();
      expect(requests, hasLength(2));
      expect(jsonEncode(requests.last.$2), first);
      expect(session.userId, account);
    },
  );

  test(
    'failed prekey upload keeps pending credentials and does not log in',
    () async {
      api.failUpload = true;
      await expectLater(
        recovery.completeLogin(
          await approval(),
          acceptIdentityReplacement: true,
        ),
        throwsA(isA<AuthApiException>()),
      );
      expect(session.isLoggedIn, isFalse);
      expect(await recovery.hasPendingLogin(), isTrue);
      final public = await keys.localIdentityPublicKey();
      api.failUpload = false;
      coordinator();
      expect(await recovery.resumePendingLogin(), isTrue);
      expect(
        api.calls.where((call) => call.$1.endsWith('/complete')),
        hasLength(1),
      );
      expect(await keys.localIdentityPublicKey(), public);
      expect(session.userId, account);
    },
  );

  test(
    'restored foreign account blocks before key activation or completion',
    () async {
      session.userId = other;
      await expectLater(approval(), throwsA(isA<AuthApiException>()));
      expect(api.calls.where((call) => call.$1.endsWith('/complete')), isEmpty);
      expect(await keys.localIdentityPublicKey(), isNull);
      expect(session.userId, other);
    },
  );

  test(
    'expired confirmed completion restarts with retained private identity',
    () async {
      api.failUpload = true;
      await expectLater(
        recovery.completeLogin(
          await approval(),
          acceptIdentityReplacement: true,
        ),
        throwsA(isA<AuthApiException>()),
      );
      final public = await keys.localIdentityPublicKey();
      await recovery.restartPendingLogin();
      expect(await recovery.hasPendingLogin(), isFalse);
      expect(await keys.localIdentityPublicKey(), public);
      expect(session.isLoggedIn, isFalse);
      api.bundle = await keys.generateAndSerializeInitialBundle();
      expect((await approval()).requiresIdentityReplacement, isFalse);
    },
  );

  test('expiry and malformed server fields fail closed', () async {
    final grant = await approval();
    now = now.add(const Duration(minutes: 6));
    await expectLater(
      recovery.completeLogin(grant, acceptIdentityReplacement: true),
      throwsA(isA<AuthApiException>()),
    );
    api.malformed = true;
    await expectLater(
      recovery.requestLogin('user@example.com'),
      throwsA(isA<AuthApiException>()),
    );
    expect(await recovery.hasPendingLogin(), isFalse);
    expect(session.isLoggedIn, isFalse);
  });

  test(
    'unknown completion can be deliberately restarted without auto retry',
    () async {
      api.loseResponse = true;
      await expectLater(
        recovery.completeLogin(
          await approval(),
          acceptIdentityReplacement: true,
        ),
        throwsA(isA<AuthApiException>()),
      );
      await recovery.restartPendingLogin();
      expect(await recovery.hasPendingLogin(), isFalse);
      expect(session.isLoggedIn, isFalse);
      expect(await keys.localIdentityPublicKey(), isNull);
    },
  );
}

class _Api extends AuthApi {
  _Api(this.bundle) : super(baseUrl: 'http://unused');
  SerializedPreKeyBundle bundle;
  final calls = <(String, Map<String, Object?>, String?)>[];
  bool loseResponse = false;
  bool failUpload = false;
  bool malformed = false;
  int uploads = 0;
  @override
  Future<Map<String, Object?>> recoveryRequest(
    String endpoint,
    Map<String, Object?> body, {
    String? accessToken,
  }) async {
    calls.add((endpoint, Map.of(body), accessToken));
    if (malformed) return {};
    if (endpoint.endsWith('/recovery-email/status')) return {'bound': false};
    if (endpoint.endsWith('/recovery-email/request'))
      return {
        'challengeId': challengeId,
        'nonce': nonce,
        'credentialEpoch': 'epoch',
        'identityProtocol': 'v1',
        'expiresIn': 600,
      };
    if (endpoint.endsWith('/recovery-email/verify')) return {'status': 'ok'};
    if (endpoint.endsWith('/login/request'))
      return {'challengeId': challengeId, 'expiresIn': 600};
    if (endpoint.endsWith('/login/verify'))
      return {
        'userId': account,
        'recoveryToken': capability,
        'identityProtocol': 'v1',
        'identityPublicKey': base64Encode(bundle.identityPublicKey),
        'registrationId': bundle.registrationId,
        'expiresIn': 300,
      };
    if (endpoint.endsWith('/login/complete')) {
      final preimage = [
        'securechat/recovery-complete/v1',
        body['recoveryToken'],
        body['completionId'],
        account,
        body['mode'],
        body['identityProtocol'],
        body['identityPublicKey'],
        '${body['registrationId']}',
      ].join('\n');
      expect(
        signal.Curve.verifySignature(
          signal.IdentityKey.fromBytes(
            base64Decode(body['identityPublicKey'] as String),
            0,
          ).publicKey,
          Uint8List.fromList(utf8.encode(preimage)),
          base64Decode(body['signature'] as String),
        ),
        isTrue,
      );
      if (loseResponse) {
        loseResponse = false;
        throw const AuthApiException.network();
      }
      return {
        'userId': account,
        'token': 'recovered-access',
        'refreshToken': 'recovered-refresh',
        'identityReplaced': body['mode'] == 'replace',
      };
    }
    throw StateError('Unexpected endpoint');
  }

  @override
  Future<void> uploadPreKeys(
    SerializedPreKeyBundle bundle,
    String accessToken,
  ) async {
    expect(accessToken, 'recovered-access');
    uploads++;
    if (failUpload)
      throw const AuthApiException('unavailable', statusCode: 503);
  }
}
