import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
    final token = response.json['registrationToken'] as String?;
    if (response.statusCode != 200 ||
        response.json['verified'] != true ||
        token == null ||
        token.isEmpty) {
      throw response.error(fallback: 'Dogrulama kodu gecersiz');
    }
    return token;
  }

  Future<RegisterResult> register({
    required String userId,
    required String phoneHash,
    String? registrationToken,
  }) async {
    final response = await _post('/api/v1/users/register', {
      'userId': userId,
      'phoneHash': phoneHash,
      if (registrationToken != null) 'registrationToken': registrationToken,
    });
    if (response.statusCode != 200) throw response.error();
    final access = response.json['accessToken'] as String? ?? '';
    final refresh = response.json['refreshToken'] as String? ?? '';
    if (access.isEmpty || refresh.isEmpty) {
      throw const AuthApiException('Sunucu token dondurmedi');
    }
    return RegisterResult(
      userId: response.json['userId'] as String? ?? userId,
      isNew: response.json['isNew'] as bool? ?? true,
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

  Future<bool> uploadPreKeys(
    SerializedPreKeyBundle bundle,
    String accessToken,
  ) async {
    final response = await _post(
      '/api/v1/prekeys/upload',
      bundle.toJson(),
      bearerToken: accessToken,
    );
    return response.statusCode == 200;
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
