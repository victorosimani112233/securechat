import 'dart:async';
import 'dart:io';

import 'package:web_socket_channel/io.dart';

enum SocketFailureCategory {
  refused,
  timeout,
  dns,
  tls,
  authentication,
  protocol,
  network,
  unknown,
}

class SocketFailureRecord {
  const SocketFailureRecord({
    required this.exceptionType,
    required this.category,
    required this.timestamp,
    this.httpStatus,
  });

  final String exceptionType;
  final SocketFailureCategory category;
  final DateTime timestamp;
  final int? httpStatus;

  Map<String, Object?> toRedactedJson() => {
    'exceptionType': exceptionType,
    'category': category.name,
    'timestamp': timestamp.toUtc().toIso8601String(),
    'httpStatus': httpStatus,
  };
}

class WebSocketTelemetrySnapshot {
  const WebSocketTelemetrySnapshot({
    this.connects = 0,
    this.disconnects = 0,
    this.failures = 0,
    this.reconnectAttempts = 0,
    this.authRejections = 0,
    this.lastFailure,
    this.lastWasNormalClose = false,
  });

  final int connects;
  final int disconnects;
  final int failures;
  final int reconnectAttempts;
  final int authRejections;
  final SocketFailureRecord? lastFailure;
  final bool lastWasNormalClose;

  Map<String, Object?> toRedactedJson() => {
    'connects': connects,
    'disconnects': disconnects,
    'failures': failures,
    'reconnectAttempts': reconnectAttempts,
    'authRejections': authRejections,
    'lastFailure': lastFailure?.toRedactedJson(),
    'lastWasNormalClose': lastWasNormalClose,
  };
}

class WebSocketTelemetry {
  final _states = StreamController<WebSocketTelemetrySnapshot>.broadcast();
  WebSocketTelemetrySnapshot _current = const WebSocketTelemetrySnapshot();

  WebSocketTelemetrySnapshot get current => _current;
  Stream<WebSocketTelemetrySnapshot> get states => _states.stream;

  void recordConnected() => _publish(_copy(connects: _current.connects + 1));

  void recordDisconnected({required bool normal}) => _publish(
    _copy(disconnects: _current.disconnects + 1, lastWasNormalClose: normal),
  );

  void recordFailure(Object error, {int? httpStatus}) {
    _publish(
      _copy(
        failures: _current.failures + 1,
        lastFailure: SocketFailureRecord(
          exceptionType: error.runtimeType.toString(),
          category: classifySocketFailure(error, httpStatus: httpStatus),
          timestamp: DateTime.now(),
          httpStatus: httpStatus,
        ),
      ),
    );
  }

  void recordReconnectAttempt() =>
      _publish(_copy(reconnectAttempts: _current.reconnectAttempts + 1));

  void recordAuthRejected() =>
      _publish(_copy(authRejections: _current.authRejections + 1));

  void reset() => _publish(const WebSocketTelemetrySnapshot());

  WebSocketTelemetrySnapshot _copy({
    int? connects,
    int? disconnects,
    int? failures,
    int? reconnectAttempts,
    int? authRejections,
    SocketFailureRecord? lastFailure,
    bool? lastWasNormalClose,
  }) => WebSocketTelemetrySnapshot(
    connects: connects ?? _current.connects,
    disconnects: disconnects ?? _current.disconnects,
    failures: failures ?? _current.failures,
    reconnectAttempts: reconnectAttempts ?? _current.reconnectAttempts,
    authRejections: authRejections ?? _current.authRejections,
    lastFailure: lastFailure ?? _current.lastFailure,
    lastWasNormalClose: lastWasNormalClose ?? _current.lastWasNormalClose,
  );

  void _publish(WebSocketTelemetrySnapshot next) {
    _current = next;
    if (!_states.isClosed) _states.add(next);
  }

  Future<void> dispose() async {
    if (!_states.isClosed) await _states.close();
  }
}

