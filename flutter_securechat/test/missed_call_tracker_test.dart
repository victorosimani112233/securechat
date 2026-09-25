import 'dart:async';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/media/call_models.dart';
import 'package:flutter_securechat/src/notifications/message_notification_service.dart';
import 'package:flutter_securechat/src/notifications/missed_call_tracker.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final databaseFailure in [false, true]) {
    test(
      'retransmission retries failed ${databaseFailure ? 'write' : 'notification'} without double unread',
      () async {
        final fixture = await _fixture();
        addTearDown(fixture.close);
        final dao = _FailingConversationDao(fixture.database.conversations)
          ..failNextWrite = databaseFailure;
        final presenter = _FakeMissedPresenter()
          ..failuresRemaining = databaseFailure ? 0 : 1;
        addTearDown(presenter.callbacks.close);
        final tracker = MissedCallTracker(
          conversations: dao,
          presenter: presenter,
          onCallback: (_) async {},
        );
        addTearDown(tracker.close);
        const session = CallSession(
          callId: 'retry-call',
          peerId: 'peer',
          peerName: 'Alice',
          callType: CallType.voice,
          direction: CallDirection.incoming,
          state: CallState.busy,
        );
        await expectLater(tracker.triggerNow(session), throwsStateError);
        expect(
          (await fixture.database.conversations.getById('peer'))!.unreadCount,
          databaseFailure ? 0 : 1,
        );
        expect(presenter.shown, isEmpty);
        await Future.wait([
          tracker.triggerNow(session),
          tracker.triggerNow(session),
        ]);
        await tracker.triggerNow(session);
        expect(
          (await fixture.database.conversations.getById('peer'))!.unreadCount,
          1,
        );
        expect(dao.writeAttempts, databaseFailure ? 2 : 1);
        expect(presenter.attempts, databaseFailure ? 1 : 2);
        expect(presenter.shown, hasLength(1));
        expect(presenter.shown.single.silent, isTrue);
      },
    );
  }

  test(
    'atomic missed call preserves queued flags and current unread count',
    () async {
      final fixture = await _fixture(conversationId: 'direct-row');
      addTearDown(fixture.close);
      final dao = fixture.database.conversations;
      final initial = (await dao.getById('direct-row'))!;
      await dao.update(
        initial.copyWith(
          unreadCount: 3,
          contactNote: 'Keep note',
          isPinned: true,
          lastMessage: 'Old outgoing photo',
          lastMessageType: StorageMessageContentType.image.name,
          lastMessageOutgoing: true,
          lastMessageStatus: StorageMessageStatus.read.name,
        ),
      );
      await Future.wait([
        dao.updateMuted('direct-row', true),
        dao.updateLocked('direct-row', true),
        dao.incrementUnreadCount('peer'),
        dao.recordMissedCall('direct-row', 'Missed call', 1234),
      ]);
      final current = (await dao.getById('direct-row'))!;
      expect(current.unreadCount, 5);
      expect(current.isMuted, isTrue);
      expect(current.isLocked, isTrue);
      expect(current.isPinned, isTrue);
      expect(current.contactNote, 'Keep note');
      expect(current.lastMessage, 'Missed call');
      expect(current.lastMessageTimestamp, 1234);
      expect(current.lastMessageType, StorageMessageContentType.system.name);
      expect(current.lastMessageOutgoing, isFalse);
      expect(current.lastMessageStatus, isNull);

      await Future.wait([
        dao.delete('direct-row'),
        dao.recordMissedCall('direct-row', 'Missed call', 1235),
      ]);
      expect(await dao.getById('direct-row'), isNull);
    },
  );

  test('triggerNow after close does not write or present', () async {
    final fixture = await _fixture();
    addTearDown(fixture.close);
    final presenter = _FakeMissedPresenter();
    addTearDown(presenter.callbacks.close);
    final tracker = MissedCallTracker(
      conversations: fixture.database.conversations,
      presenter: presenter,
      onCallback: (_) async {},
    );
    await tracker.close();
    await tracker.triggerNow(
      const CallSession(
        callId: 'closed-call',
        peerId: 'peer',
        peerName: 'Alice',
        callType: CallType.voice,
        direction: CallDirection.incoming,
        state: CallState.busy,
      ),
    );
    expect(presenter.shown, isEmpty);
    expect(
      (await fixture.database.conversations.getById('peer'))!.unreadCount,
      0,
    );
  });

  for (final group in [false, true]) {
    test(
      'busy missed call updates resolved row and identity: group $group',
      () async {
        final fixture = await _fixture(conversationId: 'direct-row');
        addTearDown(fixture.close);
        if (group) {
          await fixture.database.conversations.insert(
            const ConversationEntity(
              id: 'group-row',
              peerId: 'group-routing-peer',
              peerName: 'Group',
              peerPhone: '',
              isGroup: true,
              unreadCount: 4,
            ),
          );
        }
        final presenter = _FakeMissedPresenter();
        addTearDown(presenter.callbacks.close);
        final tracker = MissedCallTracker(
          conversations: fixture.database.conversations,
          presenter: presenter,
          onCallback: (_) async {},
        );
        addTearDown(tracker.close);
        final session = CallSession(
          callId: 'busy-call',
          peerId: 'peer',
          peerName: 'Alice',
          callType: CallType.voice,
          direction: CallDirection.incoming,
          state: CallState.busy,
          isGroupCall: group,
          groupId: group ? 'group-row' : null,
        );
        await tracker.triggerNow(session);
        await tracker.triggerNow(session);
        final row = await fixture.database.conversations.getById(
          group ? 'group-row' : 'direct-row',
        );
        expect(row!.lastMessage, 'Kaçırılan arama');
        expect(row.unreadCount, group ? 5 : 1);
        expect(row.lastMessageTimestamp, isNotNull);
        expect(presenter.shown, hasLength(1));
        expect(presenter.shown.single.silent, isTrue);
        expect(presenter.shown.single.isGroupCall, group);
        expect(presenter.shown.single.peerId, group ? 'group-row' : 'peer');
        expect(presenter.shown.single.peerName, group ? 'Group' : 'Alice');
        if (group) {
          final direct = await fixture.database.conversations.getById(
            'direct-row',
          );
          expect(direct!.unreadCount, 0);
          expect(direct.lastMessage, isNull);
        }
      },
    );
  }

  test('concurrent missed calls retain both unread increments', () async {
    final fixture = await _fixture(conversationId: 'direct-row');
    addTearDown(fixture.close);
    final presenter = _FakeMissedPresenter();
    addTearDown(presenter.callbacks.close);
    final tracker = MissedCallTracker(
      conversations: fixture.database.conversations,
      presenter: presenter,
      onCallback: (_) async {},
    );
    addTearDown(tracker.close);
    await Future.wait([
      for (final id in ['busy-1', 'busy-2'])
        tracker.triggerNow(
          CallSession(
            callId: id,
            peerId: 'peer',
            peerName: 'Alice',
            callType: CallType.voice,
            direction: CallDirection.incoming,
            state: CallState.busy,
          ),
        ),
    ]);
    expect(
      (await fixture.database.conversations.getById('direct-row'))!.unreadCount,
      2,
    );
    expect(presenter.shown, hasLength(2));
  });

  test('unanswered incoming call is recorded once after timeout', () async {
    final fixture = await _fixture();
    addTearDown(fixture.close);
    final presenter = _FakeMissedPresenter();
    final callbacks = <MissedCallAction>[];
    final tracker = MissedCallTracker(
      conversations: fixture.database.conversations,
      presenter: presenter,
      timeout: const Duration(milliseconds: 10),
      onCallback: (action) async => callbacks.add(action),
    );
    addTearDown(tracker.close);
    const session = CallSession(
      callId: 'call-1',
      peerId: 'peer',
      peerName: 'Alice',
      callType: CallType.video,
      direction: CallDirection.incoming,
      state: CallState.ringing,
    );

    tracker.start(session);
    await _eventually(() => presenter.shown.isNotEmpty);
    await tracker.triggerNow(session);

    final conversation = await fixture.database.conversations.getById('peer');
    expect(conversation?.lastMessage, 'Kaçırılan arama');
    expect(conversation?.unreadCount, 1);
    expect(presenter.shown, hasLength(1));
    expect(presenter.shown.single.callType, CallType.video);
    expect(presenter.shown.single.silent, isFalse);

    presenter.callbacks.add(
      const MissedCallAction(peerId: 'peer', callType: CallType.video),
    );
    await _eventually(() => callbacks.isNotEmpty);
    expect(callbacks.single.peerId, 'peer');
  });

  test(
    'answered or rejected call cancellation prevents missed notification',
    () async {
      final fixture = await _fixture();
      addTearDown(fixture.close);
      final presenter = _FakeMissedPresenter();
      final tracker = MissedCallTracker(
        conversations: fixture.database.conversations,
        presenter: presenter,
        timeout: const Duration(milliseconds: 10),
        onCallback: (_) async {},
      );
      addTearDown(tracker.close);
      const session = CallSession(
        callId: 'call-2',
        peerId: 'peer',
        peerName: 'Alice',
        callType: CallType.voice,
        direction: CallDirection.incoming,
        state: CallState.ringing,
      );

      tracker.start(session);
      tracker.cancel(session.callId);
      await Future<void>.delayed(const Duration(milliseconds: 25));

      expect(presenter.shown, isEmpty);
      expect(
        (await fixture.database.conversations.getById('peer'))?.unreadCount,
        0,
      );
    },
  );
}

