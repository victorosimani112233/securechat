import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/chat/chat_activity_service.dart';
import 'package:flutter_securechat/src/chat/chat_info_service.dart';
import 'package:flutter_securechat/src/chat/message_interaction_service.dart';
import 'package:flutter_securechat/src/chat/poll_service.dart';
import 'package:flutter_securechat/src/core/models.dart';
import 'package:flutter_securechat/src/features/chat/chat_screen.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations.dart';
import 'package:flutter_securechat/src/services/app_container.dart';
import 'package:flutter_securechat/src/services/conversation_repository.dart';
import 'package:flutter_securechat/src/theme/secure_chat_theme.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app_container.dart';

void main() {
  testWidgets(
    'quick reactions preserve white heart without an emoji keyboard',
    (tester) async {
      final interactions = _Interactions();
      await _open(tester, interactions: interactions);
      await tester.longPress(find.text('Message 0'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.add_reaction_outlined), findsNothing);
      expect(find.byKey(const ValueKey('reaction-emoji-input')), findsNothing);
      for (final emoji in allowedMessageReactions) {
        expect(find.byKey(ValueKey('message-reaction-$emoji')), findsOneWidget);
      }
      await tester.tap(find.byKey(const ValueKey('message-reaction-🤍')));
      await tester.pumpAndSettle();
      expect(interactions.reactions, [('m0', '🤍')]);
      expect(tester.testTextInput.isVisible, isFalse);
    },
  );

  for (final group in [false, true]) {
    testWidgets('reaction counts only appear in groups, group=$group', (
      tester,
    ) async {
      await _open(tester, group: group, reactions: '{"🤍":["me","peer"]}');
      expect(find.text(group ? '🤍 2' : '🤍'), findsOneWidget);
      expect(find.text(group ? '🤍' : '🤍 2'), findsNothing);
    });

    testWidgets('existing pin hides another pin action, group=$group', (
      tester,
    ) async {
      await _open(tester, group: group, pinned: true, count: 2);
      await tester.longPress(find.text('Message 1'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('message-action-pin')), findsNothing);
      Navigator.of(
        tester.element(find.byKey(const ValueKey('message-action-list'))),
      ).pop();
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Message 0').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('message-action-pin')), findsOneWidget);
      expect(find.text('Sabitlemeyi kaldır'), findsOneWidget);
    });
  }

  for (final method in ['button', 'outside', 'drag']) {
    testWidgets('iOS composer dismisses by $method without losing draft', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await _open(tester, count: 30, platform: TargetPlatform.iOS);
      final composer = find.byKey(const ValueKey('chat-message-composer'));
      await tester.enterText(composer, 'Draft stays here');
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      final editable = tester.widget<EditableText>(
        find.byType(EditableText).last,
      );
      expect(editable.focusNode.hasFocus, isTrue);
      expect(
        find.byKey(const ValueKey('chat-dismiss-keyboard')),
        findsOneWidget,
      );
      if (method == 'button') {
        await tester.tap(find.byKey(const ValueKey('chat-dismiss-keyboard')));
      } else if (method == 'outside') {
        await tester.tapAt(
          tester.getTopLeft(find.byKey(const ValueKey('chat-message-list'))) +
              const Offset(5, 5),
        );
      } else {
        await tester.drag(
          find.byKey(const ValueKey('chat-message-list')),
          const Offset(0, 90),
        );
      }
      await tester.pumpAndSettle();
      expect(editable.focusNode.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(
        tester.widget<TextField>(composer).controller!.text,
        'Draft stays here',
      );
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _open(
  WidgetTester tester, {
  bool group = false,
  bool pinned = false,
  String? reactions,
  int count = 1,
  TargetPlatform platform = TargetPlatform.android,
  _Interactions? interactions,
}) async {
  final base = createWidgetTestContainer();
  final conversation = Conversation(
    id: group ? 'group' : 'peer',
    peerId: group ? 'group' : 'peer',
    peerName: 'Test conversation',
    peerPhone: '',
    isGroup: group,
    groupMembers: group ? ['me', 'peer'] : [],
    groupAdmins: group ? ['me'] : [],
  );
  final repository = InMemoryConversationRepository(
    conversations: [conversation],
    messages: {
      conversation.id: [
        for (var i = 0; i < count; i++)
          LocalMessage(
            id: 'm$i',
            conversationId: conversation.id,
            peerId: conversation.peerId,
            senderId: 'peer',
            content: 'Message $i',
            contentType: MessageContentType.text,
            timestamp: DateTime.now().subtract(Duration(minutes: count - i)),
            status: MessageStatus.delivered,
            isOutgoing: false,
            isPinned: pinned && i == 0,
            reactions: i == 0 ? reactions : null,
          ),
      ],
    },
  );
  final container = AppContainer.testing(
    session: base.session,
    conversations: repository,
    crypto: base.crypto,
    signaling: base.signaling,
    chatAccessRuntime: base.chatAccessRuntime,
    callReadinessRuntime: base.callReadinessRuntime,
    chatInfoRuntime: interactions == null
        ? null
        : AppChatInfoRuntime(
            service: _Info(),
            polls: _Polls(),
            interactions: interactions,
            activity: _Activity(),
          ),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
  });
  await tester.pumpWidget(
    AppContainerScope(
      container: container,
      child: MaterialApp(
        theme: SecureChatTheme.light().copyWith(platform: platform),
        locale: const Locale('tr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          settings: RouteSettings(arguments: conversation),
          builder: (_) => const ChatScreen(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _Interactions implements MessageInteractionService {
  final reactions = <(String, String)>[];
  @override
  Future<bool> toggleReaction(String messageId, String emoji) async {
    reactions.add((messageId, emoji));
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Info implements ChatInfoService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Polls implements PollService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Activity implements ChatActivityService {
  @override
  Future<void> stopTyping() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
