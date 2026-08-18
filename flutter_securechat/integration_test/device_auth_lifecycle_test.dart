import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_securechat/src/auth/auth_api.dart';
import 'package:flutter_securechat/src/auth/auth_coordinator.dart';
import 'package:flutter_securechat/src/config/app_config.dart';
import 'package:flutter_securechat/src/crypto/crypto_protocol_store.dart';
import 'package:flutter_securechat/src/crypto/pre_key_manager.dart';
import 'package:flutter_securechat/src/network/tls_pinning.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/key_material_store.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'physical device pinned auth token lifecycle',
    (tester) async {
      await tester.runAsync(_runAuthLifecycle);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

Future<void> _runAuthLifecycle() async {
  const config = AppConfig.current;
  config.validateNetworkSecurity();
  expect(config.apiBaseUrl, 'https://127.0.0.1:18444');
  expect(config.signalingUrl, 'wss://127.0.0.1:18444');
  expect(config.allowsDebugLoopbackTransport, isTrue);

  final clients = SecureHttpClientFactory(TlsPinPolicy.fromConfig(config));
  final signaling = WebSocketSignalingService(httpClient: clients.create());
  final root = Directory(
    '${(await getTemporaryDirectory()).path}/device-auth-'
    '${DateTime.now().microsecondsSinceEpoch}',
  );
  await root.create(recursive: true);
  final sessionFile = File('${root.path}/session.securejson');
  final databaseFile = File('${root.path}/storage.securejson');
  final key = await PlatformKeyMaterialStore().readOrCreateMasterKey();
  final crypto = LocalAeadCryptoService(SecretKey(key));
  final database = await SecureChatDatabase.open(
    file: databaseFile,
    crypto: crypto,
  );
  final session = await PersistentSessionStore.open(
    file: sessionFile,
    crypto: crypto,
  );
  final api = AuthApi(baseUrl: config.apiBaseUrl, client: clients.create());
  final coordinator = AuthCoordinator(
    api: api,
    session: session,
    preKeys: PreKeyManager(
      DatabaseCryptoProtocolStore(database),
      batchSize: 8,
      refreshThreshold: 2,
    ),
    signaling: signaling,
    signalingUrl: config.signalingUrl,
  );

  try {
    final limited = await coordinator.requestOtp('rate-limit@qa.invalid');
    expect(limited.status, OtpRequestStatus.rateLimited);
    expect(limited.retryAfter, const Duration(seconds: 3));
    final smtpDisabled = await coordinator.requestOtp(
      'smtp-disabled@qa.invalid',
    );
    expect(smtpDisabled.status, OtpRequestStatus.smtpDisabled);
    expect(
      coordinator.verifyOtp('device-auth@qa.invalid', '000000'),
      throwsA(
        isA<AuthApiException>().having(
          (error) => error.statusCode,
          'statusCode',
          HttpStatus.unauthorized,
        ),
      ),
    );

    expect(
      (await coordinator.requestOtp('device-auth@qa.invalid')).status,
      OtpRequestStatus.sent,
    );
    final registration = await coordinator.verifyOtp(
      'device-auth@qa.invalid',
      '654321',
    );
    await coordinator.registerAndLogin(
      displayName: 'Device Auth QA',
      phoneNumber: '+90 555 000 00 01',
      registrationToken: registration,
    );
    expect(session.isLoggedIn, isTrue);
    expect(signaling.currentStatus.isConnected, isTrue);
    expect(await database.preKeys.count(), 8);
    expect(await sessionFile.readAsString(), isNot(contains('Device Auth QA')));
    debugPrint('[device-auth] otp-register-wss-persisted');

    final originalRefreshToken = session.refreshToken!;
    final refreshedAccessToken = await coordinator.refreshAccessToken();
    expect(refreshedAccessToken, isNotEmpty);
    expect(session.refreshToken, isNot(originalRefreshToken));
    expect(
      api.refresh(originalRefreshToken),
      throwsA(
        isA<AuthApiException>().having(
          (error) => error.statusCode,
          'statusCode',
          HttpStatus.unauthorized,
        ),
      ),
    );
    final persistedAfterRefresh = await PersistentSessionStore.open(
      file: sessionFile,
      crypto: crypto,
    );
    expect(persistedAfterRefresh.accessToken, refreshedAccessToken);
    expect(persistedAfterRefresh.refreshToken, session.refreshToken);
    await persistedAfterRefresh.close();
    debugPrint('[device-auth] refresh-rotated-old-token-rejected');

    final revokedRefreshToken = session.refreshToken!;
    await coordinator.logout();
    expect(session.isLoggedIn, isFalse);
    expect(signaling.currentStatus.isConnected, isFalse);
    expect(
      api.refresh(revokedRefreshToken),
      throwsA(
        isA<AuthApiException>().having(
          (error) => error.statusCode,
          'statusCode',
          HttpStatus.unauthorized,
        ),
      ),
    );
    final persistedAfterLogout = await PersistentSessionStore.open(
      file: sessionFile,
      crypto: crypto,
    );
    expect(persistedAfterLogout.isLoggedIn, isFalse);
    await persistedAfterLogout.close();
    debugPrint('[device-auth] logout-revoked-and-cleared');

    final secondRegistration = await coordinator.verifyOtp(
      'device-auth@qa.invalid',
      '654321',
    );
    await coordinator.registerAndLogin(
      displayName: 'Device Auth QA',
      phoneNumber: '+90 555 000 00 01',
      registrationToken: secondRegistration,
    );
    expect(session.isLoggedIn, isTrue);
    expect(signaling.currentStatus.isConnected, isTrue);
    await coordinator.logout();
    debugPrint('[device-auth] relogin-complete');
  } finally {
    await signaling.dispose();
    await session.close();
    await database.close();
    clients.close();
    if (await root.exists()) await root.delete(recursive: true);
  }
}
