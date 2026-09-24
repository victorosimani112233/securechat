import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/services/peer_identity_review_service.dart';
import 'package:flutter_securechat/src/features/chat/peer_identity_review_screen.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final locale in ['en', 'tr', 'de', 'ar']) {
    testWidgets('identity review uses all localized strings in $locale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = _ReviewService();
      late PeerIdentityReviewStrings strings;
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(locale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Builder(
            builder: (context) {
              strings = PeerIdentityReviewStrings.localized(context);
              final l10n = AppLocalizations.of(context);
              expect(
                [
                  strings.title,
                  strings.warning,
                  strings.previous,
                  strings.current,
                  strings.local,
                  strings.noPrevious,
                  strings.unchanged,
                  strings.confirm,
                  strings.approve,
                  strings.approved,
                  strings.stale,
                  strings.failed,
                  strings.retry,
                ],
                [
                  l10n.identity_review_title,
                  l10n.identity_review_warning,
                  l10n.identity_review_previous,
                  l10n.identity_review_current,
                  l10n.identity_review_local,
                  l10n.identity_review_no_previous,
                  l10n.identity_review_unchanged,
                  l10n.identity_review_confirm,
                  l10n.identity_review_approve,
                  l10n.identity_review_approved,
                  l10n.identity_review_stale,
                  l10n.identity_review_failed,
                  l10n.identity_review_retry,
                ],
              );
              return PeerIdentityReviewScreen(
                service: service,
                peerId: 'peer',
                peerName: 'Test',
                strings: strings,
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(strings.title), findsOneWidget);
      expect(find.text(strings.warning), findsOneWidget);
      if (locale != 'en') {
        expect(
          find.text(const PeerIdentityReviewStrings().warning),
          findsNothing,
        );
        expect(
          strings.approved,
          isNot(const PeerIdentityReviewStrings().approved),
        );
      }
      if (locale == 'tr') expect(find.text('Kimliği doğrula'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text(service.review.currentFingerprint),
        180,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 100,
      );
      expect(find.text(service.review.currentFingerprint), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byType(Checkbox),
        180,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 100,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      final approve = find.byKey(const ValueKey('identity-review-approve'));
      await tester.scrollUntilVisible(
        approve,
        180,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 100,
      );
      await tester.pumpAndSettle();
      await tester.tap(approve);
      await tester.pumpAndSettle();
      expect(service.approved, isTrue);
      expect(find.text(strings.approved), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

class _ReviewService implements PeerIdentityReviewService {
  final review = PeerIdentityReview(
    peerId: 'peer',
    previousIdentity: List.filled(33, 1),
    currentIdentity: List.filled(33, 2),
    localIdentity: List.filled(33, 3),
  );
  bool approved = false;

  @override
  Future<PeerIdentityReview> reviewPeerIdentity(String peerId) async => review;

  @override
  Future<void> approvePeerIdentity(PeerIdentityReview review) async {
    expect(identical(review, this.review), isTrue);
    approved = true;
  }
}
