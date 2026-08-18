import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/app.dart';
import 'package:flutter_securechat/src/services/conversation_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_app_container.dart';

Future<void> runDeviceCoreFlow(WidgetTester tester) async {
  final container = createWidgetTestContainer();
  final conversations =
      container.conversations as InMemoryConversationRepository;
  await tester.pumpWidget(SecureChatFlutterApp(container: container));
  await tester.pumpAndSettle();
  debugPrint('[device-core] app-ready');

  expect(find.byKey(const ValueKey('main-horizontal-pager')), findsOneWidget);
  expect(find.text('Ayse Demir'), findsOneWidget);

  await tester.tap(find.text('Ayse Demir').first);
  await tester.pumpAndSettle();
  debugPrint('[device-core] chat-open');
  expect(find.byKey(const ValueKey('chat-message-list')), findsOneWidget);
  expect(find.byKey(const ValueKey('chat-message-composer')), findsOneWidget);

  await tester.tap(find.byIcon(Icons.attach_file));
  await tester.pumpAndSettle();
  debugPrint('[device-core] attachment-tray');
  expect(find.text('Kamera'), findsOneWidget);
  expect(find.text('Galeri'), findsOneWidget);
  expect(find.text('Dosya'), findsOneWidget);
  expect(find.text('Anket'), findsOneWidget);

  await tester.tap(find.byKey(const ValueKey('chat-view-once-action')));
  await tester.enterText(
    find.byKey(const ValueKey('chat-message-composer')),
    'Fiziksel cihaz QA mesajı',
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('chat-send-action')));
  await tester.pump(const Duration(milliseconds: 500));
  final persisted = await conversations.watchMessages('peer-ayse').first;
  expect(
    persisted.any((message) => message.content == 'Fiziksel cihaz QA mesajı'),
    isTrue,
  );
  await tester.drag(
    find.byKey(const ValueKey('chat-message-list')),
    const Offset(0, -600),
  );
  await tester.pumpAndSettle();
  expect(find.text('Bu medya artık açılamaz'), findsOneWidget);
  debugPrint('[device-core] view-once-sent');

  await tester.tap(find.byType(BackButton));
  await tester.pumpAndSettle();
  debugPrint('[device-core] chat-closed');
  expect(find.byKey(const ValueKey('main-horizontal-pager')), findsOneWidget);

  await tester.tap(find.text('Arama').last);
  await tester.pumpAndSettle();
  debugPrint('[device-core] calls-tab');
  expect(find.text('Henüz arama kaydı yok.'), findsOneWidget);

  await tester.tap(find.text('Rehber').last);
  await tester.pumpAndSettle();
  debugPrint('[device-core] contacts-tab');
  expect(find.byIcon(Icons.sync), findsOneWidget);

  await tester.tap(find.text('Ayarlar').last);
  await tester.pumpAndSettle();
  debugPrint('[device-core] settings-tab');
  expect(find.text('Elcim Kullanici'), findsOneWidget);
  await tester.drag(
    find.byKey(const ValueKey('settings-list')),
    const Offset(0, -900),
  );
  await tester.pumpAndSettle();
  expect(find.text('Yedekleme'), findsOneWidget);
  debugPrint('[device-core] settings-scroll');

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await container.dispose();
  debugPrint('[device-core] disposed');
}