class _FakeMissedPresenter implements MissedCallNotificationPresenter {
  final shown = <MissedCallNotification>[];
  final callbacks = StreamController<MissedCallAction>.broadcast();
  int failuresRemaining = 0;
  int attempts = 0;

  @override
  Stream<MissedCallAction> get missedCallCallbacks => callbacks.stream;

  @override
  Future<void> showMissedCall(MissedCallNotification notification) async {
    attempts++;
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw StateError('Notification unavailable');
    }
    shown.add(notification);
  }
}

class _FailingConversationDao extends Fake implements ConversationDao {
  _FailingConversationDao(this.delegate);
  final ConversationDao delegate;
  bool failNextWrite = false;
  int writeAttempts = 0;

  @override
  Future<ConversationEntity?> getByPeerId(String peerId) =>
      delegate.getByPeerId(peerId);

  @override
  Future<void> recordMissedCall(
    String conversationId,
    String message,
    int timestamp,
  ) async {
    writeAttempts++;
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('Database unavailable');
    }
    await delegate.recordMissedCall(conversationId, message, timestamp);
  }
}

class _Fixture {
  const _Fixture(this.root, this.database);
  final Directory root;
  final SecureChatDatabase database;

  Future<void> close() async {
    await database.close();
    await root.delete(recursive: true);
  }
}

Future<_Fixture> _fixture({String conversationId = 'peer'}) async {
  final root = await Directory.systemTemp.createTemp('missed_call_');
  final database = await SecureChatDatabase.open(
    file: File('${root.path}/storage.securejson'),
    crypto: LocalAeadCryptoService(
      SecretKey(List<int>.generate(32, (index) => index + 1)),
    ),
  );
  await database.conversations.insert(
    ConversationEntity(
      id: conversationId,
      peerId: 'peer',
      peerName: 'Alice',
      peerPhone: '',
    ),
  );
  return _Fixture(root, database);
}

Future<void> _eventually(bool Function() predicate) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Expected asynchronous event was not observed');
}
