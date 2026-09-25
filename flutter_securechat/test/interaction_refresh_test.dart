import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_securechat/src/app.dart';
import 'package:flutter_securechat/src/chat/message_reactions.dart';
import 'package:flutter_securechat/src/core/models.dart';
import 'package:flutter_securechat/src/features/chat/chat_screen.dart';
import 'package:flutter_securechat/src/features/contacts/recipient_picker_screen.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations.dart';
import 'package:flutter_securechat/src/theme/secure_chat_theme.dart';
import 'package:flutter_securechat/src/services/app_container.dart';
import 'support/test_app_container.dart';

void main() {
  setUpAll(() async {
    for (final font in {
      'Inter': 'assets/fonts/inter_regular.ttf',
      'SpaceGrotesk': 'assets/fonts/space_grotesk_semibold.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });

  test('reactions accept one grapheme and preserve one reaction per user', () {
    for (final emoji in ['🫶', '👨‍👩‍👧‍👦', '👍🏽', '🇹🇷', '1️⃣', '❤️']) {
      expect(isValidMessageReaction(emoji), isTrue, reason: emoji);
    }
    for (final invalid in ['', 'hello', 'A', '👍👍', '👍 hi', '1']) {
      expect(isValidMessageReaction(invalid), isFalse, reason: invalid);
    }
    var raw = applyMessageReaction(null, 'me', '🫶', remove: false);
    raw = applyMessageReaction(raw, 'me', '👨‍👩‍👧‍👦', remove: false);
    raw = applyMessageReaction(raw, 'other', '🫶', remove: false);
    expect(parseReactions(raw), {
      '👨‍👩‍👧‍👦': {'me'},
      '🫶': {'other'},
    });
    raw = applyMessageReaction(raw, 'me', '👨‍👩‍👧‍👦', remove: true);
    expect(parseReactions(raw), {
      '🫶': {'other'},
    });
  });

  for (final width in [320.0, 390.0, 768.0]) {
    testWidgets('recipient selection survives search and fits $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final choices = Stream.value(
        List.generate(
          20,
          (i) => RecipientChoice(
            id: '$i',
            name: i == 0 ? 'Uzun Isimli Test Kullanicisi' : 'Kisi $i',
            detail: '+90500000$i',
          ),
        ),
      );
      final done = Completer<bool>();
      var submitted = 0;
      await tester.pumpWidget(
        AppContainerScope(
          container: createWidgetTestContainer(),
          child: MaterialApp(
            theme: SecureChatTheme.light(),
            locale: const Locale('tr'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(width == 320 ? 1.5 : 1)),
              child: RepaintBoundary(
                key: const ValueKey('capture'),
                child: child!,
              ),
            ),
            home: RecipientPickerScreen(
              title: 'Yeni Grup',
              actionLabel: 'Grubu kur ve Kişileri Ekle',
              choices: choices,
              onConfirm: (selected) {
                submitted++;
                expect(selected.map((e) => e.id), ['0', '19']);
                return done.future;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('recipient-0')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('recipient-search')),
        'Kisi 19',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('recipient-19')));
      await tester.pumpAndSettle();
      expect(find.byType(InputChip), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await _capture(tester, 'recipients-$width');
      await tester.tap(find.byKey(const ValueKey('recipient-confirm')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('recipient-confirm')));
      expect(submitted, 1);
      done.complete(false);
      await tester.pumpAndSettle();
      expect(find.byType(InputChip), findsNWidgets(2));
    });
  }

  testWidgets(
    'long message expands and collapses without losing original text',
    (tester) async {
      final content = List.generate(
        35,
        (i) => 'Mesaj satiri $i: deneme metni.',
      ).join('\n');
      final container = createWidgetTestContainer(
        messagesFor: (id) => [
          LocalMessage(
            id: 'long',
            conversationId: id,
            peerId: 'peer-ayse',
            senderId: 'peer-ayse',
            content: content,
            contentType: MessageContentType.text,
            timestamp: DateTime.now(),
            status: MessageStatus.delivered,
            isOutgoing: false,
          ),
        ],
      );
      await tester.pumpWidget(SecureChatFlutterApp(container: container));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ayse Demir').first);
      await tester.pumpAndSettle();
      expect(find.text('Daha fazlasını gör'), findsOneWidget);
      await tester.tap(find.text('Daha fazlasını gör'));
      await tester.pumpAndSettle();
      expect(find.text('Daha az göster'), findsOneWidget);
      await tester.ensureVisible(find.text('Daha az göster'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Daha az göster'));
      await tester.pumpAndSettle();
      expect(find.text('Daha fazlasını gör'), findsOneWidget);
      expect(
        (await container.conversations.watchMessages('peer-ayse').first)
            .single
            .content,
        content,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'forwarding taps whole text row and has no checkbox for view once',
    (tester) async {
      final container = createWidgetTestContainer(
        messagesFor: (id) => [
          for (var i = 0; i < 3; i++)
            LocalMessage(
              id: 'item-$i',
              conversationId: id,
              peerId: 'peer-ayse',
              senderId: 'peer-ayse',
              content: 'Text $i',
              isViewOnce: i == 2,
              contentType: MessageContentType.text,
              timestamp: DateTime.now().add(Duration(seconds: i)),
              status: MessageStatus.delivered,
              isOutgoing: false,
            ),
        ],
      );
      await tester.pumpWidget(SecureChatFlutterApp(container: container));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ayse Demir').first);
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Text 0'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.add_reaction_outlined), findsNothing);
      expect(find.byKey(const ValueKey('message-reaction-🤍')), findsOneWidget);
      await tester.tap(find.text('İlet'));
      await tester.pumpAndSettle();
      expect(find.byType(Checkbox), findsNWidgets(2));
      await tester.tapAt(tester.getCenter(find.text('Text 1')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<Checkbox>(find.byType(Checkbox))
            .every((box) => box.value == true),
        isTrue,
      );
      expect(find.byType(ChatScreen), findsOneWidget);
    },
  );
}

Future<void> _capture(WidgetTester tester, String name) async {
  final target = Platform.environment['INTERACTION_SCREENSHOTS'];
  if (target == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await Directory(target).create(recursive: true);
    await File('$target/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
}
