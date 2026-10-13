import 'dart:async';
import 'dart:math';

import '../contacts/contact_discovery_api.dart';
import '../services/session_store.dart';
import '../services/signaling_service.dart';
import 'auth_api.dart';
import 'account_recovery_coordinator.dart';
import 'secure_account_recovery_coordinator.dart';
import '../crypto/vodozemac/olm_pre_key_publisher.dart';
import 'phone_privacy.dart';
import 'session_token_refresher.dart';

/// Giris oncesi yerel verinin yeni hesaba ait olmasini saglar
/// (bkz `LocalDataOwnerGuard.claim`).
typedef LocalDataClaim = Future<void> Function(String userId);

class AuthCoordinator {
  AuthCoordinator({
    required AuthApi api,
    required SessionStore session,
    required RecoveryIdentity olmPreKeys,
    required SignalingService signaling,
    required String signalingUrl,
    ContactDiscoveryApi? privateDirectory,
    Random? random,
    AccountRecoveryCoordinator? recovery,
    LocalDataClaim? claimLocalData,
  }) : _api = api,
       _session = session,
       _olmPreKeys = olmPreKeys,
       _signaling = signaling,
       _signalingUrl = signalingUrl,
       _privateDirectory = privateDirectory,
       _random = random ?? Random.secure(),
       _claimLocalData = claimLocalData {
    this.recovery =
        recovery ??
        SecureAccountRecoveryCoordinator(
          api: api,
          session: session,
          recoveryKeys: olmPreKeys,
          signaling: signaling,
          signalingUrl: signalingUrl,
          refreshAccessToken: refreshAccessToken,
          claimLocalData: claimLocalData,
        );
  }

  final AuthApi _api;
  final SessionStore _session;

  /// Olm acik anahtarlarini yayinlar; hesap kurtarma kimligi de budur.
  ///
  /// Mesajlasmanin kullandigi tek kimlik. libsignal bundle yuklemesi
  /// kaldirildi: kurtarma artik bu hesabin Ed25519 imzalama anahtarini
  /// pinliyor (`users.signing_public_key`).
  final RecoveryIdentity _olmPreKeys;
  final SignalingService _signaling;
  final String _signalingUrl;
  final ContactDiscoveryApi? _privateDirectory;
  final Random _random;
  final LocalDataClaim? _claimLocalData;
  late final AccountRecoveryCoordinator recovery;

  Future<OtpRequestResult> requestOtp(String email) =>
      _api.requestOtp(email.trim().toLowerCase());

  Future<String> verifyOtp(String email, String otp) =>
      _api.verifyOtp(email.trim().toLowerCase(), otp.trim());

  Future<void> registerAndLogin({
    required String displayName,
    required String phoneNumber,
    required String registrationToken,
    bool bindRecoveryEmail = false,
  }) async {
    // A restored profile is still an existing identity even without tokens.
    // A generic registration grant must not replace it with a new UUID.
    if (_session.userId != null ||
        await _olmPreKeys.readPendingRecovery() != null) {
      throw const ExistingAccountLoginRequired();
    }
    final normalized = normalizePhoneDigits(phoneNumber);
    final userId = _uuidV4();
    final result = await _api.register(
      userId: userId,
      registrationToken: registrationToken,
      bindRecoveryEmail: bindRecoveryEmail,
    );
    if (!result.isNew) throw const ExistingAccountLoginRequired();
    if (result.userId != userId) {
      throw const AuthApiException.invalidResponse();
    }

    await _privateDirectory?.checkUsers(
      const [],
      result.accessToken,
      ownPhoneHash: await hashPhoneNumber(normalized),
      ownUserId: result.userId,
    );

    // Directory rejection must not establish a local session. Once it succeeds,
    // retain credentials before fallible key setup so upload errors cannot
    // strand the account that now owns this directory identity.
    // Cihazda baska hesabin verisi kaldiysa yeni hesap onu gormemeli.
    await _claimLocalData?.call(result.userId);
    await _session.loginAndPersist(
      userId: result.userId,
      displayName: _sanitizeName(displayName),
      phoneNumber: '+$normalized',
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
    );
    // Mesajlasmanin ve hesap kurtarmanin kullandigi TEK kimlik. Bu cagri BASARISIZ
    // olursa kayit da basarisiz olmali: Olm anahtari olmayan bir hesaba
    // kimse mesaj gonderemez ve kullanici bunu ancak ilk mesaj
    // gonderilmediginde fark eder.
    await _olmPreKeys.publishIfNeeded();
    await _signaling.connect(
      userId: result.userId,
      url: _signalingUrl,
      accessToken: result.accessToken,
      tokenProvider: () async => _session.accessToken,
      refreshToken: refreshAccessToken,
    );
  }

  final _credentialsExpired = StreamController<void>.broadcast();

  /// Sunucu oturumu kalici olarak reddettiginde yayinlar (QA 2026-10-12
  /// R1). Uygulama kullaniciyi giris ekranina goturur; yerel veri durur.
  Stream<void> get credentialsExpired => _credentialsExpired.stream;

  /// Access token'i yeniler; bkz. [refreshSessionTokens].
  ///
  /// Oturum burada ya da arka plan isolate'inde sona erdiyse `null` doner
  /// ve [credentialsExpired] yayinlanir.
  Future<String?> refreshAccessToken() async {
    final token = await refreshSessionTokens(
      session: _session,
      api: _api,
      deviceKey: _olmPreKeys,
    );
    if (token == null && _session.credentialsExpired) {
      _credentialsExpired.add(null);
    }
    return token;
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
      try {
        await _olmPreKeys.clearLocalCryptoState();
      } finally {
        await _session.clearAndPersist();
      }
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

  /// Suresi dolmus access token'da bir kez yenileyip tekrar dener.
  Future<void> submitAbuseReport(Map<String, Object?> report) async {
    final access = _session.accessToken;
    if (access == null || access.isEmpty) {
      throw StateError('Bildirim için geçerli oturum bulunamadı.');
    }
    try {
      await _api.submitAbuseReport(accessToken: access, report: report);
    } on AuthApiException catch (error) {
      if (error.statusCode != 401) rethrow;
      final refreshed = await refreshAccessToken();
      if (refreshed == null) rethrow;
      await _api.submitAbuseReport(accessToken: refreshed, report: report);
    }
  }

  Future<void> clearLocalAuthentication() async {
    await _signaling.disconnect();
    try {
      await _olmPreKeys.clearLocalCryptoState();
    } finally {
      await _session.clearAndPersist();
    }
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
