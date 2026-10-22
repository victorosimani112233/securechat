import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/contacts/contact_service.dart';
import 'package:flutter_securechat/src/core/models.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/features/chat/chat_screen.dart';
import 'package:flutter_securechat/src/features/groups/group_info_screen.dart';
import 'package:flutter_securechat/src/groups/group_management_service.dart';
import 'package:flutter_securechat/src/incoming/incoming_message_handler.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations.dart';
import 'package:flutter_securechat/src/l10n/service_strings.dart';
import 'package:flutter_securechat/src/services/app_container.dart';
import 'package:flutter_securechat/src/services/conversation_repository.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app_container.dart';

const _saved = '00000000-0000-4000-8000-000000000001';
const _shared = '00000000-0000-4000-8000-000000000002';
const _unknown = '00000000-0000-4000-8000-000000000003';
const _sharedPhone = '+905551112233';
const _group = Conversation(
  id: 'identity-group',
  peerId: 'identity-group',
  peerName: 'Team',
  peerPhone: '',
  isGroup: true,
  groupMembers: ['me', _saved, _shared, _unknown],
  groupAdmins: ['me'],
);

void main() {
  testWidgets('open chat loses composer and calls when membership changes', (
    tester,
  ) async {
    final f = (await tester.runAsync(_Fixture.open))!;
    addTearDown(f.close);
    final conversations = [_group];
    final repo = InMemoryConversationRepository(
      conversations: conversations,
      messages: {},
      session: f.session,
    );
    await tester.pumpWidget(f.app(const ChatScreen(), repository: repo));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    conversations[0] = _group.copyWith(
      groupMembers: [_saved, _shared, _unknown],
    );
    await repo.setArchived(_group.id, true);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(
      find.text('You are no longer a member of this group.'),
      findsOneWidget,
    );
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    final calls = tester
        .widgetList<PopupMenuItem<String>>(find.byType(PopupMenuItem<String>))
        .where(
          (item) => item.value == 'voice_call' || item.value == 'video_call',
        );
    expect(calls, hasLength(2));
    expect(calls.every((item) => !item.enabled), isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('typing @ in a group offers members and sends the mention', (
    tester,
  ) async {
    final f = (await tester.runAsync(_Fixture.open))!;
    addTearDown(f.close);
    final repo = _MentionRecordingRepository(
      conversations: [_group],
      messages: {},
      session: f.session,
    );
    await tester.pumpWidget(f.app(const ChatScreen(), repository: repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Merhaba @sav');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mention-suggestions')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mention-option-$_saved')),
      findsOneWidget,
    );
    // Kendisi ve adi bilinmeyen uye onerilmez; sorguya uymayan da.
    expect(find.byKey(const ValueKey('mention-option-me')), findsNothing);
    expect(
      find.byKey(const ValueKey('mention-option-$_unknown')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('mention-option-$_shared')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('mention-option-$_saved')));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'Merhaba @Saved Name ');
    expect(find.byKey(const ValueKey('mention-suggestions')), findsNothing);

    await tester.enterText(
      find.byType(TextField),
      '${field.controller!.text}nasılsın',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.send).last);
    await tester.pumpAndSettle();
    expect(repo.sent, hasLength(1));
    expect(repo.sent.single.$1, 'Merhaba @Saved Name nasılsın');
    expect(repo.sent.single.$2, [_saved]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('admin edits the group description and photo from group info', (
    tester,
  ) async {
    final f = (await tester.runAsync(_Fixture.open))!;
    final photo = Uint8List.fromList([
      0xFF,
      0xD8,
      0xFF,
      0xE0,
      ...List.filled(64, 1),
    ]);
    final previousPicker = GroupInfoScreen.pickPhoto;
    GroupInfoScreen.pickPhoto = () async => photo;
    addTearDown(() => GroupInfoScreen.pickPhoto = previousPicker);
    // Degisiklik uyelere gider; bagli olmayan sinyal sahte saatte beklerdi.
    await tester.runAsync(
      () => f.signaling.connect(
        userId: 'me',
        url: 'ws://test',
        accessToken: 'test-only',
      ),
    );
    await tester.pumpWidget(f.app(const GroupInfoScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Add group description'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('group-description')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('group-description-field')),
      'Cuma toplantıları',
    );
    await tester.tap(find.text('Save'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Cuma toplantıları'), findsOneWidget);
    expect(find.text('Group description'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('group-photo-edit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('group-photo-remove')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('group-photo-choose')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    final stored = (await tester.runAsync(
      () => f.database.conversations.getById(_group.id),
    ))!;
    expect(stored.groupDescription, 'Cuma toplantıları');
    expect(stored.groupPhoto, base64.encode(photo));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await _closeWhilePumping(tester, f);
  });

  testWidgets('departed group hides leave and stale admin actions', (
    tester,
  ) async {
    final f = (await tester.runAsync(_Fixture.open))!;
    addTearDown(f.close);
    await tester.runAsync(
      () => f.database.conversations.updateGroupMembers(
        _group.id,
        [_saved, _shared, _unknown].join(','),
      ),
    );
    await tester.pumpWidget(f.app(const GroupInfoScreen()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('You are no longer a member of this group.'),
      200,
    );
    expect(find.text('Leave Group'), findsNothing);
    expect(find.byIcon(Icons.person_add_outlined), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  test(
    'batch identity uses local names and verified direct phone only',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      final resolver = ContactIdentityResolver(database: f.database);
      expect(await resolver.resolveMany(const []), isEmpty);
      final identities = await resolver.resolveMany([
        _saved,
        _shared,
        _unknown,
        _saved,
        _group.id,
      ]);
      expect(identities, hasLength(4));
      expect(identities[_saved]!.displayName, 'Saved Name');
      expect(identities[_saved]!.phoneNumber, '+905550000001');
      expect(identities[_shared]!.displayName, _sharedPhone);
      expect(identities[_unknown]!.phoneNumber, isEmpty);
      expect(identities[_group.id]!.phoneNumber, isEmpty);
      for (final id in identities.keys) {
        final single = await resolver.resolve(id);
        expect(identities[id]!.displayName, single.displayName);
        expect(identities[id]!.phoneNumber, single.phoneNumber);
      }
      expect(f.signaling.sentMessages, isEmpty);
    },
  );

  test(
    'member labels follow contact and shared-phone updates without reopen',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      final events = <Map<String, ContactIdentity>>[];
      final sub = f.groups.watchMemberIdentities(_group.id).listen(events.add);
      addTearDown(sub.cancel);
      await _until(() => events.isNotEmpty);
      expect(events.last.keys.toSet(), _group.groupMembers.toSet());

      await f.database.conversations.updatePeerIdentity(
        _shared,
        '+905551119999',
        '+905551119999',
      );
      await _until(() => events.last[_shared]?.phoneNumber == '+905551119999');
      await f.database.contacts.insert(
        const ContactEntity(
          id: _shared,
          phoneNumber: '+905551119999',
          phoneHash: 'local-shared',
          displayName: 'New Contact Name',
          isRegistered: true,
        ),
      );
      await _until(
        () => events.last[_shared]?.displayName == 'New Contact Name',
      );
      await f.database.contacts.delete(_shared);
      await _until(() => events.last[_shared]?.displayName == '+905551119999');
      expect(f.signaling.sentMessages, isEmpty);
    },
  );

  test(
    'new group events never fall back to visible routing identifiers',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      final failures = <Object>[];
      final handler = IncomingMessageHandler(
        signaling: f.signaling,
        crypto: f.crypto,
        database: f.database,
        session: f.session,
        strings: ServiceStrings.fixed('en'),
        onAsyncFailure: (_, error, _) async => failures.add(error),
      )..start();
      addTearDown(handler.close);
      for (final entry in {
        _saved: 'Saved Name',
        _shared: _sharedPhone,
        _unknown: 'Unknown member',
      }.entries) {
        final groupId = 'notice-${entry.key}';
        for (final action in ['CREATE', 'UPDATE_NAME']) {
          f.signaling.addIncoming(
            GroupNotificationSignal(
              senderId: entry.key,
              recipientId: 'me',
              timestamp: DateTime.now(),
              groupId: groupId,
              groupName: 'Event group',
              action: action,
              groupMembers: ['me', entry.key],
            ),
          );
          await handler.waitForIdle();
          final group = await f.database.conversations.getById(groupId);
          expect(group!.lastMessage, startsWith(entry.value));
          expect(group.lastMessage, isNot(contains(entry.key)));
        }
        final messages = await f.database.messages.getMessagesImmediate(
          groupId,
        );
        expect(messages.single.content, startsWith(entry.value));
        expect(messages.single.content, isNot(contains(entry.key)));
      }
      expect(failures, isEmpty);
    },
  );

  for (final width in [390.0, 768.0]) {
    testWidgets('group member list resolves identities at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = (await tester.runAsync(_Fixture.open))!;
      addTearDown(f.close);
      await tester.pumpWidget(f.app(const GroupInfoScreen()));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('group-member-$_unknown')),
        200,
      );
      await tester.pumpAndSettle();
      expect(find.text('Saved Name'), findsOneWidget);
      expect(find.text(_sharedPhone), findsOneWidget);
      expect(find.text('Unknown member'), findsOneWidget);
      expect(find.text('You'), findsOneWidget);
      expect(find.text(_saved), findsNothing);
      expect(find.text(_shared), findsNothing);
      expect(find.text(_unknown), findsNothing);
      expect(find.text('me'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.runAsync(
        () => f.database.contacts.insert(
          const ContactEntity(
            id: _shared,
            phoneNumber: _sharedPhone,
            phoneHash: 'local-shared',
            displayName: 'Updated Local Name',
            isRegistered: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Updated Local Name'), findsOneWidget);
      expect(f.signaling.sentMessages, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('long member name remains readable at double text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final f = (await tester.runAsync(_Fixture.open))!;
    addTearDown(f.close);
    const name = 'Alexandra Elizabeth Montgomery Williamson';
    await tester.runAsync(
      () => f.database.contacts.insert(
        const ContactEntity(
          id: _saved,
          phoneNumber: '+905550000001',
          phoneHash: 'local-saved',
          displayName: name,
          isRegistered: true,
        ),
      ),
    );
    await tester.pumpWidget(f.app(const GroupInfoScreen(), textScale: 2));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('group-member-$_saved')),
      180,
    );
    await tester.pumpAndSettle();
    expect(find.text(name), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('group-member-$_unknown')),
      180,
    );
    await tester.pumpAndSettle();
    expect(find.text('Unknown member'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'group bubbles and replies name the person instead of the group',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = (await tester.runAsync(_Fixture.open))!;
      addTearDown(f.close);
      await tester.pumpWidget(f.app(const ChatScreen()));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('message-sender-saved-message')),
            )
            .data,
        'Saved Name',
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('message-sender-shared-message')),
            )
            .data,
        _sharedPhone,
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('message-sender-unknown-message')),
            )
            .data,
        'Unknown member',
      );
      expect(find.text('Saved Name'), findsNWidgets(2));
      expect(find.text(_saved), findsNothing);
      expect(find.text(_shared), findsNothing);
      expect(find.text(_unknown), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.runAsync(
        () => f.database.contacts.insert(
          const ContactEntity(
            id: _shared,
            phoneNumber: _sharedPhone,
            phoneHash: 'local-shared',
            displayName: 'Live Contact Name',
            isRegistered: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Live Contact Name'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}

Future<void> _until(bool Function() predicate) async {
  for (var i = 0; i < 100; i++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Local identity stream did not update');
}

/// Ekrandan tetiklenen yazmalar sahte saatte dinleyici biraktigi icin
/// veritabani da sahte saatte, zaman ilerletilerek kapatilir; aksi halde
/// kapanis dinleyicinin bitisini sonsuza dek bekler.
Future<void> _closeWhilePumping(WidgetTester tester, _Fixture f) async {
  var closed = false;
  unawaited(f.close().then((_) => closed = true));
  for (var i = 0; i < 50 && !closed; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(closed, isTrue);
}

class _MentionRecordingRepository extends InMemoryConversationRepository {
  _MentionRecordingRepository({
    required super.conversations,
    required super.messages,
    super.session,
  });

  final sent = <(String, List<String>)>[];

  @override
  Future<void> sendText(
    String conversationId,
    String text, {
    String? replyToId,
    bool isViewOnce = false,
    List<String> mentionedUserIds = const [],
  }) async {
    sent.add((text, mentionedUserIds));
  }
}

class _Fixture {
  _Fixture(this.root, this.database, this.crypto, this.session, this.signaling)
    : groups = GroupManagementService(
        database: database,
        session: session,
        signaling: signaling,
        crypto: crypto,
      );

  final Directory root;
  final SecureChatDatabase database;
  final LocalAeadCryptoService crypto;
  final SessionStore session;
  final InMemorySignalingService signaling;
  final GroupManagementService groups;

  static Future<_Fixture> open() async {
    final root = await Directory.systemTemp.createTemp('group_identity_');
    final crypto = LocalAeadCryptoService(SecretKey(List.filled(32, 12)));
    final database = await SecureChatDatabase.open(
      file: File('${root.path}/local.db'),
      crypto: crypto,
    );
    await database.contacts.insert(
      const ContactEntity(
        id: _saved,
        phoneNumber: '+905550000001',
        phoneHash: 'local-saved',
        displayName: 'Saved Name',
        isRegistered: true,
      ),
    );
    await database.conversations.insert(
      const ConversationEntity(
        id: _shared,
        peerId: _shared,
        peerName: _sharedPhone,
        peerPhone: _sharedPhone,
      ),
    );
    await database.conversations.insert(
      ConversationEntity(
        id: _group.id,
        peerId: _group.id,
        peerName: _group.peerName,
        peerPhone: '+999999999999',
        isGroup: true,
        groupMembers: _group.groupMembers.join(','),
        groupAdmins: 'me',
      ),
    );
    return _Fixture(
      root,
      database,
      crypto,
      SessionStore(
        userId: 'me',
        accessToken: 'test-only',
        sharePhoneNumber: false,
      ),
      InMemorySignalingService(),
    );
  }

  Widget app(
    Widget screen, {
    double textScale = 1,
    ConversationRepository? repository,
  }) {
    final defaults = createWidgetTestContainer();
    final now = DateTime.now();
    LocalMessage message(String id, String sender, {String? replyTo}) =>
        LocalMessage(
          id: id,
          conversationId: _group.id,
          senderId: sender,
          peerId: _group.id,
          content: '$id content',
          contentType: MessageContentType.text,
          timestamp: now,
          status: MessageStatus.delivered,
          isOutgoing: false,
          replyToId: replyTo,
        );
    final container = AppContainer.testing(
      session: session,
      conversations:
          repository ??
          InMemoryConversationRepository(
            conversations: [_group],
            messages: {
              _group.id: [
                message('saved-message', _saved),
                message('shared-message', _shared, replyTo: 'saved-message'),
                message('unknown-message', _unknown),
              ],
            },
          ),
      crypto: crypto,
      signaling: signaling,
      groupRuntime: AppGroupRuntime(service: groups),
      chatAccessRuntime: defaults.chatAccessRuntime,
      callReadinessRuntime: defaults.callReadinessRuntime,
    );
    return AppContainerScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          settings: const RouteSettings(arguments: _group),
          builder: (_) => screen,
        ),
      ),
    );
  }

  Future<void> close() async {
    await signaling.dispose();
    await database.close();
    await root.delete(recursive: true);
  }
}
