import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_securechat/src/network/socket_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('telemetry records only counters and redacted failure metadata', () {
    final telemetry = WebSocketTelemetry();
    telemetry.recordConnected();
    telemetry.recordDisconnected(normal: false);
    telemetry.recordReconnectAttempt();
    telemetry.recordAuthRejected();
    telemetry.recordFailure(
      Exception('access-secret user-42 private-message'),
      httpStatus: 502,
    );

    final snapshot = telemetry.current;
    expect(snapshot.connects, 1);
    expect(snapshot.disconnects, 1);
    expect(snapshot.reconnectAttempts, 1);
    expect(snapshot.authRejections, 1);
    expect(snapshot.failures, 1);
    expect(snapshot.lastFailure?.httpStatus, 502);
    final exported = jsonEncode(snapshot.toRedactedJson());
    expect(exported, isNot(contains('access-secret')));
    expect(exported, isNot(contains('user-42')));
    expect(exported, isNot(contains('private-message')));
  });

  test('failure classifier separates auth, TLS, timeout and refusal', () {
    expect(
      classifySocketFailure(Exception(), httpStatus: 401),
      SocketFailureCategory.authentication,
    );
    expect(
      classifySocketFailure(const HandshakeException('certificate detail')),
      SocketFailureCategory.tls,
    );
    expect(
      classifySocketFailure(TimeoutException('private endpoint')),
      SocketFailureCategory.timeout,
    );
    expect(
      classifySocketFailure(
        const SocketException('refused', osError: OSError('refused', 111)),
      ),
      SocketFailureCategory.refused,
    );
  });

  test(
    'compatibility probe checks configured health and authenticated ws only',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final requests = <String>[];
      server.listen((request) async {
        requests.add(request.uri.path);
        if (request.uri.path == '/health') {
          request.response.statusCode = 204;
          request.response.write('private-health-body');
          await request.response.close();
          return;
        }
        if (request.uri.path == '/ws' &&
            request.headers.value(HttpHeaders.authorizationHeader) ==
                'Bearer access-secret') {
          final socket = await WebSocketTransformer.upgrade(request);
          socket.listen((_) {});
          return;
        }
        request.response.statusCode = 404;
        await request.response.close();
      });

      final report = await ServerCompatibilityChecker(httpClient: client).check(
        baseUrl: 'ws://${server.address.address}:${server.port}',
        userId: 'private-user',
        accessToken: 'access-secret',
      );

      expect(report.healthReachable, isTrue);
      expect(report.healthStatus, 204);
      expect(report.webSocketCompatible, isTrue);
      expect(requests, ['/health', '/ws']);
      final exported = jsonEncode(report.toRedactedJson());
      expect(exported, isNot(contains('access-secret')));
      expect(exported, isNot(contains('private-user')));
      expect(exported, isNot(contains('private-health-body')));
      expect(exported, isNot(contains(server.port.toString())));
    },
  );

  test('compatibility probe rejects non-websocket schemes before I/O', () {
    expect(
      () => ServerCompatibilityChecker().check(
        baseUrl: 'https://example.invalid',
        userId: 'user',
        accessToken: 'token',
      ),
      throwsArgumentError,
    );
  });
}
