import 'dart:async';

import '../core/signal_message.dart';
import '../network/network_monitor.dart';
import 'async_operation_tracker.dart';
import 'session_store.dart';
import 'signaling_service.dart';

typedef LifecycleTask = Future<void> Function();

class AppLifecycleCoordinator {
  AppLifecycleCoordinator({
    required SessionStore session,
    required SignalingService signaling,
    required String signalingUrl,
    required LifecycleTask foregroundMaintenance,
    required LifecycleTask refreshPushRegistration,
    Future<String?> Function()? refreshAccessToken,
    NetworkStatusMonitor? networkMonitor,
    bool allowLoopbackWhenOffline = false,
    AsyncOperationFailureHandler? onAsyncFailure,
  }) : _session = session,
       _signaling = signaling,
       _signalingUrl = signalingUrl,
       _foregroundMaintenance = foregroundMaintenance,
       _refreshPushRegistration = refreshPushRegistration,
       _refreshAccessToken = refreshAccessToken,
       _networkMonitor = networkMonitor,
       _allowLoopbackWhenOffline = allowLoopbackWhenOffline,
       _onAsyncFailure = onAsyncFailure;

  final SessionStore _session;
  final SignalingService _signaling;
  final String _signalingUrl;
  final LifecycleTask _foregroundMaintenance;
  final LifecycleTask _refreshPushRegistration;
  final Future<String?> Function()? _refreshAccessToken;
  final NetworkStatusMonitor? _networkMonitor;
  final bool _allowLoopbackWhenOffline;
  final AsyncOperationFailureHandler? _onAsyncFailure;
  StreamSubscription<NetworkSnapshot>? _networkSubscription;
  Future<void> _transition = Future.value();
  Future<void>? _disposeTask;
  bool _foreground = false;
  bool _disposed = false;

  bool get isForeground => _foreground;

  Future<void> enterForeground() {
    _ensureUsable();
    return _serialize(_enterForeground);
  }

  Future<void> enterBackground() {
    _ensureUsable();
    return _serialize(_enterBackground);
  }

  Future<void> _enterForeground() async {
    if (_foreground) return;
    _foreground = true;
    final monitor = _networkMonitor;
    if (monitor != null) {
      final snapshot = await monitor.start();
      await _signaling.onNetworkChanged(
        isAvailable: _isSignalingTransportAvailable(snapshot),
      );
      _networkSubscription ??= monitor.changes.listen((snapshot) {
        if (_disposed || !_foreground) return;
        unawaited(_applyNetworkChange(snapshot));
      });
    }
    if (!_session.isLoggedIn) {
      await _runMaintenance();
      return;
    }
    final userId = _session.userId!;
    final token = _session.accessToken!;
    if (!_signaling.currentStatus.isConnected ||
        _signaling.currentUserId != userId) {
      await _signaling.connect(
        userId: userId,
        url: _signalingUrl,
        accessToken: token,
        tokenProvider: () async => _session.accessToken,
        refreshToken: _refreshAccessToken,
      );
    }
    await _runMaintenance();
    if (await _signaling.ensureConnected(
      timeout: const Duration(seconds: 10),
    )) {
      await _signaling.send(
        PresenceUpdateSignal(
          senderId: userId,
          recipientId: 'server',
          timestamp: DateTime.now(),
          isOnline: true,
          lastSeen: DateTime.now(),
          hideLastSeen: !_session.shareLastSeen,
        ),
      );
    }
    try {
      await _refreshPushRegistration();
    } catch (_) {
      // Push kaydi WebSocket yasam dongusunu bozmamali; sonraki resume dener.
    }
  }

  Future<void> _applyNetworkChange(NetworkSnapshot snapshot) async {
    try {
      await _serialize(
        () => _signaling.onNetworkChanged(
          isAvailable: _isSignalingTransportAvailable(snapshot),
        ),
      );
    } catch (error, stackTrace) {
      final handler = _onAsyncFailure;
      if (handler != null) {
        try {
          await handler('lifecycle.network-change', error, stackTrace);
        } catch (_) {
          // Diagnostics failures must not escape a stream callback.
        }
      }
    }
  }

  bool _isSignalingTransportAvailable(NetworkSnapshot snapshot) =>
      snapshot.isAvailable || _allowLoopbackWhenOffline;

  Future<void> _enterBackground() async {
    if (!_foreground) return;
    _foreground = false;
    if (!_session.isLoggedIn) {
      if (_signaling.currentStatus.isConnected) await _signaling.disconnect();
      await _stopNetworkMonitor();
      return;
    }
    if (_signaling.currentStatus.isConnected) {
      final now = DateTime.now();
      await _signaling.send(
        PresenceUpdateSignal(
          senderId: _session.userId!,
          recipientId: 'server',
          timestamp: now,
          isOnline: false,
          lastSeen: now,
          hideLastSeen: !_session.shareLastSeen,
        ),
      );
    }
    await _signaling.disconnect();
    await _stopNetworkMonitor();
  }

  Future<void> _serialize(Future<void> Function() action) {
    final next = _transition.then((_) => action());
    _transition = next.catchError((_) {});
    return next;
  }

  Future<void> _runMaintenance() async {
    try {
      await _foregroundMaintenance();
    } catch (_) {
      // Tek bir cleanup hatasi reconnect/presence akisini engellememelidir.
    }
  }

  Future<void> _stopNetworkMonitor() async {
    await _networkSubscription?.cancel();
    _networkSubscription = null;
    await _networkMonitor?.stop();
  }

  Future<void> dispose() {
    final active = _disposeTask;
    if (active != null) return active;
    _disposed = true;
    final operation = _serialize(() async {
      await _enterBackground();
      await _stopNetworkMonitor();
    });
    _disposeTask = operation;
    return operation;
  }

  void _ensureUsable() {
    if (_disposed) throw StateError('Application lifecycle is disposed');
  }
}
