import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/features/chat/chat_screen.dart';
import 'package:flutter_securechat/src/features/chat/media_preview_screen.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations_tr.dart';
import 'package:flutter_securechat/src/media/media_attachment.dart';
import 'package:flutter_securechat/src/services/app_container.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app_container.dart';

/// QA 2026-10-12 Bulgu 15: tek gosterim anahtari ankette yok sayiliyor ve
/// sonraki metne kaliyordu.
void main() {
  final l10n = AppLocalizationsTr();

  testWidgets('a poll cannot be started while view once is on', (tester) async {
    final container = createWidgetTestContainer();
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await tester.pumpWidget(
      AppContainerScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('tr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ChatScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('chat-view-once-action')));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.attach_file));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.poll));
    await tester.pumpAndSettle();

    expect(find.text(l10n.poll_view_once_unsupported), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    // Anahtar acik kalir; kullanici bilerek kapatir.
    final toggle = tester.getSemantics(
      find.byKey(const ValueKey('chat-view-once-action')),
    );
    expect(toggle.flagsCollection.isToggled, ui.Tristate.isTrue);
  });

  for (final (mime, expected) in [
    ('image/jpeg', true),
    ('application/pdf', false),
  ]) {
    testWidgets('preview starts with the composer view-once for $mime', (
      tester,
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
                    builder: (_) => MediaPreviewScreen(
                      attachments: [
                        MediaAttachment(
                          path: '/tmp/x',
                          fileName: 'x',
                          mimeType: mime,
                          fileSize: 1,
                        ),
                      ],
                      initialViewOnce: true,
                    ),
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
      await tester.tap(find.byKey(const Key('media-send')));
      await tester.pumpAndSettle();
      expect(result!.isViewOnce, expected);
    });
  }
}
