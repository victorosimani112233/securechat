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

  @override
  Stream<MissedCallAction> get missedCallCallbacks => callbacks.stream;

  @override
  Future<void> showMissedCall(MissedCallNotification notification) async {
    shown.add(notification);
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

Future<_Fixture> _fixture() async {
  final root = await Directory.systemTemp.createTemp('missed_call_');
  final database = await SecureChatDatabase.open(
    file: File('${root.path}/storage.securejson'),
    crypto: LocalAeadCryptoService(
      SecretKey(List<int>.generate(32, (index) => index + 1)),
    ),
  );
  await database.conversations.insert(
    const ConversationEntity(
      id: 'peer',
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
