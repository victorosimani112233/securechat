import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/auth/auth_api.dart';
import 'package:flutter_securechat/src/auth/auth_coordinator.dart';
import 'package:flutter_securechat/src/background/background_scheduler.dart';
import 'package:flutter_securechat/src/background/scheduled_message_service.dart';
import 'package:flutter_securechat/src/diagnostics/crash_reporter.dart';
import 'package:flutter_securechat/src/domain/send_message_use_case.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/settings/account_data_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_securechat/src/crypto/vodozemac/olm_pre_key_publisher.dart';

void main() {
  test('local data deletion logs out and clears every managed store', () async {
    final fixture = await _AccountFixture.open();
    addTearDown(fixture.close);

    await fixture.service.deleteLocalData();

    expect(fixture.session.isLoggedIn, isFalse);
    expect(await fixture.database.conversations.getById('alice'), isNull);
    expect(await fixture.managedDirectory.exists(), isFalse);
    expect(fixture.server.paths, contains('/api/v1/auth/logout'));
    expect(fixture.scheduler.cancelled, contains('plan-1'));
    expect(fixture.afterCleanupCalls, 1);
  });

  // QA 2026-10-12 R2: cikistan sonra 200 cokme kaydi onceki hesabin
  // userHash degeriyle cihazda kaliyordu.
  test('logout removes crash reports that carry the account hash', () async {
    final fixture = await _AccountFixture.open();
    addTearDown(fixture.close);
    final report = await fixture.diagnostics.recordException(
      StateError('x'),
      StackTrace.current,
    );
    expect(await report!.readAsString(), contains('"userHash":"'));
    final partial = File('${report.path}.tmp')..writeAsStringSync('{}');

    await fixture.service.deleteLocalData();

    expect(await fixture.diagnostics.listReports(), isEmpty);
    expect(partial.existsSync(), isFalse);
    final next = await fixture.diagnostics.recordException(
      StateError('y'),
      StackTrace.current,
    );
    expect(await next!.readAsString(), contains('"userHash":null'));
  });

  // QA 2026-10-13: sona ermis oturumu olan cihaz "Farklı hesapla başla" ile
  // temizlenir; token olmadigi icin sunucuya cikis istegi gitmez.
  test('an expired session is wiped locally without a server call', () async {
    final fixture = await _AccountFixture.open();
    addTearDown(fixture.close);
    await fixture.session.expireCredentialsAndPersist();

    await fixture.service.deleteLocalData();

    expect(fixture.session.userId, isNull);
    expect(fixture.session.credentialsExpired, isFalse);
    expect(await fixture.database.conversations.getById('alice'), isNull);
    expect(await fixture.managedDirectory.exists(), isFalse);
    expect(fixture.server.paths, isNot(contains('/api/v1/auth/logout')));
  });

  test('server rejection preserves local account and device data', () async {
    final fixture = await _AccountFixture.open(accountDeleteStatus: 500);
    addTearDown(fixture.close);
    await fixture.diagnostics.recordException(
      StateError('x'),
      StackTrace.current,
    );

    await expectLater(
      fixture.service.deleteAccount(),
      throwsA(isA<AuthApiException>()),
    );

    expect(fixture.session.isLoggedIn, isTrue);
    expect(await fixture.database.conversations.getById('alice'), isNotNull);
    expect(await fixture.managedDirectory.exists(), isTrue);
    expect(await fixture.diagnostics.listReports(), hasLength(1));
    expect(fixture.afterCleanupCalls, 0);
  });

  test(
    'confirmed server deletion removes local credentials and data',
    () async {
      final fixture = await _AccountFixture.open();
      addTearDown(fixture.close);

      await fixture.service.deleteAccount();

      expect(fixture.server.paths, contains('/api/v1/account/delete'));
      expect(fixture.server.authorization, contains('Bearer access-secret'));
      expect(fixture.session.isLoggedIn, isFalse);
      expect(await fixture.database.conversations.getById('alice'), isNull);
      expect(await fixture.managedDirectory.exists(), isFalse);
      expect(fixture.afterCleanupCalls, 1);
    },
  );
}

class _AccountFixture {
  _AccountFixture({
    required this.directory,
    required this.managedDirectory,
    required this.database,
    required this.session,
    required this.signaling,
    required this.scheduler,
    required this.server,
    required this.service,
    required this.diagnostics,
  });

  final Directory directory;
  final Directory managedDirectory;
  final SecureChatDatabase database;
  final PersistentSessionStore session;
  final InMemorySignalingService signaling;
  final _FakeScheduler scheduler;
  final _TestAuthServer server;
  final AccountDataService service;
  final PrivacyCrashReporter diagnostics;
  int afterCleanupCalls = 0;

