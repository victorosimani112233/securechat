import 'dart:convert';
import 'dart:math';

import '../crypto/vodozemac/olm_pre_key_publisher.dart';
import '../services/session_store.dart';
import '../services/signaling_service.dart';
import 'account_recovery_coordinator.dart';
import 'auth_api.dart';

class SecureAccountRecoveryCoordinator extends AccountRecoveryCoordinator {
  SecureAccountRecoveryCoordinator({
    required AuthApi api,
    required SessionStore session,
    required RecoveryIdentity recoveryKeys,
    required SignalingService signaling,
    required String signalingUrl,
    required Future<String?> Function() refreshAccessToken,
    DateTime Function()? now,
    Future<void> Function(String userId)? claimLocalData,
  }) : _api = api,
       _session = session,
       _recovery = recoveryKeys,
       _signaling = signaling,
       _signalingUrl = signalingUrl,
       _refreshAccessToken = refreshAccessToken,
       _now = now ?? DateTime.now,
       _claimLocalData = claimLocalData;

  final AuthApi _api;
  final SessionStore _session;
  // Kurtarma kimligi vodozemac Ed25519 (mesaj kriptosuyla ayni Olm hesabi);
  // imza, pending kayit ve kurtarma sonrasi Olm yayini buradan.
  final RecoveryIdentity _recovery;
  final SignalingService _signaling;
  final String _signalingUrl;
  final Future<String?> Function() _refreshAccessToken;
  final DateTime Function() _now;
  final Future<void> Function(String userId)? _claimLocalData;
  Future<void> _tail = Future.value();

