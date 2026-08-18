import 'dart:async';

import '../incoming/incoming_message_handler.dart';

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
  const IncomingPeerActivitySource(this._incoming);

  final IncomingMessageHandler _incoming;

  @override
  Stream<AppPeerActivity> watch(String peerId) {
    late final StreamController<AppPeerActivity> controller;
    StreamSubscription<Map<String, bool>>? typingSubscription;
    StreamSubscription<Map<String, PresenceInfo>>? presenceSubscription;
    var typing = false;
    var online = false;
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
      },
      onCancel: () async {
        await typingSubscription?.cancel();
        await presenceSubscription?.cancel();
      },
    );
    return controller.stream;
  }
}
