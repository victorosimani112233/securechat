import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/background/background_scheduler.dart';
import 'package:flutter_securechat/src/background/background_tasks.dart';
import 'package:flutter_securechat/src/background/scheduled_message_service.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/crypto/crypto_protocol_store.dart';
import 'package:flutter_securechat/src/domain/send_message_use_case.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/private_chat_control_support.dart';

void main() {
  test('custom schedule chooses the next selected weekday', () {
    final next = ScheduledMessageService.calculateNextTrigger(
      hour: 9,
      minute: 30,
      repeat: ScheduledRepeat.custom,
      days: {1, 5},
      now: DateTime(2026, 8, 13, 10), // Thursday.
    );
    expect(next, DateTime(2026, 8, 14, 9, 30));
  });

  test('one-off scheduled message sends encrypted and removes plan', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.close);
    final now = DateTime(2026, 8, 13, 10);
    final scheduler = _FakeScheduler();
    final service = fixture.scheduled(scheduler, now);
    final plan = await service.save(
      const ScheduledMessageDraft(
        content: 'later secret',
        recipients: ['alice'],
        recipientNames: ['Alice'],
        hour: 11,
        minute: 0,
      ),
    );

    expect(scheduler.scheduled.single.id, plan.id);
    expect(await service.processPlan(plan.id), isTrue);
    expect(await fixture.database.scheduledMessages.getById(plan.id), isNull);
    expect(
      fixture.signaling.sentMessages.whereType<EncryptedSignalMessage>(),
      hasLength(1),
    );
    expect(await fixture.file.readAsString(), isNot(contains('later secret')));
  });

  test('daily scheduled message advances and is re-registered', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.close);
    final now = DateTime(2026, 8, 13, 10);
    final scheduler = _FakeScheduler();
    final service = fixture.scheduled(scheduler, now);
    final plan = await service.save(
      const ScheduledMessageDraft(
        content: 'daily secret',
        recipients: ['alice'],
        recipientNames: ['Alice'],
        hour: 9,
        minute: 0,
        repeat: ScheduledRepeat.daily,
      ),
    );
    scheduler.scheduled.clear();

    await service.processPlan(plan.id);

    final updated = await fixture.database.scheduledMessages.getById(plan.id);
    expect(
      updated?.nextTriggerTime,
      DateTime(2026, 8, 14, 9).millisecondsSinceEpoch,
    );
    expect(scheduler.scheduled.single.id, plan.id);
  });

  test('timer update persists offline then flushes after reconnect', () async {
    final fixture = await _Fixture.open(connected: false);
    addTearDown(fixture.close);
    final service = PendingTimerUpdateService(
      dao: fixture.database.pendingTimerUpdates,
      signaling: fixture.signaling,
      session: fixture.session,
      crypto: fixture.crypto,
    );
    await service.sendOrQueue(
      targetUserId: 'alice',
      conversationId: 'alice',
      durationMs: 60000,
    );
    expect(await fixture.database.pendingTimerUpdates.getAll(), hasLength(1));

    await fixture.connect();
    expect(await service.flush(), 1);
    expect(await fixture.database.pendingTimerUpdates.getAll(), isEmpty);
    final wire = fixture.signaling.sentMessages.single;
    expect(wire, isA<EncryptedSignalMessage>());
    expect(
      await decryptTestPrivateChatControl(
        crypto: fixture.crypto,
        wire: wire as EncryptedSignalMessage,
      ),
      isA<DisappearingTimerSignal>(),
    );
  });

  test('sender key rotation distributes before committing new key', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.close);
    await fixture.database.conversations.insert(
      const ConversationEntity(
        id: 'group-1',
        peerId: 'group-1',
        peerName: 'Group',
        peerPhone: '',
        isGroup: true,
        groupMembers: 'me,alice,bob',
      ),
    );
    final store = DatabaseCryptoProtocolStore(fixture.database);
    final service = SenderKeyRotationService(
      database: fixture.database,
      store: store,
      crypto: fixture.crypto,
      signaling: fixture.signaling,
      session: fixture.session,
      random: Random(7),
    );

    expect(await service.rotate('group-1'), isTrue);
    expect(await store.loadSenderKey('group-1', 'me', 1), hasLength(32));
    final deliveries = fixture.signaling.sentMessages
        .whereType<EncryptedSignalMessage>()
        .toList();
    expect(deliveries.map((message) => message.recipientId).toSet(), {
      'alice',
      'bob',
    });
    expect(
      deliveries.every((message) => !message.envelope.contains('SKDM:')),
      isTrue,
    );
  });
}

class _Fixture {
  _Fixture({
    required this.directory,
    required this.file,
    required this.database,
    required this.crypto,
    required this.signaling,
    required this.session,
  });

  final Directory directory;
  final File file;
  final SecureChatDatabase database;
  final LocalAeadCryptoService crypto;
  final InMemorySignalingService signaling;
  final SessionStore session;

  static Future<_Fixture> open({bool connected = true}) async {
    final directory = await Directory.systemTemp.createTemp('background_test_');
    final file = File('${directory.path}/storage.securejson');
    final crypto = LocalAeadCryptoService(
      SecretKey(List.generate(32, (index) => index + 1)),
    );
    final database = await SecureChatDatabase.open(file: file, crypto: crypto);
    await database.conversations.insert(
      const ConversationEntity(
        id: 'alice',
        peerId: 'alice',
        peerName: 'Alice',
        peerPhone: '',
      ),
    );
    final signaling = InMemorySignalingService();
    final session = SessionStore(userId: 'me', accessToken: 'token');
    final fixture = _Fixture(
      directory: directory,
      file: file,
      database: database,
      crypto: crypto,
      signaling: signaling,
      session: session,
    );
    if (connected) await fixture.connect();
    return fixture;
  }

  Future<void> connect() =>
      signaling.connect(userId: 'me', url: 'ws://local', accessToken: 'token');

  ScheduledMessageService scheduled(
    BackgroundScheduler scheduler,
    DateTime now,
  ) => ScheduledMessageService(
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
    now: () => now,
    random: Random(1),
  );

  Future<void> close() async {
    await database.close();
    await signaling.disconnect();
    await directory.delete(recursive: true);
  }
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
  Future<void> scheduleMessage(ScheduledMessageEntity message) async =>
      scheduled.add(message);
}
