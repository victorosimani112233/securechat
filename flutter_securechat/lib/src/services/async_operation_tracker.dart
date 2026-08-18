import 'dart:async';

typedef AsyncOperationFailureHandler =
    FutureOr<void> Function(
      String operation,
      Object error,
      StackTrace stackTrace,
    );

/// Owns fire-and-forget work started by stream and timer callbacks.
///
/// Every failure is contained and reported through the injected privacy-safe
/// boundary. [close] stops accepting work and waits until all already-owned
/// operations finish, including work registered by another owned operation.
class AsyncOperationTracker {
  AsyncOperationTracker({AsyncOperationFailureHandler? onFailure})
    : _onFailure = onFailure;

  final AsyncOperationFailureHandler? _onFailure;
  final Set<Future<void>> _pending = {};
  Future<void>? _closeTask;
  bool _accepting = true;

  int get pendingCount => _pending.length;
  bool get isClosed => _closeTask != null;

  void run(String operation, Future<dynamic> future) {
    if (!_accepting) {
      throw StateError(
        'Cannot start $operation after operation tracker closed',
      );
    }
    late final Future<void> tracked;
    tracked = _observe(
      operation,
      future,
    ).whenComplete(() => _pending.remove(tracked));
    _pending.add(tracked);
  }

  Future<void> close() {
    final active = _closeTask;
    if (active != null) return active;
    _accepting = false;
    final operation = _drain();
    _closeTask = operation;
    return operation;
  }

  /// Waits for work already owned by this tracker without closing it.
  /// Callers must first quiesce the source that can enqueue new work.
  Future<void> waitForIdle() => _drain();

  Future<void> _observe(String operation, Future<dynamic> future) async {
    try {
      await future;
    } catch (error, stackTrace) {
      try {
        await _onFailure?.call(operation, error, stackTrace);
      } catch (_) {
        // A diagnostics backend must never turn a contained callback failure
        // into a second uncaught asynchronous error.
      }
    }
  }

  Future<void> _drain() async {
    while (_pending.isNotEmpty) {
      await Future.wait(_pending.toList(growable: false));
    }
  }
}
