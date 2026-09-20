import 'dart:async';

import '../core/signal_message.dart';
import '../incoming/incoming_message_handler.dart';
import 'session_store.dart';
import 'signaling_service.dart';

class AppPeerActivity {
  const AppPeerActivity({
    this.isTyping = false,
    this.isOnline = false,
    this.lastSeen,
  });

  final bool isTyping;
  final bool isOnline;
  final DateTime? lastSeen;

  @override
  bool operator ==(Object other) =>
      other is AppPeerActivity &&
      other.isTyping == isTyping &&
      other.isOnline == isOnline &&
      other.lastSeen == lastSeen;

  @override
  int get hashCode => Object.hash(isTyping, isOnline, lastSeen);
}

abstract interface class AppPeerActivitySource {
  Stream<AppPeerActivity> watch(String peerId);
}

/// Presentation adapter for the incoming signaling state.
///
/// Feature widgets consume only the privacy-safe activity projection and do
/// not depend on the incoming-message/WebSocket implementation.
class IncomingPeerActivitySource implements AppPeerActivitySource {
  const IncomingPeerActivitySource(
    this._incoming, {
    required SignalingService signaling,
    required SessionStore session,
  }) : _signaling = signaling,
       _session = session;

  final IncomingMessageHandler _incoming;
  final SignalingService _signaling;
  final SessionStore _session;

  @override
  Stream<AppPeerActivity> watch(String peerId) {
    late final StreamController<AppPeerActivity> controller;
    StreamSubscription<Map<String, bool>>? typingSubscription;
    StreamSubscription<Map<String, PresenceInfo>>? presenceSubscription;
    StreamSubscription<SignalingStatus>? statusSubscription;
    var typing = false;
    var online = false;
    var subscribed = false;
    var subscribing = false;
    var closing = false;
    Future<void>? pendingSubscription;
    DateTime? lastSeen;
    AppPeerActivity? previous;

    void emit() {
      final next = AppPeerActivity(
        isTyping: typing,
        isOnline: online,
        lastSeen: lastSeen,
      );
      if (next == previous || controller.isClosed) return;
      previous = next;
      controller.add(next);
    }

    Future<void> subscribe() async {
      if (closing || subscribed || subscribing) return;
      final userId = _session.userId;
      if (userId == null || !_signaling.currentStatus.isConnected) return;
      subscribing = true;
      try {
        subscribed = await _signaling.send(
          PresenceSubscribeSignal(
            senderId: userId,
            recipientId: peerId,
            timestamp: DateTime.now(),
          ),
        );
      } catch (_) {
        subscribed = false;
      } finally {
        subscribing = false;
      }
    }

    void requestSubscription() {
      if (pendingSubscription != null) return;
      late final Future<void> operation;
      operation = subscribe().whenComplete(() {
        if (identical(pendingSubscription, operation)) {
          pendingSubscription = null;
        }
      });
      pendingSubscription = operation;
      unawaited(operation);
    }

    controller = StreamController<AppPeerActivity>(
      onListen: () {
        typingSubscription = _incoming.typingStates.listen((states) {
          typing = states[peerId] ?? false;
          emit();
        }, onError: controller.addError);
        presenceSubscription = _incoming.presenceStates.listen((states) {
          final presence = states[peerId];
          online = presence?.isOnline ?? false;
          lastSeen = presence?.lastSeen;
          emit();
        }, onError: controller.addError);
        statusSubscription = _signaling.statuses.listen((status) {
          if (status.isConnected) {
            requestSubscription();
          } else {
            subscribed = false;
          }
        }, onError: controller.addError);
      },
      onCancel: () async {
        closing = true;
        await statusSubscription?.cancel();
        await pendingSubscription;
        final userId = _session.userId;
        if (subscribed &&
            userId != null &&
            _signaling.currentStatus.isConnected) {
          try {
            await _signaling.send(
              PresenceUnsubscribeSignal(
                senderId: userId,
                recipientId: peerId,
                timestamp: DateTime.now(),
              ),
            );
          } catch (_) {
            // Socket teardown also clears the server-side subscription.
          }
        }
        await typingSubscription?.cancel();
        await presenceSubscription?.cancel();
      },
    );
    return controller.stream;
  }
}
