import 'dart:convert';
import 'dart:io';

import 'package:flutter_securechat/src/auth/auth_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const userId = 'a93815cc-e5f1-4a2a-a369-6c127b599510';
  const success = <String, Object?>{
    'userId': userId,
    'isNew': true,
    'accessToken': 'access',
    'refreshToken': 'refresh',
  };

  test(
    'registration requires a nonempty OTP grant before any request',
    () async {
      final fixture = await _serve(success);
      await expectLater(
        fixture.api.register(userId: userId, registrationToken: '  '),
        throwsA(isA<AuthApiException>()),
      );
      expect(fixture.requests, isEmpty);
    },
  );

  test(
    'create-only request contains no email or phone lookup identifier',
    () async {
      final fixture = await _serve(success);
      final result = await fixture.api.register(
        userId: userId,
        registrationToken: 'verified-grant',
      );
      expect(result.userId, userId);
      expect(result.isNew, isTrue);
      expect(fixture.paths, ['/api/v1/users/register']);
      expect(fixture.requests.single, {
        'userId': userId,
        'registrationToken': 'verified-grant',
      });
    },
  );

  for (final response in [
    {...success, 'userId': 'another-user'},
    {...success}..remove('userId'),
    {...success}..remove('isNew'),
    {...success, 'isNew': 'true'},
    {...success, 'accessToken': 123},
    {...success, 'refreshToken': ' '},
  ]) {
    test('rejects ambiguous registration response $response', () async {
      final fixture = await _serve(response);
      await expectLater(
        fixture.api.register(userId: userId, registrationToken: 'grant'),
        throwsA(
          isA<AuthApiException>().having(
            (error) => error.kind,
            'kind',
            AuthApiFailureKind.invalidResponse,
          ),
        ),
      );
    });
  }

  test('legacy existing-account response is never accepted as login', () async {
    final fixture = await _serve({...success, 'isNew': false});
    await expectLater(
      fixture.api.register(userId: userId, registrationToken: 'grant'),
      throwsA(isA<ExistingAccountLoginRequired>()),
    );
  });

  test('documented registration conflict requires separate login', () async {
    final fixture = await _serve({
      'error': 'directory_identity_already_registered',
    }, status: 409);
    await expectLater(
      fixture.api.register(userId: userId, registrationToken: 'grant'),
      throwsA(isA<ExistingAccountLoginRequired>()),
    );
    expect(fixture.paths, ['/api/v1/users/register']);
  });

  for (final response in [
    {'verified': true},
    {'verified': false, 'registrationToken': 'grant'},
    {'verified': true, 'registrationToken': 123},
    {'verified': true, 'registrationToken': ' '},
  ]) {
    test('OTP must return a verified nonempty grant: $response', () async {
      final fixture = await _serve(response);
      await expectLater(
        fixture.api.verifyOtp('user@example.com', '123456'),
        throwsA(
          isA<AuthApiException>().having(
            (error) => error.kind,
            'kind',
            AuthApiFailureKind.invalidResponse,
          ),
        ),
      );
      expect(fixture.paths, ['/api/v1/otp/verify']);
    });
  }

  for (final status in [401, 403, 429, 503]) {
    test('HTTP $status cannot yield credentials', () async {
      final fixture = await _serve(success, status: status);
      await expectLater(
        fixture.api.register(userId: userId, registrationToken: 'grant'),
        throwsA(
          isA<AuthApiException>().having(
            (error) => error.statusCode,
            'statusCode',
            status,
          ),
        ),
      );
    });
  }
}

Future<_Fixture> _serve(Map<String, Object?> body, {int status = 200}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final client = HttpClient();
  addTearDown(() async {
    client.close(force: true);
    await server.close(force: true);
  });
  final fixture = _Fixture(
    AuthApi(
      baseUrl: 'http://${server.address.address}:${server.port}',
      client: client,
    ),
  );
  server.listen((request) async {
    fixture.paths.add(request.uri.path);
    fixture.requests.add(jsonDecode(await utf8.decoder.bind(request).join()));
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await request.response.close();
  });
  return fixture;
}

class _Fixture {
  _Fixture(this.api);
  final AuthApi api;
  final paths = <String>[];
  final requests = <Object?>[];
}
