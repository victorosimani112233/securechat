import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/signal_message.dart';
import '../network/socket_diagnostics.dart';

enum SignalingConnectionState { disconnected, connecting, connected, error }

class SignalingStatus {
  const SignalingStatus(this.state, {this.error});

  final SignalingConnectionState state;
  final Object? error;

  bool get isConnected => state == SignalingConnectionState.connected;
}

typedef AccessTokenProvider = Future<String?> Function();

abstract interface class SignalingService {
  Stream<SignalMessage> get incoming;
  Stream<SignalingStatus> get statuses;
  SignalingStatus get currentStatus;
  String? get currentUserId;

  Future<void> connect({
    required String userId,
    required String url,
    required String accessToken,
    AccessTokenProvider? tokenProvider,
    AccessTokenProvider? refreshToken,
  });
  Future<bool> ensureConnected({Duration timeout});
  Future<bool> send(SignalMessage message);
  Future<void> retryConnection();
  Future<void> onNetworkChanged({required bool isAvailable});
  Future<void> disconnect();
  Future<void> dispose();
}

class InMemorySignalingService implements SignalingService {
  final _controller = StreamController<SignalMessage>.broadcast();
  final _statusController = StreamController<SignalingStatus>.broadcast();
  final sentMessages = <SignalMessage>[];
  final networkChanges = <bool>[];
  SignalingStatus _status = const SignalingStatus(
    SignalingConnectionState.disconnected,
  );
  String? _userId;
  bool _disposed = false;
  Future<void>? _disposeTask;

  @override
  Stream<SignalMessage> get incoming => _controller.stream;

  @override
  Stream<SignalingStatus> get statuses async* {
    yield _status;
    yield* _statusController.stream;
  }

  @override
  SignalingStatus get currentStatus => _status;

  @override
  String? get currentUserId => _userId;

  @override
  Future<void> connect({
    required String userId,
    required String url,
    required String accessToken,
    AccessTokenProvider? tokenProvider,
    AccessTokenProvider? refreshToken,
  }) async {
    _ensureUsable();
    _userId = userId;
    setConnected(true);
  }

  void setConnected(bool connected) {
    _ensureUsable();
    _status = SignalingStatus(
      connected
          ? SignalingConnectionState.connected
          : SignalingConnectionState.disconnected,
    );
    _statusController.add(_status);
  }

  void addIncoming(SignalMessage message) {
    _ensureUsable();
    _controller.add(message);
  }

  @override
  Future<bool> ensureConnected({
    Duration timeout = const Duration(seconds: 8),
  }) async => _status.isConnected;

  @override
  Future<bool> send(SignalMessage message) async {
    if (!_status.isConnected) return false;
    sentMessages.add(message);
    return true;
  }

  @override
  Future<void> retryConnection() async => setConnected(true);

  @override
  Future<void> onNetworkChanged({required bool isAvailable}) async {
    _ensureUsable();
    networkChanges.add(isAvailable);
    if (_userId != null) setConnected(isAvailable);
  }

  @override
  Future<void> disconnect() async {
    if (_disposed) return;
    _userId = null;
    setConnected(false);
  }

  @override
  Future<void> dispose() {
    final active = _disposeTask;
    if (active != null) return active;
    _userId = null;
    _disposed = true;
    final operation = _dispose();
    _disposeTask = operation;
    return operation;
  }

  Future<void> _dispose() async {
    await _controller.close();
    await _statusController.close();
  }

  void _ensureUsable() {
    if (_disposed) throw StateError('Signaling service is disposed');
  }
}

class WebSocketSignalingService implements SignalingService {
  WebSocketSignalingService({
    Random? random,
    HttpClient? httpClient,
    WebSocketTelemetry? telemetry,
  }) : _random = random ?? Random.secure(),
       _httpClient = httpClient,
       telemetry = telemetry ?? WebSocketTelemetry();

