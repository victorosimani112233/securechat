import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_securechat/src/app.dart';
import 'package:flutter_securechat/src/core/models.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app_container.dart';

const _conversation = Conversation(
  id: 'peer-ayse',
  peerId: 'peer-ayse',
  peerName: 'Ayse Demir',
  peerPhone: '+90 532 000 00 01',
);

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

  for (final width in [320.0, 390.0, 768.0]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('short bubbles stay compact at $width / $scale', (
        tester,
      ) async {
        await _openChat(
          tester,
          width: width,
          scale: scale,
          messages: [
            _message('received', 'Hi'),
            _message('sent', 'Hello', outgoing: true),
          ],
        );

        _expectInsets(
          tester,
          'received',
          const EdgeInsets.fromLTRB(12, 8, 12, 6),
        );
        _expectInsets(tester, 'sent', const EdgeInsets.fromLTRB(16, 10, 14, 8));
        final received = tester.getRect(_bubble('received'));
        final sent = tester.getRect(_bubble('sent'));
        expect(received.width, lessThan(180));
        expect(sent.width, lessThan(180));
        expect(received.left, closeTo(12, .01));
        expect(sent.right, closeTo(width - 12, .01));
        expect(
          find.descendant(
            of: _messageText('received'),
            matching: find.byType(LayoutBuilder),
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('long received bubble wraps and expands at $width / $scale', (
        tester,
      ) async {
        final content = List.filled(
          30,
          'A received message should wrap naturally inside its bubble.',
        ).join(' ');
        await _openChat(
          tester,
          width: width,
          scale: scale,
          messages: [_message('long', content)],
        );

        _expectInsets(tester, 'long', const EdgeInsets.fromLTRB(12, 8, 12, 6));
        // List padding (16) and directional bubble gutters (52) remain intact.
        final maxWidth = math.min(320.0, width - 68);
        final collapsed = tester.getRect(_bubble('long'));
        expect(collapsed.width, closeTo(maxWidth, .01));
        final text = find
            .descendant(of: _messageText('long'), matching: find.byType(Text))
            .first;
        expect(tester.widget<Text>(text).maxLines, 8);
        expect(tester.widget<Text>(text).textSpan!.toPlainText(), content);
        final l10n = AppLocalizations.of(tester.element(text));
        expect(find.text(l10n.message_show_more), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text(l10n.message_show_more));
        await tester.pumpAndSettle();
        expect(tester.widget<Text>(text).maxLines, isNull);
        expect(
          tester.getSize(_bubble('long')).height,
          greaterThan(collapsed.height),
        );
        expect(tester.getSize(_bubble('long')).width, closeTo(maxWidth, .01));
        expect(tester.takeException(), isNull);

        await tester.ensureVisible(find.text(l10n.message_show_less));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.message_show_less));
        await tester.pumpAndSettle();
        expect(tester.widget<Text>(text).maxLines, 8);
        expect(tester.widget<Text>(text).textSpan!.toPlainText(), content);
        expect(
          tester.getSize(_bubble('long')).height,
          closeTo(collapsed.height, .01),
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('narrow multiline received bubble shrink-wraps at $width', (
      tester,
    ) async {
      // Seven short lines exercise the LayoutBuilder path without needing
      // expansion or a wide bubble.
      await _openChat(
        tester,
        width: width,
        messages: [_message('multiline', List.filled(7, 'Hi').join('\n'))],
      );
      expect(
        find.descendant(
          of: _messageText('multiline'),
          matching: find.byType(LayoutBuilder),
        ),
        findsOneWidget,
      );
      _expectInsets(
        tester,
        'multiline',
        const EdgeInsets.fromLTRB(12, 8, 12, 6),
      );
      expect(tester.getSize(_bubble('multiline')).width, lessThan(180));
      final l10n = AppLocalizations.of(
        tester.element(_messageText('multiline')),
      );
      expect(find.text(l10n.message_show_more), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'RTL mirrors bubble alignment and preserves directional padding',
    (tester) async {
      await _openChat(
        tester,
        width: 320,
        language: 'ar',
        messages: [
          _message('received', 'Hi'),
          _message('sent', 'Hello', outgoing: true),
        ],
      );
      expect(
        Directionality.of(tester.element(_messageText('received'))),
        TextDirection.rtl,
      );
      _expectInsets(
        tester,
        'received',
        const EdgeInsets.fromLTRB(12, 8, 12, 6),
      );
      _expectInsets(tester, 'sent', const EdgeInsets.fromLTRB(14, 10, 16, 8));
      expect(tester.getRect(_bubble('received')).right, closeTo(308, .01));
      expect(tester.getRect(_bubble('sent')).left, closeTo(12, .01));
      expect(tester.takeException(), isNull);
    },
  );
}

Finder _messageText(String id) => find.byKey(ValueKey('message-text-$id'));

Finder _bubble(String id) =>
    find.ancestor(of: _messageText(id), matching: find.byType(Material)).first;

void _expectInsets(WidgetTester tester, String id, EdgeInsets expected) {
  final padding = tester.widget<Padding>(
    find.ancestor(of: _messageText(id), matching: find.byType(Padding)).first,
  );
  final direction = Directionality.of(tester.element(_messageText(id)));
  expect(padding.padding.resolve(direction), expected);
  final bubble = tester.getRect(_bubble(id));
  final content = tester.getRect(find.byWidget(padding.child!));
  expect(content.left - bubble.left, closeTo(expected.left, .01));
  expect(content.top - bubble.top, closeTo(expected.top, .01));
  expect(bubble.right - content.right, closeTo(expected.right, .01));
  expect(bubble.bottom - content.bottom, closeTo(expected.bottom, .01));
}

LocalMessage _message(String id, String content, {bool outgoing = false}) =>
    LocalMessage(
      id: id,
      conversationId: _conversation.id,
      peerId: _conversation.peerId,
      senderId: outgoing ? 'me' : _conversation.peerId,
      content: content,
      contentType: MessageContentType.text,
      timestamp: DateTime(2026, 9, 24, 12, 34),
      status: MessageStatus.delivered,
      isOutgoing: outgoing,
    );

Future<void> _openChat(
  WidgetTester tester, {
  required double width,
  required List<LocalMessage> messages,
  double scale = 1,
  String language = 'en',
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final container = createWidgetTestContainer(
    messagesFor: (id) => id == _conversation.id ? messages : [],
  );
  container.session.languagePreference = language;
  await tester.pumpWidget(SecureChatFlutterApp(container: container));
  await tester.pumpAndSettle();
  tester
      .state<NavigatorState>(find.byType(Navigator).first)
      .pushNamed('/chat', arguments: _conversation);
  await tester.pumpAndSettle();
}
