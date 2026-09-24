import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/core/models.dart';
import 'package:flutter_securechat/src/features/chat/media_viewer_screen.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations.dart';
import 'package:flutter_securechat/src/media/local_file_actions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final viewOnce in [false, true]) {
    testWidgets(
      'caption is visible in ${viewOnce ? 'view-once' : 'normal'} viewer',
      (tester) async {
        await tester.pumpWidget(_app(viewOnce: viewOnce));
        await tester.pumpAndSettle();
        expect(find.text('Private caption'), findsOneWidget);
        expect(
          find.byIcon(Icons.share_outlined),
          viewOnce ? findsNothing : findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('unavailable media does not reveal a view-once caption', (
    tester,
  ) async {
    await tester.pumpWidget(_app(viewOnce: true, exists: false));
    await tester.pumpAndSettle();
    expect(find.text('Private caption'), findsNothing);
    expect(find.byIcon(Icons.share_outlined), findsNothing);
  });

  testWidgets('long caption is scrollable on a small screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _app(
        viewOnce: true,
        caption: List.filled(100, 'Private caption').join(' '),
        textScale: 1.5,
        image: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('media-viewer-caption')), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _app({
  required bool viewOnce,
  bool exists = true,
  String caption = 'Private caption',
  double textScale = 1,
  bool image = false,
}) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: MediaViewerScreen(
    message: LocalMessage(
      id: 'media',
      conversationId: 'chat',
      senderId: 'peer',
      peerId: 'me',
      content: LocalMessage.buildFileContent(
        filePath: '/missing-test-media',
        fileName: 'Photo',
        mimeType: image ? 'image/png' : 'application/pdf',
        fileSize: 123,
      ),
      contentType: MessageContentType.image,
      timestamp: DateTime(2026),
      status: MessageStatus.delivered,
      isOutgoing: false,
      isViewOnce: viewOnce,
      caption: caption,
    ),
    fileActions: _Files(exists),
  ),
);

class _Files implements LocalFileActions {
  _Files(this.present);
  final bool present;
  @override
  bool exists(String path) => present;
  @override
  Future<void> open({required String path, required String mimeType}) async {}
  @override
  Future<void> share({
    required String path,
    required String mimeType,
    required String fileName,
  }) async {}
}
