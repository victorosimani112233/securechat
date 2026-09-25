import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/contacts/contact_service.dart';
import 'package:flutter_securechat/src/core/models.dart';
import 'package:flutter_securechat/src/features/chat/chat_screen.dart';
import 'package:flutter_securechat/src/groups/group_management_service.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations.dart';
import 'package:flutter_securechat/src/services/app_container.dart';
import 'package:flutter_securechat/src/services/conversation_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app_container.dart';

const _alice = '11111111-1111-4111-8111-111111111111';
const _bora = '22222222-2222-4222-8222-222222222222';
const _newMember = '33333333-3333-4333-8333-333333333333';
const _unknown = '44444444-4444-4444-8444-444444444444';
const _phone = '+90 555 000 00 02';
const _body = 'Receipt regression message';
const _group = Conversation(
  id: 'receipt-group',
  peerId: 'receipt-group',
  peerName: 'Receipt group',
  peerPhone: '',
  isGroup: true,
  groupMembers: ['me', _alice, _bora, _unknown],
  groupAdmins: ['me'],
);

LocalMessage _message({
  String id = 'receipt-message',
  List<String>? recipients = const [_alice, _bora, _unknown],
  List<String> delivered = const [],
  List<String> read = const [],
  MessageStatus status = MessageStatus.sent,
}) => LocalMessage(
  id: id,
  conversationId: _group.id,
  peerId: _group.id,
  senderId: 'me',
  content: _body,
  contentType: MessageContentType.text,
  timestamp: DateTime(2026, 1, 1, 12),
  status: status,
  isOutgoing: true,
  receiptRecipients: recipients,
  deliveredTo: delivered,
  readBy: read,
);

Finder _section(String name) => find.byKey(ValueKey('message-info-$name'));

Finder _sectionText(String section, String text) =>
    find.descendant(of: _section(section), matching: find.text(text));

void main() {
  testWidgets('group receipts show actual subsets, delivered before read', (
    tester,
  ) async {
    await _openInfo(tester, _message(delivered: [_alice], read: [_bora]));

    expect(_sectionText('delivered', 'Alice'), findsOneWidget);
    expect(_sectionText('delivered', _phone), findsOneWidget);
    expect(_sectionText('delivered', '2/3'), findsOneWidget);
    expect(_sectionText('read', _phone), findsOneWidget);
    expect(_sectionText('read', 'Alice'), findsNothing);
    expect(_sectionText('read', '1/3'), findsOneWidget);
    expect(_sectionText('delivered', 'Unknown member'), findsNothing);
    expect(
      tester.getTopLeft(_section('delivered')).dy,
      lessThan(tester.getTopLeft(_section('read')).dy),
    );
  });

  testWidgets('open dialog refreshes receipts for its message ID', (
    tester,
  ) async {
    final repo = await _openInfo(tester, _message());
    expect(_sectionText('delivered', '0/3'), findsOneWidget);
    expect(_sectionText('read', '0/3'), findsOneWidget);

    repo.emitMessages([
      _message(id: 'another-message', read: [_unknown]),
      _message(delivered: [_alice]),
    ]);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(_sectionText('delivered', 'Alice'), findsOneWidget);
    expect(_sectionText('read', 'Alice'), findsNothing);
    expect(_sectionText('delivered', 'Unknown member'), findsNothing);

    repo.emitMessages([
      _message(delivered: [_alice], read: [_alice, _bora]),
    ]);
    await tester.pumpAndSettle();
    expect(_sectionText('delivered', '2/3'), findsOneWidget);
    expect(_sectionText('read', '2/3'), findsOneWidget);
    expect(_sectionText('read', 'Alice'), findsOneWidget);
    expect(_sectionText('read', _phone), findsOneWidget);
  });

  testWidgets(
    'frozen recipients exclude new members and retain departed ones',
    (tester) async {
      final changedGroup = _group.copyWith(
        groupMembers: ['me', _bora, _newMember],
      );
      final repo = await _openInfo(
        tester,
        _message(
          recipients: [_alice, _bora],
          delivered: [_alice, _newMember, 'me', ''],
          read: [_newMember],
        ),
        conversation: changedGroup,
      );
      expect(_sectionText('delivered', 'Alice'), findsOneWidget);
      expect(_sectionText('delivered', '1/2'), findsOneWidget);
      expect(_sectionText('read', '0/2'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('New member'),
        ),
        findsNothing,
      );

      repo.emitConversation(
        changedGroup.copyWith(groupMembers: ['me', _newMember]),
      );
      repo.emitMessages([
        _message(
          recipients: [_alice, _bora],
          delivered: [_alice, _bora, _newMember],
          read: [_bora, _newMember],
        ),
      ]);
      await tester.pumpAndSettle();
      expect(_sectionText('delivered', '2/2'), findsOneWidget);
      expect(_sectionText('read', '1/2'), findsOneWidget);
      expect(_sectionText('read', _phone), findsOneWidget);
      expect(_sectionText('delivered', 'New member'), findsNothing);
    },
  );

  testWidgets('legacy global group read never invents individual receipts', (
    tester,
  ) async {
    await _openInfo(
      tester,
      _message(recipients: null, status: MessageStatus.read),
    );
    for (final section in ['delivered', 'read']) {
      expect(_section(section), findsOneWidget);
      for (final label in ['Alice', _phone, 'Unknown member']) {
        expect(_sectionText(section, label), findsNothing);
      }
    }
  });

  testWidgets(
    'read privacy hides identities and counts, including live updates',
    (tester) async {
      final repo = await _openInfo(
        tester,
        _message(read: [_alice], status: MessageStatus.read),
        shareReads: false,
      );
      expect(_sectionText('delivered', 'Alice'), findsOneWidget);
      expect(_sectionText('read', 'Alice'), findsNothing);
      expect(_sectionText('read', '1/3'), findsNothing);

      repo.emitMessages([
        _message(read: [_alice, _bora]),
      ]);
      await tester.pumpAndSettle();
      expect(_sectionText('delivered', '2/3'), findsOneWidget);
      expect(_sectionText('delivered', _phone), findsOneWidget);
      expect(_sectionText('read', 'Alice'), findsNothing);
      expect(_sectionText('read', _phone), findsNothing);
      expect(_sectionText('read', '2/3'), findsNothing);
    },
  );

  testWidgets('recipient labels use names, phones or unknown, never UUIDs', (
    tester,
  ) async {
    await _openInfo(tester, _message(delivered: [_alice, _bora, _unknown]));
    expect(_sectionText('delivered', 'Alice'), findsOneWidget);
    expect(_sectionText('delivered', _phone), findsOneWidget);
    expect(_sectionText('delivered', 'Unknown member'), findsOneWidget);
    for (final id in [_alice, _bora, _unknown]) {
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining(id),
        ),
        findsNothing,
      );
    }
  });
}

