import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_securechat/src/chat/chat_activity_service.dart';
import 'package:flutter_securechat/src/chat/chat_info_service.dart';
import 'package:flutter_securechat/src/chat/message_interaction_service.dart';
import 'package:flutter_securechat/src/chat/poll_service.dart';
import 'package:flutter_securechat/src/core/models.dart';
import 'package:flutter_securechat/src/services/peer_identity_review_service.dart';
import 'package:flutter_securechat/src/features/chat/chat_info_screen.dart';
import 'package:flutter_securechat/src/features/chat/peer_identity_review_screen.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations.dart';
import 'package:flutter_securechat/src/services/app_container.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';

import 'support/test_app_container.dart';

const _strings = PeerIdentityReviewStrings();
final _approveButton = find.byKey(const ValueKey('identity-review-approve'));

void main() {
  testWidgets(
    'shows both peer fingerprints and requires explicit verification',
    (tester) async {
      final service = _ReviewService();
      await tester.pumpWidget(_screen(service));
      await tester.pumpAndSettle();
      expect(find.text(_strings.warning), findsOneWidget);
      expect(find.text(service.review.previousFingerprint!), findsOneWidget);
      expect(find.text(service.review.currentFingerprint), findsOneWidget);
      expect(find.text(service.review.localFingerprint), findsOneWidget);
      await _scrollTo(tester, _approveButton);
      expect(tester.widget<FilledButton>(_approveButton).onPressed, isNull);
      expect(service.approved, isEmpty);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(_approveButton);
      await tester.pumpAndSettle();
      expect(service.approved.single, same(service.review));
      expect(find.text(_strings.approved), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing);
    },
  );

  testWidgets(
    'stale approval discards consent and requires reloading new fingerprint',
    (tester) async {
      final service = _ReviewService()
        ..approvalError = const PeerIdentityReviewStaleException();
      await tester.pumpWidget(_screen(service));
      await tester.pumpAndSettle();
      await _scrollTo(tester, find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await _scrollTo(tester, _approveButton);
      await tester.tap(_approveButton);
      await tester.pumpAndSettle();
      expect(find.text(_strings.stale), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing);
      expect(_approveButton, findsNothing);
      final oldFingerprint = service.review.currentFingerprint;
      service.review = _review(9);
      service.approvalError = null;
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle();
      expect(find.text(oldFingerprint), findsNothing);
      expect(find.text(service.review.currentFingerprint), findsOneWidget);
      await _scrollTo(tester, _approveButton);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
      expect(tester.widget<FilledButton>(_approveButton).onPressed, isNull);
    },
  );

  testWidgets('load failure and retry never grant approval', (tester) async {
    final service = _ReviewService()..loadError = StateError('offline');
    await tester.pumpWidget(_screen(service));
    await tester.pumpAndSettle();
    expect(find.text(_strings.failed), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
    service.loadError = null;
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();
    expect(find.text(service.review.currentFingerprint), findsOneWidget);
    expect(service.approved, isEmpty);
  });

  testWidgets('pending approval disables consent and duplicate submissions', (
    tester,
  ) async {
    final service = _ReviewService()..approvalGate = Completer<void>();
    await tester.pumpWidget(_screen(service));
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await _scrollTo(tester, _approveButton);
    await tester.tap(_approveButton);
    await tester.pump();
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).onChanged, isNull);
    expect(tester.widget<FilledButton>(_approveButton).onPressed, isNull);
    expect(service.approved, hasLength(1));
    service.approvalGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text(_strings.approved), findsOneWidget);
  });

  testWidgets(
    'narrow screen and large text keep full fingerprints and controls accessible',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = _ReviewService();
      await tester.pumpWidget(_screen(service, scale: 2));
      await tester.pumpAndSettle();
      await _scrollTo(tester, find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await _scrollTo(tester, _approveButton);
      expect(tester.widget<FilledButton>(_approveButton).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'person info opens real review with peer ID, and back does not approve',
    (tester) async {
      final defaults = createWidgetTestContainer();
      final service = _ReviewService();
      final container = AppContainer.testing(
        session: defaults.session,
        conversations: defaults.conversations,
        crypto: service,
        signaling: defaults.signaling,
        chatAccessRuntime: defaults.chatAccessRuntime,
        callReadinessRuntime: defaults.callReadinessRuntime,
        chatInfoRuntime: AppChatInfoRuntime(
          service: _InfoService(),
          polls: _Polls(),
          interactions: _Interactions(),
          activity: _Activity(),
        ),
      );
      await tester.pumpWidget(
        AppContainerScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              settings: const RouteSettings(
                arguments: Conversation(
                  id: 'conversation-not-peer-id',
                  peerId: 'peer',
                  peerName: 'Peer',
                  peerPhone: '',
                ),
              ),
              builder: (_) => const ChatInfoScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(_strings.title));
      await tester.tap(find.text(_strings.title));
      await tester.pumpAndSettle();
      expect(find.byType(PeerIdentityReviewScreen), findsOneWidget);
      expect(service.reviewedPeers, ['peer']);
      expect(find.text(service.review.currentFingerprint), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(ChatInfoScreen), findsOneWidget);
      expect(service.approved, isEmpty);
    },
  );
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 100,
  );
  await tester.pump();
}

Widget _screen(_ReviewService service, {double scale = 1}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: PeerIdentityReviewScreen(
    service: service,
    peerId: 'peer',
    peerName: 'Peer',
  ),
);

PeerIdentityReview _review(int current) => PeerIdentityReview(
  peerId: 'peer',
  previousIdentity: List.filled(33, 1),
  currentIdentity: List.filled(33, current),
  localIdentity: List.filled(33, 3),
);

class _ReviewService implements PeerIdentityReviewService, CryptoService {
  PeerIdentityReview review = _review(2);
  final approved = <PeerIdentityReview>[];
  final reviewedPeers = <String>[];
  Object? loadError;
  Object? approvalError;
  Completer<void>? approvalGate;

  @override
  Future<PeerIdentityReview> reviewPeerIdentity(String peerId) async {
    reviewedPeers.add(peerId);
    if (loadError != null) throw loadError!;
    return review;
  }

  @override
  Future<void> approvePeerIdentity(PeerIdentityReview review) async {
    approved.add(review);
    await approvalGate?.future;
    if (approvalError != null) throw approvalError!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _InfoService implements ChatInfoService {
  @override
  Stream<ConversationEntity?> watchConversation(String id) => Stream.value(
    const ConversationEntity(
      id: 'conversation-not-peer-id',
      peerId: 'peer',
      peerName: 'Peer',
      peerPhone: '',
    ),
  );
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
