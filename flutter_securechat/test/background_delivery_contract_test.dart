import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/background/background_scheduler.dart';
import 'package:flutter_securechat/src/background/background_tasks.dart';
import 'package:flutter_securechat/src/background/scheduled_message_service.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/domain/send_message_use_case.dart';
import 'package:flutter_securechat/src/incoming/incoming_message_handler.dart';
import 'package:flutter_securechat/src/network/network_resilience.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workmanager/workmanager.dart';

import 'support/private_chat_control_support.dart';

void main() {
  test('background sender is wired to a durable outbox', () {
    // The runtime has a private constructor and platform-only bootstrap. Keep
    // this narrow wiring guard until runtime dependencies can be injected.
    final source = File(
      'lib/src/background/background_tasks.dart',
    ).readAsStringSync();
    final start = source.indexOf('final sender = SendMessageUseCase(');
    final end = source.indexOf('final scheduler =', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    expect(
      source.substring(start, end),
      matches(RegExp(r'reliableQueue:\s*\w+')),
      reason: 'A socket enqueue must not be the only copy of scheduled work.',
    );
  });

  for (final deleted in [false, true]) {
    test(
      'worker completes ${deleted ? 'deleted' : 'disabled'} plan as no-op',
      () async {
        final fixture = await _Fixture.open();
        addTearDown(fixture.close);
        final plan = await fixture.savePlan();
        if (deleted) {
          await fixture.database.scheduledMessages.deleteById(plan.id);
        } else {
          await fixture.database.scheduledMessages.update(
            plan.copyWith(isEnabled: false),
          );
        }
        expect(
          await processScheduledBackgroundPlan(
            planId: plan.id,
            dao: fixture.database.scheduledMessages,
            service: fixture.service,
          ),
          isTrue,
        );
        expect(fixture.signaling.sentMessages, isEmpty);
        expect(await fixture.database.pendingSignals.count(), 0);
        expect(
          await fixture.database.scheduledMessages.getHistoryImmediate(),
          isEmpty,
        );
      },
    );
  }

  for (final repeat in [ScheduledRepeat.once, ScheduledRepeat.daily]) {
    for (final inWorker in [true, false]) {
      test(
        '${repeat.name} completion respects worker scope=$inWorker',
        () async {
          final fixture = await _Fixture.open();
          addTearDown(fixture.close);
          final plan = await fixture.savePlan(repeat: repeat);
          // The singleton installs its platform backend on first construction.
          Workmanager();
          final platform = _WorkmanagerRecorder();
          final original = WorkmanagerPlatform.instance;
          WorkmanagerPlatform.instance = platform;
          addTearDown(() => WorkmanagerPlatform.instance = original);
          fixture.useScheduler(
            WorkmanagerBackgroundScheduler(
              callbackDispatcher: secureChatBackgroundCallbackDispatcher,
              executingPlanId: inWorker ? plan.id : null,
            ),
            now: DateTime(2026, 9, 25, 11, 57),
          );

          expect(
            await processScheduledBackgroundPlan(
              planId: plan.id,
              dao: fixture.database.scheduledMessages,
              service: fixture.service,
            ),
            isTrue,
          );
          expect(
            platform.cancelled,
            inWorker ? isEmpty : ['securechat-scheduled-${plan.id}'],
          );
          expect(
            await fixture.database.scheduledMessages.getHistoryImmediate(),
            hasLength(1),
          );
          final next = await fixture.database.scheduledMessages.getById(
            plan.id,
          );
          if (repeat == ScheduledRepeat.once) {
            expect(next, isNull);
            expect(platform.registered, isEmpty);
          } else {
            expect(next!.nextTriggerTime, greaterThan(plan.nextTriggerTime));
            expect(platform.registered, [
              (
                name: 'securechat-scheduled-${plan.id}',
                policy: inWorker
                    ? ExistingWorkPolicy.append
                    : ExistingWorkPolicy.replace,
                planId: plan.id,
              ),
            ]);
          }
        },
      );
    }
  }

  for (final rejectSend in [false, true]) {
    test(
      'scheduled ciphertext survives close/reopen after '
      '${rejectSend ? 'post-connect rejection' : 'enqueue without ACK'}',
      () async {
        final fixture = await _Fixture.open();
        addTearDown(fixture.close);
        fixture.signaling.rejectSend = rejectSend;
        final plan = await fixture.savePlan();
        final attempts = <String>[];
        fixture.signaling.beforeSend = (signal) async {
          final pending = await fixture.database.pendingSignals.getAll();
          expect(pending, hasLength(1));
          expect(pending.single.encodedSignal, signal.encode());
          attempts.add(signal.encode());
        };

        expect(await fixture.service.processPlan(plan.id), isTrue);
        final pending = (await fixture.database.pendingSignals.getAll()).single;
        final message =
            (await fixture.database.messages.getAllMessages()).single;
        expect(pending.retainUntilReceipt, isTrue);
        expect(pending.messageId, message.id);
        expect(pending.recipientId, 'alice');
        expect(pending.encodedSignal, isNot(contains('scheduled secret')));
        final wire =
            SignalMessage.decode(pending.encodedSignal)
                as EncryptedSignalMessage;
        expect(wire.deliveryId, pending.id);
        expect(attempts, [pending.encodedSignal]);

        // No receipt arrives. Closing must be bounded and must retain the
        // encrypted retry record, even when the socket claimed success.
        await fixture.reopen().timeout(const Duration(seconds: 5));
        final restored =
            (await fixture.database.pendingSignals.getAll()).single;
        expect(restored.id, pending.id);
        expect(restored.encodedSignal, pending.encodedSignal);
        final result = await fixture.queue.flushQueue();
        expect(result.sent, 1);
        expect(result.remaining, 1);
        expect(fixture.signaling.sentMessages.single.encode(), attempts.single);
        expect(await fixture.database.messages.getAllMessages(), hasLength(1));
      },
    );
  }

  test('late matching receipt clears reopened scheduled outbox only', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.close);
    final plan = await fixture.savePlan();
    expect(await fixture.service.processPlan(plan.id), isTrue);
    final pending = (await fixture.database.pendingSignals.getAll()).single;
    await fixture.reopen();

    await fixture.queue.acknowledgeReceipt(pending.messageId!, 'other-peer');
    expect(await fixture.database.pendingSignals.count(), 1);
    await fixture.queue.acknowledgeReceipt('other-message', 'alice');
    expect(await fixture.database.pendingSignals.count(), 1);
    await fixture.queue.acknowledgeReceipt(pending.messageId!, 'alice');
    expect(await fixture.database.pendingSignals.count(), 0);
    expect((await fixture.queue.flushQueue()).sent, 0);
  });

  test('receipt wait times out with ciphertext still durable', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.close);
    final plan = await fixture.savePlan();
    await fixture.service.processPlan(plan.id);
    final pending = (await fixture.database.pendingSignals.getAll()).single;

    expect(
      await waitForBackgroundOutboxReceipts(
        outbox: fixture.queue,
        signaling: fixture.signaling,
        maxWait: const Duration(milliseconds: 30),
        pollInterval: const Duration(milliseconds: 5),
      ).timeout(const Duration(seconds: 2)),
      1,
    );
    await fixture.reopen();
    expect(
      (await fixture.database.pendingSignals.getAll()).single.encodedSignal,
      pending.encodedSignal,
    );
  });

  test('receipt wait sees deletion committed in another isolate', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.close);
    final plan = await fixture.savePlan();
    await fixture.service.processPlan(plan.id);
    final pending = (await fixture.database.pendingSignals.getAll()).single;
    final path = fixture.file.path;
    final messageId = pending.messageId!;
    final wait = waitForBackgroundOutboxReceipts(
      outbox: fixture.queue,
      signaling: fixture.signaling,
      maxWait: const Duration(seconds: 5),
      pollInterval: const Duration(milliseconds: 10),
    );
    await Isolate.run(() => _deleteReceiptInWorker(path, messageId));
    expect(await wait, 0);
    await fixture.reopen();
    expect(await fixture.database.pendingSignals.count(), 0);
  });

  test('connected foreground recovers worker send without restart', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.close);
    final recovery = ScheduledOutboxRecovery(
      scheduledMessages: fixture.database.scheduledMessages,
      outbox: fixture.queue,
      signaling: fixture.signaling,
    );
    addTearDown(recovery.close);
    final sent = Completer<String>();
    fixture.signaling.beforeSend = (wire) async {
      if (!sent.isCompleted) sent.complete(wire.encode());
    };
    final directory = fixture.directory.path;
    final workerWire = await _sendInSeparateIsolate(directory);
    expect(await sent.future.timeout(const Duration(seconds: 5)), workerWire);
    expect(fixture.signaling.currentStatus.isConnected, isTrue);
    final pending = (await fixture.database.pendingSignals.getAll()).single;
    final failures = <Object>[];
    final incoming = IncomingMessageHandler(
      database: fixture.database,
      signaling: fixture.signaling,
      session: fixture.session,
      crypto: fixture.crypto,
      onAsyncFailure: (operation, error, stack) async => failures.add(error),
    )..start();
    addTearDown(incoming.close);
    fixture.signaling.addIncoming(
      await encryptTestPrivateChatControl(
        crypto: fixture.crypto,
        control: DeliveryReceiptSignal(
          senderId: 'alice',
          recipientId: 'me',
          timestamp: DateTime.now(),
          messageId: pending.messageId!,
          status: 'DELIVERED',
        ),
      ),
    );
    await incoming.waitForIdle();
    expect(failures, isEmpty);
    expect(await fixture.database.pendingSignals.count(), 0);
    expect(
      (await fixture.database.messages.getById(pending.messageId!))?.status,
      StorageMessageStatus.delivered,
    );
    // Receipt and unrelated writes must not trigger an endless history flush.
    await fixture.database.conversations.updateMuted('alice', true);
    await Future<void>.delayed(Duration.zero);
    expect(fixture.signaling.sentMessages, hasLength(1));
  });
}

