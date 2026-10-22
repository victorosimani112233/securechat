import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:web_socket_channel/io.dart';

import '../network/pinned_web_socket.dart';
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

  /// Gercek soketin cozulemeyen veya limiti asan cerceve aldiginda yaptigi
  /// gibi akisa hata basar. Aboneler bunu isleyebiliyor mu diye test eder.
  void addIncomingError(Object error, [StackTrace? stackTrace]) {
    _ensureUsable();
    _controller.addError(error, stackTrace ?? StackTrace.current);
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
    PinnedWebSocketConnector? webSocketConnector,
    WebSocketTelemetry? telemetry,
    bool callCapable = true,
    int frameBurst = defaultFrameBurst,
    int framesPerSecond = defaultFramesPerSecond,
  }) : _frameBurst = frameBurst,
       _framesPerSecond = framesPerSecond,
       _frameTokens = frameBurst.toDouble(),
       _random = random ?? Random.secure(),
       _httpClient = httpClient,
       _webSocketConnector = webSocketConnector,
       _callCapable = callCapable,
       telemetry = telemetry ?? WebSocketTelemetry();

  static const callCapabilityHeader = 'X-SecureChat-Call-Capable';
  static const initialReconnectDelay = Duration(seconds: 2);
  static const maximumReconnectDelay = Duration(seconds: 30);
  static const serverShutdownDelay = Duration(seconds: 5);

  final _controller = StreamController<SignalMessage>.broadcast();
  final _statusController = StreamController<SignalingStatus>.broadcast();
  final Random _random;
  final HttpClient? _httpClient;

  /// Pinlenmis WebSocket baglayicisi.
  ///
  /// `IOWebSocketChannel.connect(..., customClient:)` BILEREK kullanilmiyor:
  /// pinleme `HttpClient.connectionFactory` ile yapiliyor ve o yol WebSocket
  /// yukseltmesiyle uyusmuyor — yukseltmeden sonra ham sokete `detachSocket()`
  /// ile el konuluyor ve baglanti sessizce asili kaliyor. Olculdu: ayni
  /// pinlenmis istemciyle HTTPS 200 donerken WebSocket 8 saniyede zaman
  /// asimina dusuyor ve sunucu istegi hic gormuyor.
  final PinnedWebSocketConnector? _webSocketConnector;
  // A headless message drain has no CallManager and must not consume offers.
  final bool _callCapable;
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
  final _fileFrameClock = Stopwatch()..start();
  Future<void> _fileSendTail = Future.value();
  int _lastFileFrameMicros = -50000;

  /// Tum cikan cercevelerin ortak hiz siniri (jeton kovasi).
  ///
  /// Sunucu bir hesabin 20 saniyede 1000 cerceveyi asmasina izin vermez ve
  /// asan baglantiyi kapatir. Grup mesaji her uyeye ayri cerceveyle gider
  /// (grup kaydi, gerekirse gonderici anahtari, mesaj): 255 uyelik grupta
  /// tek mesaj 765 cerceveye cikabilir ve hepsi ayni anda yaziliyordu;
  /// 50'den fazla uyeli gruba yazan kisinin baglantisi kopuyordu. Kova
  /// [defaultFrameBurst] cerceveyi hemen gecirir, sonra saniyede
  /// [defaultFramesPerSecond]; 20 saniyede en cok 950 cerceve eder.
  /// Siralama korunur; gundelik kullanimda bekleme olmaz.
  static const defaultFrameBurst = 150;
  static const defaultFramesPerSecond = 40;
  final int _frameBurst;
  final int _framesPerSecond;
  final _frameClock = Stopwatch()..start();
  double _frameTokens;
  int _frameTokensAtMicros = 0;
  Future<void> _frameTail = Future.value();
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
      final headers = <String, Object>{
        HttpHeaders.authorizationHeader: 'Bearer $token',
        callCapabilityHeader: _callCapable.toString(),
      };
      const pingInterval = Duration(seconds: 20);
      const connectTimeout = Duration(seconds: 8);
      final connector = _webSocketConnector;
      final WebSocketChannel channel;
      if (connector != null) {
        final socket = await connector.connect(
          uri,
          headers: headers,
          timeout: connectTimeout,
        );
        socket.pingInterval = pingInterval;
        channel = IOWebSocketChannel(socket);
      } else {
        channel = IOWebSocketChannel.connect(
          uri,
          headers: headers,
          pingInterval: pingInterval,
          connectTimeout: connectTimeout,
          customClient: _httpClient,
        );
      }
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
    if (message is FileTransferSignal) {
      final generation = _generation;
      final pending = _fileSendTail.then((_) async {
        // Keep bulk media below the shared 50-message/second abuse ceiling,
        // leaving capacity for keys, call signaling and ordinary messages.
        final remaining =
            50000 -
            (_fileFrameClock.elapsedMicroseconds - _lastFileFrameMicros);
        if (remaining > 0) {
          await Future<void>.delayed(Duration(microseconds: remaining));
        }
        if (_disposed || generation != _generation) return false;
        final sent = await _sendPaced(message, generation);
        _lastFileFrameMicros = _fileFrameClock.elapsedMicroseconds;
        return sent;
      });
      _fileSendTail = pending.then<void>((_) {}, onError: (_, _) {});
      return pending;
    }
    return _sendPaced(message, _generation);
  }

  Future<bool> _sendPaced(SignalMessage message, int generation) {
    final pending = _frameTail.then((_) async {
      final wait = _takeFrameToken();
      if (wait > Duration.zero) await Future<void>.delayed(wait);
      if (_disposed || generation != _generation) return false;
      return _sendNow(message);
    });
    _frameTail = pending.then<void>((_) {}, onError: (_, _) {});
    return pending;
  }

  /// Bir jeton harcar; kova bossa jetonun dolmasi icin beklenecek sure.
  Duration _takeFrameToken() {
    final now = _frameClock.elapsedMicroseconds;
    _frameTokens = min(
      _frameBurst.toDouble(),
      _frameTokens + (now - _frameTokensAtMicros) * _framesPerSecond / 1e6,
    );
    _frameTokensAtMicros = now;
    _frameTokens -= 1;
    if (_frameTokens >= 0) return Duration.zero;
    return Duration(
      microseconds: (-_frameTokens * 1e6 / _framesPerSecond).ceil(),
    );
  }

  bool _sendNow(SignalMessage message) {
    if (_disposed) return false;
    final channel = _channel;
    if (channel == null || !_status.isConnected) return false;
    try {
      final encoded = message.encode();
      if (utf8.encode(encoded).length > SignalMessage.maxEncodedBytes) {
        return false;
      }
      channel.sink.add(encoded);
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
