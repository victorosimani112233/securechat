import 'dart:async';

import 'package:flutter_securechat/src/incoming/incoming_message_handler.dart';
import 'package:flutter_securechat/src/notifications/message_notification_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('delayed presentation cannot replace a newer privacy summary', () async {
    final fixture = await _Fixture.start();
    fixture.send('alice');
    await fixture.presenter.firstStarted.future;
    fixture.send('bob');
    await Future<void>.delayed(Duration.zero);
    fixture.presenter.release.complete();
    await fixture.coordinator.waitForIdle();

    expect(fixture.presenter.completed.map((item) => item.count), [1, 2]);
    expect(fixture.presenter.visible.single.body, '2 messages from 2 chats');
    expect(fixture.presenter.visible.single.payload, isNull);
  });

  test(
    'clear waits for accepted shows and later messages start at one',
    () async {
      final fixture = await _Fixture.start();
      fixture.send('alice');
      await fixture.presenter.firstStarted.future;
      fixture.send('bob');
      var cleared = false;
      final clearing = fixture.coordinator.clear().then((_) => cleared = true);
      await Future<void>.delayed(Duration.zero);
      final clearedWhileShowing = cleared;
      fixture.presenter.release.complete();
      await clearing;
      await fixture.coordinator.waitForIdle();

      expect(clearedWhileShowing, isFalse);
      expect(fixture.presenter.visible, isEmpty);
      expect(fixture.presenter.operations, ['show:1', 'show:2', 'cancel']);
      fixture.send('alice');
      await fixture.coordinator.waitForIdle();
      expect(fixture.presenter.visible.single.count, 1);
      expect(fixture.presenter.visible.single.body, '1 message from 1 chat');
    },
  );

  test(
    'queued messages retain their arrival-time suppression decision',
    () async {
      final fixture = await _Fixture.start();
      fixture.send('alice');
      await fixture.presenter.firstStarted.future;
      final owner = Object();
      fixture.coordinator.setActiveConversation('bob', owner: owner);
      fixture.send('bob');
      fixture.coordinator.setAppForeground(false);
      fixture.send('bob');
      fixture.coordinator.setAppForeground(true);
      fixture.send('bob');
      fixture.presenter.release.complete();
      await fixture.coordinator.waitForIdle();

      expect(fixture.presenter.completed.map((item) => item.count), [1, 2]);
      expect(fixture.presenter.visible.single.body, '2 messages from 2 chats');
      expect(fixture.presenter.operations, ['show:1', 'show:2', 'reconcile']);
      fixture.coordinator.clearActiveConversation(Object());
      fixture.send('bob');
      await fixture.coordinator.waitForIdle();
      expect(fixture.presenter.completed, hasLength(2));
      fixture.coordinator.clearActiveConversation(owner);
      fixture.send('bob');
      await fixture.coordinator.waitForIdle();
      expect(fixture.presenter.completed.last.count, 3);
    },
  );

  test(
    'failed presentation does not poison queued clear or later shows',
    () async {
      final failures = <String>[];
      final fixture = await _Fixture.start(failFirst: true, failures: failures);
      fixture.send('alice');
      await fixture.presenter.firstStarted.future;
      final clearing = fixture.coordinator.clear();
      fixture.send('bob');
      fixture.presenter.release.complete();
      await clearing;
      await fixture.coordinator.waitForIdle();

      expect(failures, ['notification.present-message']);
      expect(fixture.presenter.operations, ['cancel', 'show:1']);
      expect(fixture.presenter.visible.single.count, 1);
    },
  );
}

class _Fixture {
  _Fixture({required bool failFirst})
    : presenter = _DelayedPresenter(failFirst: failFirst);

  final input = StreamController<IncomingMessageEvent>.broadcast(sync: true);
  final _DelayedPresenter presenter;
  late final MessageNotificationCoordinator coordinator;
  int _serial = 0;

  static Future<_Fixture> start({
    bool failFirst = false,
    List<String>? failures,
  }) async {
    final fixture = _Fixture(failFirst: failFirst);
    fixture.coordinator = MessageNotificationCoordinator(
      incomingMessages: fixture.input.stream,
      session: SessionStore(languagePreference: 'en'),
      presenter: fixture.presenter,
      onAsyncFailure: (operation, _, _) => failures?.add(operation),
    );
    addTearDown(() async {
      if (!fixture.presenter.release.isCompleted) {
        fixture.presenter.release.complete();
      }
      await fixture.coordinator.close();
      await fixture.input.close();
    });
    await fixture.coordinator.start();
    return fixture;
  }

  void send(String conversationId) => input.add(
    IncomingMessageEvent(
      messageId: 'message-${_serial++}',
      conversationId: conversationId,
      title: 'Private sender',
      preview: 'Private content',
      timestamp: DateTime.utc(2026),
      isMuted: false,
      isMention: false,
    ),
  );
}

class _DelayedPresenter implements LocalNotificationPresenter {
  _DelayedPresenter({required this.failFirst});

  final bool failFirst;
  final firstStarted = Completer<void>();
  final release = Completer<void>();
  final completed = <LocalMessageNotification>[];
  final _visible = <int, LocalMessageNotification>{};
  final operations = <String>[];
  Iterable<LocalMessageNotification> get visible => _visible.values;

  @override
  Stream<String> get taps => const Stream.empty();
  @override
  Stream<NotificationDismissal> get dismissals => const Stream.empty();
  @override
  Future<void> initialize() async {}
  @override
  Future<void> show(LocalMessageNotification notification) async {
    if (!firstStarted.isCompleted) {
      firstStarted.complete();
      await release.future;
      if (failFirst) throw StateError('Test presentation failure');
    }
    operations.add('show:${notification.count}');
    completed.add(notification);
    _visible[notification.id] = notification;
  }

  @override
  Future<void> reconcileDismissals() async => operations.add('reconcile');
  @override
  Future<void> cancelAll() async {
    operations.add('cancel');
    _visible.clear();
  }
}
