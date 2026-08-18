import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_securechat/src/push/push_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('push wake payload carries no relationship metadata', () {
    final event = PushWakeEvent.fromMap({'type': 'securechat_wake_v2'});
    expect(event.isWakeUp, isTrue);
    expect(event.type, 'securechat_wake_v2');
    expect(PushWakeEvent.fromMap({'type': 'new_message'}).isWakeUp, isFalse);
  });

  test(
    'push coordinator registers, refreshes, wakes socket and unregisters',
    () async {
      final requests = <_Request>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        requests.add(
          _Request(
            request.uri.path,
            request.headers.value(HttpHeaders.authorizationHeader),
            jsonDecode(body) as Map<String, dynamic>,
          ),
        );
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
      });
      final transport = _FakePushTransport('token-1');
      final signaling = InMemorySignalingService();
      signaling.setConnected(false);
      final session = SessionStore(
        userId: 'me',
        accessToken: 'access',
        refreshToken: 'refresh',
      );
      final coordinator = PushCoordinator(
        transport: transport,
        api: PushTokenApi(
          baseUrl: 'http://${server.address.host}:${server.port}',
        ),
        session: session,
        signaling: signaling,
      );
      addTearDown(coordinator.close);

      await coordinator.initialize();
      expect(transport.permissionRequested, isFalse);
      expect(session.pushToken, 'token-1');
      expect(requests.single.path, '/api/v1/fcm/register');
      expect(requests.single.authorization, 'Bearer access');
      expect(requests.single.body, {'userId': 'me', 'fcmToken': 'token-1'});

      expect(await coordinator.requestPermissionAndRegister(), isTrue);
      expect(transport.permissionRequested, isTrue);
      expect(requests, hasLength(2));

      transport.refresh('token-2');
      await _eventually(() => requests.length == 3);
      expect(session.pushToken, 'token-2');

      transport.wake(const PushWakeEvent(type: 'securechat_wake_v2'));
      await _eventually(() => signaling.currentStatus.isConnected);

      expect(await coordinator.unregister(), isTrue);
      expect(transport.deleted, isTrue);
      expect(session.pushToken, isNull);
      expect(requests.last.path, '/api/v1/fcm/unregister');
    },
  );
}

class _FakePushTransport implements PushTransport {
  _FakePushTransport(this.token);

  String? token;
  bool permissionRequested = false;
  bool deleted = false;
  final _tokens = StreamController<String>.broadcast();
  final _messages = StreamController<PushWakeEvent>.broadcast();

  @override
  Stream<PushWakeEvent> get foregroundMessages => _messages.stream;

  @override
  Stream<String> get tokenRefreshes => _tokens.stream;

  @override
  Future<void> deleteToken() async {
    deleted = true;
    token = null;
  }

  @override
  Future<String?> getToken() async => token;

  @override
  Future<bool> requestPermission() async {
    permissionRequested = true;
    return true;
  }

  void refresh(String value) => _tokens.add(value);
  void wake(PushWakeEvent event) => _messages.add(event);
}

class _Request {
  const _Request(this.path, this.authorization, this.body);
  final String path;
  final String? authorization;
  final Map<String, dynamic> body;
}

Future<void> _eventually(bool Function() predicate) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Condition was not satisfied before timeout');
}
