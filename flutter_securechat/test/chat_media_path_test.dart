import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/core/models.dart';
import 'package:flutter_securechat/src/features/chat/chat_screen.dart';
import 'package:flutter_securechat/src/features/chat/media_viewer_screen.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations.dart';
import 'package:flutter_securechat/src/media/local_file_actions.dart';
import 'package:flutter_securechat/src/services/app_container.dart';
import 'package:flutter_securechat/src/storage/storage_management_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app_container.dart';

void main() {
  for (final viewer in [false, true]) {
    for (final relocated in [false, true]) {
      testWidgets(
        '${viewer ? 'viewer' : 'chat card'} decodes ${relocated ? 'resolved container path' : 'file URI'}',
        (tester) async {
          final photo = await _image(tester);
          final raw = relocated
              ? '/old-container/photo.png'
              : photo.uri.toString();
          final paths = relocated ? _Paths({raw: photo.path}) : null;
          final message = _message(raw);
          final container = _container(message, paths);
          addTearDown(container.signaling.dispose);
          await tester.pumpWidget(
            _app(
              container,
              viewer
                  ? MediaViewerScreen(message: message, fileActions: _Files())
                  : const ChatScreen(),
            ),
          );
          await tester.pumpAndSettle();
          for (var i = 0; i < 12; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await tester.pump();
          }
          final image = find.byWidgetPredicate(
            (widget) => widget is Image && widget.image is FileImage,
          );
          expect(image, findsOneWidget);
          expect(
            (tester.widget<Image>(image).image as FileImage).file.path,
            photo.path,
          );
          final decoded = tester
              .widget<RawImage>(
                find.descendant(of: image, matching: find.byType(RawImage)),
              )
              .image;
          expect(decoded, isNotNull);
          expect(decoded!.width, 80);
          expect(decoded.height, 40);
          if (paths != null) expect(paths.requests, contains(raw));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await FileImage(photo).evict();
        },
      );
    }
  }

  testWidgets(
    'chat image failure keeps visible filename and fallback instead of blank card',
    (tester) async {
      final message = _message('/missing-private-image.png');
      final container = _container(message, _Paths({message.filePath!: null}));
      addTearDown(container.signaling.dispose);
      await tester.pumpWidget(_app(container, const ChatScreen()));
      await tester.pumpAndSettle();
      expect(find.text('preview.png'), findsOneWidget);
      expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Image && widget.image is FileImage,
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final once in [false, true]) {
    testWidgets(
      'protected chat preview does not resolve path: viewOnce=$once',
      (tester) async {
        final paths = _Paths({});
        final message = _message(
          '/private/hidden.png',
          once: once,
          deferred: !once,
        );
        final container = _container(message, paths);
        addTearDown(container.signaling.dispose);
        await tester.pumpWidget(_app(container, const ChatScreen()));
        await tester.pumpAndSettle();
        expect(paths.requests, isEmpty);
        expect(
          find.byWidgetPredicate(
            (widget) => widget is Image && widget.image is FileImage,
          ),
          findsNothing,
        );
      },
    );
  }

  testWidgets(
    'document viewer sends decoded local URI to native open and share',
    (tester) async {
      final path = '${Directory.systemTemp.path}/document with spaces.pdf';
      final message = _message(
        Uri.file(path).toString(),
        mime: 'application/pdf',
      );
      final container = _container(message, null);
      addTearDown(container.signaling.dispose);
      final actions = _Files();
      await tester.pumpWidget(
        _app(
          container,
          MediaViewerScreen(message: message, fileActions: actions),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.open_in_new));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.share_outlined));
      await tester.pumpAndSettle();
      expect(actions.opened, [path]);
      expect(actions.shared, [path]);
    },
  );
}

LocalMessage _message(
  String path, {
  String mime = 'image/png',
  bool once = false,
  bool deferred = false,
}) => LocalMessage(
  id: 'media-path',
  conversationId: 'peer-ayse',
  senderId: 'peer-ayse',
  peerId: 'peer-ayse',
  content: LocalMessage.buildFileContent(
    fileName: 'preview.png',
    mimeType: mime,
    fileSize: 200,
    filePath: path,
  ),
  contentType: MessageContentType.image,
  timestamp: DateTime.now(),
  status: MessageStatus.delivered,
  isOutgoing: false,
  isViewOnce: once,
  isMediaPreviewDeferred: deferred,
);

AppContainer _container(LocalMessage message, _Paths? paths) {
  final defaults = createWidgetTestContainer(messagesFor: (_) => [message]);
  return AppContainer.testing(
    session: defaults.session,
    conversations: defaults.conversations,
    crypto: defaults.crypto,
    signaling: defaults.signaling,
    chatAccessRuntime: defaults.chatAccessRuntime,
    callReadinessRuntime: defaults.callReadinessRuntime,
    storageRuntime: paths == null ? null : AppStorageRuntime(service: paths),
  );
}

Widget _app(AppContainer container, Widget home) => AppContainerScope(
  container: container,
  child: MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  ),
);

Future<File> _image(WidgetTester tester) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(Colors.green, BlendMode.src);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(80, 40);
  final data = (await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.png),
  ))!;
  image.dispose();
  picture.dispose();
  final directory = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('chat-media-path-'),
  ))!;
  addTearDown(() => directory.delete(recursive: true));
  return (await tester.runAsync(
    () => File(
      '${directory.path}/image #1.png',
    ).writeAsBytes(data.buffer.asUint8List()),
  ))!;
}

class _Paths extends Fake implements StorageManagementService {
  _Paths(this.paths);
  final Map<String, String?> paths;
  final requests = <String>[];
  @override
  Future<String?> resolveMediaPath(String path, {bool strict = false}) async {
    requests.add(path);
    return paths[path];
  }
}

class _Files implements LocalFileActions {
  final opened = <String>[];
  final shared = <String>[];
  @override
  bool exists(String path) => true;
  @override
  Future<void> open({required String path, required String mimeType}) async =>
      opened.add(path);
  @override
  Future<void> share({
    required String path,
    required String mimeType,
    required String fileName,
  }) async => shared.add(path);
}
