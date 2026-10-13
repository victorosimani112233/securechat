import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/auth/account_recovery_coordinator.dart';
import 'package:flutter_securechat/src/auth/auth_api.dart';
import 'package:flutter_securechat/src/auth/secure_account_recovery_coordinator.dart';
import 'package:flutter_securechat/src/crypto/vodozemac/olm_pre_key_publisher.dart';
import 'package:flutter_securechat/src/crypto/vodozemac/securechat_crypto_ffi.dart';
import 'package:flutter_securechat/src/crypto/vodozemac/vodozemac_protocol_store.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_test/flutter_test.dart';

const account = '12345678-1234-4234-8234-123456789abc';
const other = '87654321-1234-4234-8234-123456789abc';
const registrationId = 1234;
final challengeId = base64UrlEncode(List.filled(32, 1)).replaceAll('=', '');
final capability = base64UrlEncode(List.filled(32, 2)).replaceAll('=', '');
final nonce = base64UrlEncode(List.filled(32, 3)).replaceAll('=', '');

/// Hesap kurtarma — vodozemac Ed25519 kimligi.
///
/// Kurtarma kimligi cihazin Olm hesabinin Ed25519 imzalama anahtari. Testler
/// GERCEK vodozemac kullanir ve sahte sunucu her imzayi `cryptography`
/// paketinin Ed25519'u ile dogrular — sunucunun JDK Ed25519 dogrulamasiyla
/// ayni standart. Sahte sunucu ayrica gercek sunucunun preserve/replace
/// kurallarini uygular (bkz. `RecoveryAuthService.complete`).
void main() {
  final libraryPath = _resolveHostLibrary();
  if (libraryPath == null) {
    test('hesap kurtarma (atlandi: native kutuphane derlenmemis)', () {
      markTestSkipped(
        'Derlemek icin: cd native/securechat_crypto && cargo build --release',
      );
    }, skip: true);
    return;
  }

  late Directory directory;
  late SecureChatDatabase database;
  late VodozemacProtocolStore store;
  late _RecoveryKeys keys;
  late SessionStore session;
  late InMemorySignalingService signaling;
  late _Api api;
  late SecureAccountRecoveryCoordinator recovery;
  var now = DateTime.utc(2026, 9, 23);
  void coordinator() {
    recovery = SecureAccountRecoveryCoordinator(
      api: api,
      session: session,
      recoveryKeys: keys,
      signaling: signaling,
      signalingUrl: 'ws://test',
      refreshAccessToken: () async => null,
      now: () => now,
    );
  }

  setUp(() async {
    now = DateTime.utc(2026, 9, 23);
    directory = await Directory.systemTemp.createTemp('recovery_flow_');
    final masterKey = List<int>.filled(32, 27);
    database = await SecureChatDatabase.open(
      file: File('${directory.path}/db'),
      crypto: LocalAeadCryptoService(SecretKey(masterKey)),
    );
    store = VodozemacProtocolStore(
      database: database,
      crypto: SecureChatCrypto.open(libraryPath: libraryPath),
      pickleKey: await VodozemacProtocolStore.derivePickleKey(masterKey),
    );
    // Uygulama acilisinda on plan yayincisi hesabi yaratir; kurtarma her
    // zaman mevcut bir Olm hesabiyla calisir.
    await store.withAccount((_) async {});
    keys = _RecoveryKeys(store);
    session = SessionStore();
    signaling = InMemorySignalingService();
    // Varsayilan: sunucu BASKA bir cihazin anahtarini pinlemis (yeni cihaz).
    api = _Api(pinned: _foreignKey());
    coordinator();
  });
  tearDown(() async {
    await signaling.dispose();
    await database.close();
    await directory.delete(recursive: true);
  });

  Future<RecoveryLoginApproval> approval() async => recovery.verifyLogin(
    await recovery.requestLogin('User@Example.com'),
    '123456',
  );

  test(
    'trusted enrollment signs exact purpose nonce account epoch email',
    () async {
      session.login(
        userId: account,
        displayName: 'A',
        phoneNumber: '',
        accessToken: 'trusted',
        refreshToken: 'refresh',
      );
      expect(await recovery.getEnrollmentStatus(), isFalse);
      final challenge = await recovery.requestEnrollment(' User@Example.com ');
      await recovery.verifyEnrollment(challenge, '123456');
      final request = api.calls.last;
      expect(request.$1, endsWith('/recovery-email/verify'));
      expect(request.$3, 'trusted');
      final preimage = [
        'securechat/recovery-enroll/v1',
        challengeId,
        nonce,
        account,
        'epoch',
        'user@example.com',
        'olm',
      ].join('\n');
      expect(
        await _verify(
          (await store.recoverySigningPublicKey())!,
          preimage,
          request.$2['signature'] as String,
        ),
        isTrue,
      );
    },
  );

  test('enrollment refuses a server that is not on the Olm protocol', () async {
    session.login(
      userId: account,
      displayName: 'A',
      phoneNumber: '',
      accessToken: 'trusted',
      refreshToken: 'refresh',
    );
    api.enrollmentProtocol = 'v1';
    await expectLater(
      recovery.requestEnrollment('user@example.com'),
      throwsA(isA<AuthApiException>()),
    );
  });

  // QA 2026-10-13 T10: cikis Olm hesabini siler; uygulama yeniden
  // baslamadan kurtarma "recovery_trusted_device_required" ile dusuyordu.
  test('recovery right after logout creates the device identity', () async {
    await database.clearCryptoProtocolState();
    expect(await store.hasAccount(), isFalse);

    final grant = await approval();
    expect(grant.requiresIdentityReplacement, isTrue);
    await recovery.completeLogin(grant, acceptIdentityReplacement: true);

    expect(session.isLoggedIn, isTrue);
    expect(await store.hasAccount(), isTrue);
    final sent = api.completions.single;
    expect(sent['mode'], 'replace');
    expect(sent['identityPublicKey'], await store.recoverySigningPublicKey());
    expect(keys.republishes, 1);
  });

  test(
    'fresh device requires explicit identity approval and preserves UUID',
    () async {
      final grant = await approval();
      expect(grant.requiresIdentityReplacement, isTrue);
      await expectLater(
        recovery.completeLogin(grant, acceptIdentityReplacement: false),
        throwsA(isA<AuthApiException>()),
      );
      expect(await recovery.hasPendingLogin(), isFalse);
      await recovery.completeLogin(grant, acceptIdentityReplacement: true);
      expect(session.userId, account);
      expect(session.isLoggedIn, isTrue);
      expect(session.sharePhoneNumber, isFalse);
      expect(await recovery.hasPendingLogin(), isFalse);
      expect(signaling.currentStatus.isConnected, isTrue);
      final sent = api.completions.single;
      expect(sent['mode'], 'replace');
      expect(sent['identityProtocol'], 'olm');
      // Kurtarma kimligi bu cihazin MEVCUT Olm anahtari; ayri kimlik yok.
      expect(sent['identityPublicKey'], await store.recoverySigningPublicKey());
      // Sunucu replace'te Olm kimligini sildi: plain yayin degil, zorunlu
      // yeniden yayin.
      expect(keys.republishes, 1);
      expect(keys.publishes, 0);
    },
  );

  test('same device preserves key and echoes the registration id', () async {
    api.pinned = (await store.recoverySigningPublicKey())!;
    session.userId = account;
    final grant = await approval();
    expect(grant.requiresIdentityReplacement, isFalse);
    await recovery.completeLogin(grant, acceptIdentityReplacement: false);
    final sent = api.completions.single;
    expect(sent['mode'], 'preserve');
    expect(sent['registrationId'], registrationId);
    expect(keys.publishes, 1);
    expect(keys.republishes, 0);
  });

  test(
    'recovery claims local data for the account before the session logs in',
    () async {
      final claims = <(String, bool)>[];
      recovery = SecureAccountRecoveryCoordinator(
        api: api,
        session: session,
        recoveryKeys: keys,
        signaling: signaling,
        signalingUrl: 'ws://test',
        refreshAccessToken: () async => null,
        now: () => now,
        claimLocalData: (userId) async =>
            claims.add((userId, session.isLoggedIn)),
      );
      api.pinned = (await store.recoverySigningPublicKey())!;
      await recovery.completeLogin(
        await approval(),
        acceptIdentityReplacement: false,
      );
      // Onceki hesabin verisi oturum acilmadan ONCE temizlenmeli.
      expect(claims, [(account, false)]);
      expect(session.userId, account);
      expect(session.isLoggedIn, isTrue);
    },
  );

  test('server key in another encoding is rejected, not silently adopted', () async {
    // Sunucu daima kanonik dolgulu base64 doner. Dolgusuz bir deger ayni
    // anahtar olsa bile reddedilmeli; aksi halde istemci karsilastirmasi
    // ile sunucunun `b64(key) == request` kontrolu birbirinden ayrisir.
    api.pinned = (await store.recoverySigningPublicKey())!.replaceAll('=', '');
    await expectLater(approval(), throwsA(isA<AuthApiException>()));
  });

  test(
    'lost completion response retries exact saved signature and key',
    () async {
      api.loseResponse = true;
      await expectLater(
        recovery.completeLogin(
          await approval(),
          acceptIdentityReplacement: true,
        ),
        throwsA(isA<AuthApiException>()),
      );
      expect(session.isLoggedIn, isFalse);
      expect(await recovery.hasPendingLogin(), isTrue);
      final first = jsonEncode(api.calls.last.$2);
      coordinator();
      expect(await recovery.resumePendingLogin(), isTrue);
      final requests = api.calls
          .where((call) => call.$1.endsWith('/complete'))
          .toList();
      expect(requests, hasLength(2));
      expect(jsonEncode(requests.last.$2), first);
      expect(session.userId, account);
    },
  );

  test(
    'failed key publish does not undo a recovery the server already accepted',
    () async {
      keys.failPublish = true;
      await recovery.completeLogin(
        await approval(),
        acceptIdentityReplacement: true,
      );
      // Sunucu kimlik bilgilerini donderdi; bu cihaz artik yetkili. Yayin
      // hatasi yeni bir OTP gerektirmez, bakim dongusu tekrar dener.
      expect(session.isLoggedIn, isTrue);
      expect(session.userId, account);
      expect(await recovery.hasPendingLogin(), isFalse);
      expect(keys.republishes, 1);
      expect(api.completions, hasLength(1));
    },
  );

  test(
    'restored foreign account blocks before completion or key publish',
    () async {
      session.userId = other;
      await expectLater(approval(), throwsA(isA<AuthApiException>()));
      expect(api.completions, isEmpty);
      expect(keys.publishes + keys.republishes, 0);
      expect(session.userId, other);
    },
  );

  test(
    'identity change between approval and resume fails closed',
    () async {
      api.loseResponse = true;
      await expectLater(
        recovery.completeLogin(
          await approval(),
          acceptIdentityReplacement: true,
        ),
        throwsA(isA<AuthApiException>()),
      );
      // Hesap arada yeniden yaratildi: kanittaki anahtar artik bu cihazin
      // degil. Yanlis kimligi oturuma baglamak yerine durmali.
      await database.vodozemacAccount.delete();
      await store.withAccount((_) async {});
      coordinator();
      await expectLater(
        recovery.resumePendingLogin(),
        throwsA(isA<AuthApiException>()),
      );
      expect(session.isLoggedIn, isFalse);
    },
  );

  test(
    'expired confirmed completion restarts and the next approval preserves',
    () async {
      api.loseResponseAfterCommit = true;
      await expectLater(
        recovery.completeLogin(
          await approval(),
          acceptIdentityReplacement: true,
        ),
        throwsA(isA<AuthApiException>()),
      );
      await recovery.restartPendingLogin();
      expect(await recovery.hasPendingLogin(), isFalse);
      expect(session.isLoggedIn, isFalse);
      // Sunucu replace'i uyguladi ve bu cihazin anahtarini pinledi: yeni bir
      // deneme artik ayni cihaz sayilir.
      expect((await approval()).requiresIdentityReplacement, isFalse);
    },
  );

  test('libsignal-era pending record cannot resume and is restartable', () async {
    await keys.writePendingRecovery(
      jsonEncode({'schema': 1, 'userId': account, 'request': {}}),
    );
    await expectLater(
      recovery.resumePendingLogin(),
      throwsA(isA<AuthApiException>()),
    );
    await recovery.restartPendingLogin();
    expect(await recovery.hasPendingLogin(), isFalse);
  });

  test('expiry and malformed server fields fail closed', () async {
    final grant = await approval();
    now = now.add(const Duration(minutes: 6));
    await expectLater(
      recovery.completeLogin(grant, acceptIdentityReplacement: true),
      throwsA(isA<AuthApiException>()),
    );
    api.malformed = true;
    await expectLater(
      recovery.requestLogin('user@example.com'),
      throwsA(isA<AuthApiException>()),
    );
    expect(await recovery.hasPendingLogin(), isFalse);
    expect(session.isLoggedIn, isFalse);
  });

  test(
    'unknown completion can be deliberately restarted without auto retry',
    () async {
      api.loseResponse = true;
      await expectLater(
        recovery.completeLogin(
          await approval(),
          acceptIdentityReplacement: true,
        ),
        throwsA(isA<AuthApiException>()),
      );
      await recovery.restartPendingLogin();
      expect(await recovery.hasPendingLogin(), isFalse);
      expect(session.isLoggedIn, isFalse);
      expect(keys.publishes + keys.republishes, 0);
    },
  );
}

