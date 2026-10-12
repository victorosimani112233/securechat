import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_securechat/src/core/models.dart';
import 'package:flutter_securechat/src/features/chat/media_preview_screen.dart';
import 'package:flutter_securechat/src/features/chat/media_viewer_screen.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations_tr.dart';
import 'package:flutter_securechat/src/media/local_file_actions.dart';
import 'package:flutter_securechat/src/media/media_attachment.dart';
import 'package:flutter_test/flutter_test.dart';

/// QA 2026-10-12 Bulgu 16: tek gosterim ekrani korumayi kendisi zorlamiyordu;
/// "1" dugmesinin erisilebilirlik etiketi/durumu yoktu.
void main() {
  const channel = MethodChannel('com.securechat/native');
  final calls = <String>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Widget viewer({required bool viewOnce}) => MaterialApp(
    locale: const Locale('tr'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: MediaViewerScreen(
      message: LocalMessage(
        id: 'm',
        conversationId: 'c',
        senderId: 'peer',
        peerId: 'peer',
        content: LocalMessage.buildFileContent(
          filePath: '/missing',
          fileName: 'foto.jpg',
          mimeType: 'image/jpeg',
          fileSize: 1,
        ),
        contentType: MessageContentType.image,
        timestamp: DateTime(2026),
        status: MessageStatus.delivered,
        isOutgoing: false,
        isViewOnce: viewOnce,
      ),
      fileActions: const _NoFiles(),
    ),
  );

  testWidgets('a view-once viewer forces protection and releases it', (
    tester,
  ) async {
    await tester.pumpWidget(viewer(viewOnce: true));
    await tester.pumpAndSettle();
    expect(calls, ['enableScreenProtectionForced']);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(calls, [
      'enableScreenProtectionForced',
      'releaseForcedScreenProtection',
    ]);
  });

  testWidgets('an ordinary viewer leaves the policy alone', (tester) async {
    await tester.pumpWidget(viewer(viewOnce: false));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    expect(calls, isEmpty);
  });

  testWidgets('the preview "1" button is a labelled toggle', (tester) async {
    final l10n = AppLocalizationsTr();
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('tr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaPreviewScreen(
          attachments: [
            MediaAttachment(
              path: '/tmp/x.jpg',
              fileName: 'x.jpg',
              mimeType: 'image/jpeg',
              fileSize: 1,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = find.bySemanticsLabel(l10n.view_once);
    expect(button, findsOneWidget);
    expect(
      tester.getSemantics(button).flagsCollection.isToggled,
      ui.Tristate.isFalse,
    );
    await tester.tap(find.byKey(const Key('media-view-once')));
    await tester.pump();
    expect(
      tester.getSemantics(button).flagsCollection.isToggled,
      ui.Tristate.isTrue,
    );
    handle.dispose();
  });
}

class _NoFiles implements LocalFileActions {
  const _NoFiles();
  @override
  bool exists(String path) => false;
  @override
  Future<void> open({required String path, required String mimeType}) async {}
  @override
  Future<void> share({
    required String path,
    required String mimeType,
    required String fileName,
  }) async {}
}
