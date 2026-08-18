import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/app.dart';
import 'package:flutter_securechat/src/incoming/incoming_message_handler.dart';
import 'package:flutter_securechat/src/notifications/message_notification_service.dart';
import 'package:flutter_securechat/src/services/app_container.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app_container.dart';

void main() {
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
