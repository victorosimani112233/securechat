import 'dart:convert';
import 'dart:math';

import '../crypto/pre_key_manager.dart';
import '../services/session_store.dart';
import '../services/signaling_service.dart';
import 'account_recovery_coordinator.dart';
import 'auth_api.dart';

class SecureAccountRecoveryCoordinator extends AccountRecoveryCoordinator {
  SecureAccountRecoveryCoordinator({
    required AuthApi api,
    required SessionStore session,
    required PreKeyManager preKeys,
    required SignalingService signaling,
    required String signalingUrl,
    required Future<String?> Function() refreshAccessToken,
    DateTime Function()? now,
  }) : _api = api,
       _session = session,
       _keys = preKeys,
       _signaling = signaling,
       _signalingUrl = signalingUrl,
       _refreshAccessToken = refreshAccessToken,
       _now = now ?? DateTime.now;

  final AuthApi _api;
  final SessionStore _session;
  final PreKeyManager _keys;
  final SignalingService _signaling;
  final String _signalingUrl;
  final Future<String?> Function() _refreshAccessToken;
  final DateTime Function() _now;
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
        if (await _keys.localIdentityPublicKey() == null) {
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
        challenge.identityProtocol != 'v1') {
      throw const AuthApiException('recovery_trusted_device_required');
    }
    _unexpired(challenge.expiresAt);
    final signature = await _keys.signRecoveryProof(
      [
        'securechat/recovery-enroll/v1',
        challenge.id,
        challenge.nonce!,
        challenge.userId!,
        challenge.credentialEpoch!,
        challenge.email,
        'v1',
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
    final sameKey =
        protocol == 'v1' &&
        await _keys.localIdentityPublicKey() == public &&
        await _keys.localRegistrationId() == reg;
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
    final RecoveryKeyMaterial? material;
    final SerializedPreKeyBundle bundle;
    if (approval.requiresIdentityReplacement) {
      material = _keys.createRecoveryKeyMaterial();
      bundle = material.bundle;
    } else {
      material = null;
      if (await _keys.localIdentityPublicKey() != approval.identityPublicKey) {
        throw const AuthApiException('recovery_identity_changed');
      }
      bundle = await _keys.generateAndSerializeInitialBundle();
      if (bundle.registrationId != approval.registrationId) {
        throw const AuthApiException('recovery_identity_changed');
      }
    }
    final mode = material == null ? 'preserve' : 'replace';
    final completionId = base64UrlEncode(
      List.generate(32, (_) => Random.secure().nextInt(256)),
    ).replaceAll('=', '');
    final identity = base64Encode(bundle.identityPublicKey);
    final proof = [
      'securechat/recovery-complete/v1',
      approval.capability,
      completionId,
      approval.userId,
      mode,
      'v1',
      identity,
      '${bundle.registrationId}',
    ].join('\n');
    final signature = material == null
        ? await _keys.signRecoveryProof(proof)
        : material.sign(proof);
    final pending = <String, Object?>{
      'schema': 1,
      'userId': approval.userId,
      'request': {
        'recoveryToken': approval.capability,
        'completionId': completionId,
        'mode': mode,
        'identityProtocol': 'v1',
        'identityPublicKey': identity,
        'registrationId': bundle.registrationId,
        'signature': signature,
      },
      'material': material?.toJson(),
      'bundle': bundle.toJson(),
      'displayName': _session.displayName ?? 'Elçim',
      'phoneNumber': _session.phoneNumber ?? '',
    };
    await _keys.writePendingRecovery(jsonEncode(pending));
    await _resume();
  });

  @override
  Future<bool> hasPendingLogin() async =>
      await _keys.readPendingRecovery() != null;

  @override
  Future<bool> resumePendingLogin() => _exclusive(_resume);

