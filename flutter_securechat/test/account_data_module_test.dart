import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/auth/auth_api.dart';
import 'package:flutter_securechat/src/auth/auth_coordinator.dart';
import 'package:flutter_securechat/src/background/background_scheduler.dart';
import 'package:flutter_securechat/src/background/scheduled_message_service.dart';
import 'package:flutter_securechat/src/crypto/crypto_protocol_store.dart';
import 'package:flutter_securechat/src/crypto/pre_key_manager.dart';
import 'package:flutter_securechat/src/domain/send_message_use_case.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/settings/account_data_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test('server rejection preserves local account and device data', () async {
    final fixture = await _AccountFixture.open(accountDeleteStatus: 500);
    addTearDown(fixture.close);

    await expectLater(
      fixture.service.deleteAccount(),
      throwsA(isA<AuthApiException>()),
    );

    expect(fixture.session.isLoggedIn, isTrue);
    expect(await fixture.database.conversations.getById('alice'), isNotNull);
    expect(await fixture.managedDirectory.exists(), isTrue);
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
  });

  final Directory directory;
  final Directory managedDirectory;
  final SecureChatDatabase database;
  final PersistentSessionStore session;
  final InMemorySignalingService signaling;
  final _FakeScheduler scheduler;
  final _TestAuthServer server;
  final AccountDataService service;
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
      preKeys: PreKeyManager(DatabaseCryptoProtocolStore(database)),
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
    late _AccountFixture fixture;
    final service = AccountDataService(
      auth: auth,
      database: database,
      scheduledMessages: scheduled,
      managedDirectories: [managedDirectory],
      unregisterPush: () async => true,
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