/// Gercek vodozemac store'u uzerinde kurtarma kimligi; yayini sayar.
///
/// Uretimde `OlmPreKeyPublisher` ayni store'a delege eder. Yayinin HTTP
/// tarafi burada olculmuyor (bkz. olm_pre_key_publisher_test); kimlik,
/// imza ve pending kayit gercek.
class _RecoveryKeys implements RecoveryIdentity {
  _RecoveryKeys(this.store);
  final VodozemacProtocolStore store;
  int publishes = 0;
  int republishes = 0;
  bool failPublish = false;

  void _maybeFail() {
    if (failPublish) {
      throw const AuthApiException('unavailable', statusCode: 503);
    }
  }

  @override
  Future<void> publishIfNeeded() async {
    publishes++;
    _maybeFail();
  }

  @override
  Future<void> republishAfterIdentityReset() async {
    republishes++;
    _maybeFail();
  }

  @override
  Future<String?> recoverySigningPublicKey() =>
      store.recoverySigningPublicKey();

  @override
  Future<String> ensureRecoverySigningKey() async {
    await store.withAccount((_) async {});
    return (await store.recoverySigningPublicKey())!;
  }

  @override
  Future<String> signRecoveryProof(String message) =>
      store.signRecoveryProof(message);

  @override
  Future<String?> readPendingRecovery() => store.readPendingRecovery();

