import 'dart:async';
import 'dart:io';

import 'auth_api.dart';

enum AuthErrorPresentation {
  connection,
  requestRejected,
  verificationRejected,
  loginRequired,

  /// Cihazda eski hesap duruyor; once o kaldirilmali.
  deviceHasAccount,
}

/// Converts transport details into a small UI-safe error vocabulary. Native
/// socket, TLS and timeout messages may contain endpoint or platform details
/// and must never be rendered directly in the authentication screen.
AuthErrorPresentation classifyAuthError(
  Object error, {
  required bool duringVerification,
}) {
  if (error is ExistingAccountLoginRequired) {
    return switch (error.reason) {
      ExistingAccountReason.phoneRegistered =>
        AuthErrorPresentation.loginRequired,
      ExistingAccountReason.deviceHasAccount =>
        AuthErrorPresentation.deviceHasAccount,
    };
  }
  if (error is TimeoutException || error is IOException) {
    return AuthErrorPresentation.connection;
  }
  if (error is AuthApiException &&
      (error.kind == AuthApiFailureKind.network ||
          error.kind == AuthApiFailureKind.invalidResponse)) {
    return AuthErrorPresentation.connection;
  }
  return duringVerification
      ? AuthErrorPresentation.verificationRejected
      : AuthErrorPresentation.requestRejected;
}
