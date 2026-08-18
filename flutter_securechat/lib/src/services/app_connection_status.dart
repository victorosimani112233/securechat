import 'signaling_service.dart';

/// Presentation-safe connection phases exposed to feature widgets.
///
/// The adapter keeps the WebSocket/signaling implementation outside the UI
/// boundary while preserving live status and explicit retry behavior.
enum AppConnectionPhase { disconnected, connecting, connected, error }

class AppConnectionStatus {
  const AppConnectionStatus(this.phase, {this.error});

  final AppConnectionPhase phase;
  final Object? error;

  bool get isConnected => phase == AppConnectionPhase.connected;
}

abstract interface class AppConnectionStatusSource {
  Stream<AppConnectionStatus> get statuses;
  AppConnectionStatus get current;
  Future<void> retry();
}

class SignalingConnectionStatusSource implements AppConnectionStatusSource {
  const SignalingConnectionStatusSource(this._signaling);

  final SignalingService _signaling;

  @override
  Stream<AppConnectionStatus> get statuses => _signaling.statuses.map(_map);

  @override
  AppConnectionStatus get current => _map(_signaling.currentStatus);

  @override
  Future<void> retry() => _signaling.retryConnection();

  static AppConnectionStatus _map(SignalingStatus status) =>
      AppConnectionStatus(switch (status.state) {
        SignalingConnectionState.disconnected =>
          AppConnectionPhase.disconnected,
        SignalingConnectionState.connecting => AppConnectionPhase.connecting,
        SignalingConnectionState.connected => AppConnectionPhase.connected,
        SignalingConnectionState.error => AppConnectionPhase.error,
      }, error: status.error);
}