  static const initialReconnectDelay = Duration(seconds: 2);
  static const maximumReconnectDelay = Duration(seconds: 30);
  static const serverShutdownDelay = Duration(seconds: 5);

  final _controller = StreamController<SignalMessage>.broadcast();
  final _statusController = StreamController<SignalingStatus>.broadcast();
  final Random _random;
  final HttpClient? _httpClient;
  final WebSocketTelemetry telemetry;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Future<void>? _reconnectTask;
  Timer? _reconnectDelayTimer;
  Completer<bool>? _reconnectDelay;
  String? _userId;
  String? _url;
  String? _accessToken;
  AccessTokenProvider? _tokenProvider;
  AccessTokenProvider? _refreshToken;
  bool _manualDisconnect = false;
  bool _serverShutdownSeen = false;
  bool _networkAvailable = true;
  bool _disposed = false;
  Future<void>? _disposeTask;
  Future<void>? _refreshTask;
  int _generation = 0;
  SignalingStatus _status = const SignalingStatus(
    SignalingConnectionState.disconnected,
  );

  @override
  Stream<SignalMessage> get incoming => _controller.stream;

  @override
  Stream<SignalingStatus> get statuses async* {
    yield _status;
    yield* _statusController.stream;
  }

  @override
  SignalingStatus get currentStatus => _status;

  @override
  String? get currentUserId => _userId;

  @override
  Future<void> connect({
    required String userId,
    required String url,
    required String accessToken,
    AccessTokenProvider? tokenProvider,
    AccessTokenProvider? refreshToken,
  }) async {
    _ensureUsable();
    _manualDisconnect = true;
    _cancelReconnectDelay();
    await _closeSocket();
    await _waitForReconnectLoopToStop();
    _manualDisconnect = false;
    _userId = userId;
    _url = url;
    _accessToken = accessToken;
    _tokenProvider = tokenProvider;
    _refreshToken = refreshToken;
    if (!_networkAvailable) {
      _setStatus(null, SignalingConnectionState.disconnected);
      return;
    }
    await _open(scheduleOnFailure: true);
  }

  Future<void> _open({required bool scheduleOnFailure}) async {
    final userId = _userId;
    final url = _url;
    if (_disposed ||
        _manualDisconnect ||
        !_networkAvailable ||
        userId == null ||
        url == null) {
      return;
    }
    if (_status.state == SignalingConnectionState.connecting ||
        _status.isConnected) {
      return;
    }

    final token = await _tokenProvider?.call() ?? _accessToken;
    if (token == null || token.trim().isEmpty) {
      _setStatus(
        StateError('Access token unavailable'),
        SignalingConnectionState.error,
      );
      return;
    }
    _accessToken = token;
    _setStatus(null, SignalingConnectionState.connecting);
    final generation = ++_generation;
    try {
      final base = Uri.parse(url);
      final uri = base.replace(
        path: _joinPath(base.path, 'ws'),
        queryParameters: {...base.queryParameters, 'userId': userId},
      );
      final channel = IOWebSocketChannel.connect(
        uri,
        headers: {HttpHeaders.authorizationHeader: 'Bearer $token'},
        pingInterval: const Duration(seconds: 20),
        connectTimeout: const Duration(seconds: 8),
        customClient: _httpClient,
      );
      _channel = channel;
      _subscription = channel.stream.listen(
        (event) => _onMessage(event, generation),
        onError: (Object error, StackTrace stackTrace) {
          if (generation != _generation) return;
          _controller.addError(error, stackTrace);
          telemetry.recordFailure(error);
          _setStatus(error, SignalingConnectionState.error);
        },
        onDone: () => _onDone(generation),
        cancelOnError: false,
      );
      await channel.ready.timeout(const Duration(seconds: 8));
      if (generation != _generation || _manualDisconnect) {
        await channel.sink.close();
        return;
      }
      _setStatus(null, SignalingConnectionState.connected);
      telemetry.recordConnected();
    } catch (error, stackTrace) {
      if (generation != _generation) return;
      _controller.addError(error, stackTrace);
      telemetry.recordFailure(error);
      _setStatus(error, SignalingConnectionState.error);
      await _closeSocket(invalidate: false);
      if (scheduleOnFailure && !_manualDisconnect) _beginReconnect();
    }
  }