  @override
  Future<void> writePendingRecovery(String record) =>
      store.writePendingRecovery(record);

  @override
  Future<void> clearPendingRecovery() => store.clearPendingRecovery();

  @override
  Future<void> clearLocalCryptoState() => store.clearPendingRecovery();
}

/// Sunucunun kurtarma uclari. `RecoveryAuthService` kurallarini taklit eder.
class _Api extends AuthApi {
  _Api({required this.pinned}) : super(baseUrl: 'http://unused');

  /// Sunucunun pinledigi Ed25519 anahtari (kanonik dolgulu base64).
  String pinned;
  String enrollmentProtocol = 'olm';
  final calls = <(String, Map<String, Object?>, String?)>[];
  final completions = <Map<String, Object?>>[];
  bool loseResponse = false;

  /// Sunucu tamamlamayi UYGULAR ama cevap kaybolur.
  bool loseResponseAfterCommit = false;
  bool malformed = false;

  @override
  Future<Map<String, Object?>> recoveryRequest(
    String endpoint,
    Map<String, Object?> body, {
    String? accessToken,
  }) async {
    calls.add((endpoint, Map.of(body), accessToken));
    if (malformed) return {};
    if (endpoint.endsWith('/recovery-email/status')) return {'bound': false};
    if (endpoint.endsWith('/recovery-email/request'))
      return {
        'challengeId': challengeId,
        'nonce': nonce,
        'credentialEpoch': 'epoch',
        'identityProtocol': enrollmentProtocol,
        'expiresIn': 600,
      };
    if (endpoint.endsWith('/recovery-email/verify')) return {'status': 'ok'};
    if (endpoint.endsWith('/login/request'))
      return {'challengeId': challengeId, 'expiresIn': 600};
    if (endpoint.endsWith('/login/verify'))
      return {
        'userId': account,
        'recoveryToken': capability,
        'identityProtocol': 'olm',
        'identityPublicKey': pinned,
        'registrationId': registrationId,
        'expiresIn': 300,
      };
    if (endpoint.endsWith('/login/complete')) {
      completions.add(Map.of(body));
      final key = body['identityPublicKey'] as String;
      // RecoveryAuthService.complete ile ayni kontroller.
      expect(body['identityProtocol'], 'olm');
      final raw = base64Decode(key);
      expect(raw, hasLength(32));
      expect(base64Encode(raw), key, reason: 'kanonik dolgulu base64');
      if (body['mode'] == 'preserve') {
        expect(key, pinned);
        expect(body['registrationId'], registrationId);
      }
      final preimage = [
        'securechat/recovery-complete/v1',
        body['recoveryToken'],
        body['completionId'],
        account,
        body['mode'],
        body['identityProtocol'],
        key,
        '${body['registrationId']}',
      ].join('\n');
      expect(await _verify(key, preimage, body['signature'] as String), isTrue);
      if (loseResponse) {
        loseResponse = false;
        throw const AuthApiException.network();
      }
      // Replace'ten sonra cihaz yeniden yayinlar ve sunucu bu anahtari pinler.
      if (body['mode'] == 'replace') pinned = key;
      if (loseResponseAfterCommit) {
        loseResponseAfterCommit = false;
        throw const AuthApiException.network();
      }
      return {
        'userId': account,
        'token': 'recovered-access',
        'refreshToken': 'recovered-refresh',
        'identityReplaced': body['mode'] == 'replace',
      };
    }
    throw StateError('Unexpected endpoint');
  }
}

Future<bool> _verify(String publicKey, String message, String signature) =>
    Ed25519().verify(
      utf8.encode(message),
      signature: Signature(
        base64Decode(base64.normalize(signature)),
        publicKey: SimplePublicKey(
          base64Decode(base64.normalize(publicKey)),
          type: KeyPairType.ed25519,
        ),
      ),
    );

/// Bu cihaza ait olmayan, gecerli bicimde bir Ed25519 acik anahtari.
String _foreignKey() =>
    base64Encode(Uint8List.fromList(List.generate(32, (i) => 200 - i)));

String? _resolveHostLibrary() {
  for (final candidate in const [
    'native/securechat_crypto/target/release/libsecurechat_crypto.so',
    'native/securechat_crypto/target/debug/libsecurechat_crypto.so',
  ]) {
    if (File(candidate).existsSync()) return File(candidate).absolute.path;
  }
  return null;
}
