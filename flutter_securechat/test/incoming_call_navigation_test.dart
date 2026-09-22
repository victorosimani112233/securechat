import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/app.dart';
import 'package:flutter_securechat/src/calls/call_history_service.dart';
import 'package:flutter_securechat/src/features/auth/auth_screen.dart';
import 'package:flutter_securechat/src/features/calls/call_screen.dart';
import 'package:flutter_securechat/src/media/call_manager.dart';
import 'package:flutter_securechat/src/media/call_models.dart';
import 'package:flutter_securechat/src/services/app_container.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app_container.dart';

const incoming = CallSession(
  callId: 'incoming-1',
  peerId: 'peer-ayse',
  peerName: 'Ayse Demir',
  callType: CallType.voice,
  direction: CallDirection.incoming,
  state: CallState.ringing,
);

Future<void> settleLaunch(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 800));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

Future<_Calls> mountApp(WidgetTester tester, {CallSession? initial}) async {
  final calls = _Calls(initial);
  final container = createWidgetTestContainer(mediaRuntime: _Media(calls));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await calls.close();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
  await tester.pumpWidget(SecureChatFlutterApp(container: container));
  return calls;
}

void main() {
  testWidgets(
    'launcher cold start opens an existing ringing call without a tap',
    (tester) async {
      final calls = await mountApp(tester, initial: incoming);
      await settleLaunch(tester);
      expect(find.byType(CallScreen), findsOneWidget);
      expect(calls.answers, 0);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(Icons.call));
      await tester.pump();
      expect(calls.answers, 1);
    },
  );

  testWidgets(
    'offer arriving after launch opens once and back keeps a ringing banner',
    (tester) async {
      final calls = await mountApp(tester);
      await settleLaunch(tester);
      calls.emit(incoming);
      await settleLaunch(tester);
      expect(find.byType(CallScreen), findsOneWidget);
      calls.emit(incoming);
      await tester.pump();
      await tester.tap(find.byType(BackButton));
      await settleLaunch(tester);
      expect(find.byType(CallScreen), findsNothing);
      expect(find.byKey(const ValueKey('ongoing-call-bar')), findsOneWidget);
      expect(calls.answers, 0);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('ongoing-call-bar')));
      await settleLaunch(tester);
      expect(find.byType(CallScreen), findsOneWidget);
      await tester.tap(find.byIcon(Icons.call_end));
      await settleLaunch(tester);
      expect(find.byType(CallScreen), findsNothing);
      expect(find.byKey(const ValueKey('ongoing-call-bar')), findsNothing);
    },
  );

  testWidgets(
    'foreground resume restores an unanswered call without notification action',
    (tester) async {
      final calls = await mountApp(tester);
      await settleLaunch(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      calls.emit(incoming);
      await tester.pump();
      expect(find.byType(CallScreen), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settleLaunch(tester);
      expect(find.byType(CallScreen), findsOneWidget);
      expect(calls.answers, 0);
    },
  );

  testWidgets('call ending during launch does not open a stale call screen', (
    tester,
  ) async {
    final calls = await mountApp(tester, initial: incoming);
    await tester.pump();
    calls.emit(null);
    await settleLaunch(tester);
    expect(find.byType(CallScreen), findsNothing);
    expect(find.byKey(const ValueKey('ongoing-call-bar')), findsNothing);
  });

  testWidgets('call ending in background is not resurrected on resume', (
    tester,
  ) async {
    final calls = await mountApp(tester);
    await settleLaunch(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    calls.emit(incoming);
    await tester.pump();
    calls.emit(null);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settleLaunch(tester);
    expect(find.byType(CallScreen), findsNothing);
  });

  testWidgets('outgoing ringing does not force navigation on launch', (
    tester,
  ) async {
    await mountApp(
      tester,
      initial: const CallSession(
        callId: 'outgoing-1',
        peerId: 'peer-ayse',
        peerName: 'Ayse Demir',
        callType: CallType.voice,
        direction: CallDirection.outgoing,
        state: CallState.ringing,
      ),
    );
    await settleLaunch(tester);
    expect(find.byType(CallScreen), findsNothing);
  });

  testWidgets('incoming call waits for authentication route to finish', (
    tester,
  ) async {
    final calls = await mountApp(tester);
    await settleLaunch(tester);
    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    unawaited(navigator.pushNamed('/auth'));
    await settleLaunch(tester);
    calls.emit(incoming);
    await settleLaunch(tester);
    expect(find.byType(AuthScreen), findsOneWidget);
    expect(find.byType(CallScreen), findsNothing);
    navigator.pop();
    await settleLaunch(tester);
    expect(find.byType(CallScreen), findsOneWidget);
  });

  testWidgets(
    'group invitation also opens from launcher without a native tap',
    (tester) async {
      await mountApp(
        tester,
        initial: const CallSession(
          callId: 'group-call-1',
          peerId: 'peer-ayse',
          peerName: 'Operations',
          callType: CallType.voice,
          direction: CallDirection.incoming,
          state: CallState.ringing,
          isGroupCall: true,
          groupId: 'group-ops',
        ),
      );
      await settleLaunch(tester);
      expect(find.byType(CallScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class _Calls implements CallManager {
  _Calls(this.currentSession);
  final updates = StreamController<CallSession?>.broadcast();
  int answers = 0;

  @override
  CallSession? currentSession;
  @override
  Stream<CallSession?> get sessions async* {
    yield currentSession;
    yield* updates.stream;
  }

  @override
  Stream<void> get openRequests => const Stream.empty();
  @override
  Duration get currentDuration => Duration.zero;
  @override
  Future<bool> acceptCall() async {
    answers++;
    return true;
  }

  @override
  Future<void> rejectCall() async => emit(null);

  void emit(CallSession? session) {
    currentSession = session;
    updates.add(session);
  }

  Future<void> close() => updates.close();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Media implements AppMediaRuntime {
  _Media(this.calls);
  @override
  final CallManager calls;
  @override
  final CallHistoryService callHistory = _History();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _History implements CallHistoryService {
  @override
  Stream<List<CallHistoryEntry>> watchAll() => Stream.value(const []);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