  void _onMessage(dynamic event, int generation) {
    if (_disposed || generation != _generation || event is! String) return;
    try {
      final signal = SignalMessage.decode(event);
      if (signal is ServerShutdownSignal) _serverShutdownSeen = true;
      _controller.add(signal);
    } catch (error, stackTrace) {
      _controller.addError(error, stackTrace);
    }
  }

  void _onDone(int generation) {
    if (_disposed || generation != _generation) return;
    final closeCode = _channel?.closeCode;
    _channel = null;
    _subscription = null;
    if (_manualDisconnect) return;
    _setStatus(null, SignalingConnectionState.disconnected);
    telemetry.recordDisconnected(normal: false);
    if (closeCode == 1008) {
      telemetry.recordAuthRejected();
      _beginTokenRefresh();
    } else {
      _beginReconnect();
    }
  }

  Future<void> _refreshAfterPolicyRejection() async {
    if (_disposed) return;
    final refresh = _refreshToken;
    if (refresh == null) {
      _beginReconnect();
      return;
    }
    try {
      final token = await refresh();
      if (token == null || token.isEmpty) {
        _setStatus(
          StateError('Token refresh failed; login required'),
          SignalingConnectionState.error,
        );
        return;
      }
      _accessToken = token;
      await _open(scheduleOnFailure: true);
    } catch (error) {
      _setStatus(error, SignalingConnectionState.error);
    }
  }

  void _beginTokenRefresh() {
    if (_disposed || _refreshTask != null) return;
    late final Future<void> task;
    task = _refreshAfterPolicyRejection().whenComplete(() {
      if (identical(_refreshTask, task)) _refreshTask = null;
    });
    _refreshTask = task;
  }

  void _beginReconnect() {
    if (_reconnectTask != null ||
        _disposed ||
        _manualDisconnect ||
        !_networkAvailable) {
      return;
    }
    late final Future<void> task;
    task = _reconnectLoop().whenComplete(() {
      if (identical(_reconnectTask, task)) _reconnectTask = null;
    });
    _reconnectTask = task;
  }

  Future<void> _reconnectLoop() async {
    var delay = initialReconnectDelay;
    if (_serverShutdownSeen) {
      if (!await _waitForReconnect(serverShutdownDelay)) return;
      _serverShutdownSeen = false;
    }
    while (!_disposed &&
        !_manualDisconnect &&
        _networkAvailable &&
        !_status.isConnected) {
      final jitter = Duration(
        milliseconds: (delay.inMilliseconds * 0.2 * _random.nextDouble())
            .round(),
      );
      if (!await _waitForReconnect(delay + jitter)) return;
      if (_disposed ||
          _manualDisconnect ||
          !_networkAvailable ||
          _status.isConnected) {
        return;
      }
      telemetry.recordReconnectAttempt();
      await _open(scheduleOnFailure: false);
      delay = Duration(
        milliseconds: min(
          maximumReconnectDelay.inMilliseconds,
          delay.inMilliseconds * 2,
        ),
      );
    }
  }

