import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/chat/chat_activity_service.dart';
import 'package:flutter_securechat/src/chat/chat_info_service.dart';
import 'package:flutter_securechat/src/chat/message_interaction_service.dart';
import 'package:flutter_securechat/src/chat/poll_service.dart';
import 'package:flutter_securechat/src/contacts/contact_service.dart';
import 'package:flutter_securechat/src/core/models.dart';
import 'package:flutter_securechat/src/features/chat/chat_info_screen.dart';
import 'package:flutter_securechat/src/features/chat/shared_content_browser.dart';
import 'package:flutter_securechat/src/features/groups/group_info_screen.dart';
import 'package:flutter_securechat/src/groups/group_management_service.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations.dart';
import 'package:flutter_securechat/src/services/app_container.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_securechat/src/widgets/local_image_view.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app_container.dart';

const _conversation = Conversation(
  id: 'shared-chat',
  peerId: 'peer',
  peerName: 'Shared chat',
  peerPhone: '',
);
const _entity = ConversationEntity(
  id: 'shared-chat',
  peerId: 'peer',
  peerName: 'Shared chat',
  peerPhone: '',
  groupMembers: 'me,peer',
  groupAdmins: 'me',
);

MessageEntity _message(
  String id, {
  String? content,
  String? caption,
  StorageMessageContentType type = StorageMessageContentType.text,
  bool viewOnce = false,
  bool viewed = false,
}) => MessageEntity(
  id: id,
  conversationId: _conversation.id,
  senderId: 'peer',
  content: content ?? id,
  caption: caption,
  contentType: type,
  timestamp: 1700000000000,
  status: StorageMessageStatus.read,
  isOutgoing: false,
  isViewOnce: viewOnce,
  isViewed: viewed,
);

