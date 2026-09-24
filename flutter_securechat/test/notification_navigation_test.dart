import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/app.dart';
import 'package:flutter_securechat/src/incoming/incoming_message_handler.dart';
import 'package:flutter_securechat/src/notifications/message_notification_service.dart';
import 'package:flutter_securechat/src/services/app_container.dart';
import 'package:flutter_securechat/src/features/chat/chat_info_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app_container.dart';

void main() {
  testWidgets(
    'covered chat alerts, returning to visible chat suppresses alerts',
    (tester) async {
      final incoming = StreamController<IncomingMessageEvent>.broadcast();
      final presenter = _RecordingPresenter();
      final coordinator = MessageNotificationCoordinator(
        incomingMessages: incoming.stream,
        session: createLoggedInTestSession(),
        presenter: presenter,
      );
      await coordinator.start();
      final container = createWidgetTestContainer(
        notificationRuntime: AppNotificationRuntime(coordinator: coordinator),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await coordinator.close();
        await incoming.close();
      });
      var serial = 0;
      Future<void> deliver() async {
        incoming.add(
          IncomingMessageEvent(
            messageId: 'm-${serial++}',
            conversationId: 'peer-ayse',
            title: 'Ayse',
            preview: 'Test',
            timestamp: DateTime.now(),
            isMuted: false,
            isMention: false,
          ),
        );
        await tester.pump();
        await coordinator.waitForIdle();
        await tester.pump();
      }

      await tester.pumpWidget(SecureChatFlutterApp(container: container));
      await tester.pumpAndSettle();
      await deliver();
      expect(presenter.shown, hasLength(1));
      await tester.tap(find.text('Ayse Demir').first);
      await tester.pumpAndSettle();
      await deliver();
      expect(presenter.shown, hasLength(1));
      await tester.tap(find.text('Ayse Demir'));
      await tester.pumpAndSettle();
      expect(find.byType(ChatInfoScreen), findsOneWidget);
      await deliver();
      expect(presenter.shown, hasLength(2));
      Navigator.of(tester.element(find.byType(ChatInfoScreen))).pop();
      await tester.pumpAndSettle();
      await deliver();
      expect(presenter.shown, hasLength(2));
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await deliver();
      expect(presenter.shown, hasLength(3));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('cold notification tap opens its conversation', (tester) async {
    final presenter = _InitialTapPresenter('peer-ayse');
    final coordinator = MessageNotificationCoordinator(
      incomingMessages: const Stream<IncomingMessageEvent>.empty(),
      session: createLoggedInTestSession(),
      presenter: presenter,
    );
    await coordinator.start();
    final container = createWidgetTestContainer(
      notificationRuntime: AppNotificationRuntime(coordinator: coordinator),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await coordinator.close();
    });

    await tester.pumpWidget(SecureChatFlutterApp(container: container));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(find.byKey(const ValueKey('chat-message-list')), findsOneWidget);
    expect(find.text('Ayse Demir'), findsWidgets);
    expect(find.byType(BackButton), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _RecordingPresenter extends _InitialTapPresenter {
  _RecordingPresenter() : super('');
  final shown = <LocalMessageNotification>[];
  @override
  Stream<String> get taps => const Stream.empty();
  @override
  Future<void> show(LocalMessageNotification notification) async =>
      shown.add(notification);
}

class _InitialTapPresenter implements LocalNotificationPresenter {
  _InitialTapPresenter(this.initialTap);

  final String initialTap;

  @override
  Stream<String> get taps => Stream.value(initialTap);

  @override
  Stream<NotificationDismissal> get dismissals => const Stream.empty();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> show(LocalMessageNotification notification) async {}

  @override
  Future<void> reconcileDismissals() async {}

  @override
  Future<void> cancelAll() async {}
}
