import 'dart:async';

import '../media/call_models.dart';
import '../services/async_operation_tracker.dart';
import '../storage/secure_chat_database.dart';
import 'message_notification_service.dart';

typedef MissedCallCallback = Future<void> Function(MissedCallAction action);

abstract interface class MissedCallLifecycle {
  void start(CallSession session);
  void cancel(String callId);
  Future<void> triggerNow(CallSession session);
  Future<void> close();
}

class MissedCallTracker implements MissedCallLifecycle {
  MissedCallTracker({
    required ConversationDao conversations,
    required MissedCallNotificationPresenter presenter,
    required MissedCallCallback onCallback,
    this.timeout = const Duration(seconds: 30),
    AsyncOperationFailureHandler? onAsyncFailure,
  }) : _conversations = conversations,
       _presenter = presenter,
       _onCallback = onCallback,
       _operations = AsyncOperationTracker(onFailure: onAsyncFailure) {
    _callbackSubscription = presenter.missedCallCallbacks.listen((action) {
      if (!_closed) {
        _operations.run('missed-call.callback', _onCallback(action));
      }
    });
  }

  final ConversationDao _conversations;
  final MissedCallNotificationPresenter _presenter;
  final MissedCallCallback _onCallback;
  final AsyncOperationTracker _operations;
  final Duration timeout;
  final Map<String, Timer> _timers = {};
  final Set<String> _recorded = {};
  late final StreamSubscription<MissedCallAction> _callbackSubscription;
  Future<void>? _closeTask;
  bool _closed = false;

  @override
  void start(CallSession session) {
    if (_closed) return;
    cancel(session.callId);
    _timers[session.callId] = Timer(timeout, () {
      if (!_closed) {
        _operations.run('missed-call.timeout', triggerNow(session));
      }
    });
  }

  @override
  void cancel(String callId) {
    _timers.remove(callId)?.cancel();
  }

  @override
  Future<void> triggerNow(CallSession session) async {
    cancel(session.callId);
    if (!_recorded.add(session.callId)) return;
    final conversation = await _conversations.getByPeerId(session.peerId);
    if (conversation != null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _conversations.updateLastMessage(
        session.peerId,
        'Kaçırılan arama',
        now,
      );
      await _conversations.incrementUnreadCount(session.peerId);
    }
    await _presenter.showMissedCall(
      MissedCallNotification(
        id: _stableNotificationId(session.peerId),
        callId: session.callId,
        peerId: session.peerId,
        peerName: session.peerName,
        callType: session.callType,
      ),
    );
  }

  @override
  Future<void> close() {
    final active = _closeTask;
    if (active != null) return active;
    _closed = true;
    final operation = _close();
    _closeTask = operation;
    return operation;
  }

  Future<void> _close() async {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    await _callbackSubscription.cancel();
    await _operations.close();
  }
}

int _stableNotificationId(String value) {
  var hash = 0x811c9dc5;
  for (final codeUnit in value.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return 3000 + (hash == 0 ? 1 : hash);
}
