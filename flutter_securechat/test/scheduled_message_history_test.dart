import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/background/background_scheduler.dart';
import 'package:flutter_securechat/src/background/scheduled_message_service.dart';
import 'package:flutter_securechat/src/backup/backup_service.dart';
import 'package:flutter_securechat/src/calls/call_readiness_service.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/domain/send_message_use_case.dart';
import 'package:flutter_securechat/src/features/scheduled/scheduled_messages_screen.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations.dart';
import 'package:flutter_securechat/src/security/chat_access_service.dart';
import 'package:flutter_securechat/src/security/chat_lock_credential_service.dart';
import 'package:flutter_securechat/src/services/app_container.dart';
import 'package:flutter_securechat/src/services/conversation_repository.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'one-shot execution stores real outcome, full snapshot and actual time',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      final plan = await f.save();
      await f.reopen();
      expect(
        (await f.database.scheduledMessages.getById(
          plan.id,
        ))!.recipientNameList,
        ['Alice, QA'],
      );
      f.now = f.now.add(const Duration(hours: 2, seconds: 17));
      expect(await f.service.processDue(), 1);

      final history = (await f.history()).single;
      expect(history.planId, plan.id);
      expect(history.messageContent, 'scheduled secret');
      expect(history.scheduledAt, plan.nextTriggerTime);
      expect(history.executedAt, f.now.millisecondsSinceEpoch);
      expect(history.completedAt, greaterThanOrEqualTo(history.executedAt));
      expect(history.recipients.single.recipientId, 'alice');
      expect(history.recipients.single.recipientName, 'Alice, QA');
      expect(history.recipients.single.outcome, ScheduledRecipientOutcome.sent);
      expect(history.status, ScheduledHistoryStatus.sent);
      expect(await f.database.scheduledMessages.getById(plan.id), isNull);
      expect(f.scheduler.cancelled, contains(plan.id));
      expect(
        f.signaling.sentMessages.whereType<EncryptedSignalMessage>(),
        hasLength(1),
      );
      expect(
        (await f.database.messages.getAllMessages()).single.status,
        StorageMessageStatus.sent,
      );
      expect(await f.service.processPlan(plan.id), isFalse);

      await f.reopen();
      expect((await f.history()).single.toJson(), history.toJson());
      for (final file in f.directory.listSync().whereType<File>()) {
        final bytes = latin1.decode(await file.readAsBytes());
        expect(bytes, isNot(contains('scheduled secret')));
        expect(bytes, isNot(contains('Alice, QA')));
      }
    },
  );

  test(
    'daily executions remain independent after editing and deleting the plan',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      final plan = await f.save(repeat: ScheduledRepeat.daily);
      f.now = f.now.add(const Duration(hours: 2));
      expect(await f.service.processDue(), 1);
      final first = (await f.history()).single;
      final next = (await f.database.scheduledMessages.getById(plan.id))!;
      expect(next.nextTriggerTime, greaterThan(first.executedAt));
      await f.save(
        id: plan.id,
        content: 'second execution',
        repeat: ScheduledRepeat.daily,
      );
      f.now = f.now.add(const Duration(days: 1));
      expect(await f.service.processDue(), 1);
      await f.service.delete(plan.id);
      await f.reopen();
      final history = await f.history();
      expect(history, hasLength(2));
      expect(history.first.messageContent, 'second execution');
      expect(history.last.toJson(), first.toJson());
      expect(history.map((item) => item.id).toSet(), hasLength(2));
      expect(history.every((item) => item.planId == plan.id), isTrue);
    },
  );

  test(
    'partial fan-out preserves encryption and delivery failures and continues',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      f.crypto.failFor.add('bob');
      f.signaling.rejectFor.add('carol');
      f.signaling.throwFor.add('dave');
      final plan = await f.save(
        recipients: ['alice', 'bob', 'carol', 'dave', 'eve'],
      );
      await f.service.processPlan(plan.id);
      final history = (await f.history()).single;
      expect(history.status, ScheduledHistoryStatus.partialFailure);
      expect(history.recipients.map((item) => item.outcome), [
        ScheduledRecipientOutcome.sent,
        ScheduledRecipientOutcome.encryptionFailed,
        ScheduledRecipientOutcome.deliveryFailed,
        ScheduledRecipientOutcome.failed,
        ScheduledRecipientOutcome.sent,
      ]);
      final messages = await f.database.messages.getAllMessages();
      expect(
        messages.firstWhere((m) => m.conversationId == 'bob').status,
        StorageMessageStatus.failed,
      );
      expect(
        messages.firstWhere((m) => m.conversationId == 'carol').status,
        StorageMessageStatus.failed,
      );
      final encoded = jsonEncode(history.toJson());
      expect(encoded, isNot(contains('private exception detail')));
      await f.reopen();
      expect((await f.history()).single.toJson(), history.toJson());
    },
  );

  test('all failed recipients never produce a sent status', () async {
    final f = await _Fixture.open();
    addTearDown(f.close);
    f.signaling.rejectFor.add('alice');
    final plan = await f.save();
    await f.service.processPlan(plan.id);
    expect((await f.history()).single.status, ScheduledHistoryStatus.failed);
    expect(f.signaling.sentMessages, isEmpty);
  });

  test(
    'a failed repeat is recorded and the next run can succeed independently',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      final plan = await f.save(repeat: ScheduledRepeat.daily);
      f.signaling.rejectFor.add('alice');
      f.now = f.now.add(const Duration(hours: 2));
      expect(await f.service.processDue(), 1);
      final next = (await f.database.scheduledMessages.getById(plan.id))!;
      expect(f.scheduler.scheduled.last.nextTriggerTime, next.nextTriggerTime);
      f.signaling.rejectFor.clear();
      f.now = f.now.add(const Duration(days: 1));
      expect(await f.service.processDue(), 1);
      expect((await f.history()).map((run) => run.status), [
        ScheduledHistoryStatus.sent,
        ScheduledHistoryStatus.failed,
      ]);
    },
  );

  test(
    'offline execution leaves its plan pending and records no fabricated send',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      final plan = await f.save();
      f.signaling.allowConnect = false;
      f.signaling.setConnected(false);
      f.now = f.now.add(const Duration(hours: 2));
      expect(await f.service.processDue(), 0);
      expect(await f.history(), isEmpty);
      expect(await f.database.messages.getAllMessages(), isEmpty);
      expect(
        (await f.database.scheduledMessages.getById(plan.id))!.toJson(),
        plan.toJson(),
      );
      f.signaling.allowConnect = true;
      expect(await f.service.processDue(), 1);
      expect((await f.history()).single.status, ScheduledHistoryStatus.sent);
    },
  );

  test(
    'disabled schedules, including the global setting, produce no history',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      final plan = await f.save();
      f.session.scheduledMessagesEnabled = false;
      expect(await f.service.processPlan(plan.id), isFalse);
      f.session.scheduledMessagesEnabled = true;
      await f.service.setEnabled(plan.id, false);
      expect(await f.service.processPlan(plan.id), isFalse);
      expect(await f.history(), isEmpty);
      expect(f.signaling.sentMessages, isEmpty);
    },
  );

  test(
    'overlapping callbacks in one service execute a plan only once',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      final plan = await f.save();
      final first = f.service.processPlan(plan.id);
      final second = f.service.processPlan(plan.id);
      expect(await first, isTrue);
      expect(await second, isFalse);
      expect(await f.history(), hasLength(1));
      expect(f.signaling.sentMessages, hasLength(1));
    },
  );

  test(
    'history write failure leaves one-shot plan intact in memory and on disk',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      final plan = await f.save();
      f.sender.afterSend = () => f.database.store.failMidTransaction = true;
      await expectLater(f.service.processPlan(plan.id), throwsStateError);
      expect(await f.database.scheduledMessages.getById(plan.id), isNotNull);
      expect(await f.history(), isEmpty);
      expect(f.scheduler.cancelled, isEmpty);
      await f.reopen();
      expect(await f.database.scheduledMessages.getById(plan.id), isNotNull);
      expect(await f.history(), isEmpty);
    },
  );

  test('bounded history retains the latest 500 runs after reopen', () async {
    final f = await _Fixture.open();
    addTearDown(f.close);
    for (var index = 0; index < ScheduledMessageDao.historyLimit + 3; index++) {
      await f.database.scheduledMessages.completeRun(
        _entry('run-$index', index),
      );
    }
    await f.reopen();
    final history = await f.history();
    expect(history, hasLength(ScheduledMessageDao.historyLimit));
    expect(history.first.executedAt, 502);
    expect(history.last.executedAt, 3);
    expect(await f.service.watchHistory().first, hasLength(500));
  });

  test('encrypted backup includes history and restores it durably', () async {
    final f = await _Fixture.open();
    addTearDown(f.close);
    final plan = await f.save();
    await f.service.processPlan(plan.id);
    final original = (await f.history()).single;
    final backup = BackupService(
      database: f.database,
      session: f.session,
      backupDirectory: Directory('${f.directory.path}/backups'),
    );
    final file = await backup.createBackup('history-test-password');
    expect(
      latin1.decode(await file.readAsBytes()),
      isNot(contains('scheduled secret')),
    );
    await f.database.clearAll();
    expect(await f.history(), isEmpty);
    expect(
      await backup.restoreBackup(file, 'history-test-password'),
      isA<BackupRestoreSuccess>(),
    );
    await f.reopen();
    expect((await f.history()).single.toJson(), original.toJson());
  });

  test(
    'timed messages never leave a non-expiring content copy in history',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      final alice = (await f.database.conversations.getById('alice'))!;
      await f.database.conversations.update(
        alice.copyWith(disappearingDuration: 60000),
      );
      final plan = await f.save();
      await f.service.processPlan(plan.id);
      final item = (await f.history()).single;
      expect(item.status, ScheduledHistoryStatus.sent);
      expect(item.contentRetained, isFalse);
      expect(item.messageContent, isEmpty);
      expect(jsonEncode(item.toJson()), isNot(contains('scheduled secret')));
      await f.reopen();
      expect((await f.history()).single.contentRetained, isFalse);
      expect((await f.history()).single.messageContent, isEmpty);
    },
  );

  test(
    'legacy snapshots without history stay empty rather than inferring sends',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      final plan = await f.save();
      await f.service.processPlan(plan.id);
      final legacy =
          (jsonDecode(await f.database.exportPortableJson()) as Map)
              .cast<String, Object?>()
            ..remove('scheduledMessageHistory');
      await f.database.replaceFromPortableJson(jsonEncode(legacy));
      await f.reopen();
      expect(await f.database.messages.getAllMessages(), isNotEmpty);
      expect(await f.history(), isEmpty);
    },
  );

  testWidgets(
    'history tab shows descending rows and full read-only details on a narrow screen',
    (tester) async {
      final f = (await tester.runAsync(_Fixture.open))!;
      addTearDown(f.close);
      final longContent = 'Full scheduled content ' * 80;
      await tester.runAsync(() async {
        await f.database.scheduledMessages.completeRun(_entry('older', 1));
        await f.database.scheduledMessages.completeRun(
          _entry('newer', 2, content: longContent),
        );
      });
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pumpHistory(tester, f, scale: 1.5);
      expect(find.text('Create'), findsOneWidget);
      expect(find.text('Existing'), findsOneWidget);
      final newer = find.byKey(const ValueKey('scheduled-history-newer'));
      final older = find.byKey(const ValueKey('scheduled-history-older'));
      expect(
        tester.getTopLeft(newer).dy,
        lessThan(tester.getTopLeft(older).dy),
      );
      await tester.tap(newer);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(SelectableText, longContent), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(Switch), findsNothing);
      await tester.drag(find.byType(ListView).last, const Offset(0, -6000));
      await tester.pumpAndSettle();
      expect(find.text('Alice, QA'), findsOneWidget);
      expect(find.text('alice'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'locked history is redacted, fails closed, then authorizes through chatAccess',
    (tester) async {
      final f = (await tester.runAsync(_Fixture.open))!;
      addTearDown(f.close);
      await tester.runAsync(() async {
        final alice = (await f.database.conversations.getById('alice'))!;
        await f.database.conversations.update(alice.copyWith(isLocked: true));
        final plan = await f.save();
        await f.service.processPlan(plan.id);
      });
      final authenticator = _Authenticator();
      await _pumpHistory(tester, f, authenticator: authenticator);
      expect(find.text('scheduled secret'), findsNothing);
      expect(find.text('Alice, QA'), findsNothing);
      final row = find.descendant(
        of: find.byKey(const ValueKey('scheduled-history-list')),
        matching: find.byType(ListTile),
      );
      await tester.tap(row.first);
      await tester.pumpAndSettle();
      final unlock = find.byKey(const ValueKey('scheduled-history-unlock'));
      await tester.tap(unlock);
      await tester.pumpAndSettle();
      expect(authenticator.calls, 1);
      expect(find.text('scheduled secret'), findsNothing);
      authenticator.allow = true;
      await tester.tap(unlock);
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(SelectableText, 'scheduled secret'),
        findsOneWidget,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('scheduled secret'), findsNothing);
      expect(unlock, findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'stored chat passwords take precedence over device authentication',
    (tester) async {
      final f = (await tester.runAsync(_Fixture.open))!;
      addTearDown(f.close);
      final credentials = _Credentials();
      final authenticator = _Authenticator()..allow = true;
      await tester.runAsync(() async {
        await f.database.scheduledMessages.completeRun(
          _entry('locked', 1, locked: true),
        );
      });
      await _pumpHistory(
        tester,
        f,
        authenticator: authenticator,
        credentials: credentials,
      );
      await tester.tap(find.byKey(const ValueKey('scheduled-history-locked')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('scheduled-history-unlock')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('scheduled secret'), findsNothing);
      expect(authenticator.calls, 0);
      await tester.enterText(find.byType(TextField), 'correct-password');
      await tester.tap(find.byKey(const ValueKey('chat-unlock-submit')));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(SelectableText, 'scheduled secret'),
        findsOneWidget,
      );
      expect(authenticator.calls, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'locking or deleting a recipient hides an already-open history detail',
    (tester) async {
      final f = (await tester.runAsync(_Fixture.open))!;
      addTearDown(f.close);
      await tester.runAsync(
        () => f.database.scheduledMessages.completeRun(_entry('live-lock', 1)),
      );
      final authenticator = _Authenticator()..allow = true;
      await _pumpHistory(tester, f, authenticator: authenticator);
      await tester.tap(
        find.byKey(const ValueKey('scheduled-history-live-lock')),
      );
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(SelectableText, 'scheduled secret'),
        findsOneWidget,
      );
      await tester.runAsync(() async {
        final alice = (await f.database.conversations.getById('alice'))!;
        await f.database.conversations.update(alice.copyWith(isLocked: true));
      });
      await tester.pumpAndSettle();
      expect(find.text('scheduled secret'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('scheduled-history-unlock')));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(SelectableText, 'scheduled secret'),
        findsOneWidget,
      );
      await tester.runAsync(() => f.database.conversations.delete('alice'));
      await tester.pumpAndSettle();
      expect(find.text('scheduled secret'), findsNothing);
      expect(
        find.byKey(const ValueKey('scheduled-history-unlock')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}

ScheduledMessageHistoryEntity _entry(
  String id,
  int executedAt, {
  String content = 'scheduled secret',
  bool locked = false,
}) => ScheduledMessageHistoryEntity(
  id: id,
  planId: 'plan',
  messageContent: content,
  repeatType: 'DAILY',
  scheduledAt: executedAt,
  executedAt: executedAt,
  completedAt: executedAt,
  recipients: [
    ScheduledMessageRecipientResult(
      recipientId: 'alice',
      recipientName: 'Alice, QA',
      outcome: ScheduledRecipientOutcome.sent,
      wasLocked: locked,
    ),
  ],
);

class _Fixture {
  _Fixture(this.directory, this.file, this.database);
  final Directory directory;
  final File file;
  SecureChatDatabase database;
  final crypto = _Crypto();
  final signaling = _Signaling();
  final session = SessionStore(
    userId: 'me',
    accessToken: 'token',
    phoneNumber: '+905001112233',
  );
  final scheduler = _Scheduler();
  late _Sender sender;
  late ScheduledMessageService service;
  DateTime now = DateTime(2026, 9, 22, 10);

  static Future<_Fixture> open() async {
    final directory = await Directory.systemTemp.createTemp(
      'scheduled_history_',
    );
    final file = File('${directory.path}/storage.securejson');
    final database = await SecureChatDatabase.open(
      file: file,
      crypto: _Crypto(),
    );
    final fixture = _Fixture(directory, file, database);
    await database.conversations.insert(
      const ConversationEntity(
        id: 'alice',
        peerId: 'alice',
        peerName: 'Alice, QA',
        peerPhone: '',
      ),
    );
    await fixture.signaling.connect(
      userId: 'me',
      url: 'ws://local',
      accessToken: 'token',
    );
    fixture._bind();
    return fixture;
  }

  void _bind() {
    sender = _Sender(
      database: database,
      signaling: signaling,
      session: session,
      crypto: crypto,
    );
    service = ScheduledMessageService(
      dao: database.scheduledMessages,
      sender: sender,
      signaling: signaling,
      session: session,
      scheduler: scheduler,
      now: () => now,
      random: Random(7),
    );
  }

  Future<ScheduledMessageEntity> save({
    String? id,
    String content = 'scheduled secret',
    List<String> recipients = const ['alice'],
    ScheduledRepeat repeat = ScheduledRepeat.once,
  }) => service.save(
    ScheduledMessageDraft(
      content: content,
      recipients: recipients,
      recipientNames: recipients
          .map((id) => id == 'alice' ? 'Alice, QA' : id)
          .toList(),
      hour: 11,
      minute: 0,
      repeat: repeat,
    ),
    id: id,
  );

  Future<List<ScheduledMessageHistoryEntity>> history() =>
      database.scheduledMessages.getHistoryImmediate();
  Future<void> reopen() async {
    await database.close();
    database = await SecureChatDatabase.open(file: file, crypto: crypto);
    _bind();
  }

  Future<void> close() async {
    await database.close();
    await signaling.dispose();
    await directory.delete(recursive: true);
  }
}

class _Crypto extends LocalAeadCryptoService {
  _Crypto() : super(SecretKey(List.generate(32, (index) => index + 1)));
  final failFor = <String>{};
  @override
  Future<String> encryptDirect({
    required String recipientId,
    required String plaintext,
  }) {
    if (failFor.contains(recipientId))
      throw StateError('private exception detail');
    return super.encryptDirect(recipientId: recipientId, plaintext: plaintext);
  }
}

class _Signaling extends InMemorySignalingService {
  bool allowConnect = true;
  final rejectFor = <String>{};
  final throwFor = <String>{};
  @override
  Future<void> connect({
    required String userId,
    required String url,
    required String accessToken,
    AccessTokenProvider? tokenProvider,
    AccessTokenProvider? refreshToken,
  }) async {
    if (!allowConnect) return;
    await super.connect(userId: userId, url: url, accessToken: accessToken);
  }

  @override
  Future<bool> send(SignalMessage message) {
    if (message is EncryptedSignalMessage) {
      if (throwFor.contains(message.recipientId))
        throw StateError('private exception detail');
      if (rejectFor.contains(message.recipientId)) return Future.value(false);
    }
    return super.send(message);
  }
}

class _Sender extends SendMessageUseCase {
  _Sender({
    required super.database,
    required super.signaling,
    required super.session,
    required super.crypto,
  }) : super(maxRetryCount: 0, retryDelay: Duration.zero);
  void Function()? afterSend;
  @override
  Future<SendMessageOutcome> call(SendMessageRequest request) async {
    final outcome = await super.call(request);
    afterSend?.call();
    return outcome;
  }
}

class _Scheduler implements BackgroundScheduler {
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

class _HistoryRuntime implements AppBackgroundRuntime {
  _HistoryRuntime(this.scheduledMessages);
  @override
  final ScheduledMessageService scheduledMessages;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Authenticator implements DeviceOwnerAuthenticator {
  bool allow = false;
  int calls = 0;
  @override
  Future<bool> authenticate(String title) async {
    calls++;
    return allow;
  }
}

class _Credentials implements ChatLockCredentialService {
  @override
  Future<bool> hasCredential(String conversationId) async => true;
  @override
  Future<bool> verifyPassword(String conversationId, String password) async =>
      password == 'correct-password';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpHistory(
  WidgetTester tester,
  _Fixture f, {
  _Authenticator? authenticator,
  ChatLockCredentialService? credentials,
  double scale = 1,
}) async {
  final container = AppContainer.testing(
    session: f.session,
    conversations: StorageConversationRepository(f.database, sender: f.sender),
    crypto: f.crypto,
    signaling: f.signaling,
    backgroundRuntime: _HistoryRuntime(f.service),
    chatAccessRuntime: AppChatAccessRuntime(
      service: ChatAccessService(
        authenticator: authenticator ?? _Authenticator(),
      ),
      credentials: credentials,
    ),
    callReadinessRuntime: const AppCallReadinessRuntime(
      service: CallReadinessService(
        platform: NotApplicableCallReadinessPlatform(),
      ),
    ),
  );
  await tester.pumpWidget(
    AppContainerScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const ScheduledMessagesScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('History'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('History'));
  await tester.pumpAndSettle();
}
