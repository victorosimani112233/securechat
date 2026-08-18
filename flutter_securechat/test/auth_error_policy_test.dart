import 'dart:async';
import 'dart:io';

import 'package:flutter_securechat/src/auth/auth_api.dart';
import 'package:flutter_securechat/src/auth/auth_error_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native transport details are classified as connection errors', () {
    final failures = <Object>[
      const SocketException('Connection failed: private endpoint'),
      const HandshakeException('certificate detail'),
      TimeoutException('private endpoint'),
      const AuthApiException.network(),
      const AuthApiException.invalidResponse(),
    ];

    for (final failure in failures) {
      expect(
        classifyAuthError(failure, duringVerification: false),
        AuthErrorPresentation.connection,
      );
    }
  });

  test('HTTP rejections keep request and verification semantics separate', () {
    const failure = AuthApiException('Rejected', statusCode: 401);

    expect(
      classifyAuthError(failure, duringVerification: false),
      AuthErrorPresentation.requestRejected,
    );
    expect(
      classifyAuthError(failure, duringVerification: true),
      AuthErrorPresentation.verificationRejected,
    );
  });
}
