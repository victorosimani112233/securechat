import 'dart:math';

import '../crypto/pre_key_manager.dart';
import '../services/session_store.dart';
import '../services/signaling_service.dart';
import 'auth_api.dart';
import 'phone_privacy.dart';

class AuthCoordinator {
  AuthCoordinator({
    required AuthApi api,
    required SessionStore session,
    required PreKeyManager preKeys,
    required SignalingService signaling,
    required String signalingUrl,
    Random? random,
  }) : _api = api,
       _session = session,
       _preKeys = preKeys,
       _signaling = signaling,
       _signalingUrl = signalingUrl,
       _random = random ?? Random.secure();

  final AuthApi _api;
  final SessionStore _session;
  final PreKeyManager _preKeys;
  final SignalingService _signaling;
  final String _signalingUrl;
  final Random _random;

  Future<OtpRequestResult> requestOtp(String email) =>
      _api.requestOtp(email.trim().toLowerCase());

  Future<String> verifyOtp(String email, String otp) =>
      _api.verifyOtp(email.trim().toLowerCase(), otp.trim());

  Future<void> registerAndLogin({
    required String displayName,
    required String phoneNumber,
    String? registrationToken,
  }) async {
    final normalized = normalizePhoneDigits(phoneNumber);
    final result = await _api.register(
      userId: _uuidV4(),
      phoneHash: await hashPhoneNumber(normalized),
      registrationToken: registrationToken,
    );
    await _session.loginAndPersist(
      userId: result.userId,
      displayName: _sanitizeName(displayName),
      phoneNumber: '+$normalized',
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
    );

    final bundle = await _preKeys.generateAndSerializeInitialBundle();
    await _api.uploadPreKeys(bundle, result.accessToken);
    await _signaling.connect(
      userId: result.userId,
      url: _signalingUrl,
      accessToken: result.accessToken,
      tokenProvider: () async => _session.accessToken,
      refreshToken: refreshAccessToken,
    );
  }

  Future<String?> refreshAccessToken() async {
    final refresh = _session.refreshToken;
    if (refresh == null || refresh.isEmpty) return null;
    final pair = await _api.refresh(refresh);
    await _session.updateTokensAndPersist(
      accessToken: pair.accessToken,
      refreshToken: pair.refreshToken,
    );
    return pair.accessToken;
  }

  Future<void> logout() async {
    final access = _session.accessToken;
    final refresh = _session.refreshToken;
    try {
      if (access != null && refresh != null) {
        await _api.logout(accessToken: access, refreshToken: refresh);
      }
    } catch (_) {
      // Sunucuya ulasilamasa da cihazdaki tokenlar ve socket temizlenmelidir.
    } finally {
      await _signaling.disconnect();
      await _session.clearAndPersist();
    }
  }

  /// Deletes the authenticated server account. Local credentials are not
  /// touched until the server confirms deletion so a network error cannot
  /// strand the user with an ambiguous half-deleted account state.
  Future<void> deleteAccountOnServer() async {
    final access = _session.accessToken;
    if (access == null || access.isEmpty) {
      throw StateError('Hesap silme için geçerli oturum bulunamadı.');
    }
    await _api.deleteAccount(accessToken: access);
  }

  Future<void> clearLocalAuthentication() async {
    await _signaling.disconnect();
    await _session.clearAndPersist();
  }

  String _uuidV4() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  String _sanitizeName(String name) {
    final sanitized = name
        .trim()
        .replaceAll(RegExp(r'''[;'"\\-]'''), '')
        .replaceAll(RegExp(r'\s+'), ' ');
    return sanitized.substring(0, min(50, sanitized.length));
  }
}
