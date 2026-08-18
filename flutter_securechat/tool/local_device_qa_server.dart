import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _maximumRequestBytes = 2 * 1024 * 1024;

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln(
      'Usage: dart tool/local_device_qa_server.dart CERTIFICATE_PEM KEY_PEM',
    );
    exitCode = 64;
    return;
  }
  final certificate = File(arguments[0]);
  final privateKey = File(arguments[1]);
  if (!certificate.existsSync() || !privateKey.existsSync()) {
    stderr.writeln('Ephemeral QA certificate or key is missing.');
    exitCode = 66;
    return;
  }

  final context = SecurityContext()
    ..useCertificateChain(certificate.path)
    ..usePrivateKey(privateKey.path);
  final server = await HttpServer.bindSecure(
    InternetAddress.loopbackIPv4,
    18444,
    context,
    shared: false,
  );
  stdout.writeln('SecureChat local device QA server: 127.0.0.1:18444');

  final sockets = <WebSocket>{};
  final state = _QaState();
  final signals = <StreamSubscription<ProcessSignal>>[];
  Future<void> close() async {
    for (final socket in sockets.toList(growable: false)) {
      await socket.close(WebSocketStatus.goingAway, 'QA server stopping');
    }
    await server.close(force: true);
    for (final signal in signals) {
      await signal.cancel();
    }
  }

  for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
    late final StreamSubscription<ProcessSignal> subscription;
    subscription = signal.watch().listen((_) async {
      await close();
      exit(0);
    });
    signals.add(subscription);
  }

  await for (final request in server) {
    unawaited(_handle(request, sockets, state));
  }
}

Future<void> _handle(
  HttpRequest request,
  Set<WebSocket> sockets,
  _QaState state,
) async {
  try {
    if (request.uri.path == '/ws' &&
        WebSocketTransformer.isUpgradeRequest(request)) {
      final accessToken = _bearerToken(request);
      final userId = request.uri.queryParameters['userId']?.trim() ?? '';
      if (userId.isEmpty || state.userForAccessToken(accessToken) != userId) {
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
        return;
      }
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      socket.listen(
        (_) {},
        onDone: () => sockets.remove(socket),
        onError: (_) => sockets.remove(socket),
      );
      return;
    }

    if (request.method != 'POST') {
      await _json(request.response, HttpStatus.notFound, const {
        'error': 'QA route not found',
      });
      return;
    }
    final body = await _readJson(request);
    switch (request.uri.path) {
      case '/api/v1/otp/request':
        final email = body['email']?.toString().trim().toLowerCase() ?? '';
        if (email == 'rate-limit@qa.invalid') {
          request.response.headers.set(HttpHeaders.retryAfterHeader, '3');
          await _json(request.response, HttpStatus.tooManyRequests, const {
            'error': 'Local QA rate limit',
            'retryAfter': 3,
          });
          return;
        }
        if (email == 'smtp-disabled@qa.invalid') {
          await _json(request.response, HttpStatus.serviceUnavailable, const {
            'error': 'Local QA SMTP disabled',
          });
          return;
        }
        await _json(request.response, HttpStatus.ok, const {
          'sent': true,
          'message': 'Local QA OTP generated in-memory',
        });
      case '/api/v1/otp/verify':
        if (body['otp']?.toString() != '654321') {
          await _json(request.response, HttpStatus.unauthorized, const {
            'verified': false,
            'error': 'Invalid local QA code',
          });
          return;
        }
        await _json(request.response, HttpStatus.ok, {
          'verified': true,
          'registrationToken': state.issueRegistrationToken(),
        });
      case '/api/v1/users/register':
        final userId = body['userId']?.toString().trim() ?? '';
        final registrationToken =
            body['registrationToken']?.toString().trim() ?? '';
        if (userId.isEmpty ||
            !state.consumeRegistrationToken(registrationToken)) {
          await _json(request.response, HttpStatus.badRequest, const {
            'error': 'Valid userId and registrationToken required',
          });
          return;
        }
        final tokens = state.register(userId);
        await _json(request.response, HttpStatus.ok, {
          'userId': userId,
          'isNew': true,
          'accessToken': tokens.accessToken,
          'refreshToken': tokens.refreshToken,
        });
      case '/api/v1/auth/refresh':
        final tokens = state.rotate(body['refreshToken']?.toString() ?? '');
        if (tokens == null) {
          await _json(request.response, HttpStatus.unauthorized, const {
            'error': 'Refresh token expired or revoked',
          });
          return;
        }
        await _json(request.response, HttpStatus.ok, {
          'accessToken': tokens.accessToken,
          'refreshToken': tokens.refreshToken,
        });
      case '/api/v1/prekeys/upload':
        if (!state.isAccessTokenValid(_bearerToken(request)) ||
            body['oneTimePreKeys'] is! List) {
          await _json(request.response, HttpStatus.unauthorized, const {
            'error': 'Authenticated prekey upload required',
          });
          return;
        }
        await _json(request.response, HttpStatus.ok, const {'success': true});
      case '/api/v1/fcm/register':
      case '/api/v1/fcm/unregister':
        if (!state.isAccessTokenValid(_bearerToken(request))) {
          await _json(request.response, HttpStatus.unauthorized, const {
            'error': 'Authentication required',
          });
          return;
        }
        await _json(request.response, HttpStatus.ok, const {'success': true});
      case '/api/v1/auth/logout':
        final revoked = state.logout(
          accessToken: _bearerToken(request),
          refreshToken: body['refreshToken']?.toString() ?? '',
        );
        if (!revoked) {
          await _json(request.response, HttpStatus.unauthorized, const {
            'error': 'Session already revoked',
          });
          return;
        }
        await _json(request.response, HttpStatus.ok, const {'success': true});
      case '/api/v1/account/delete':
        final accessToken = _bearerToken(request);
        if (!state.deleteAccount(accessToken)) {
          await _json(request.response, HttpStatus.unauthorized, const {
            'error': 'Authentication required',
          });
          return;
        }
        await _json(request.response, HttpStatus.ok, const {'success': true});
      default:
        await _json(request.response, HttpStatus.notFound, const {
          'error': 'QA route not found',
        });
    }
  } catch (_) {
    try {
      await _json(request.response, HttpStatus.badRequest, const {
        'error': 'Malformed QA request',
      });
    } catch (_) {
      try {
        await request.response.close();
      } catch (_) {}
    }
  }
}