  @override
  Future<void> restartPendingLogin() => _exclusive(() async {
    if (_session.isLoggedIn)
      throw const AuthApiException('recovery_already_logged_in');
    final raw = await _keys.readPendingRecovery();
    if (raw == null) return;
    final pending = _map(jsonDecode(raw));
    // Preserve confirmed private keys before discarding expired credentials.
    // Fresh OTP verification can then prove this same identity, not replace it.
    final credentials = pending['credentials'];
    if (credentials != null) {
      final userId = _uuid(pending, 'userId');
      _checkOwner(userId);
      final materialJson = pending['material'];
      _validateCredentials(_map(credentials), userId, materialJson != null);
      await _bindRecoveredProfile(pending, userId);
      if (materialJson != null) {
        final material = RecoveryKeyMaterial.fromJson(_map(materialJson));
        if (base64Encode(material.bundle.identityPublicKey) !=
            _map(pending['request'])['identityPublicKey']) {
          throw const AuthApiException.invalidResponse();
        }
        await _keys.installRecoveryKeyMaterial(material, raw);
      }
    }
    await _keys.clearPendingRecovery();
  });

  Future<bool> _resume() async {
    var raw = await _keys.readPendingRecovery();
    if (raw == null) return false;
    final pending = _map(jsonDecode(raw));
    if (pending['schema'] != 1) throw const AuthApiException.invalidResponse();
    final userId = _uuid(pending, 'userId');
    _checkOwner(userId);
    final request = _map(pending['request']);
    final materialJson = pending['material'];
    final material = materialJson == null
        ? null
        : RecoveryKeyMaterial.fromJson(_map(materialJson));
    var credentials = pending['credentials'];
    if (credentials == null) {
      credentials = await _api.recoveryRequest(
        '/api/v1/auth/login/complete',
        request,
      );
      _validateCredentials(_map(credentials), userId, material != null);
      pending['credentials'] = credentials;
      raw = jsonEncode(pending);
      // Save the exact result before activating keys/session; retries need not
      // rely on the server receipt after its short lifetime has elapsed.
      await _keys.writePendingRecovery(raw);
    }
    final result = _map(credentials);
    _validateCredentials(result, userId, material != null);
    await _signaling.disconnect();
    await _bindRecoveredProfile(pending, userId);
    if (material != null) {
      if (base64Encode(material.bundle.identityPublicKey) !=
          request['identityPublicKey']) {
        throw const AuthApiException.invalidResponse();
      }
      await _keys.installRecoveryKeyMaterial(material, raw);
    } else if (await _keys.localIdentityPublicKey() !=
        request['identityPublicKey']) {
      throw const AuthApiException('recovery_identity_changed');
    }
    final bundle = await _keys.generateAndSerializeInitialBundle();
    if (base64Encode(bundle.identityPublicKey) !=
        request['identityPublicKey']) {
      throw const AuthApiException('recovery_identity_changed');
    }
    // The completion pins the public identity; this upload only fills its
    // signed/one-time prekeys. A failure remains resumable, not a new account.
    await _api.uploadPreKeys(bundle, _text(result, 'token'));
    final oldSession = _session.toJson();
    try {
      await _session.loginAndPersist(
        userId: userId,
        displayName: pending['displayName'] as String? ?? 'Elçim',
        phoneNumber: pending['phoneNumber'] as String? ?? '',
        accessToken: _text(result, 'token'),
        refreshToken: _text(result, 'refreshToken'),
      );
    } catch (_) {
      _session.loadJson(oldSession);
      rethrow;
    }
    await _keys.clearPendingRecovery();
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
      displayName: pending['displayName'] as String? ?? 'Elçim',
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

  static String _identity(Map<String, Object?> json, String key) {
    final value = _text(json, key);
    try {
      final bytes = base64Decode(value);
      if (bytes.length != 33 ||
          bytes.first != 5 ||
          base64Encode(bytes) != value)
        throw const FormatException();
    } on FormatException {
      throw const AuthApiException.invalidResponse();
    }
    return value;
  }

  static String _protocol(Map<String, Object?> json) {
    final value = _text(json, 'identityProtocol');
    if (value != 'v1' && value != 'v2')
      throw const AuthApiException.invalidResponse();
    return value;
  }
}
