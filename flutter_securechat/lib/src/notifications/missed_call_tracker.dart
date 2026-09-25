import 'dart:async';

import '../l10n/service_strings.dart';

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
    ServiceStrings? strings,
  }) : _conversations = conversations,
       _presenter = presenter,
       _onCallback = onCallback,
       _strings = strings ?? ServiceStrings.fixed('tr'),
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
  final ServiceStrings _strings;
  final Duration timeout;
  final Map<String, Timer> _timers = {};
  final Set<String> _recorded = {};
  final Set<String> _notified = {};
  final Map<String, Future<void>> _pending = {};
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
    if (_closed) return;
    cancel(session.callId);
    if (_notified.contains(session.callId)) return;
    final pending = _pending[session.callId];
    if (pending != null) return pending;
    final operation = _recordAndNotify(session);
    _pending[session.callId] = operation;
    try {
      await operation;
    } finally {
      _pending.remove(session.callId);
    }
  }

  Future<void> _recordAndNotify(CallSession session) async {
    final targetId = session.isGroupCall ? session.groupId : session.peerId;
    if (targetId == null || targetId.isEmpty) return;
    final missedCall = (await _strings.load()).missed_call;
    final conversation = session.isGroupCall
        ? await _conversations.getById(targetId)
        : await _conversations.getByPeerId(targetId);
    if (!_recorded.contains(session.callId) && conversation != null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _conversations.recordMissedCall(conversation.id, missedCall, now);
    }
    // A presentation failure may retry, but must not increment unread again.
    _recorded.add(session.callId);
    await _presenter.showMissedCall(
      MissedCallNotification(
        id: _stableNotificationId(targetId),
        callId: session.callId,
        peerId: targetId,
        peerName: session.isGroupCall
            ? conversation?.peerName ?? session.peerName
            : session.peerName,
        callType: session.callType,
        silent: session.state == CallState.busy,
        isGroupCall: session.isGroupCall,
      ),
    );
    _notified.add(session.callId);
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
