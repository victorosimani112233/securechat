import 'dart:async';
import 'dart:math';

import 'package:flutter_securechat/src/debug/notification_debug_harness.dart';
import 'package:flutter_securechat/src/media/call_models.dart';
import 'package:flutter_securechat/src/media/native_call_integration.dart';
import 'package:flutter_securechat/src/notifications/message_notification_service.dart';
import 'package:flutter_securechat/src/notifications/missed_call_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'debug harness drives incoming, missed and privacy notification paths',
    () async {
      final native = _FakeNativeCalls();
      final missed = _FakeMissedCalls();
      final notifications = _FakeNotifications();
      final harness = NotificationDebugHarness(
        nativeCalls: native,
        missedCalls: missed,
        notifications: notifications,
        random: Random(1),
      );

      final incoming = await harness.simulateIncomingCall(
        callerName: 'Debug Alice',
        callType: CallType.video,
      );
      final missedSession = await harness.simulateMissedCall();
      await harness.simulateMessageNotification(
        sender: 'Secret Sender',
        message: 'Secret Body',
        hideContent: true,
      );
      await harness.initializeNotificationChannels();

      expect(native.incoming.single, same(incoming));
      expect(incoming.state, CallState.ringing);
      expect(missed.triggered.single, same(missedSession));
      expect(notifications.initializations, 1);
      expect(notifications.shown.single.title, 'Elçim');
      expect(notifications.shown.single.body, '1 yeni mesaj');
      expect(notifications.shown.single.payload, isNull);
      expect(notifications.shown.single.hideOnLockScreen, isTrue);
    },
  );
}

class _FakeNativeCalls implements NativeCallIntegration {
  final incoming = <CallSession>[];

  @override
  Stream<NativeCallAction> get actions => const Stream.empty();
  @override
  Future<void> initialize() async {}
  @override
  Future<void> reportIncoming(CallSession session) async =>
      incoming.add(session);
  @override
  Future<void> reportOutgoing(CallSession session) async {}
  @override
  Future<void> setActive(String callId) async {}
  @override
  Future<void> end(String callId) async {}
}

class _FakeMissedCalls implements MissedCallLifecycle {
  final triggered = <CallSession>[];
  @override
  void start(CallSession session) {}
  @override
  void cancel(String callId) {}
  @override
  Future<void> triggerNow(CallSession session) async => triggered.add(session);
  @override
  Future<void> close() async {}
}

class _FakeNotifications implements LocalNotificationPresenter {
  final shown = <LocalMessageNotification>[];
  var initializations = 0;
  @override
  Stream<String> get taps => const Stream.empty();
  @override
  Stream<NotificationDismissal> get dismissals => const Stream.empty();
  @override
  Future<void> initialize() async => initializations++;
  @override
  Future<void> show(LocalMessageNotification notification) async =>
      shown.add(notification);
  @override
  Future<void> reconcileDismissals() async {}
  @override
  Future<void> cancelAll() async {}
}
