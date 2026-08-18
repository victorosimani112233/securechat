import 'dart:async';

import 'package:flutter_securechat/src/incoming/incoming_message_handler.dart';
import 'package:flutter_securechat/src/notifications/message_notification_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'privacy mode never exposes sender, content or routing payload',
    () async {
      final input = StreamController<IncomingMessageEvent>.broadcast();
      final presenter = _FakePresenter();
      final coordinator = MessageNotificationCoordinator(
        incomingMessages: input.stream,
        session: SessionStore(showNotificationContent: false),
        presenter: presenter,
      );
      addTearDown(() async {
        await coordinator.close();
        await input.close();
      });
      await coordinator.start();
      coordinator.setAppForeground(false);

      input.add(
        _event(conversationId: 'alice', title: 'Alice', preview: 'secret'),
      );
      await _eventually(() => presenter.shown.isNotEmpty);

      final notification = presenter.shown.single;
      expect(notification.title, 'Elçim');
      expect(notification.body, '1 yeni mesaj');
      expect(notification.payload, isNull);
      expect(notification.hideOnLockScreen, isTrue);
      expect(notification.title, isNot(contains('Alice')));
      expect(notification.body, isNot(contains('secret')));
    },
  );

  test('mute is silent, while a mention overrides conversation mute', () async {
    final input = StreamController<IncomingMessageEvent>.broadcast();
    final presenter = _FakePresenter();
    final coordinator = MessageNotificationCoordinator(
      incomingMessages: input.stream,
      session: SessionStore(),
      presenter: presenter,
    );
    addTearDown(() async {
      await coordinator.close();
      await input.close();
    });
    await coordinator.start();
    coordinator.setAppForeground(false);

    input.add(_event(conversationId: 'muted', isMuted: true));
    input.add(
      _event(conversationId: 'mentioned', isMuted: true, isMention: true),
    );
    await _eventually(() => presenter.shown.length == 2);

    expect(presenter.shown[0].silent, isTrue);
    expect(presenter.shown[1].silent, isFalse);
  });

  test('foreground active conversation suppresses duplicate banner', () async {
    final input = StreamController<IncomingMessageEvent>.broadcast();
    final presenter = _FakePresenter();
    final coordinator = MessageNotificationCoordinator(
      incomingMessages: input.stream,
      session: SessionStore(showNotificationContent: true),
      presenter: presenter,
    );
    addTearDown(() async {
      await coordinator.close();
      await input.close();
    });
    await coordinator.start();
    coordinator.setAppForeground(true);
    coordinator.setActiveConversation('alice');

    input.add(_event(conversationId: 'alice'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(presenter.shown, isEmpty);

    input.add(_event(conversationId: 'bob'));
    await _eventually(() => presenter.shown.length == 1);
    expect(presenter.shown.single.silent, isTrue);
    expect(presenter.shown.single.payload, 'bob');
  });

  test(
    'dismissal clears one conversation count and summary clears all',
    () async {
      final input = StreamController<IncomingMessageEvent>.broadcast();
      final presenter = _FakePresenter();
      final coordinator = MessageNotificationCoordinator(
        incomingMessages: input.stream,
        session: SessionStore(showNotificationContent: false),
        presenter: presenter,
      );
      addTearDown(() async {
        await coordinator.close();
        await input.close();
      });
      await coordinator.start();
      coordinator.setAppForeground(false);

      input.add(_event(conversationId: 'alice'));
      await _eventually(() => presenter.shown.length == 1);
      presenter.dismissController.add(
        const NotificationDismissal.conversation('alice'),
      );
      input.add(_event(conversationId: 'alice'));
      await _eventually(() => presenter.shown.length == 2);
      expect(presenter.shown.last.count, 1);

      input.add(_event(conversationId: 'bob'));
      await _eventually(() => presenter.shown.length == 3);
      presenter.dismissController.add(const NotificationDismissal.all());
      input.add(_event(conversationId: 'alice'));
      await _eventually(() => presenter.shown.length == 4);
      expect(presenter.shown.last.count, 1);
      expect(presenter.shown.last.body, '1 yeni mesaj');
    },
  );
}

IncomingMessageEvent _event({
  required String conversationId,
  String title = 'Peer',
  String preview = 'message',
  bool isMuted = false,
  bool isMention = false,
}) => IncomingMessageEvent(
  messageId: 'message-$conversationId',
  conversationId: conversationId,
  title: title,
  preview: preview,
  timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
  isMuted: isMuted,
  isMention: isMention,
);

class _FakePresenter implements LocalNotificationPresenter {
  final shown = <LocalMessageNotification>[];
  final tapController = StreamController<String>.broadcast();
  final dismissController = StreamController<NotificationDismissal>.broadcast();

  @override
  Stream<String> get taps => tapController.stream;

  @override
  Stream<NotificationDismissal> get dismissals => dismissController.stream;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> show(LocalMessageNotification notification) async {
    shown.add(notification);
  }

  @override
  Future<void> reconcileDismissals() async {}

  @override
  Future<void> cancelAll() async => shown.clear();
}

Future<void> _eventually(bool Function() predicate) async {
  for (var attempt = 0; attempt < 30; attempt++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Notification was not presented before timeout');
}