Future<String> _sendInSeparateIsolate(String directory) =>
    Isolate.run(() => _sendScheduledInWorker(directory));

Future<String> _sendScheduledInWorker(String directory) async {
  final fixture = _Fixture(Directory(directory));
  await fixture._openResources();
  try {
    final plan = await fixture.savePlan();
    await fixture.service.processPlan(plan.id);
    return (await fixture.database.pendingSignals.getAll())
        .single
        .encodedSignal;
  } finally {
    await fixture._closeResources();
  }
}

Future<void> _deleteReceiptInWorker(String path, String messageId) async {
  final database = await SecureChatDatabase.open(
    file: File(path),
    crypto: LocalAeadCryptoService(
      SecretKey(List.generate(32, (index) => index + 1)),
    ),
  );
  try {
    await database.pendingSignals.deleteDelivered(messageId, 'alice');
  } finally {
    await database.close();
  }
}

class _Fixture {
  _Fixture(this.directory)
    : file = File('${directory.path}/storage.securejson');

  final Directory directory;
  final File file;
  final crypto = LocalAeadCryptoService(
    SecretKey(List.generate(32, (index) => index + 1)),
  );
  final session = SessionStore(userId: 'me', accessToken: 'token');
  final scheduler = _RunningTaskScheduler();
  late SecureChatDatabase database;
  late _EnqueueOnlySignaling signaling;
  late OfflineMessageQueue queue;
  late ScheduledMessageService service;