SocketFailureCategory classifySocketFailure(Object error, {int? httpStatus}) {
  if (httpStatus == 401 || httpStatus == 403) {
    return SocketFailureCategory.authentication;
  }
  if (error is TimeoutException) return SocketFailureCategory.timeout;
  if (error is HandshakeException || error is TlsException) {
    return SocketFailureCategory.tls;
  }
  if (error is SocketException) {
    final code = error.osError?.errorCode;
    if (code == 61 || code == 111) return SocketFailureCategory.refused;
    if (code == 7 || code == 8 || code == 11001) {
      return SocketFailureCategory.dns;
    }
    return SocketFailureCategory.network;
  }
  if (httpStatus != null && httpStatus >= 400) {
    return SocketFailureCategory.protocol;
  }
  return SocketFailureCategory.unknown;
}

class SocketDiagnosticReport {
  const SocketDiagnosticReport({
    required this.scheme,
    required this.healthReachable,
    required this.webSocketCompatible,
    this.healthStatus,
    this.failure,
  });

  final String scheme;
  final bool healthReachable;
  final int? healthStatus;
  final bool webSocketCompatible;
  final SocketFailureRecord? failure;

  Map<String, Object?> toRedactedJson() => {
    'scheme': scheme,
    'healthReachable': healthReachable,
    'healthStatus': healthStatus,
    'webSocketCompatible': webSocketCompatible,
    'failure': failure?.toRedactedJson(),
  };
}

class ServerCompatibilityChecker {
  ServerCompatibilityChecker({HttpClient? httpClient})
    : _httpClient = httpClient ?? HttpClient(),
      _ownsHttpClient = httpClient == null;

  final HttpClient _httpClient;
  final bool _ownsHttpClient;
  bool _disposed = false;

  Future<SocketDiagnosticReport> check({
    required String baseUrl,
    required String userId,
    required String accessToken,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (_disposed) {
      throw StateError('Server compatibility checker is disposed');
    }
    final base = Uri.parse(baseUrl);
    if (!const {'ws', 'wss'}.contains(base.scheme) || base.host.isEmpty) {
      throw ArgumentError.value(baseUrl, 'baseUrl', 'Expected ws:// or wss://');
    }
    final healthUri = base.replace(
      scheme: base.scheme == 'wss' ? 'https' : 'http',
      path: _joinPath(base.path, 'health'),
      query: null,
    );
    int? healthStatus;
    var healthReachable = false;
    try {
      final request = await _httpClient.getUrl(healthUri).timeout(timeout);
      final response = await request.close().timeout(timeout);
      healthStatus = response.statusCode;
      healthReachable = true;
      await response.drain<void>().timeout(timeout);
    } catch (_) {
      // The authenticated WebSocket probe remains authoritative.
    }

    final socketUri = base.replace(
      path: _joinPath(base.path, 'ws'),
      queryParameters: {...base.queryParameters, 'userId': userId},
    );
    try {
      final channel = IOWebSocketChannel.connect(
        socketUri,
        headers: {HttpHeaders.authorizationHeader: 'Bearer $accessToken'},
        connectTimeout: timeout,
        customClient: _httpClient,
      );
      await channel.ready.timeout(timeout);
      await channel.sink.close(1000, 'Compatibility probe complete');
      return SocketDiagnosticReport(
        scheme: base.scheme,
        healthReachable: healthReachable,
        healthStatus: healthStatus,
        webSocketCompatible: true,
      );
    } catch (error) {
      return SocketDiagnosticReport(
        scheme: base.scheme,
        healthReachable: healthReachable,
        healthStatus: healthStatus,
        webSocketCompatible: false,
        failure: SocketFailureRecord(
          exceptionType: error.runtimeType.toString(),
          category: classifySocketFailure(error),
          timestamp: DateTime.now(),
        ),
      );
    }
  }

  static String _joinPath(String base, String child) {
    final clean = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    if (clean.endsWith('/$child')) return clean;
    return '$clean/$child';
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_ownsHttpClient) _httpClient.close(force: true);
  }
}