  Future<T> _exclusive<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }

  String get _access {
    if (!_session.isLoggedIn)
      throw const AuthApiException('recovery_trusted_device_required');
    return _session.accessToken!;
  }

  @override
  Future<bool> getEnrollmentStatus() async {
    final json = await _api.recoveryRequest(
      '/api/v1/account/recovery-email/status',
      {},
      accessToken: _access,
    );
    if (json['bound'] is! bool) throw const AuthApiException.invalidResponse();
    return json['bound'] as bool;
  }

  @override
  Future<RecoveryChallenge> requestEnrollment(String email) =>
      _exclusive(() async {
        final userId = _session.userId;
        final access = _access;
        if (await _recovery.recoverySigningPublicKey() == null) {
          throw const AuthApiException('recovery_trusted_device_required');
        }
        final normalized = _email(email);
        final json = await _api.recoveryRequest(
          '/api/v1/account/recovery-email/request',
          {'email': normalized},
          accessToken: access,
        );
        if (_session.userId != userId || _session.accessToken != access) {
          throw const AuthApiException('recovery_session_changed');
        }
        return RecoveryChallenge(
          id: _opaque(json, 'challengeId'),
          email: normalized,
          userId: userId,
          nonce: _opaque(json, 'nonce'),
          credentialEpoch: _text(json, 'credentialEpoch'),
          identityProtocol: _protocol(json),
          expiresAt: _expiry(json, 600),
        );
      });

  @override
  Future<void> verifyEnrollment(
    RecoveryChallenge challenge,
    String code,
  ) => _exclusive(() async {
    final access = _access;
    if (challenge.userId != _session.userId ||
        challenge.nonce == null ||
        challenge.credentialEpoch == null ||
        challenge.identityProtocol != 'olm') {
      throw const AuthApiException('recovery_trusted_device_required');
    }
    _unexpired(challenge.expiresAt);
    final signature = await _recovery.signRecoveryProof(
      [
        'securechat/recovery-enroll/v1',
        challenge.id,
        challenge.nonce!,
        challenge.userId!,
        challenge.credentialEpoch!,
        challenge.email,
        'olm',
      ].join('\n'),
    );
    final json = await _api.recoveryRequest(
      '/api/v1/account/recovery-email/verify',
      {'challengeId': challenge.id, 'otp': _code(code), 'signature': signature},
      accessToken: access,
    );
    if (json['status'] != 'ok') throw const AuthApiException.invalidResponse();
  });

  @override
  Future<RecoveryChallenge> requestLogin(String email) => _exclusive(() async {
    if (_session.isLoggedIn)
      throw const AuthApiException('recovery_already_logged_in');
    if (await hasPendingLogin())
      throw const AuthApiException('recovery_pending');
    final normalized = _email(email);
    final json = await _api.recoveryRequest('/api/v1/auth/login/request', {
      'email': normalized,
    });
    return RecoveryChallenge(
      id: _opaque(json, 'challengeId'),
      email: normalized,
      expiresAt: _expiry(json, 600),
    );
  });

  @override
  Future<RecoveryLoginApproval> verifyLogin(
    RecoveryChallenge challenge,
    String code,
  ) => _exclusive(() async {
    if (_session.isLoggedIn)
      throw const AuthApiException('recovery_already_logged_in');
    _unexpired(challenge.expiresAt);
    final json = await _api.recoveryRequest('/api/v1/auth/login/verify', {
      'challengeId': challenge.id,
      'otp': _code(code),
    });
    final userId = _uuid(json, 'userId');
    _checkOwner(userId);
    final public = _identity(json, 'identityPublicKey');
    final protocol = _protocol(json);
    final reg = json['registrationId'];
    if (reg is! int || reg < 1 || reg > 16383)
      throw const AuthApiException.invalidResponse();
    // Olm'da cihaza ozel registrationId yok; ayni cihaz = ayni Ed25519
    // anahtari. registrationId sunucudan gelir ve tamamlama istegine aynen
    // geri yazilir.
    final sameKey =
        protocol == 'olm' &&
        await _recovery.recoverySigningPublicKey() == public;
    return RecoveryLoginApproval(
      userId: userId,
      requiresIdentityReplacement: !sameKey,
      capability: _opaque(json, 'recoveryToken'),
      identityPublicKey: public,
      identityProtocol: protocol,
      registrationId: reg,
      expiresAt: _expiry(json, 300),
    );
  });

  @override
  Future<void> completeLogin(
    RecoveryLoginApproval approval, {
    required bool acceptIdentityReplacement,
  }) => _exclusive(() async {
    if (_session.isLoggedIn)
      throw const AuthApiException('recovery_already_logged_in');
    if (await hasPendingLogin())
      throw const AuthApiException('recovery_pending');
    _checkOwner(approval.userId);
    _unexpired(approval.expiresAt);
    if (approval.requiresIdentityReplacement && !acceptIdentityReplacement) {
      throw const AuthApiException('recovery_identity_confirmation_required');
    }
    // Kurtarma kimligi cihazin MEVCUT Olm Ed25519 anahtari; ayri bir kimlik
    // uretilmez. "preserve" = sunucunun pinledigiyle ayni anahtar, "replace"
    // = farkli (yeni cihaz). Iki durumda da kanit bu anahtarla imzalanir ve
    // libsignal bundle/material yoktur. Replace sonrasi sunucu Olm kimligini
    // NULL'a ceker; `_resume` icindeki `publishIfNeeded` yeniden pinler.
    // Cikis Olm hesabini siler; uygulama yeniden baslamadan kurtarma
    // yapilirsa hesap burada uretilir (yeni cihaz gibi, "replace").
    final identity = await _recovery.ensureRecoverySigningKey();
    if (!approval.requiresIdentityReplacement &&
        identity != approval.identityPublicKey) {
      throw const AuthApiException('recovery_identity_changed');
    }
    final mode = approval.requiresIdentityReplacement ? 'replace' : 'preserve';
    final completionId = base64UrlEncode(
      List.generate(32, (_) => Random.secure().nextInt(256)),
    ).replaceAll('=', '');
    final proof = [
      'securechat/recovery-complete/v1',
      approval.capability,
      completionId,
      approval.userId,
      mode,
      'olm',
      identity,
      '${approval.registrationId}',
    ].join('\n');
    final signature = await _recovery.signRecoveryProof(proof);
    final pending = <String, Object?>{
      'schema': 2,
      'userId': approval.userId,
      'request': {
        'recoveryToken': approval.capability,
        'completionId': completionId,
        'mode': mode,
        'identityProtocol': 'olm',
        'identityPublicKey': identity,
        'registrationId': approval.registrationId,
        'signature': signature,
      },
      'displayName': _session.displayName ?? '',
      'phoneNumber': _session.phoneNumber ?? '',
    };
    await _recovery.writePendingRecovery(jsonEncode(pending));
    await _resume();
  });

  @override
  Future<bool> hasPendingLogin() async =>
      await _recovery.readPendingRecovery() != null;

  @override
  Future<bool> resumePendingLogin() => _exclusive(_resume);

  @override
  Future<void> restartPendingLogin() => _exclusive(() async {
    if (_session.isLoggedIn)
      throw const AuthApiException('recovery_already_logged_in');
    final raw = await _recovery.readPendingRecovery();
    if (raw == null) return;
    final pending = _map(jsonDecode(raw));
    // Sunucu tamamlamayi onayladiysa hesap sahipligi bilinir: profili bagla
    // ki sonraki bir kayit bu cihazin kimligini yeni bir hesaba vermesin.
    // Olm kimligi cihazda zaten duruyor, kurulacak ayri materyal yok.
    // Schema 1 (libsignal kimligiyle imzalanmis) kayitlar temiz kirilmadan
    // sonra gecersizdir; yalnizca silinir.
    final credentials = pending['credentials'];
    if (credentials != null && pending['schema'] == 2) {
      final userId = _uuid(pending, 'userId');
      _checkOwner(userId);
      final replaced = _map(pending['request'])['mode'] == 'replace';
      _validateCredentials(_map(credentials), userId, replaced);
      await _bindRecoveredProfile(pending, userId);
    }
    await _recovery.clearPendingRecovery();
  });

  Future<bool> _resume() async {
    var raw = await _recovery.readPendingRecovery();
    if (raw == null) return false;
    final pending = _map(jsonDecode(raw));
    // Schema 1 libsignal kimligiyle imzalanmisti; temiz kirilmadan sonra
    // tamamlanamaz. Kullanici restartPendingLogin ile yeniden baslar.
    if (pending['schema'] != 2) throw const AuthApiException('recovery_expired');
    final userId = _uuid(pending, 'userId');
    _checkOwner(userId);
    final request = _map(pending['request']);
    final replaced = request['mode'] == 'replace';
    var credentials = pending['credentials'];
    if (credentials == null) {
      credentials = await _api.recoveryRequest(
        '/api/v1/auth/login/complete',
        request,
      );
      _validateCredentials(_map(credentials), userId, replaced);
      pending['credentials'] = credentials;
      raw = jsonEncode(pending);
      // Save the exact result before activating keys/session; retries need not
      // rely on the server receipt after its short lifetime has elapsed.
      await _recovery.writePendingRecovery(raw);
    }
    final result = _map(credentials);
    _validateCredentials(result, userId, replaced);
    await _signaling.disconnect();
    await _bindRecoveredProfile(pending, userId);
    // Kanit bu cihazin Ed25519 anahtariyla imzalandi. Arada hesap yeniden
    // yaratildiysa yayinlanacak kimlik sunucunun pinledigi olmaz.
    if (await _recovery.recoverySigningPublicKey() !=
        request['identityPublicKey']) {
      throw const AuthApiException('recovery_identity_changed');
    }
    // Cihazda baska hesabin verisi kaldiysa kurtarilan hesap onu gormemeli.
    // Kimlik bilgileri pending kayitta duruyor; hata yeniden denenebilir.
    await _claimLocalData?.call(userId);
    final oldSession = _session.toJson();
    try {
      await _session.loginAndPersist(
        userId: userId,
        displayName: pending['displayName'] as String? ?? '',
        phoneNumber: pending['phoneNumber'] as String? ?? '',
        accessToken: _text(result, 'token'),
        refreshToken: _text(result, 'refreshToken'),
      );
    } catch (_) {
      _session.loadJson(oldSession);
      rethrow;
    }
    // Olm anahtar yayini oturum KALICI olduktan sonra (yayinci erisim
    // token'ini oturumdan okur). Replace'te sunucu kimligi ve havuzlari
    // sildi: zorunlu yeniden yayin. Preserve'de havuz azalmis olabilir.
    //
    // Hata kurtarmayi GERI ALMAZ: sunucu hesabi kurtardi ve kimlik bilgileri
    // donduruldu, bu cihaz artik yetkili. Yayinci hatayi kendi raporlar.
    // Replace'te fallback isareti yuklemeden ONCE silindigi icin normal bakim
    // dongusundeki publishIfNeeded kimligi + anahtarlari yine yukler; yeni
    // bir OTP gerekmez.
    try {
      if (replaced) {
        await _recovery.republishAfterIdentityReset();
      } else {
        await _recovery.publishIfNeeded();
      }
    } catch (_) {}
    await _recovery.clearPendingRecovery();
    try {
      await _signaling.connect(
        userId: userId,
        url: _signalingUrl,
        accessToken: _session.accessToken!,
        tokenProvider: () async => _session.accessToken,
        refreshToken: _refreshAccessToken,
      );
    } catch (_) {
      // Authentication and prekey provisioning are durable now. A socket
      // outage belongs to the connection-status/reconnect flow, not OTP retry.
    }
    return true;
  }

  void _checkOwner(String userId) {
    if (_session.userId != null && _session.userId != userId) {
      throw const AuthApiException('recovery_account_mismatch');
    }
  }

  Future<void> _bindRecoveredProfile(
    Map<String, Object?> pending,
    String userId,
  ) async {
    if (_session.userId == userId) return;
    // Account ownership is known after the server confirmation, even while
    // prekey upload is pending. Do not let a later registration reuse its keys.
    await _session.restoreProfileAndPersist(
      userId: userId,
      displayName: pending['displayName'] as String? ?? '',
      phoneNumber: pending['phoneNumber'] as String? ?? '',
    );
  }

  void _validateCredentials(
    Map<String, Object?> result,
    String userId,
    bool replaced,
  ) {
    if (_uuid(result, 'userId') != userId ||
        result['identityReplaced'] != replaced) {
      throw const AuthApiException.invalidResponse();
    }
    _text(result, 'token');
    _text(result, 'refreshToken');
  }

  DateTime _expiry(Map<String, Object?> json, int maxSeconds) {
    final seconds = json['expiresIn'];
    if (seconds is! int || seconds < 1 || seconds > maxSeconds)
      throw const AuthApiException.invalidResponse();
    return _now().add(Duration(seconds: seconds));
  }

  void _unexpired(DateTime at) {
    if (!_now().isBefore(at)) throw const AuthApiException('recovery_expired');
  }

  static String _email(String raw) {
    final value = raw.trim().toLowerCase();
    if (value.length > 254 ||
        !RegExp(r'^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$').hasMatch(value)) {
      throw const AuthApiException('recovery_invalid_email');
    }
    return value;
  }

  static String _code(String raw) {
    if (!RegExp(r'^\d{6}$').hasMatch(raw.trim()))
      throw const AuthApiException('recovery_invalid_code');
    return raw.trim();
  }

  static Map<String, Object?> _map(Object? value) {
    if (value is! Map) throw const AuthApiException.invalidResponse();
    return value.cast<String, Object?>();
  }

  static String _text(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! String ||
        value.isEmpty ||
        value.length > 8192 ||
        value.contains('\n'))
      throw const AuthApiException.invalidResponse();
    return value;
  }

  static String _opaque(Map<String, Object?> json, String key) {
    final value = _text(json, key);
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(value))
      throw const AuthApiException.invalidResponse();
    return value;
  }

  static String _uuid(Map<String, Object?> json, String key) {
    final value = _text(json, key);
    if (!RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    ).hasMatch(value))
      throw const AuthApiException.invalidResponse();
    return value;
  }

  /// Ham 32 bayt Ed25519 acik anahtari, KANONIK dolgulu base64.
  ///
  /// Sunucu `b64(key) != request.identityPublicKey` ile kanonik bicimi
  /// sart kosar ve imza preimage'ini istek alanindan kurar; dolgusuz bir
  /// deger sessizce reddedilirdi. Yerel anahtar da ayni bicimde gelir
  /// (`recoverySigningPublicKey`).
  static String _identity(Map<String, Object?> json, String key) {
    final value = _text(json, key);
    try {
      final bytes = base64Decode(value);
      if (bytes.length != 32 || base64Encode(bytes) != value) {
        throw const FormatException();
      }
    } on FormatException {
      throw const AuthApiException.invalidResponse();
    }
    return value;
  }

  static String _protocol(Map<String, Object?> json) {
    final value = _text(json, 'identityProtocol');
    if (value != 'olm') throw const AuthApiException.invalidResponse();
    return value;
  }
}
