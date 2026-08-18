import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/app.dart';
import 'package:flutter_securechat/src/core/models.dart';
import 'package:flutter_securechat/src/services/conversation_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app_container.dart';

void main() {
  testWidgets(
    'chat exposes secure chrome, search, attachments and swipe reply',
    (tester) async {
      final container = createWidgetTestContainer();
      await tester.pumpWidget(SecureChatFlutterApp(container: container));
      await tester.pumpAndSettle();
      await _openFirstConversation(tester);

      expect(find.text('Mesajlar uçtan uca şifrelenmiştir.'), findsOneWidget);
      expect(find.text('Sabitlenmiş Mesaj'), findsOneWidget);
      expect(find.text('Bugün'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.attach_file));
      await tester.pumpAndSettle();
      expect(find.text('Kamera'), findsOneWidget);
      expect(find.text('Galeri'), findsOneWidget);
      expect(find.text('Dosya'), findsOneWidget);
      expect(find.text('Anket'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sohbette Ara'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('chat-search-field')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('chat-search-field')),
        'Signal',
      );
      await tester.pump();
      expect(find.byTooltip('Önceki sonuç'), findsOneWidget);
      expect(find.byTooltip('Sonraki sonuç'), findsOneWidget);

      await tester.tap(find.byTooltip('Kapat'));
      await tester.pumpAndSettle();
      final replyTarget = find.byKey(const ValueKey('chat-reply-m3'));
      await tester.ensureVisible(replyTarget);
      await tester.drag(replyTarget, const Offset(360, 0));
      await tester.pumpAndSettle();
      expect(
        find.text('Signal/WebRTC/native bridge noktalarini ayirdim.'),
        findsWidgets,
      );
      expect(find.byTooltip('İptal'), findsOneWidget);
    },
  );

  testWidgets('view-once composer persists the privacy flag', (tester) async {
    final container = createWidgetTestContainer();
    final repository =
        container.conversations as InMemoryConversationRepository;
    await tester.pumpWidget(SecureChatFlutterApp(container: container));
    await tester.pumpAndSettle();
    await _openFirstConversation(tester);

    await tester.tap(find.byKey(const ValueKey('chat-view-once-action')));
    await tester.enterText(
      find.byKey(const ValueKey('chat-message-composer')),
      'Bir kez göster',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump(const Duration(milliseconds: 350));

    final messages = await repository.watchMessages('peer-ayse').first;
    final sent = messages.last;
    expect(sent.content, 'Bir kez göster');
    expect(sent.isViewOnce, isTrue);

    await tester.drag(
      find.byKey(const ValueKey('chat-message-list')),
      const Offset(0, -600),
    );
    await tester.pumpAndSettle();
    expect(find.text('Bu medya artık açılamaz'), findsOneWidget);
  });

  testWidgets('composer preserves usable text width and contextual action', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    await tester.pumpWidget(
      SecureChatFlutterApp(container: createWidgetTestContainer()),
    );
    await tester.pumpAndSettle();
    await _openFirstConversation(tester);

    final composer = find.byKey(const ValueKey('chat-message-composer'));
    final inputSurface = find.byKey(
      const ValueKey('chat-composer-input-surface'),
    );
    expect(tester.getSize(composer).width, greaterThanOrEqualTo(180));
    expect(tester.getSize(inputSurface).height, greaterThanOrEqualTo(52));
    expect(find.byKey(const ValueKey('chat-record-action')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-send-action')), findsNothing);

    final widthBeforeTyping = tester.getSize(composer).width;
    await tester.enterText(composer, 'Merhaba');
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('chat-record-action')), findsNothing);
    expect(find.byKey(const ValueKey('chat-send-action')), findsOneWidget);
    expect(tester.getSize(composer).width, widthBeforeTyping);
    expect(tester.takeException(), isNull);
  });

  testWidgets('read-only group keeps composer admin-only for a member', (
    tester,
  ) async {
    final container = createWidgetTestContainer();
    await tester.pumpWidget(SecureChatFlutterApp(container: container));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(Navigator).first);
    unawaited(
      Navigator.of(context).pushNamed(
        '/chat',
        arguments: const Conversation(
          id: 'readonly-group',
          peerId: 'readonly-group',
          peerName: 'Duyurular',
          peerPhone: '',
          isGroup: true,
          isReadOnly: true,
          groupMembers: ['me', 'peer-admin'],
          groupAdmins: ['peer-admin'],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Bu grup sadece yöneticilerin yazabildiği bir duyuru kanalıdır.',
      ),
      findsOneWidget,
    );
    expect(find.text('Sadece yöneticiler mesaj gönderebilir'), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-message-composer')), findsNothing);
  });
}

Future<void> _openFirstConversation(WidgetTester tester) async {
  await tester.tap(find.text('Ayse Demir').first);
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('chat-message-list')), findsOneWidget);
}