Future<_ReceiptRepository> _openInfo(
  WidgetTester tester,
  LocalMessage message, {
  Conversation conversation = _group,
  bool shareReads = true,
}) async {
  final defaults = createWidgetTestContainer();
  defaults.session.shareReadReceipts = shareReads;
  final repo = _ReceiptRepository(conversation, message);
  final container = AppContainer.testing(
    session: defaults.session,
    conversations: repo,
    crypto: defaults.crypto,
    signaling: defaults.signaling,
    chatAccessRuntime: defaults.chatAccessRuntime,
    callReadinessRuntime: defaults.callReadinessRuntime,
    groupRuntime: AppGroupRuntime(service: _Groups()),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await repo.close();
  });
  await tester.pumpWidget(
    AppContainerScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
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
  final strings = AppLocalizations.of(tester.element(find.byType(ChatScreen)));
  await tester.longPress(find.text(_body));
  await tester.pumpAndSettle();
  final info = find.text(strings.msg_action_info);
  await tester.ensureVisible(info);
  await tester.tap(info);
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsOneWidget);
  return repo;
}

class _ReceiptRepository extends InMemoryConversationRepository {
  _ReceiptRepository(this.conversation, LocalMessage message)
    : messages = [message],
      super(conversations: [], messages: {});

  Conversation conversation;
  List<LocalMessage> messages;
  final _messages = StreamController<List<LocalMessage>>.broadcast();
  final _conversations = StreamController<List<Conversation>>.broadcast();

  @override
  Stream<List<LocalMessage>> watchMessages(String conversationId) async* {
    yield messages;
    yield* _messages.stream;
  }

  @override
  Stream<List<Conversation>> watchConversations() async* {
    yield [conversation];
    yield* _conversations.stream;
  }

  @override
  Future<void> markConversationRead(String conversationId) async {}

  void emitMessages(List<LocalMessage> values) {
    messages = values;
    _messages.add(values);
  }

  void emitConversation(Conversation value) {
    conversation = value;
    _conversations.add([value]);
  }

  Future<void> close() async {
    await _messages.close();
    await _conversations.close();
  }
}

class _Groups implements GroupManagementService {
  @override
  Stream<Map<String, ContactIdentity>> watchMemberIdentities(String groupId) =>
      Stream.value(const {
        _alice: ContactIdentity(displayName: 'Alice', phoneNumber: ''),
        _bora: ContactIdentity(displayName: _bora, phoneNumber: _phone),
        _newMember: ContactIdentity(displayName: 'New member', phoneNumber: ''),
      });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