  static Future<_Fixture> open() async {
    final fixture = _Fixture(
      await Directory.systemTemp.createTemp('background_delivery_contract_'),
    );
    await fixture._openResources();
    await fixture.database.conversations.insert(
      const ConversationEntity(
        id: 'alice',
        peerId: 'alice',
        peerName: 'Alice',
        peerPhone: '',
      ),
    );
    return fixture;
  }

  Future<void> _openResources() async {
    database = await SecureChatDatabase.open(file: file, crypto: crypto);
    signaling = _EnqueueOnlySignaling();
    await signaling.connect(
      userId: 'me',
      url: 'ws://local',
      accessToken: 'token',
    );
    queue = OfflineMessageQueue(database: database, signaling: signaling);
    useScheduler(scheduler);
  }

  void useScheduler(BackgroundScheduler scheduler, {DateTime? now}) {
    service = ScheduledMessageService(
      dao: database.scheduledMessages,
      sender: SendMessageUseCase(
        database: database,
        signaling: signaling,
        session: session,
        crypto: crypto,
        reliableQueue: queue,
        maxRetryCount: 0,
        retryDelay: Duration.zero,
      ),
      signaling: signaling,
      session: session,
      scheduler: scheduler,
      now: () => now ?? DateTime(2026, 9, 25, 11, 56),
      random: Random(1),
    );
  }

  Future<ScheduledMessageEntity> savePlan({
    ScheduledRepeat repeat = ScheduledRepeat.once,
  }) => service.save(
    ScheduledMessageDraft(
      content: 'scheduled secret',
      recipients: ['alice'],
      recipientNames: ['Alice'],
      hour: 11,
      minute: 57,
      repeat: repeat,
    ),
  );

  Future<void> _closeResources() async {
    await queue.close();
    await signaling.dispose();
    await database.close();
  }

  Future<void> reopen() async {
    await _closeResources();
    await _openResources();
  }

  Future<void> close() async {
    await _closeResources();
    await directory.delete(recursive: true);
  }
}

class _WorkmanagerRecorder extends WorkmanagerPlatform {
  final cancelled = <String>[];
  final registered =
      <({String name, ExistingWorkPolicy? policy, String? planId})>[];

  @override
  Future<void> cancelByUniqueName(String uniqueName) async {
    cancelled.add(uniqueName);
  }

  @override
  Future<void> registerOneOffTask(
    String uniqueName,
    String taskName, {
    Map<String, dynamic>? inputData,
    Duration? initialDelay,
    Constraints? constraints,
    ExistingWorkPolicy? existingWorkPolicy,
    BackoffPolicy? backoffPolicy,
    Duration? backoffPolicyDelay,
    String? tag,
    OutOfQuotaPolicy? outOfQuotaPolicy,
    ForegroundServiceConfig? foregroundServiceConfig,
    bool expedited = false,
  }) async {
    expect(taskName, WorkmanagerBackgroundScheduler.scheduledMessageTask);
    registered.add((
      name: uniqueName,
      policy: existingWorkPolicy,
      planId: inputData?['planId'] as String?,
    ));
  }
}

// Models local enqueue success, not server acceptance or a recipient receipt.
class _EnqueueOnlySignaling extends InMemorySignalingService {
  bool rejectSend = false;
  Future<void> Function(SignalMessage)? beforeSend;

  @override
  Future<bool> send(SignalMessage message) async {
    await beforeSend?.call(message);
    if (rejectSend) {
      setConnected(false);
      return false;
    }
    return super.send(message);
  }
}

class _RunningTaskScheduler implements BackgroundScheduler {
  @override
  Future<void> cancelScheduledMessage(String id) async {}

  @override
  Future<void> initialize() async {}

  @override
  Future<void> registerRecurringTasks() async {}

  @override
  Future<void> scheduleMessage(ScheduledMessageEntity message) async {}
}
