import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

sealed class JanusEvent {
  const JanusEvent();
}

class JanusPublisherJoined extends JanusEvent {
  const JanusPublisherJoined(this.feedId, this.displayName);
  final int feedId;
  final String? displayName;
}

class JanusPublisherLeft extends JanusEvent {
  const JanusPublisherLeft(this.feedId);
  final int feedId;
}

class JanusRemoteOffer extends JanusEvent {
  const JanusRemoteOffer(this.feedId, this.sdp);
  final int feedId;
  final String sdp;
}

class JanusRemoteAnswer extends JanusEvent {
  const JanusRemoteAnswer(this.sdp);
  final String sdp;
}

class JanusClient {
  JanusClient({
    this.requestTimeout = const Duration(seconds: 10),
    HttpClient? httpClient,
  }) : _httpClient = httpClient;

  final Duration requestTimeout;
  final HttpClient? _httpClient;
  final _events = StreamController<JanusEvent>.broadcast();
  final _pending = <String, Completer<Map<String, Object?>>>{};
  final _subscriberHandles = <int, int>{};
  final Random _random = Random.secure();
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _keepalive;
  int _sessionId = 0;
  int _publisherHandleId = 0;
  int _roomId = 0;
  bool _connected = false;
  bool _disposed = false;
  Future<void>? _disposeTask;

  Stream<JanusEvent> get events => _events.stream;
  bool get isConnected => _connected;
  int get publisherHandleId => _publisherHandleId;
  int? subscriberHandleId(int feedId) => _subscriberHandles[feedId];

  Future<bool> connect({
    required String url,
    required String accessToken,
  }) async {
    if (_disposed) throw StateError('Janus client is disposed');
    await disconnect();
    try {
      final channel = IOWebSocketChannel.connect(
        Uri.parse(url),
        protocols: const ['janus-protocol'],
        headers: {'Authorization': 'Bearer $accessToken'},
        connectTimeout: requestTimeout,
        pingInterval: const Duration(seconds: 20),
        customClient: _httpClient,
      );
      _channel = channel;
      _subscription = channel.stream.listen(
        _handleMessage,
        onError: _handleSocketError,
        onDone: _handleSocketDone,
      );
      await channel.ready.timeout(requestTimeout);
      _connected = true;
      return true;
    } catch (_) {
      await disconnect();
      return false;
    }
  }

  Future<int> createSession() async {
    final response = await _request({'janus': 'create'});
    _sessionId = _intAt(response, ['data', 'id']);
    if (_sessionId == 0) throw StateError('Janus session id is missing');
    _keepalive = Timer.periodic(const Duration(seconds: 25), (_) {
      if (!_connected || _sessionId == 0) return;
      _send({
        'janus': 'keepalive',
        'session_id': _sessionId,
        'transaction': _transaction(),
      });
    });
    return _sessionId;
  }

  Future<int> attachVideoRoom() async {
    _requireSession();
    final response = await _request({
      'janus': 'attach',
      'session_id': _sessionId,
      'plugin': 'janus.plugin.videoroom',
    });
    _publisherHandleId = _intAt(response, ['data', 'id']);
    if (_publisherHandleId == 0)
      throw StateError('Janus publisher handle is missing');
    return _publisherHandleId;
  }

  Future<List<(int, String?)>> joinAsPublisher({
    required int roomId,
    required String displayName,
  }) async {
    _requirePublisher();
    _roomId = roomId;
    final response = await _pluginRequest(
      handleId: _publisherHandleId,
      body: {
        'request': 'join',
        'room': roomId,
        'ptype': 'publisher',
        'display': displayName,
      },
    );
    final data = _mapAt(response, ['plugindata', 'data']);
    final publishers = data?['publishers'];
    if (publishers is! List) return const [];
    return publishers
        .whereType<Map>()
        .map((raw) {
          final map = raw.cast<Object?, Object?>();
          return ((map['id'] as num?)?.toInt() ?? 0, map['display'] as String?);
        })
        .where((value) => value.$1 != 0)
        .toList(growable: false);
  }

