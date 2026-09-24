import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../crypto/pre_key_manager.dart';

enum OtpRequestStatus { sent, smtpDisabled, rateLimited }

class OtpRequestResult {
  const OtpRequestResult(this.status, {this.retryAfter});

  final OtpRequestStatus status;
  final Duration? retryAfter;
}

class RegisterResult {
  const RegisterResult({
    required this.userId,
    required this.isNew,
    required this.accessToken,
    required this.refreshToken,
  });

  final String userId;
  final bool isNew;
  final String accessToken;
  final String refreshToken;
}

class TokenPair {
  const TokenPair({required this.accessToken, required this.refreshToken});

  final String accessToken;
  final String refreshToken;
}

enum AuthApiFailureKind { http, network, invalidResponse }

/// A generic OTP registration grant cannot recover an existing account.
class ExistingAccountLoginRequired implements Exception {
  const ExistingAccountLoginRequired();
}

class AuthApiException implements Exception {
  const AuthApiException(
    this.message, {
    this.statusCode,
    this.kind = AuthApiFailureKind.http,
  });

  const AuthApiException.network()
    : message = 'Network connection failed',
      statusCode = null,
      kind = AuthApiFailureKind.network;

  const AuthApiException.invalidResponse()
    : message = 'Server response is invalid',
      statusCode = null,
      kind = AuthApiFailureKind.invalidResponse;

  final String message;
  final int? statusCode;
  final AuthApiFailureKind kind;

  @override
  String toString() => message;
}

class AuthApi {
  AuthApi({required String baseUrl, HttpClient? client})
    : _base = Uri.parse(baseUrl),
      _client = client ?? HttpClient();

  final Uri _base;
  final HttpClient _client;

  Future<OtpRequestResult> requestOtp(String email) async {
    final response = await _post('/api/v1/otp/request', {'email': email});
    return switch (response.statusCode) {
      200 => const OtpRequestResult(OtpRequestStatus.sent),
      503 => const OtpRequestResult(OtpRequestStatus.smtpDisabled),
      429 => OtpRequestResult(
        OtpRequestStatus.rateLimited,
        retryAfter: Duration(
          seconds:
              int.tryParse(
                response.json['retryAfter']?.toString() ??
                    response.headers.value('retry-after') ??
                    '',
              ) ??
              60,
        ),
      ),
      _ => throw response.error(),
    };
  }

  Future<String> verifyOtp(String email, String otp) async {
    final response = await _post('/api/v1/otp/verify', {
      'email': email,
      'otp': otp,
    });
    if (response.statusCode != 200) {
      throw response.error(fallback: 'Dogrulama kodu gecersiz');
    }
    final token = response.json['registrationToken'];
    if (response.json['verified'] != true ||
        token is! String ||
        token.trim().isEmpty) {
      throw const AuthApiException.invalidResponse();
    }
    return token;
  }

  Future<RegisterResult> register({
    required String userId,
    required String registrationToken,
  }) async {
    if (registrationToken.trim().isEmpty) {
      throw const AuthApiException('OTP verification required');
    }
    final response = await _post('/api/v1/users/register', {
      'userId': userId,
      'registrationToken': registrationToken,
    });
    if (response.statusCode == 409 &&
        response.json['error'] == 'directory_identity_already_registered') {
      throw const ExistingAccountLoginRequired();
    }
    if (response.statusCode != 200) throw response.error();
    if (response.json['isNew'] == false) {
      throw const ExistingAccountLoginRequired();
    }
    final access = response.json['accessToken'];
    final refresh = response.json['refreshToken'];
    if (response.json['userId'] != userId ||
        response.json['isNew'] != true ||
        access is! String ||
        access.trim().isEmpty ||
        refresh is! String ||
        refresh.trim().isEmpty) {
      throw const AuthApiException.invalidResponse();
    }
    return RegisterResult(
      userId: userId,
      isNew: true,
      accessToken: access,
      refreshToken: refresh,
    );
  }

  Future<TokenPair> refresh(String refreshToken) async {
    final response = await _post('/api/v1/auth/refresh', {
      'refreshToken': refreshToken,
    });
    if (response.statusCode != 200) throw response.error();
    return TokenPair(
      accessToken: response.json['accessToken'] as String? ?? '',
      refreshToken: response.json['refreshToken'] as String? ?? '',
    );
  }

  Future<void> logout({
    required String accessToken,
    required String refreshToken,
  }) async {
    final response = await _post('/api/v1/auth/logout', {
      'refreshToken': refreshToken,
    }, bearerToken: accessToken);
    if (response.statusCode != 200 && response.statusCode != 401) {
      throw response.error();
    }
  }

  Future<void> deleteAccount({required String accessToken}) async {
    final response = await _post(
      '/api/v1/account/delete',
      const <String, Object?>{},
      bearerToken: accessToken,
    );
    if (response.statusCode != 200) throw response.error();
  }

  Future<void> uploadPreKeys(
    SerializedPreKeyBundle bundle,
    String accessToken,
  ) async {
    final response = await _post(
      '/api/v1/prekeys/upload',
      bundle.toJson(),
      bearerToken: accessToken,
    );
    if (response.statusCode != 200) throw response.error();
  }

  Future<Map<String, Object?>> recoveryRequest(
    String endpoint,
    Map<String, Object?> body, {
    String? accessToken,
  }) async {
    if (!const {
      '/api/v1/account/recovery-email/status',
      '/api/v1/account/recovery-email/request',
      '/api/v1/account/recovery-email/verify',
      '/api/v1/auth/login/request',
      '/api/v1/auth/login/verify',
      '/api/v1/auth/login/complete',
    }.contains(endpoint)) {
      throw ArgumentError.value(endpoint, 'endpoint');
    }
    final response = await _post(endpoint, body, bearerToken: accessToken);
    if (response.statusCode != 200) throw response.error();
    return response.json;
  }

  Future<_ApiResponse> _post(
    String path,
    Object body, {
    String? bearerToken,
  }) async {
    try {
      final request = await _client
          .postUrl(_base.resolve(path))
          .timeout(const Duration(seconds: 15));
      request.headers.contentType = ContentType.json;
      if (bearerToken != null) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $bearerToken',
        );
      }
      request.write(jsonEncode(body));
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (const bool.fromEnvironment('SECURECHAT_LOCAL_DIAGNOSTICS')) {
        // Internal fixed endpoint only; never print a body, URL, or credential.
        debugPrint('SC-AUTH $path HTTP ${response.statusCode}');
      }
      final raw = await utf8.decoder.bind(response).join();
      Map<String, Object?> json = const {};
      if (raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) {
          throw const AuthApiException.invalidResponse();
        }
        json = decoded.cast<String, Object?>();
      }
      return _ApiResponse(response.statusCode, json, response.headers);
    } on AuthApiException {
      rethrow;
    } on TimeoutException {
      throw const AuthApiException.network();
    } on IOException {
      throw const AuthApiException.network();
    } on FormatException {
      throw const AuthApiException.invalidResponse();
    }
  }
}

class _ApiResponse {
  const _ApiResponse(this.statusCode, this.json, this.headers);

  final int statusCode;
  final Map<String, Object?> json;
  final HttpHeaders headers;

  AuthApiException error({String fallback = 'Sunucu istegi basarisiz'}) {
    return AuthApiException(
      json['error']?.toString() ?? '$fallback (HTTP $statusCode)',
      statusCode: statusCode,
    );
  }
}