  @override
  Future<bool> ensureConnected({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (_disposed) return false;
    if (_status.isConnected) return true;
    if (_status.state != SignalingConnectionState.connecting) {
      await _open(scheduleOnFailure: true);
    }
    if (_status.isConnected) return true;
    try {
      await statuses
          .firstWhere((status) => status.isConnected)
          .timeout(timeout);
      return true;
    } on TimeoutException {
      return false;
    }
  }

  @override
  Future<bool> send(SignalMessage message) async {
    if (_disposed) return false;
    final channel = _channel;
    if (channel == null || !_status.isConnected) return false;
    try {
      channel.sink.add(message.encode());
      return true;
    } catch (error) {
      _setStatus(error, SignalingConnectionState.error);
      telemetry.recordFailure(error);
      return false;
    }
  }

  @override
  Future<void> retryConnection() async {
    _ensureUsable();
    if (!_networkAvailable || _userId == null || _url == null) return;
    _cancelReconnectDelay();
    await _closeSocket();
    await _waitForReconnectLoopToStop();
    _manualDisconnect = false;
    await _open(scheduleOnFailure: true);
  }

  @override
  Future<void> onNetworkChanged({required bool isAvailable}) async {
    if (_disposed) return;
    _networkAvailable = isAvailable;
    if (!isAvailable) {
      final wasActive = _channel != null || _status.isConnected;
      _cancelReconnectDelay();
      await _closeSocket();
      await _waitForReconnectLoopToStop();
      if (!_manualDisconnect) {
        _setStatus(null, SignalingConnectionState.disconnected);
      }
      if (wasActive) telemetry.recordDisconnected(normal: false);
      return;
    }
    if (_manualDisconnect || _userId == null || _url == null) return;
    await retryConnection();
  }

  @override
  Future<void> disconnect() async {
    if (_disposed) return;
    final wasActive =
        _channel != null ||
        _status.state != SignalingConnectionState.disconnected;
    _manualDisconnect = true;
    _userId = null;
    _accessToken = null;
    _tokenProvider = null;
    _refreshToken = null;
    _cancelReconnectDelay();
    await _closeSocket();
    await _waitForReconnectLoopToStop();
    _setStatus(null, SignalingConnectionState.disconnected);
    if (wasActive) telemetry.recordDisconnected(normal: true);
  }

  @override
  Future<void> dispose() {
    final active = _disposeTask;
    if (active != null) return active;
    _disposed = true;
    _manualDisconnect = true;
    _userId = null;
    _accessToken = null;
    _tokenProvider = null;
    _refreshToken = null;
    final operation = _dispose();
    _disposeTask = operation;
    return operation;
  }

  Future<void> _dispose() async {
    _cancelReconnectDelay();
    await _closeSocket();
    await _waitForReconnectLoopToStop();
    await _refreshTask;
    await _controller.close();
    await _statusController.close();
    await telemetry.dispose();
  }

  Future<bool> _waitForReconnect(Duration delay) {
    if (_disposed || _manualDisconnect || !_networkAvailable) {
      return Future.value(false);
    }
    final completer = Completer<bool>();
    _reconnectDelay = completer;
    _reconnectDelayTimer = Timer(delay, () {
      if (!completer.isCompleted) completer.complete(true);
      if (identical(_reconnectDelay, completer)) {
        _reconnectDelay = null;
        _reconnectDelayTimer = null;
      }
    });
    return completer.future;
  }

  void _cancelReconnectDelay() {
    _reconnectDelayTimer?.cancel();
    _reconnectDelayTimer = null;
    final completer = _reconnectDelay;
    _reconnectDelay = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete(false);
    }
  }

  Future<void> _waitForReconnectLoopToStop() async {
    final active = _reconnectTask;
    if (active != null) await active;
  }

  Future<void> _closeSocket({bool invalidate = true}) async {
    if (invalidate) _generation++;
    final subscription = _subscription;
    final channel = _channel;
    _subscription = null;
    _channel = null;
    await subscription?.cancel();
    await channel?.sink.close(1000, 'Client disconnect');
  }

  void _setStatus(Object? error, SignalingConnectionState state) {
    _status = SignalingStatus(state, error: error);
    if (!_statusController.isClosed) _statusController.add(_status);
  }

  void _ensureUsable() {
    if (_disposed) throw StateError('Signaling service is disposed');
  }

  String _joinPath(String base, String child) {
    final clean = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    if (clean.endsWith('/$child')) return clean;
    return '$clean/$child';
  }
}