  Future<String> publishSdp(String offerSdp) async {
    _requirePublisher();
    final response = await _pluginRequest(
      handleId: _publisherHandleId,
      body: const {'request': 'configure', 'audio': true, 'video': true},
      jsep: {'type': 'offer', 'sdp': stripPrivateCandidates(offerSdp)},
    );
    final sdp = _mapAt(response, ['jsep'])?['sdp'] as String?;
    if (sdp == null || sdp.isEmpty)
      throw StateError('Janus SDP answer is missing');
    return sdp;
  }

  Future<String> subscribeToFeed(int feedId) async {
    if (_roomId == 0) throw StateError('Janus room is not joined');
    final handleId = await _attachSubscriberHandle();
    _subscriberHandles[feedId] = handleId;
    final response = await _pluginRequest(
      handleId: handleId,
      body: {
        'request': 'join',
        'room': _roomId,
        'ptype': 'subscriber',
        'feed': feedId,
      },
    );
    final sdp = _mapAt(response, ['jsep'])?['sdp'] as String?;
    if (sdp == null || sdp.isEmpty)
      throw StateError('Janus subscriber offer is missing');
    return sdp;
  }

  Future<void> answerSubscription({
    required int feedId,
    required String answerSdp,
  }) async {
    final handleId = _subscriberHandles[feedId];
    if (handleId == null) throw StateError('Subscriber handle is missing');
    await _pluginRequest(
      handleId: handleId,
      body: {'request': 'start', 'room': _roomId},
      jsep: {'type': 'answer', 'sdp': stripPrivateCandidates(answerSdp)},
    );
  }

  bool trickleIce({
    required int handleId,
    required String candidate,
    required String? sdpMid,
    required int sdpMLineIndex,
  }) {
    if (isPrivateCandidate(candidate)) return false;
    return _send({
      'janus': 'trickle',
      'session_id': _sessionId,
      'handle_id': handleId,
      'transaction': _transaction(),
      'candidate': {
        'candidate': candidate,
        if (sdpMid != null) 'sdpMid': sdpMid,
        'sdpMLineIndex': sdpMLineIndex,
      },
    });
  }

  bool trickleIceCompleted(int handleId) => _send({
    'janus': 'trickle',
    'session_id': _sessionId,
    'handle_id': handleId,
    'transaction': _transaction(),
    'candidate': const {'completed': true},
  });

  Future<void> leaveRoom() async {
    if (_sessionId == 0 || _publisherHandleId == 0) return;
    try {
      await _pluginRequest(
        handleId: _publisherHandleId,
        body: const {'request': 'leave'},
      );
    } catch (_) {
      // Disconnect still closes the authenticated Janus session.
    }
  }

  Future<int> _attachSubscriberHandle() async {
    final response = await _request({
      'janus': 'attach',
      'session_id': _sessionId,
      'plugin': 'janus.plugin.videoroom',
    });
    final id = _intAt(response, ['data', 'id']);
    if (id == 0) throw StateError('Janus subscriber handle is missing');
    return id;
  }

  Future<Map<String, Object?>> _pluginRequest({
    required int handleId,
    required Map<String, Object?> body,
    Map<String, Object?>? jsep,
  }) => _request({
    'janus': 'message',
    'session_id': _sessionId,
    'handle_id': handleId,
    'body': body,
    if (jsep != null) 'jsep': jsep,
  });

  Future<Map<String, Object?>> _request(Map<String, Object?> message) async {
    if (!_connected) throw StateError('Janus socket is not connected');
    final transaction = _transaction();
    final completer = Completer<Map<String, Object?>>();
    _pending[transaction] = completer;
    if (!_send({...message, 'transaction': transaction})) {
      _pending.remove(transaction);
      throw StateError('Janus request could not be sent');
    }
    try {
      return await completer.future.timeout(requestTimeout);
    } finally {
      _pending.remove(transaction);
    }
  }

  bool _send(Map<String, Object?> value) {
    final channel = _channel;
    if (channel == null) return false;
    try {
      channel.sink.add(jsonEncode(value));
      return true;
    } catch (_) {
      return false;
    }
  }

  void _handleMessage(dynamic raw) {
    if (raw is! String) return;
    try {
      final json = (jsonDecode(raw) as Map).cast<String, Object?>();
      final kind = json['janus'] as String?;
      final transaction = json['transaction'] as String?;
      if (transaction != null && kind != 'ack') {
        final completer = _pending[transaction];
        if (completer != null && !completer.isCompleted) {
          if (kind == 'error') {
            final reason =
                _mapAt(json, ['error'])?['reason'] ?? 'Unknown Janus error';
            completer.completeError(StateError(reason.toString()));
          } else {
            completer.complete(json);
          }
        }
      }
      if (kind == 'event') _handleEvent(json);
    } catch (_) {
      // Invalid unsolicited frames cannot mutate call state.
    }
  }