void main() {
  testWidgets('media decodes local thumbnails but never view-once files', (
    tester,
  ) async {
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('shared-content-test-'),
    ))!;
    addTearDown(() => root.delete(recursive: true));
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.green, BlendMode.src);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(2, 2);
    final data = (await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.png),
    ))!;
    final bytes = data.buffer.asUint8List();
    image.dispose();
    picture.dispose();
    final photo = File('${root.path}/photo.png')..writeAsBytesSync(bytes);
    final secret = File('${root.path}/secret.png')..writeAsBytesSync(bytes);
    final service = _InfoService([
      _message(
        'photo',
        content: 'Photo.png|image/png|68|${photo.path}',
        type: StorageMessageContentType.image,
      ),
      _message(
        'once',
        content: 'Secret.png|image/png|68|${secret.path}',
        type: StorageMessageContentType.image,
        viewOnce: true,
      ),
      _message(
        'viewed',
        content: 'Viewed.png|image/png|68|${secret.path}',
        type: StorageMessageContentType.image,
        viewOnce: true,
        viewed: true,
      ),
      _message(
        'empty',
        content: 'Empty.png|image/png|0|',
        type: StorageMessageContentType.image,
      ),
      _message(
        'missing',
        content: 'Missing.png|image/png|68|${root.path}/absent.png',
        type: StorageMessageContentType.image,
      ),
    ]);
    await tester.pumpWidget(_browserApp(service, SharedContentSection.media));
    await tester.pumpAndSettle();
    for (var attempt = 0; attempt < 30; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      if (tester
              .widgetList<RawImage>(find.byType(RawImage))
              .any((image) => image.image != null) &&
          find.byIcon(Icons.broken_image_outlined).evaluate().length == 2)
        break;
    }
    expect(find.byType(GridView), findsOneWidget);
    expect(
      tester
          .widgetList<LocalImageView>(find.byType(LocalImageView))
          .every((image) => image.maxDecodeSize == 384),
      isTrue,
    );
    expect(
      tester
          .widgetList<RawImage>(find.byType(RawImage))
          .any((image) => image.image != null),
      isTrue,
    );
    expect(
      tester
          .widgetList<LocalImageView>(find.byType(LocalImageView))
          .map((image) => image.path),
      contains(photo.path),
    );
    expect(find.byKey(const ValueKey('chat-info-message-once')), findsNothing);
    expect(
      find.byKey(const ValueKey('chat-info-message-viewed')),
      findsNothing,
    );
    expect(find.textContaining('Secret'), findsNothing);
    expect(
      PaintingBinding.instance.imageCache.containsKey(FileImage(secret)),
      isFalse,
    );
    expect(find.byIcon(Icons.broken_image_outlined), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  for (final section in SharedContentSection.values) {
    testWidgets('${section.name} rejects view-once rows from an older stream', (
      tester,
    ) async {
      final service = _InfoService([
        _message('secret-text', content: 'private text', viewOnce: true),
        _message(
          'secret-file',
          content: 'private.pdf|application/pdf|8|/secret',
          type: StorageMessageContentType.file,
          viewOnce: true,
        ),
        _message(
          'deleted',
          content: 'deleted content',
          type: StorageMessageContentType.deleted,
        ),
        _message(
          'system',
          content: 'hidden payload',
          type: StorageMessageContentType.system,
        ),
      ]);
      await tester.pumpWidget(_browserApp(service, section));
      await tester.pumpAndSettle();
      if (section == SharedContentSection.search) {
        await tester.enterText(find.byType(TextField), 'private');
        await tester.pumpAndSettle();
      }
      expect(find.byType(LocalImageView), findsNothing);
      expect(find.byType(Image), findsNothing);
      expect(find.text('private text'), findsNothing);
      expect(find.textContaining('private.pdf'), findsNothing);
      expect(find.text('hidden payload'), findsNothing);
      expect(find.byType(ListTile), findsNothing);
      expect(find.byType(GridView), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('documents show human filenames, never serialized paths', (
    tester,
  ) async {
    final service = _InfoService([
      _message(
        'document',
        content: 'Quarterly report.pdf|application/pdf|42|/internal/cache/uuid',
        caption: 'Document caption stays out of the filename row',
        type: StorageMessageContentType.file,
      ),
    ]);
    await tester.pumpWidget(
      _browserApp(service, SharedContentSection.documents),
    );
    await tester.pumpAndSettle();
    expect(find.text('Quarterly report.pdf'), findsOneWidget);
    expect(
      find.text('Document caption stays out of the filename row'),
      findsNothing,
    );
    expect(find.textContaining('/internal/'), findsNothing);
    expect(find.textContaining('application/pdf'), findsNothing);
  });

  testWidgets('search trims queries and clearing removes previous results', (
    tester,
  ) async {
    final service = _InfoService([_message('found')]);
    await tester.pumpWidget(_browserApp(service, SharedContentSection.search));
    await tester.pumpAndSettle();
    expect(service.queries, isEmpty);
    await tester.enterText(find.byType(TextField), '  found  ');
    await tester.pumpAndSettle();
    expect(service.queries, ['found']);
    expect(
      find.byKey(const ValueKey('chat-info-message-found')),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField), ' ');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-info-message-found')), findsNothing);
    expect(service.queries, ['found']);
  });

  testWidgets(
    'search shows visible captions and poll options and rejects metadata-only matches',
    (tester) async {
      final service = _InfoService([
        _message(
          'photo-caption',
          content: 'hidden-match.png|image/png|42|/internal/hidden-match',
          caption: 'Needle photo caption',
          type: StorageMessageContentType.image,
        ),
        _message(
          'file-caption',
          content:
              'Notes.pdf|application/hidden-match|42|/internal/hidden-match',
          caption: 'Needle document caption',
          type: StorageMessageContentType.file,
        ),
        _message(
          'poll-option',
          content:
              '{"question":"Which destination?","options":["First","Second","Third","Needle fourth option"],"votes":{"3":["hidden-match"]}}',
          type: StorageMessageContentType.poll,
        ),
        _message(
          'private-caption',
          content: 'Secret.png|image/png|42|/internal/hidden-match',
          caption: 'Needle hidden-match private caption',
          type: StorageMessageContentType.image,
          viewOnce: true,
        ),
        _message('unrelated', content: 'Unrelated visible text'),
        _message(
          'malformed-poll',
          content: 'hidden-match',
          type: StorageMessageContentType.poll,
        ),
      ]);
      await tester.pumpWidget(
        _browserApp(service, SharedContentSection.search),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '  NEEDLE  ');
      await tester.pumpAndSettle();
      expect(find.text('Needle photo caption'), findsOneWidget);
      expect(find.text('Notes.pdf\nNeedle document caption'), findsOneWidget);
      final pollText = find.text(
        'Which destination?\nFirst\nSecond\nThird\nNeedle fourth option',
      );
      expect(pollText, findsOneWidget);
      expect(tester.widget<Text>(pollText).maxLines, isNull);
      expect(
        tester.getSize(pollText).height,
        greaterThan(
          tester.getSize(find.text('Needle photo caption')).height * 4,
        ),
      );
      expect(find.byType(ListTile), findsNWidgets(3));
      expect(
        find.byKey(const ValueKey('chat-info-message-private-caption')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('chat-info-message-unrelated')),
        findsNothing,
      );
      expect(find.textContaining('/internal/'), findsNothing);
      expect(find.text('Poll'), findsNothing);

      await tester.enterText(find.byType(TextField), 'destination');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('chat-info-message-poll-option')),
        findsOneWidget,
      );
      expect(find.byType(ListTile), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'hidden-match');
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsNothing);
      expect(find.byType(LocalImageView), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final isGroup in [false, true]) {
    for (final section in SharedContentSection.values) {
      testWidgets(
        '${isGroup ? 'group' : 'contact'} ${section.name} forwards focus result through both routes',
        (tester) async {
          final service = _InfoService([
            _message(
              'target',
              content: 'Report.png|image/png|0|',
              caption: 'Report caption',
              type: StorageMessageContentType.image,
            ),
          ]);
          Object? result;
          await tester.pumpWidget(
            _infoApp(service, isGroup, (value) => result = value),
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          for (final entry in SharedContentSection.values) {
            expect(
              find.byKey(ValueKey('shared-content-${entry.name}')),
              findsOneWidget,
            );
          }
          await tester.tap(
            find.byKey(ValueKey('shared-content-${section.name}')),
          );
          await tester.pumpAndSettle();
          if (section == SharedContentSection.search) {
            await tester.enterText(find.byType(TextField), 'Report');
            await tester.pumpAndSettle();
          }
          expect(service.conversationIds, everyElement(_conversation.id));
          await tester.tap(
            find.byKey(const ValueKey('chat-info-message-target')),
          );
          await tester.pumpAndSettle();
          expect(result, isA<ChatInfoResult>());
          expect((result as ChatInfoResult).messageId, 'target');
          expect((result as ChatInfoResult).lockEnabled, isFalse);
          expect(find.byType(SharedContentBrowser), findsNothing);
          expect(find.byType(ChatInfoScreen), findsNothing);
          expect(find.byType(GroupInfoScreen), findsNothing);
          expect(find.text('Open'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      '${isGroup ? 'group' : 'contact'} browser back returns to info without focusing',
      (tester) async {
        Object? result;
        await tester.pumpWidget(
          _infoApp(_InfoService([]), isGroup, (value) => result = value),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('shared-content-media')));
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(
          find.byType(isGroup ? GroupInfoScreen : ChatInfoScreen),
          findsOneWidget,
        );
        expect(find.byType(SharedContentBrowser), findsNothing);
        expect(result, isNull);
      },
    );
  }
}

Widget _localizedApp({Widget? home}) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

Widget _browserApp(ChatInfoService service, SharedContentSection section) =>
    AppContainerScope(
      container: createWidgetTestContainer(),
      child: _localizedApp(
        home: SharedContentBrowser(
          service: service,
          conversationId: _conversation.id,
          section: section,
        ),
      ),
    );

Widget _infoApp(
  _InfoService service,
  bool isGroup,
  ValueChanged<Object?> onResult,
) {
  final defaults = createWidgetTestContainer();
  final container = AppContainer.testing(
    session: defaults.session,
    conversations: defaults.conversations,
    crypto: defaults.crypto,
    signaling: defaults.signaling,
    chatAccessRuntime: defaults.chatAccessRuntime,
    callReadinessRuntime: defaults.callReadinessRuntime,
    chatInfoRuntime: AppChatInfoRuntime(
      service: service,
      polls: _Polls(),
      interactions: _Interactions(),
      activity: _Activity(),
    ),
    groupRuntime: AppGroupRuntime(service: _Groups()),
  );
  return AppContainerScope(
    container: container,
    child: _localizedApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              final result = await Navigator.push<Object?>(
                context,
                MaterialPageRoute<Object?>(
                  settings: const RouteSettings(arguments: _conversation),
                  builder: (_) => isGroup
                      ? const GroupInfoScreen()
                      : const ChatInfoScreen(),
                ),
              );
              onResult(result);
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

class _InfoService implements ChatInfoService {
  _InfoService(this.messages);
  final List<MessageEntity> messages;
  final queries = <String>[];
  final conversationIds = <String>[];

  Stream<List<MessageEntity>> _results(String id) {
    conversationIds.add(id);
    return Stream.value(messages);
  }

  @override
  Stream<ConversationEntity?> watchConversation(String id) =>
      Stream.value(_entity);
  @override
  Stream<List<MessageEntity>> watchMedia(String id) => _results(id);
  @override
  Stream<List<MessageEntity>> watchDocuments(String id) => _results(id);
  @override
  Stream<List<MessageEntity>> watchStarred(String id) => _results(id);
  @override
  Stream<List<MessageEntity>> search(String id, String query) {
    queries.add(query);
    return _results(id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Groups implements GroupManagementService {
  @override
  String get localUserId => 'me';
  @override
  bool isLocalAdmin(ConversationEntity group) => true;
  @override
  bool isLocalMember(ConversationEntity group) =>
      (group.groupMembers ?? '').split(',').contains(localUserId);
  @override
  Stream<ConversationEntity?> watchGroup(String id) => Stream.value(_entity);
  @override
  Stream<List<ContactEntity>> watchContacts() => Stream.value(const []);
  @override
  Stream<Map<String, ContactIdentity>> watchMemberIdentities(String id) =>
      Stream.value(const {});
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Polls implements PollService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Interactions implements MessageInteractionService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Activity implements ChatActivityService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
