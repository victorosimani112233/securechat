import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/calls/call_history_service.dart';
import 'package:flutter_securechat/src/chat/chat_info_service.dart';
import 'package:flutter_securechat/src/core/models.dart';
import 'package:flutter_securechat/src/features/chat/chat_screen.dart';
import 'package:flutter_securechat/src/features/chat/media_viewer_screen.dart';
import 'package:flutter_securechat/src/features/chat/shared_content_browser.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations.dart';
import 'package:flutter_securechat/src/media/local_file_actions.dart';
import 'package:flutter_securechat/src/media/media_attachment.dart';
import 'package:flutter_securechat/src/media/media_message_service.dart';
import 'package:flutter_securechat/src/services/app_container.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_securechat/src/widgets/local_image_view.dart';
import 'package:flutter_securechat/src/widgets/local_video_thumbnail.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app_container.dart';

LocalMessage _message(String mime, {bool deferred = true, bool once = false}) =>
    LocalMessage(
      id: 'attachment',
      conversationId: 'peer-ayse',
      senderId: 'peer-ayse',
      peerId: 'peer-ayse',
      content: LocalMessage.buildFileContent(
        fileName: 'original-report',
        mimeType: mime,
        fileSize: 600 * 1024,
        filePath: '/retained/attachment',
      ),
      contentType: mime.startsWith('image/')
          ? MessageContentType.image
          : MessageContentType.file,
      timestamp: DateTime(2026, 9, 25),
      status: MessageStatus.delivered,
      isOutgoing: false,
      isViewOnce: once,
      isMediaPreviewDeferred: deferred,
    );

Widget _app(Widget home, {AppContainer? container}) => AppContainerScope(
  container: container ?? createWidgetTestContainer(),
  child: MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  ),
);

void main() {
  for (final mime in ['image/png', 'video/mp4', 'application/pdf']) {
    testWidgets('deferred $mime bubble has manual open without preview', (
      tester,
    ) async {
      final container = createWidgetTestContainer(
        messagesFor: (_) => [_message(mime)],
      );
      await tester.pumpWidget(_app(const ChatScreen(), container: container));
      await tester.pumpAndSettle();
      expect(find.text('original-report'), findsOneWidget);
      final l10n = AppLocalizations.of(tester.element(find.byType(ChatScreen)));
      expect(find.text(l10n.tap_to_open), findsOneWidget);
      expect(find.byType(LocalVideoThumbnail), findsNothing);
      expect(find.byType(LocalImageView), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Image && widget.image is FileImage,
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final once in [false, true]) {
    testWidgets('manual open uses refreshed message, view-once=$once', (
      tester,
    ) async {
      final original = _message('application/pdf', once: once);
      final service = _MediaMessages(
        original.copyWith(
          isMediaPreviewDeferred: false,
          content: LocalMessage.buildFileContent(
            fileName: 'original-report',
            mimeType: 'application/pdf',
            fileSize: 600 * 1024,
            filePath: '/retained/refreshed',
          ),
        ),
      );
      final container = createWidgetTestContainer(
        messagesFor: (_) => [original],
        mediaRuntime: _Runtime(service),
      );
      await tester.pumpWidget(_app(const ChatScreen(), container: container));
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(tester.element(find.byType(ChatScreen)));
      await tester.tap(find.text(l10n.tap_to_open));
      await tester.pumpAndSettle();
      expect(service.activations, 1);
      expect(service.claims, once ? 1 : 0);
      final viewer = tester.widget<MediaViewerScreen>(
        find.byType(MediaViewerScreen),
      );
      expect(viewer.message.isMediaPreviewDeferred, isFalse);
      expect(viewer.message.filePath, '/retained/refreshed');
      expect(viewer.message.isViewOnce, once);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(service.finished, once);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'shared media defers image/video thumbnails but remains selectable',
    (tester) async {
      final messages = [
        for (final mime in ['image/png', 'video/mp4'])
          MessageEntity.fromJson({..._message(mime).toJson(), 'id': mime}),
      ];
      String? selected;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  selected = await Navigator.push<String>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SharedContentBrowser(
                        service: _Info(messages),
                        conversationId: 'peer-ayse',
                        section: SharedContentSection.media,
                      ),
                    ),
                  );
                },
                child: const Text('Browse'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Browse'));
      await tester.pumpAndSettle();
      expect(find.byType(LocalImageView), findsNothing);
      expect(find.byType(LocalVideoThumbnail), findsNothing);
      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.insert_drive_file_outlined), findsNWidgets(2));
      await tester.tap(
        find.byKey(const ValueKey('chat-info-message-image/png')),
      );
      await tester.pumpAndSettle();
      expect(selected, 'image/png');
      expect(tester.takeException(), isNull);
    },
  );
}

class _MediaMessages implements MediaMessageService {
  _MediaMessages(this.refreshed);
  final LocalMessage refreshed;
  int activations = 0;
  int claims = 0;
  bool finished = false;
  @override
  Future<LocalMessage?> activateMediaPreview(LocalMessage message) async {
    activations++;
    return refreshed;
  }

  @override
  Future<bool> markViewOnceViewed(LocalMessage message) async {
    expect(message.isMediaPreviewDeferred, isFalse);
    claims++;
    return true;
  }

  @override
  void finishViewOnce(String id) => finished = true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Runtime implements AppMediaRuntime {
  _Runtime(this.mediaMessages);
  @override
  final MediaMessageService mediaMessages;
  @override
  final mediaSelection = _Selection();
  @override
  final callHistory = _History();
  @override
  final localFiles = _Files();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Selection implements MediaSelectionService {
  @override
  Future<List<MediaAttachment>> recoverLostSelection() async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _History implements CallHistoryService {
  @override
  Stream<List<CallHistoryEntry>> watchPeer(String peerId) => Stream.value([]);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Files implements LocalFileActions {
  @override
  bool exists(String path) => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Info implements ChatInfoService {
  _Info(this.messages);
  final List<MessageEntity> messages;
  @override
  Stream<List<MessageEntity>> watchMedia(String id) => Stream.value(messages);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
