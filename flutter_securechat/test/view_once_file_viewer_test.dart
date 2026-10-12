import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/core/models.dart';
import 'package:flutter_securechat/src/features/chat/media_preview_screen.dart';
import 'package:flutter_securechat/src/features/chat/media_viewer_screen.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations_tr.dart';
import 'package:flutter_securechat/src/media/local_file_actions.dart';
import 'package:flutter_securechat/src/media/media_attachment.dart';
import 'package:flutter_test/flutter_test.dart';

/// QA 2026-10-12 Bulgu 12: tek gosterimlik dosya "Uygulamayla ac" ile dis
/// uygulamaya verilebiliyordu; orada kalici kopyalanabilir.
void main() {
  final l10n = AppLocalizationsTr();

  testWidgets('view-once document has no way out of the app', (tester) async {
    final files = _Files();
    await tester.pumpWidget(
      _viewer(_message(viewOnce: true, mime: 'application/pdf'), files),
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.open_with_app), findsNothing);
    expect(find.byIcon(Icons.share_outlined), findsNothing);
    expect(find.text(l10n.view_once_unsupported_type), findsOneWidget);
    expect(files.opened, isEmpty);
    expect(files.shared, isEmpty);
  });

  testWidgets('view-once text file is shown inside the app', (tester) async {
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('view_once_text_'),
    ))!;
    addTearDown(() => root.delete(recursive: true));
    final file = File('${root.path}/qa_dosya_1.txt');
    await tester.runAsync(() => file.writeAsString('gizli-not-123'));
    final files = _Files();

    await tester.pumpWidget(
      _viewer(
        _message(viewOnce: true, mime: 'text/plain', path: file.path),
        files,
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (find.text('gizli-not-123').evaluate().isNotEmpty) break;
    }

    expect(find.text('gizli-not-123'), findsOneWidget);
    expect(find.text(l10n.open_with_app), findsNothing);
    expect(files.opened, isEmpty);
  });

  testWidgets('ordinary document can still be opened with another app', (
    tester,
  ) async {
    final files = _Files();
    await tester.pumpWidget(
      _viewer(_message(viewOnce: false, mime: 'application/pdf'), files),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.open_with_app));
    await tester.pump();
    expect(files.opened, ['/managed/report.pdf']);
  });

  group('sending', () {
    Future<MediaSendRequest?> send(
      WidgetTester tester,
      MediaAttachment attachment,
    ) async {
      MediaSendRequest? result;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('tr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await Navigator.push<MediaSendRequest>(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        MediaPreviewScreen(attachments: [attachment]),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('media-view-once')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('media-send')));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('a pdf cannot be sent as view once', (tester) async {
      final request = await send(
        tester,
        const MediaAttachment(
          path: '/tmp/report.pdf',
          fileName: 'report.pdf',
          mimeType: 'application/pdf',
          fileSize: 10,
        ),
      );
      expect(request!.isViewOnce, isFalse);
    });

    testWidgets('a text file can be sent as view once', (tester) async {
      final request = await send(
        tester,
        const MediaAttachment(
          path: '/tmp/note.txt',
          fileName: 'note.txt',
          mimeType: 'text/plain',
          fileSize: 10,
        ),
      );
      expect(request!.isViewOnce, isTrue);
    });
  });

  test('only in-app viewable types qualify for view once', () {
    expect(isViewOnceViewableMime('image/jpeg'), isTrue);
    expect(isViewOnceViewableMime('text/plain; charset=utf-8'), isTrue);
    expect(isViewOnceViewableMime('video/mp4'), isFalse);
    expect(isViewOnceViewableMime('application/pdf'), isFalse);
    expect(isViewOnceViewableMime('text/html'), isFalse);
  });
}

LocalMessage _message({
  required bool viewOnce,
  required String mime,
  String path = '/managed/report.pdf',
}) => LocalMessage(
  id: 'file-1',
  conversationId: 'chat',
  senderId: 'peer',
  peerId: 'me',
  content: LocalMessage.buildFileContent(
    filePath: path,
    fileName: path.split('/').last,
    mimeType: mime,
    fileSize: 13,
  ),
  contentType: MessageContentType.file,
  timestamp: DateTime(2026),
  status: MessageStatus.delivered,
  isOutgoing: false,
  isViewOnce: viewOnce,
);

Widget _viewer(LocalMessage message, _Files files) => MaterialApp(
  locale: const Locale('tr'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: MediaViewerScreen(message: message, fileActions: files),
);

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
