import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_securechat/src/core/models.dart';
import 'package:flutter_securechat/src/features/conversations/conversations_screen.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations.dart';
import 'package:flutter_securechat/src/services/app_container.dart';
import 'package:flutter_securechat/src/services/conversation_repository.dart';
import 'package:flutter_securechat/src/theme/secure_chat_theme.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app_container.dart';

void main() {
  for (final language in ['tr', 'en']) {
    testWidgets(
      'poll previews hide stored JSON and retain icons in $language',
      (tester) async {
        final base = createWidgetTestContainer();
        const payload =
            'Anket: {"question":"private question","options":["A","B"]}';
        final repo = InMemoryConversationRepository(
          conversations: [
            for (final group in [false, true])
              Conversation(
                id: '$group',
                peerId: '$group',
                peerName: 'Peer $group',
                peerPhone: '',
                isGroup: group,
                lastMessage: payload,
                lastMessageType: MessageContentType.poll,
              ),
            const Conversation(
              id: 'ordinary',
              peerId: 'ordinary',
              peerName: 'Ordinary text',
              peerPhone: '',
              lastMessage: 'Anket: normal text',
              lastMessageType: MessageContentType.text,
            ),
          ],
          messages: {},
        );
        final container = AppContainer.testing(
          session: base.session,
          conversations: repo,
          crypto: base.crypto,
          signaling: base.signaling,
          chatAccessRuntime: base.chatAccessRuntime,
          callReadinessRuntime: base.callReadinessRuntime,
        );
        await tester.pumpWidget(
          AppContainerScope(
            container: container,
            child: MaterialApp(
              locale: Locale(language),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const ConversationsScreen(embedded: true),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(language == 'tr' ? 'Anket' : 'Poll'),
          findsNWidgets(2),
        );
        expect(find.byIcon(Icons.bar_chart), findsNWidgets(2));
        expect(find.textContaining('private question'), findsNothing);
        expect(find.text('Anket: normal text'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  setUpAll(() async {
    for (final font in {
      'Inter': 'assets/fonts/inter_regular.ttf',
      'JetBrainsMono': 'assets/fonts/jetbrains_mono_regular.ttf',
      'SpaceGrotesk': 'assets/fonts/space_grotesk_semibold.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });
  for (final width in [320.0, 390.0, 768.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final locale in ['tr', 'en', 'ar']) {
        testWidgets('one-row filters and full dates at $width/$scale/$locale', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final base = createWidgetTestContainer();
          final now = DateTime.now();
          final repo = InMemoryConversationRepository(
            conversations: [
              Conversation(
                id: 'today',
                peerId: 'today',
                peerName: 'Today group',
                peerPhone: '',
                isGroup: true,
                unreadCount: 2,
                lastMessage: 'New message',
                lastMessageTimestamp: DateTime(
                  now.year,
                  now.month,
                  now.day,
                  9,
                  27,
                ).toUtc(),
              ),
              Conversation(
                id: 'old',
                peerId: 'old',
                peerName: 'Older favorite',
                peerPhone: '',
                isFavorite: true,
                lastMessage: 'Older message',
                lastMessageTimestamp: DateTime(2020, 9, 23, 15, 30),
              ),
            ],
            messages: {},
          );
          final container = AppContainer.testing(
            session: base.session,
            conversations: repo,
            crypto: base.crypto,
            signaling: base.signaling,
            chatAccessRuntime: base.chatAccessRuntime,
            callReadinessRuntime: base.callReadinessRuntime,
          );
          await tester.pumpWidget(
            AppContainerScope(
              container: container,
              child: MaterialApp(
                theme: width == 390
                    ? SecureChatTheme.dark()
                    : SecureChatTheme.light(),
                locale: Locale(locale),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: RepaintBoundary(
                    key: const ValueKey('home-capture'),
                    child: child!,
                  ),
                ),
                home: const ConversationsScreen(embedded: true),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final bar = find.byKey(const ValueKey('conversation-filters'));
          expect(
            find.descendant(of: bar, matching: find.byType(Scrollable)),
            findsNothing,
          );
          expect(find.text('23.09.2020'), findsOneWidget);
          expect(find.text('09:27'), findsOneWidget);
          final centers = <double>[];
          for (final filter in ['none', 'unread', 'groups', 'favorites']) {
            final chip = find.byKey(ValueKey('conversation-filter-$filter'));
            expect(chip.hitTestable(), findsOneWidget);
            centers.add(tester.getCenter(chip).dy);
            final bounds = tester.getRect(chip);
            expect(bounds.left, greaterThanOrEqualTo(0));
            expect(bounds.right, lessThanOrEqualTo(width));
          }
          expect(centers.toSet().length, 1);
          if (scale == 1 && locale == 'tr') {
            for (final label in ['Tümü', 'Okunmamış', 'Gruplar', 'Favoriler']) {
              expect(
                find.descendant(of: bar, matching: find.text(label)),
                findsOneWidget,
              );
            }
          }
          await _capture(tester, 'home-$width-$scale-$locale');
          for (final filter in ['unread', 'groups', 'favorites', 'none']) {
            final chip = find.byKey(ValueKey('conversation-filter-$filter'));
            await tester.tap(chip);
            await tester.pumpAndSettle();
            expect(tester.widget<FilterChip>(chip).selected, isTrue);
            expect(tester.takeException(), isNull);
          }
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  }
}

Future<void> _capture(WidgetTester tester, String name) async {
  final path = Platform.environment['HOME_CONTROLS_SCREENSHOTS'];
  if (path == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('home-capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(path).create(recursive: true);
    await File('$path/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
