import 'dart:math';

import 'package:flutter/foundation.dart';

import '../media/call_models.dart';
import '../media/native_call_integration.dart';
import '../notifications/message_notification_service.dart';
import '../notifications/missed_call_tracker.dart';

class NotificationDebugHarness {
  NotificationDebugHarness({
    required NativeCallIntegration nativeCalls,
    required MissedCallLifecycle missedCalls,
    required LocalNotificationPresenter notifications,
    Random? random,
  }) : _nativeCalls = nativeCalls,
       _missedCalls = missedCalls,
       _notifications = notifications,
       _random = random ?? Random.secure();

  final NativeCallIntegration _nativeCalls;
  final MissedCallLifecycle _missedCalls;
  final LocalNotificationPresenter _notifications;
  final Random _random;

  Future<CallSession> simulateIncomingCall({
    String callerName = 'Test Caller',
    CallType callType = CallType.voice,
  }) async {
    _debugOnly();
    final session = _session('test-caller', callerName, callType);
    await _nativeCalls.reportIncoming(session);
    return session;
  }

  Future<CallSession> simulateMissedCall({
    String callerName = 'Missed Caller',
    CallType callType = CallType.voice,
  }) async {
    _debugOnly();
    final session = _session('missed-caller', callerName, callType);
    await _missedCalls.triggerNow(session);
    return session;
  }

  Future<void> simulateMessageNotification({
    String sender = 'Test User',
    String message = 'This is a test message.',
    bool hideContent = false,
  }) async {
    _debugOnly();
    await _notifications.show(
      LocalMessageNotification(
        id: 900001,
        title: hideContent ? 'Elçim' : sender,
        body: hideContent ? '1 yeni mesaj' : message,
        payload: hideContent ? null : 'debug-conversation',
        conversationId: 'debug-conversation',
        count: 1,
        silent: false,
        hideOnLockScreen: hideContent,
      ),
    );
  }

  Future<void> initializeNotificationChannels() async {
    _debugOnly();
    await _notifications.initialize();
  }

  CallSession _session(String peerId, String peerName, CallType callType) =>
      CallSession(
        callId: 'debug-${_random.nextInt(0x7fffffff)}',
        peerId: peerId,
        peerName: peerName,
        callType: callType,
        direction: CallDirection.incoming,
        state: CallState.ringing,
      );

  static void _debugOnly() {
    if (!kDebugMode) {
      throw StateError('NotificationDebugHarness is disabled outside debug');
    }
  }
}
