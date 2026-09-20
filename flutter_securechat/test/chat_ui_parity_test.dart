import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  testWidgets('call actions live in overflow so presence keeps header width', (
    tester,
  ) async {
    await tester.pumpWidget(
      SecureChatFlutterApp(container: createWidgetTestContainer()),
    );
    await tester.pumpAndSettle();
    await _openFirstConversation(tester);

    expect(find.byIcon(Icons.call_outlined), findsNothing);
    expect(find.byIcon(Icons.videocam_outlined), findsNothing);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('Sesli ara'), findsOneWidget);
    expect(find.text('Görüntülü ara'), findsOneWidget);
    expect(find.byIcon(Icons.call_outlined), findsOneWidget);
    expect(find.byIcon(Icons.videocam_outlined), findsOneWidget);
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

  testWidgets('tapping composer returns a long conversation to the bottom', (
    tester,
  ) async {
    final container = createWidgetTestContainer(
      messagesFor: (_) => _longConversationMessages(),
    );
    await tester.pumpWidget(SecureChatFlutterApp(container: container));
    await tester.pumpAndSettle();
    await _openFirstConversation(tester);

    final list = find.byKey(const ValueKey('chat-message-list'));
    for (var index = 0; index < 4; index++) {
      await tester.drag(list, const Offset(0, 1200));
      await tester.pump();
    }
    expect(find.text('Message 0').hitTestable(), findsOneWidget);
    expect(find.text('Message 39').hitTestable(), findsNothing);

    await tester.tap(find.byKey(const ValueKey('chat-message-composer')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('Message 39').hitTestable(), findsOneWidget);
  });

  testWidgets('message action sheet keeps bottom actions reachable', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 560);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      SecureChatFlutterApp(container: createWidgetTestContainer()),
    );
    await tester.pumpAndSettle();
    await _openFirstConversation(tester);

    final message = find.byKey(const ValueKey('chat-reply-m3'));
    await tester.ensureVisible(message);
    await tester.pumpAndSettle();
    await tester.longPress(
      find.descendant(
        of: message,
        matching: find.text('Signal/WebRTC/native bridge noktalarini ayirdim.'),
      ),
    );
    await tester.pumpAndSettle();

    final actionList = find.byKey(const ValueKey('message-action-list'));
    expect(actionList, findsOneWidget);
    expect(
      find.byKey(const ValueKey('message-action-delete')).hitTestable(),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('message-action-delete')).hitTestable(),
    );
    await tester.pumpAndSettle();
    expect(actionList, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('copy action writes the original message text to clipboard', (
    tester,
  ) async {
    final platformCalls = <MethodCall>[];
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      SecureChatFlutterApp(container: createWidgetTestContainer()),
    );
    await tester.pumpAndSettle();
    await _openFirstConversation(tester);

    final message = find.byKey(const ValueKey('chat-reply-m3'));
    await tester.ensureVisible(message);
    await tester.pumpAndSettle();
    await tester.longPress(
      find.descendant(
        of: message,
        matching: find.text('Signal/WebRTC/native bridge noktalarini ayirdim.'),
      ),
    );
    await tester.pumpAndSettle();
    final copyAction = find.byKey(const ValueKey('message-action-copy'));
    expect(copyAction, findsOneWidget);
    await tester.ensureVisible(copyAction);
    await tester.pumpAndSettle();
    expect(copyAction.hitTestable(), findsOneWidget);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        platformCalls.add(call);
        return null;
      },
    );
    await tester.tap(copyAction);
    await tester.pumpAndSettle();

    final clipboardCall = platformCalls.lastWhere(
      (call) => call.method == 'Clipboard.setData',
    );
    expect(
      (clipboardCall.arguments as Map<Object?, Object?>)['text'],
      'Signal/WebRTC/native bridge noktalarini ayirdim.',
    );
    expect(find.text('Mesaj kopyalandı.'), findsOneWidget);
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

List<LocalMessage> _longConversationMessages() {
  final now = DateTime.now();
  return List.generate(
    40,
    (index) => LocalMessage(
      id: 'scroll-$index',
      conversationId: 'peer-ayse',
      senderId: index.isEven ? 'peer-ayse' : 'me',
      peerId: 'peer-ayse',
      content: 'Message $index',
      contentType: MessageContentType.text,
      timestamp: now.subtract(Duration(minutes: 40 - index)),
      status: MessageStatus.delivered,
      isOutgoing: index.isOdd,
    ),
  );
}

Future<void> _openFirstConversation(WidgetTester tester) async {
  await tester.tap(find.text('Ayse Demir').first);
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('chat-message-list')), findsOneWidget);
}
