import 'dart:async';

import '../core/signal_message.dart';
import '../services/signaling_service.dart';
import '../services/async_operation_tracker.dart';
import '../storage/secure_chat_database.dart';
import '../storage/storage_entities.dart';

class QueueFlushResult {
  const QueueFlushResult({required this.sent, required this.remaining});

  final int sent;
  final int remaining;
}

/// Persistent offline signaling queue. Only already-encrypted wire signals are
/// accepted, so plaintext never enters the queue even transiently.
class OfflineMessageQueue {
  OfflineMessageQueue({
    required SecureChatDatabase database,
    required SignalingService signaling,
    AsyncOperationFailureHandler? onAsyncFailure,
  }) : _database = database,
       _signaling = signaling,
       _onAsyncFailure = onAsyncFailure,
       _operations = AsyncOperationTracker(onFailure: onAsyncFailure);

  final SecureChatDatabase _database;
  final SignalingService _signaling;
  final AsyncOperationFailureHandler? _onAsyncFailure;
  final AsyncOperationTracker _operations;
  StreamSubscription<SignalingStatus>? _connectionSubscription;
  Future<QueueFlushResult>? _activeFlush;
  var _sequence = 0;
  Future<void>? _closeTask;
  bool _closed = false;

  void start() {
    if (_closed) throw StateError('Offline message queue is closed');
    _connectionSubscription ??= _signaling.statuses.listen((status) {
      if (status.isConnected && !_closed) {
        _operations.run('offline-queue.flush', flushQueue());
      }
    });
  }

  Future<bool> sendOrQueue(SignalMessage encryptedSignal) async {
    if (encryptedSignal is! EncryptedSignalMessage &&
        encryptedSignal is! GroupMessageFanoutSignal &&
        encryptedSignal is! FileTransferSignal) {
      throw ArgumentError.value(
        encryptedSignal.type,
        'encryptedSignal',
        'Offline queue accepts encrypted payload signals only',
      );
    }
    if (await _sendSafely('offline-queue.send', encryptedSignal)) return true;

    final now = DateTime.now().microsecondsSinceEpoch;
    await _database.pendingSignals.put(
      PendingSignalEntity(
        id: '$now-${_sequence++}',
        encodedSignal: encryptedSignal.encode(),
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    return false;
  }

  Future<int> getPendingCount() => _database.pendingSignals.count();

  Future<QueueFlushResult> flushQueue() {
    final running = _activeFlush;
    if (running != null) return running;
    final flush = _flush();
    _activeFlush = flush;
    return flush.whenComplete(() => _activeFlush = null);
  }

  Future<QueueFlushResult> _flush() async {
    var sent = 0;
    final snapshot = await _database.pendingSignals.getAll();
    for (final pending in snapshot) {
      final signal = SignalMessage.decode(pending.encodedSignal);
      if (await _sendSafely('offline-queue.flush-send', signal)) {
        await _database.pendingSignals.delete(pending.id);
        sent++;
      } else {
        await _database.pendingSignals.put(
          pending.copyWith(attempts: pending.attempts + 1),
        );
        break;
      }
    }
    return QueueFlushResult(
      sent: sent,
      remaining: await _database.pendingSignals.count(),
    );
  }

  Future<void> clearQueue() => _database.pendingSignals.clear();

  Future<bool> _sendSafely(String operation, SignalMessage signal) async {
    try {
      return await _signaling.send(signal);
    } catch (error, stackTrace) {
      try {
        await _onAsyncFailure?.call(operation, error, stackTrace);
      } catch (_) {
        // Diagnostics must not turn a recoverable transport failure into
        // message loss. The already-encrypted signal remains queueable.
      }
      return false;
    }
  }

  Future<void> close() {
    final active = _closeTask;
    if (active != null) return active;
    _closed = true;
    final operation = _close();
    _closeTask = operation;
    return operation;
  }

  Future<void> _close() async {
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    await _operations.close();
    await _activeFlush;
  }
}

class StuckMessageRecovery {
  StuckMessageRecovery(this._database);

  static const defaultTimeout = Duration(seconds: 30);
  final SecureChatDatabase _database;

  Future<int> recoverStuckMessages({
    Duration timeout = defaultTimeout,
    DateTime? now,
  }) {
    final cutoff = (now ?? DateTime.now()).subtract(timeout);
    return _database.messages.markStuckMessagesAsFailed(
      cutoff.millisecondsSinceEpoch,
    );
  }
}