  static Future<_AccountFixture> open({int accountDeleteStatus = 200}) async {
    final directory = await Directory.systemTemp.createTemp('account_data_');
    final managedDirectory = Directory('${directory.path}/media');
    await managedDirectory.create(recursive: true);
    await File('${managedDirectory.path}/secret.bin').writeAsString('secret');
    final crypto = LocalAeadCryptoService(
      SecretKey(List<int>.generate(32, (index) => 65 + index)),
    );
    final database = await SecureChatDatabase.open(
      file: File('${directory.path}/database.securejson'),
      crypto: crypto,
    );
    await database.conversations.insert(
      const ConversationEntity(
        id: 'alice',
        peerId: 'alice',
        peerName: 'Alice',
        peerPhone: '+1',
      ),
    );
    final future = DateTime.now().add(const Duration(days: 1));
    await database.scheduledMessages.insert(
      ScheduledMessageEntity(
        id: 'plan-1',
        messageContent: 'later',
        repeatType: 'ONCE',
        hour: future.hour,
        minute: future.minute,
        recipientIds: 'alice',
        recipientNames: 'Alice',
        nextTriggerTime: future.millisecondsSinceEpoch,
      ),
    );
    final session = await PersistentSessionStore.open(
      file: File('${directory.path}/session.securejson'),
      crypto: crypto,
    );
    await session.loginAndPersist(
      userId: 'me',
      displayName: 'Me',
      phoneNumber: '+90000',
      accessToken: 'access-secret',
      refreshToken: 'refresh-secret',
    );
    final signaling = InMemorySignalingService();
    await signaling.connect(
      userId: 'me',
      url: 'ws://local',
      accessToken: 'access-secret',
    );
    final server = await _TestAuthServer.start(
      accountDeleteStatus: accountDeleteStatus,
    );
    final auth = AuthCoordinator(
      api: AuthApi(baseUrl: server.baseUrl),
      session: session,
      olmPreKeys: _RecordingOlmKeyPublisher(),
      signaling: signaling,
      signalingUrl: 'ws://local',
    );
    final scheduler = _FakeScheduler();
    final scheduled = ScheduledMessageService(
      dao: database.scheduledMessages,
      sender: SendMessageUseCase(
        database: database,
        signaling: signaling,
        session: session,
        crypto: crypto,
        maxRetryCount: 0,
        retryDelay: Duration.zero,
      ),
      signaling: signaling,
      session: session,
      scheduler: scheduler,
    );
    final diagnostics =
        await PrivacyCrashReporter.open(
            directory: Directory('${directory.path}/crash_logs'),
            platform: const _NoDiagnosticsPlatform(),
          )
          ..setUserId('me');
    late _AccountFixture fixture;
    final service = AccountDataService(
      auth: auth,
      database: database,
      scheduledMessages: scheduled,
      managedDirectories: [managedDirectory],
      unregisterPush: () async => true,
      forgetDiagnostics: diagnostics.forgetAccount,
      afterLocalCleanup: () async => fixture.afterCleanupCalls++,
    );
    fixture = _AccountFixture(
      directory: directory,
      managedDirectory: managedDirectory,
      database: database,
      session: session,
      signaling: signaling,
      scheduler: scheduler,
      server: server,
      service: service,
      diagnostics: diagnostics,
    );
    return fixture;
  }

  Future<void> close() async {
    await server.close();
    await database.close();
    await signaling.disconnect();
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

class _TestAuthServer {
  _TestAuthServer(this._server, this.accountDeleteStatus);

  final HttpServer _server;
  final int accountDeleteStatus;
  final paths = <String>[];
  final authorization = <String>[];

  String get baseUrl => 'http://${_server.address.address}:${_server.port}';

  static Future<_TestAuthServer> start({
    required int accountDeleteStatus,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fixture = _TestAuthServer(server, accountDeleteStatus);
    server.listen(fixture._handle);
    return fixture;
  }

  Future<void> _handle(HttpRequest request) async {
    paths.add(request.uri.path);
    final bearer = request.headers.value(HttpHeaders.authorizationHeader);
    if (bearer != null) authorization.add(bearer);
    await utf8.decoder.bind(request).join();
    final status = request.uri.path == '/api/v1/account/delete'
        ? accountDeleteStatus
        : 200;
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode(status == 200 ? {'status': 'ok'} : {'error': 'rejected'}),
    );
    await request.response.close();
  }

  Future<void> close() => _server.close(force: true);
}

class _FakeScheduler implements BackgroundScheduler {
  final scheduled = <ScheduledMessageEntity>[];
  final cancelled = <String>[];

  @override
  Future<void> cancelScheduledMessage(String id) async => cancelled.add(id);

  @override
  Future<void> initialize() async {}

  @override
  Future<void> registerRecurringTasks() async {}

  @override
  Future<void> scheduleMessage(ScheduledMessageEntity message) async {
    scheduled.add(message);
  }
}

/// Kayit akisi testleri anahtar yayinini degil kayit mantigini olcuyor.
class _RecordingOlmKeyPublisher implements RecoveryIdentity {
  int calls = 0;
  String? _pending;

  @override
  Future<void> publishIfNeeded() async => calls++;

  @override
  Future<void> republishAfterIdentityReset() async => calls++;

  @override
  Future<void> clearLocalCryptoState() async => _pending = null;

  // Bu testler kurtarmayi olcmuyor: kimlik yok, imza istenirse hata.
  @override
  Future<String?> recoverySigningPublicKey() async => null;

  @override
  Future<String> signRecoveryProof(String message) async =>
      throw StateError('kurtarma kimligi bu testte yok');

  @override
  Future<String?> readPendingRecovery() async => _pending;

  @override
  Future<void> writePendingRecovery(String record) async => _pending = record;

  @override
  Future<void> clearPendingRecovery() async => _pending = null;
}

class _NoDiagnosticsPlatform implements DiagnosticsPlatformGateway {
  const _NoDiagnosticsPlatform();

  @override
  Future<CrashMetadata> metadata() async => const CrashMetadata(
    versionName: 'test',
    versionCode: '1',
    operatingSystem: 'test',
    osVersion: 'test',
    deviceModel: 'test',
    manufacturer: 'test',
  );

  @override
  Future<bool> share(File file) async => false;
}