String _bearerToken(HttpRequest request) {
  final header =
      request.headers.value(HttpHeaders.authorizationHeader)?.trim() ?? '';
  return header.startsWith('Bearer ') ? header.substring(7).trim() : '';
}

class _QaState {
  int _sequence = 0;
  final Set<String> _registrationTokens = {};
  final Map<String, String> _accessUsers = {};
  final Map<String, String> _refreshUsers = {};

  String issueRegistrationToken() {
    final token = 'local-device-qa-registration-${++_sequence}';
    _registrationTokens.add(token);
    return token;
  }

  bool consumeRegistrationToken(String token) =>
      token.isNotEmpty && _registrationTokens.remove(token);

  ({String accessToken, String refreshToken}) register(String userId) =>
      _issueTokens(userId);

  ({String accessToken, String refreshToken})? rotate(String refreshToken) {
    final userId = _refreshUsers.remove(refreshToken);
    if (userId == null) return null;
    _accessUsers.removeWhere((_, owner) => owner == userId);
    return _issueTokens(userId);
  }

  bool logout({required String accessToken, required String refreshToken}) {
    final accessUser = _accessUsers[accessToken];
    final refreshUser = _refreshUsers[refreshToken];
    if (accessUser == null || accessUser != refreshUser) return false;
    _accessUsers.remove(accessToken);
    _refreshUsers.remove(refreshToken);
    return true;
  }

  bool deleteAccount(String accessToken) {
    final userId = _accessUsers[accessToken];
    if (userId == null) return false;
    _accessUsers.removeWhere((_, owner) => owner == userId);
    _refreshUsers.removeWhere((_, owner) => owner == userId);
    return true;
  }

  bool isAccessTokenValid(String accessToken) =>
      _accessUsers.containsKey(accessToken);

  String? userForAccessToken(String accessToken) => _accessUsers[accessToken];

  ({String accessToken, String refreshToken}) _issueTokens(String userId) {
    final id = ++_sequence;
    final accessToken = 'local-device-qa-access-$id';
    final refreshToken = 'local-device-qa-refresh-$id';
    _accessUsers[accessToken] = userId;
    _refreshUsers[refreshToken] = userId;
    return (accessToken: accessToken, refreshToken: refreshToken);
  }
}

Future<Map<String, Object?>> _readJson(HttpRequest request) async {
  final bytes = <int>[];
  await for (final chunk in request) {
    if (bytes.length + chunk.length > _maximumRequestBytes) {
      throw const FormatException('QA request too large');
    }
    bytes.addAll(chunk);
  }
  if (bytes.isEmpty) return const {};
  final decoded = jsonDecode(utf8.decode(bytes));
  if (decoded is! Map) throw const FormatException('Expected JSON object');
  return decoded.cast<String, Object?>();
}

Future<void> _json(
  HttpResponse response,
  int status,
  Map<String, Object?> body,
) async {
  response.statusCode = status;
  response.headers.contentType = ContentType.json;
  response.write(jsonEncode(body));
  await response.close();
}