  void _handleEvent(Map<String, Object?> json) {
    final data = _mapAt(json, ['plugindata', 'data']);
    final publishers = data?['publishers'];
    if (publishers is List) {
      for (final raw in publishers.whereType<Map>()) {
        final feedId = (raw['id'] as num?)?.toInt();
        if (feedId != null) {
          _events.add(JanusPublisherJoined(feedId, raw['display'] as String?));
        }
      }
    }
    final left = (data?['unpublished'] ?? data?['leaving']) as num?;
    if (left != null) {
      final feedId = left.toInt();
      _subscriberHandles.remove(feedId);
      _events.add(JanusPublisherLeft(feedId));
    }
    final jsep = _mapAt(json, ['jsep']);
    final sdp = jsep?['sdp'] as String?;
    if (sdp == null) return;
    if (jsep?['type'] == 'answer') {
      _events.add(JanusRemoteAnswer(sdp));
    } else if (jsep?['type'] == 'offer') {
      final sender = (json['sender'] as num?)?.toInt();
      final feed = sender == null
          ? null
          : _subscriberHandles.entries
                .where((entry) => entry.value == sender)
                .firstOrNull
                ?.key;
      if (feed != null) _events.add(JanusRemoteOffer(feed, sdp));
    }
  }

  void _handleSocketError(Object error, [StackTrace? stack]) {
    _connected = false;
    for (final request in _pending.values) {
      if (!request.isCompleted) request.completeError(error, stack);
    }
    _pending.clear();
  }

  void _handleSocketDone() {
    _handleSocketError(StateError('Janus socket closed'));
  }

  void _requireSession() {
    if (_sessionId == 0) throw StateError('Janus session is not created');
  }

  void _requirePublisher() {
    _requireSession();
    if (_publisherHandleId == 0) throw StateError('VideoRoom is not attached');
  }

  String _transaction() => List.generate(
    12,
    (_) => 'abcdefghijklmnopqrstuvwxyz0123456789'[_random.nextInt(36)],
  ).join();

  Future<void> disconnect() async {
    _keepalive?.cancel();
    _keepalive = null;
    _connected = false;
    for (final request in _pending.values) {
      if (!request.isCompleted) {
        request.completeError(StateError('Janus client disconnected'));
      }
    }
    _pending.clear();
    _subscriberHandles.clear();
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close(1000, 'Client disconnect');
    _channel = null;
    _sessionId = 0;
    _publisherHandleId = 0;
    _roomId = 0;
  }

  Future<void> dispose() {
    final active = _disposeTask;
    if (active != null) return active;
    _disposed = true;
    final operation = _dispose();
    _disposeTask = operation;
    return operation;
  }

  Future<void> _dispose() async {
    await disconnect();
    await _events.close();
  }

  static String stripPrivateCandidates(String sdp) => sdp
      .split(RegExp(r'\r?\n'))
      .where(
        (line) => !line.startsWith('a=candidate:') || !isPrivateCandidate(line),
      )
      .join('\r\n');

  static bool isPrivateCandidate(String candidate) => RegExp(
    r'\s(?:10\.\d+\.\d+\.\d+|172\.(?:1[6-9]|2\d|3[01])\.\d+\.\d+|192\.168\.\d+\.\d+|169\.254\.\d+\.\d+|fe80:[0-9a-f:]+|[a-f0-9.-]+\.local)\s',
    caseSensitive: false,
  ).hasMatch(candidate);

  static Map<String, Object?>? _mapAt(
    Map<String, Object?> root,
    List<String> path,
  ) {
    Object? value = root;
    for (final part in path) {
      if (value is! Map) return null;
      value = value[part];
    }
    return value is Map ? value.cast<String, Object?>() : null;
  }

  static int _intAt(Map<String, Object?> root, List<String> path) {
    Object? value = root;
    for (final part in path) {
      if (value is! Map) return 0;
      value = value[part];
    }
    return (value as num?)?.toInt() ?? 0;
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
