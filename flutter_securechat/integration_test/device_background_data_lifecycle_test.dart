import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_securechat/src/auth/auth_api.dart';
import 'package:flutter_securechat/src/auth/auth_coordinator.dart';
import 'package:flutter_securechat/src/background/background_scheduler.dart';
import 'package:flutter_securechat/src/background/background_tasks.dart';
import 'package:flutter_securechat/src/background/scheduled_message_service.dart';
import 'package:flutter_securechat/src/backup/backup_crypto.dart';
import 'package:flutter_securechat/src/backup/backup_service.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/crypto/crypto_protocol_store.dart';
import 'package:flutter_securechat/src/crypto/pre_key_manager.dart';
import 'package:flutter_securechat/src/domain/send_message_use_case.dart';
import 'package:flutter_securechat/src/export/export_audit_service.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/settings/account_data_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_securechat/src/storage/storage_management_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'physical background, backup, export, storage and account lifecycle',
    (tester) async {
      await tester.runAsync(_verifyDataLifecycle);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

Future<void> _verifyDataLifecycle() async {
  final root = await Directory.systemTemp.createTemp('device_data_lifecycle_');
  final databaseFile = File('${root.path}/storage.securejson');
  final sessionFile = File('${root.path}/session.securejson');
  final managedDirectory = Directory('${root.path}/managed-media');
  final backupDirectory = Directory('${root.path}/backups');
  final crypto = LocalAeadCryptoService(
    SecretKey(List<int>.generate(32, (index) => index + 71)),
  );
  final database = await SecureChatDatabase.open(
    file: databaseFile,
    crypto: crypto,
  );
  final session = await PersistentSessionStore.open(
    file: sessionFile,
    crypto: crypto,
  );
  final signaling = InMemorySignalingService();
  _DeviceAuthServer? server;
  try {
    await session.loginAndPersist(
      userId: 'me',
      displayName: 'Device User',
      phoneNumber: '+905000001234',
      accessToken: 'device-access-secret',
      refreshToken: 'device-refresh-secret',
    );
    await signaling.connect(
      userId: 'me',
      url: 'ws://device.invalid',
      accessToken: 'device-access-secret',
    );
    await managedDirectory.create(recursive: true);
    final mediaFile = File('${managedDirectory.path}/media.bin');
    await mediaFile.writeAsBytes(
      List<int>.generate(513, (index) => index % 251),
    );

    await database.conversations.insert(
      const ConversationEntity(
        id: 'alice',
        peerId: 'alice',
        peerName: 'Alice',
        peerPhone: '+905551234567',
      ),
    );
    await database.conversations.insert(
      const ConversationEntity(
        id: 'group-device',
        peerId: 'group-device',
        peerName: 'Device Group',
        peerPhone: '',
        isGroup: true,
        groupMembers: 'me,admin-2,member',
        groupAdmins: 'me,admin-2',
        isExportEnabled: true,
      ),
    );
    await database.messages.insert(
      const MessageEntity(
        id: 'text-keep',
        conversationId: 'alice',
        senderId: 'me',
        content: 'Device text survives media cleanup',
        contentType: StorageMessageContentType.text,
        timestamp: 100,
        status: StorageMessageStatus.sent,
        isOutgoing: true,
      ),
    );
    await database.messages.insert(
      MessageEntity(
        id: 'media-clean',
        conversationId: 'alice',
        senderId: 'me',
        content: 'media.bin|application/octet-stream|513|${mediaFile.path}',
        contentType: StorageMessageContentType.file,
        timestamp: 200,
        status: StorageMessageStatus.sent,
        isOutgoing: true,
      ),
    );
    await database.messages.insert(
      const MessageEntity(
        id: 'group-export-message',
        conversationId: 'group-device',
        senderId: 'me',
        content: 'Device export content',
        contentType: StorageMessageContentType.text,
        timestamp: 300,
        status: StorageMessageStatus.sent,
        isOutgoing: true,
      ),
    );

    final sender = SendMessageUseCase(
      database: database,
      signaling: signaling,
      session: session,
      crypto: crypto,
      maxRetryCount: 0,
      retryDelay: Duration.zero,
    );
    final scheduler = _DeviceScheduler();
    final scheduled = ScheduledMessageService(
      dao: database.scheduledMessages,
      sender: sender,
      signaling: signaling,
      session: session,
      scheduler: scheduler,
      now: () => DateTime(2026, 8, 18, 10),
      random: Random(3),
    );
    final oneOff = await scheduled.save(
      const ScheduledMessageDraft(
        content: 'Device scheduled secret',
        recipients: ['alice'],
        recipientNames: ['Alice'],
        hour: 11,
        minute: 0,
      ),
    );
    expect(scheduler.scheduled.map((item) => item.id), contains(oneOff.id));
    expect(await scheduled.processPlan(oneOff.id), isTrue);
    expect(await database.scheduledMessages.getById(oneOff.id), isNull);
    expect(
      signaling.sentMessages.whereType<EncryptedSignalMessage>(),
      isNotEmpty,
    );
    expect(
      await databaseFile.readAsString(),
      isNot(contains('Device scheduled secret')),
    );

    final timerUpdates = PendingTimerUpdateService(
      dao: database.pendingTimerUpdates,
      signaling: signaling,
      session: session,
      crypto: crypto,
    );
    await signaling.disconnect();
    await timerUpdates.sendOrQueue(
      targetUserId: 'alice',
      conversationId: 'alice',
      durationMs: 60000,
    );
    expect(await database.pendingTimerUpdates.getAll(), hasLength(1));
    await signaling.connect(
      userId: 'me',
      url: 'ws://device.invalid',
      accessToken: 'device-access-secret',
    );
    expect(await timerUpdates.flush(), 1);
    expect(await database.pendingTimerUpdates.getAll(), isEmpty);
    debugPrint('[device-data] scheduled-and-offline-timer');

    final backups = BackupService(
      database: database,
      session: session,
      backupDirectory: backupDirectory,
      crypto: BackupCrypto(random: Random(9)),
    );
    final backup = await backups.createBackup('device-password');
    final backupRaw = utf8.decode(
      await backup.readAsBytes(),
      allowMalformed: true,
    );
    expect(backupRaw, isNot(contains('Device export content')));
    expect(backupRaw, isNot(contains('device-access-secret')));
    await database.messages.delete('group-export-message');
    expect(
      await backups.restoreBackup(backup, 'device-password'),
      isA<BackupRestoreSuccess>(),
    );
    expect(
      (await database.messages.getById('group-export-message'))?.content,
      'Device export content',
    );
    debugPrint('[device-data] encrypted-backup-restore');

    final audit = ExportAuditService(
      database: database,
      session: session,
      crypto: crypto,
      signaling: signaling,
    );
    final exported = await audit.exportConversation('group-device');
    expect(exported.text, contains('Ben: Device export content'));
    final auditWire = signaling.sentMessages
        .whereType<AdminEncryptedLogSignal>()
        .single;
    expect(auditWire.adminPayloads.keys, ['admin-2']);
    expect(
      auditWire.toJson().toString(),
      isNot(contains('Device export content')),
    );
    expect(auditWire.toJson().toString(), isNot(contains('EXPORT')));
    debugPrint('[device-data] export-admin-audit');

    final storage = StorageManagementService(database);
    final policy = const AutoDownloadPolicy().copyWith(
      videosOnCellular: true,
      maxAutoDownloadBytes: 1024,
    );
    await storage.savePolicy(policy);
    expect((await storage.loadPolicy()).videosOnCellular, isTrue);
    expect(
      storage.shouldDownload(
        policy: policy,
        category: MediaCategory.video,
        fileSize: 1024,
        network: NetworkKind.cellular,
      ),
      isTrue,
    );
    final breakdown = (await storage.analyzeAll()).singleWhere(
      (item) => item.conversationId == 'alice',
    );
    expect(breakdown.fileBytes, 513);
    expect(await storage.cleanFiles('alice'), 513);
    expect(await mediaFile.exists(), isFalse);
    expect(await database.messages.getById('media-clean'), isNull);
    expect(
      (await database.messages.getById('text-keep'))?.content,
      'Device text survives media cleanup',
    );
    expect(
      await databaseFile.readAsString(),
      isNot(contains('videosOnCellular')),
    );
    debugPrint('[device-data] storage-policy-analysis-clean');

    final recurring = await scheduled.save(
      const ScheduledMessageDraft(
        content: 'Recurring cleanup marker',
        recipients: ['alice'],
        recipientNames: ['Alice'],
        hour: 12,
        minute: 0,
        repeat: ScheduledRepeat.daily,
      ),
    );
    server = await _DeviceAuthServer.start();
    final auth = AuthCoordinator(
      api: AuthApi(baseUrl: server.baseUrl),
      session: session,
      preKeys: PreKeyManager(DatabaseCryptoProtocolStore(database)),
      signaling: signaling,
      signalingUrl: 'ws://device.invalid',
    );
    var cleanupCallbacks = 0;
    var pushUnregisters = 0;
    final accountData = AccountDataService(
      auth: auth,
      database: database,
      scheduledMessages: scheduled,
      managedDirectories: [managedDirectory, backupDirectory],
      unregisterPush: () async {
        pushUnregisters++;
        return true;
      },
      afterLocalCleanup: () async => cleanupCallbacks++,
    );
    await accountData.deleteAccount();
    expect(server.paths, contains('/api/v1/account/delete'));
    expect(server.authorization, contains('Bearer device-access-secret'));
    expect(session.isLoggedIn, isFalse);
    expect(await database.conversations.getById('alice'), isNull);
    expect(await managedDirectory.exists(), isFalse);
    expect(await backupDirectory.exists(), isFalse);
    expect(scheduler.cancelled, contains(recurring.id));
    expect(pushUnregisters, 1);
    expect(cleanupCallbacks, 1);
    final sessionRaw = await sessionFile.readAsString();
    expect(sessionRaw, isNot(contains('device-access-secret')));
    expect(sessionRaw, isNot(contains('device-refresh-secret')));
    debugPrint('[device-data] server-confirmed-account-delete');
  } finally {
    await server?.close();
    await signaling.disconnect();
    await session.close();
    await database.close();
    if (await root.exists()) await root.delete(recursive: true);
  }
}

class _DeviceScheduler implements BackgroundScheduler {
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

class _DeviceAuthServer {
  _DeviceAuthServer(this._server);

  final HttpServer _server;
  final paths = <String>[];
  final authorization = <String>[];

  String get baseUrl => 'http://${_server.address.address}:${_server.port}';

  static Future<_DeviceAuthServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fixture = _DeviceAuthServer(server);
    server.listen(fixture._handle);
    return fixture;
  }

  Future<void> _handle(HttpRequest request) async {
    paths.add(request.uri.path);
    final bearer = request.headers.value(HttpHeaders.authorizationHeader);
    if (bearer != null) authorization.add(bearer);
    await utf8.decoder.bind(request).join();
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok'}));
    await request.response.close();
  }

  Future<void> close() => _server.close(force: true);
}
