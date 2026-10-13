import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/auth/auth_api.dart';
import 'package:flutter_securechat/src/auth/auth_coordinator.dart';
import 'package:flutter_securechat/src/auth/phone_privacy.dart';
import 'package:flutter_securechat/src/contacts/contact_discovery_api.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_securechat/src/crypto/vodozemac/olm_pre_key_publisher.dart';

void main() {
  group('token yenileme dongusu', () {
    // Yenileme basarisiz oldugunda kurtarma YALNIZCA token gercekten
    // degismisse gecerlidir. Degismemis bir token dondurmek, az once
    // reddedileni gecerli gibi sunmak demek: cagiran onunla baglaniyor,
    // sunucu reddediyor, yeniden yenileme isteniyor — geri cekilmesiz
    // sonsuz dongu. Iki cihazda olculdu: saniyede birkac
    // `/api/v1/auth/refresh`, IP basina 30/10dk siniri aninda doluyor ve
    // uygulama bir daha baglanamiyordu.
    test('degismemis token kurtarma sayilmaz, hata yukselir', () async {
      final session = _FakeSession(access: 'bayat', refresh: 'bayat-refresh');
      final api = _FailingRefreshApi();
      final coordinator = AuthCoordinator(
        api: api,
        session: session,
        olmPreKeys: _RecordingOlmKeyPublisher(),
        signaling: InMemorySignalingService(),
        signalingUrl: 'wss://example.invalid',
      );

      await expectLater(coordinator.refreshAccessToken(), throwsA(anything));
    });

    test('diger isolate yenilediyse onun tokeni alinir', () async {
      final session = _FakeSession(
        access: 'bayat',
        refresh: 'bayat-refresh',
        onReload: 'kazananin-tokeni',
      );
      final api = _FailingRefreshApi();
      final coordinator = AuthCoordinator(
        api: api,
        session: session,
        olmPreKeys: _RecordingOlmKeyPublisher(),
        signaling: InMemorySignalingService(),
        signalingUrl: 'wss://example.invalid',
      );

      expect(await coordinator.refreshAccessToken(), 'kazananin-tokeni');
      // Kilidi beklerken sonuc zaten gelmis: token BIR KEZ DAHA
      // dondurulmemeli, yoksa kazananin token'ini biz oldururduk.
      expect(api.refreshCalls, 0);
    });

    test('es zamanli iki yenileme SIRALI kosar', () async {
      // Paralel yenileme, refresh token tek kullanimlik oldugu icin
      // birinin token'ini kalici olarak oldururdu. Siralama gercek depoda
      // yasiyor (dosya kilidi + isolate ici kuyruk), o yuzden sahte degil
      // `PersistentSessionStore` kullaniliyor.
      final directory = await Directory.systemTemp.createTemp('refresh-lock');
      addTearDown(() => directory.delete(recursive: true));
      final session = await PersistentSessionStore.open(
        file: File('${directory.path}/session.securejson'),
        crypto: LocalAeadCryptoService(
          SecretKey(List<int>.generate(32, (index) => index + 11)),
        ),
      );
      addTearDown(session.close);
      session.login(
        userId: 'kullanici',
        displayName: 'Ad',
        phoneNumber: '+900000000000',
        accessToken: 'eski',
        refreshToken: 'eski-refresh',
      );
      await session.updateTokensAndPersist(
        accessToken: 'eski',
        refreshToken: 'eski-refresh',
      );
      final api = _CountingRefreshApi();
      final coordinator = AuthCoordinator(
        api: api,
        session: session,
        olmPreKeys: _RecordingOlmKeyPublisher(),
        signaling: InMemorySignalingService(),
        signalingUrl: 'wss://example.invalid',
      );

      final results = await Future.wait([
        coordinator.refreshAccessToken(),
        coordinator.refreshAccessToken(),
      ]);

      // Ikincisi birincinin sonucunu gormeli, kendi basina yenilememeli.
      expect(api.refreshCalls, 1, reason: 'token iki kez dondurulmus');
      expect(results.first, 'yeni-1');
      expect(results.last, 'yeni-1');
    });
  });

  // QA 2026-10-12 R1: refresh 401 alinca uygulama ayni olu token'la
  // tekrar tekrar deniyor, kullaniciya da bir sey soylemiyordu.
  group('kalici olarak reddedilen oturum', () {
    late Directory directory;
    late File file;
    late LocalAeadCryptoService crypto;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('session-expired');
      file = File('${directory.path}/session.securejson');
      crypto = LocalAeadCryptoService(
        SecretKey(List<int>.generate(32, (index) => index + 21)),
      );
    });
    tearDown(() => directory.delete(recursive: true));

    Future<PersistentSessionStore> openLoggedIn() async {
      final session = await PersistentSessionStore.open(
        file: file,
        crypto: crypto,
      );
      await session.loginAndPersist(
        userId: 'kullanici',
        displayName: 'Ad',
        phoneNumber: '+900000000000',
        accessToken: 'eski',
        refreshToken: 'eski-refresh',
      );
      return session;
    }

    AuthCoordinator coordinatorFor(SessionStore session, AuthApi api) =>
        AuthCoordinator(
          api: api,
          session: session,
          olmPreKeys: _RecordingOlmKeyPublisher(),
          signaling: InMemorySignalingService(),
          signalingUrl: 'wss://example.invalid',
        );

    test('401 tokenlari siler, hesabi birakir ve bir kez bildirir', () async {
      final session = await openLoggedIn();
      addTearDown(session.close);
      final api = _StatusRefreshApi(401);
      final coordinator = coordinatorFor(session, api);
      final expired = <void>[];
      coordinator.credentialsExpired.listen(expired.add);

      expect(await coordinator.refreshAccessToken(), isNull);
      expect(session.isLoggedIn, isFalse);
      expect(session.credentialsExpired, isTrue);
      expect(session.refreshToken, isNull);
      expect(session.userId, 'kullanici');
      expect(session.displayName, 'Ad');

      // Olu token'la sunucu bir daha yorulmaz.
      expect(await coordinator.refreshAccessToken(), isNull);
      expect(api.refreshCalls, 1);
      await Future<void>.delayed(Duration.zero);
      expect(expired, hasLength(2));

      // Yeniden acilista (ya da diger isolate'te) ayni durum gorulur.
      final reopened = await PersistentSessionStore.open(
        file: file,
        crypto: crypto,
      );
      addTearDown(reopened.close);
      expect(reopened.credentialsExpired, isTrue);
      expect(reopened.isLoggedIn, isFalse);
      expect(reopened.userId, 'kullanici');
    });

    // QA 2026-10-13 R3 madde 3: olu refresh token + cihazin Olm anahtari.
    AuthCoordinator coordinatorWithDeviceKey(
      SessionStore session,
      AuthApi api,
      _DeviceKeyPublisher keys,
    ) => AuthCoordinator(
      api: api,
      session: session,
      olmPreKeys: keys,
      signaling: InMemorySignalingService(),
      signalingUrl: 'wss://example.invalid',
    );

    test('401 sonrasi cihaz anahtari oturumu geri getirir', () async {
      final session = await openLoggedIn();
      addTearDown(session.close);
      final api = _DeviceReauthApi.success();
      final keys = _DeviceKeyPublisher();
      final coordinator = coordinatorWithDeviceKey(session, api, keys);

      expect(await coordinator.refreshAccessToken(), 'cihaz-access');

      expect(session.isLoggedIn, isTrue);
      expect(session.credentialsExpired, isFalse);
      expect(session.refreshToken, 'cihaz-refresh');
      expect(api.deviceCalls, 1);
      expect(api.lastUserId, 'kullanici');
      expect(api.lastRefreshToken, 'eski-refresh');
      expect(keys.signed, hasLength(1));
    });

    test('cihaz anahtari da reddedilirse oturum suresi doldu olur', () async {
      final session = await openLoggedIn();
      addTearDown(session.close);
      final api = _DeviceReauthApi.failing(
        const AuthApiException('rejected', statusCode: 401),
      );
      final coordinator = coordinatorWithDeviceKey(
        session,
        api,
        _DeviceKeyPublisher(),
      );

      expect(await coordinator.refreshAccessToken(), isNull);
      expect(session.credentialsExpired, isTrue);
      expect(session.refreshToken, isNull);
      expect(api.deviceCalls, 1);
    });

    test('cihaz yolu olmayan eski sunucuda oturum suresi doldu olur', () async {
      final session = await openLoggedIn();
      addTearDown(session.close);
      final api = _DeviceReauthApi.failing(
        const AuthApiException('not found', statusCode: 404),
      );
      final coordinator = coordinatorWithDeviceKey(
        session,
        api,
        _DeviceKeyPublisher(),
      );

      expect(await coordinator.refreshAccessToken(), isNull);
      expect(session.credentialsExpired, isTrue);
    });

    test('cihaz yolunda gecici hata oturumu korur', () async {
      final session = await openLoggedIn();
      addTearDown(session.close);
      final api = _DeviceReauthApi.failing(const AuthApiException.network());
      final coordinator = coordinatorWithDeviceKey(
        session,
        api,
        _DeviceKeyPublisher(),
      );

      await expectLater(
        coordinator.refreshAccessToken(),
        throwsA(isA<AuthApiException>()),
      );
      expect(session.credentialsExpired, isFalse);
      expect(session.refreshToken, 'eski-refresh');
    });

    test('cihazda kimlik yoksa sunucuya cihaz istegi gitmez', () async {
      final session = await openLoggedIn();
      addTearDown(session.close);
      final api = _DeviceReauthApi.success();
      final coordinator = coordinatorFor(session, api);

      expect(await coordinator.refreshAccessToken(), isNull);
      expect(api.deviceCalls, 0);
      expect(session.credentialsExpired, isTrue);
    });

    for (final failure in [
      const AuthApiException('unavailable', statusCode: 503),
      const AuthApiException.network(),
    ]) {
      test(
        'gecici hata (${failure.statusCode ?? 'ag'}) oturumu korur',
        () async {
          final session = await openLoggedIn();
          addTearDown(session.close);
          final coordinator = coordinatorFor(
            session,
            _StatusRefreshApi.failing(failure),
          );

          await expectLater(
            coordinator.refreshAccessToken(),
            throwsA(isA<AuthApiException>()),
          );
          expect(session.isLoggedIn, isTrue);
          expect(session.credentialsExpired, isFalse);
          expect(session.refreshToken, 'eski-refresh');
        },
      );
    }

    test('yeniden giris isareti kaldirir', () async {
      final session = await openLoggedIn();
      addTearDown(session.close);
      await session.expireCredentialsAndPersist();

      await session.loginAndPersist(
        userId: 'kullanici',
        displayName: 'Ad',
        phoneNumber: '+900000000000',
        accessToken: 'yeni',
        refreshToken: 'yeni-refresh',
      );

      expect(session.credentialsExpired, isFalse);
      expect(session.isLoggedIn, isTrue);
    });

    test('cikis isareti de temizler', () async {
      final session = await openLoggedIn();
      addTearDown(session.close);
      await session.expireCredentialsAndPersist();
      await session.clearAndPersist();
      expect(session.credentialsExpired, isFalse);
      expect(session.userId, isNull);
    });
  });

  test('oturum diskten tazelenince digerinin yazdigi token gorulur', () async {
    // Refresh token TEK KULLANIMLIK: sunucu her yenilemede
    // `rotateRefreshGeneration` cagiriyor. On plan ve arka plan AYRI
    // isolate'ler ve oturumu yalniz acilista bellege aliyorlar, dolayisiyla
    // biri yeniledigi anda digerinin elindeki token oluyor.
    //
    // Cihazda olculen sonuc: yarisi kaybeden taraf kalici 401 aliyor, mesaj
    // gonderemiyor ve WebSocket'e baglanamiyordu. Tazeleme olmadan o
    // durumdan cikis yok, cunku elindeki token bir daha gecerli olmuyor.
    final directory = await Directory.systemTemp.createTemp('session-race');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/session.securejson');
    final crypto = LocalAeadCryptoService(
      SecretKey(List<int>.generate(32, (index) => index + 9)),
    );

    final first = await PersistentSessionStore.open(file: file, crypto: crypto);
    first.login(
      userId: 'kullanici',
      displayName: 'Ad',
      phoneNumber: '+900000000000',
      accessToken: 'ilk-access',
      refreshToken: 'ilk-refresh',
    );
    await first.updateTokensAndPersist(
      accessToken: 'ilk-access',
      refreshToken: 'ilk-refresh',
    );

    // Ikinci isolate ayni dosyayi acar ve yeniler.
    final second = await PersistentSessionStore.open(
      file: file,
      crypto: crypto,
    );
    await second.updateTokensAndPersist(
      accessToken: 'yeni-access',
      refreshToken: 'yeni-refresh',
    );
    await second.close();

    // Birincinin bellegi hala bayat.
    expect(first.accessToken, 'ilk-access');

    await first.reloadFromDisk();

    expect(first.accessToken, 'yeni-access');
    expect(first.refreshToken, 'yeni-refresh');
    await first.close();
  });

  test(
    'phone normalization and local discovery hash match privacy contract',
    () async {
      expect(normalizePhoneDigits('0555 123 45 67'), '905551234567');
      expect(normalizePhoneDigits('+90 555 123 45 67'), '905551234567');
      expect(await hashPhoneNumber('5551234567'), hasLength(64));
    },
  );

  test(
    'OTP registration persists tokens, publishes Olm keys and connects',
    () async {
      final requests = <String, Map<String, Object?>>{};
      final authHeaders = <String, String?>{};
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        final path = request.uri.path;
        final raw = await utf8.decoder.bind(request).join();
        requests[path] = raw.isEmpty
            ? <String, Object?>{}
            : (jsonDecode(raw) as Map).cast<String, Object?>();
        authHeaders[path] = request.headers.value(
          HttpHeaders.authorizationHeader,
        );
        request.response.headers.contentType = ContentType.json;
        switch (path) {
          case '/api/v1/otp/request':
            request.response.write(jsonEncode({'sent': true}));
          case '/api/v1/otp/verify':
            request.response.write(
              jsonEncode({'verified': true, 'registrationToken': 'reg-1'}),
            );
          case '/api/v1/users/register':
            request.response.write(
              jsonEncode({
                'userId': requests[path]!['userId'],
                'isNew': true,
                'accessToken': 'access-1',
                'refreshToken': 'refresh-1',
              }),
            );
          case '/api/v1/auth/refresh':
            request.response.write(
              jsonEncode({
                'accessToken': 'access-2',
                'refreshToken': 'refresh-2',
              }),
            );
          default:
            request.response.statusCode = 404;
            request.response.write(jsonEncode({'error': 'not found'}));
        }
        await request.response.close();
      });

      final fixture = await _openFixture();
      addTearDown(fixture.close);
      final api = AuthApi(
        baseUrl: 'http://${server.address.address}:${server.port}',
      );
      final signaling = InMemorySignalingService();
      final session = SessionStore();
      final directoryApi = _RecordingDirectoryApi();
      final keys = _RecordingOlmKeyPublisher();
      final coordinator = AuthCoordinator(
        api: api,
        session: session,
        olmPreKeys: keys,
        signaling: signaling,
        signalingUrl: 'ws://local',
        privateDirectory: directoryApi,
      );

      expect(
        (await coordinator.requestOtp('User@Example.com')).status,
        OtpRequestStatus.sent,
      );
      final registrationToken = await coordinator.verifyOtp(
        'User@Example.com',
        '123456',
      );
      await coordinator.registerAndLogin(
        displayName: 'Alice Example',
        phoneNumber: '0555 123 45 67',
        registrationToken: registrationToken,
        bindRecoveryEmail: true,
      );

      final registeredId = requests['/api/v1/users/register']!['userId'];
      // Kayit e-postasi kurtarma e-postasi olarak da baglanir (QA R3).
      expect(requests['/api/v1/users/register']?['bindRecoveryEmail'], isTrue);
      expect(session.userId, registeredId);
      expect(session.accessToken, 'access-1');
      expect(signaling.currentStatus.isConnected, isTrue);
      expect(requests['/api/v1/otp/request']?['email'], 'user@example.com');
      expect(requests['/api/v1/users/register']?['registrationToken'], 'reg-1');
      expect(requests['/api/v1/users/register'], isNot(contains('phoneHash')));
      expect(directoryApi.phoneHashes, isEmpty);
      expect(directoryApi.accessToken, 'access-1');
      expect(directoryApi.ownUserId, registeredId);
      expect(directoryApi.ownPhoneHash, await hashPhoneNumber('905551234567'));
      expect(
        requests['/api/v1/users/register'],
        isNot(contains('encryptedPhone')),
      );
      // Mesajlasma ve kurtarma ayni Olm kimligini kullanir; libsignal bundle
      // yuklemesi KALDIRILDI ve o uca hic gidilmemeli.
      expect(keys.calls, 1);
      expect(requests.containsKey('/api/v1/prekeys/upload'), isFalse);

      expect(await coordinator.refreshAccessToken(), 'access-2');
      expect(session.refreshToken, 'refresh-2');

      expect(keys.clears, 0);
      await coordinator.logout();
      expect(session.userId, isNull);
      // Cikis yerel kripto durumunu (Olm hesabi, oturumlar, pinler, devam
      // eden kurtarma) siler; aksi halde sonraki hesap ayni kimligi kullanir.
      expect(keys.clears, 1);
    },
  );

  test(
    'registration claims local data for the new account before login',
    () async {
      final fixture = await _openFixture();
      addTearDown(fixture.close);
      final session = SessionStore();
      final claims = <(String, bool)>[];
      final coordinator = AuthCoordinator(
        api: _RegistrationApi('accepted'),
        session: session,
        olmPreKeys: _RecordingOlmKeyPublisher(),
        signaling: InMemorySignalingService(),
        signalingUrl: 'ws://local',
        privateDirectory: _RecordingDirectoryApi(),
        claimLocalData: (userId) async =>
            claims.add((userId, session.isLoggedIn)),
      );

      await coordinator.registerAndLogin(
        displayName: 'Alice',
        phoneNumber: '+905551234567',
        registrationToken: 'otp-grant',
      );

      // Onceki hesabin verisi oturum acilmadan ONCE temizlenmeli.
      expect(claims, [(session.userId, false)]);
      expect(session.isLoggedIn, isTrue);
    },
  );

  for (final scenario in [
    'restored identity',
    'existing account response',
    'different account response',
    'directory rejection',
  ]) {
    test('$scenario cannot establish or replace a local session', () async {
      final fixture = await _openFixture();
      addTearDown(fixture.close);
      final keys = _RecordingOlmKeyPublisher();
      final session = SessionStore(
        userId: scenario == 'restored identity' ? 'restored-user' : null,
        displayName: 'Existing profile',
        phoneNumber: '+905551234567',
      );
      final sessionBefore = session.toJson();
      final api = _RegistrationApi(scenario);
      final directory = _RecordingDirectoryApi(
        reject: scenario == 'directory rejection',
      );
      final signaling = InMemorySignalingService();
      final claims = <String>[];
      final coordinator = AuthCoordinator(
        api: api,
        session: session,
        olmPreKeys: keys,
        signaling: signaling,
        signalingUrl: 'ws://local',
        privateDirectory: directory,
        claimLocalData: (userId) async => claims.add(userId),
      );
      await expectLater(
        coordinator.registerAndLogin(
          displayName: 'Replacement profile',
          phoneNumber: '+905559876543',
          registrationToken: 'otp-grant',
        ),
        throwsA(
          scenario == 'restored identity' ||
                  scenario == 'existing account response'
              ? isA<ExistingAccountLoginRequired>()
              : isA<AuthApiException>(),
        ),
      );
      expect(session.toJson(), sessionBefore);
      expect(session.isLoggedIn, isFalse);
      expect(signaling.currentStatus.isConnected, isFalse);
      // Reddedilen kayit yerel kimligi ne siler ne de yayinlar.
      expect(keys.clears, 0);
      // Reddedilen kayit yerel veriye de dokunmaz.
      expect(claims, isEmpty);
      if (scenario == 'restored identity') expect(api.registerCalls, 0);
      expect(keys.calls, 0);
      if (scenario.contains('response') || scenario == 'restored identity') {
        expect(directory.accessToken, isNull);
      }
    });
  }

  test(
    'Olm key publish failure retains durable credentials and identity',
    () async {
      final fixture = await _openFixture();
      addTearDown(fixture.close);
      final keys = _RecordingOlmKeyPublisher()..failPublish = true;
      final sessionFile = File('${fixture.directory.path}/session.securejson');
      final storageCrypto = LocalAeadCryptoService(
        SecretKey(List<int>.generate(32, (index) => index + 1)),
      );
      final session = await PersistentSessionStore.open(
        file: sessionFile,
        crypto: storageCrypto,
      );
      addTearDown(session.close);
      final api = _RegistrationApi('accepted');
      final directory = _RecordingDirectoryApi();
      final signaling = InMemorySignalingService();
      final coordinator = AuthCoordinator(
        api: api,
        session: session,
        olmPreKeys: keys,
        signaling: signaling,
        signalingUrl: 'ws://local',
        privateDirectory: directory,
      );

      await expectLater(
        coordinator.registerAndLogin(
          displayName: 'Alice',
          phoneNumber: '+905551234567',
          registrationToken: 'otp-grant',
        ),
        throwsA(isA<AuthApiException>()),
      );
      expect(directory.ownUserId, session.userId);
      expect(keys.calls, 1);
      expect(signaling.currentStatus.isConnected, isFalse);
      expect(keys.clears, 0);

      final reopened = await PersistentSessionStore.open(
        file: sessionFile,
        crypto: storageCrypto,
      );
      addTearDown(reopened.close);
      expect(reopened.userId, directory.ownUserId);
      expect(reopened.accessToken, 'access');
      expect(reopened.refreshToken, 'refresh');
      expect(reopened.isLoggedIn, isTrue);
      expect(reopened.displayName, 'Alice');

      // A retry must not register another UUID or discard the retained identity.
      await expectLater(
        coordinator.registerAndLogin(
          displayName: 'Alice',
          phoneNumber: '+905551234567',
          registrationToken: 'another-grant',
        ),
        throwsA(isA<ExistingAccountLoginRequired>()),
      );
      expect(api.registerCalls, 1);
      expect(keys.clears, 0);
    },
  );
}

class _RegistrationApi extends AuthApi {
  _RegistrationApi(this.scenario) : super(baseUrl: 'http://unused.invalid');

  final String scenario;
  int registerCalls = 0;

  @override
  Future<RegisterResult> register({
    required String userId,
    required String registrationToken,
    bool bindRecoveryEmail = false,
  }) async {
    registerCalls++;
    return RegisterResult(
      userId: scenario == 'different account response' ? 'other-user' : userId,
      isNew: scenario != 'existing account response',
      accessToken: 'access',
      refreshToken: 'refresh',
    );
  }
}

Future<_Fixture> _openFixture() async {
  final directory = await Directory.systemTemp.createTemp('securechat_auth_');
  final database = await SecureChatDatabase.open(
    file: File('${directory.path}/storage.securejson'),
    crypto: LocalAeadCryptoService(
      SecretKey(List<int>.generate(32, (index) => 100 + index)),
    ),
  );
  return _Fixture(directory, database);
}

class _Fixture {
  const _Fixture(this.directory, this.database);

  final Directory directory;
  final SecureChatDatabase database;

  Future<void> close() async {
    await database.close();
    await directory.delete(recursive: true);
  }
}

class _RecordingDirectoryApi implements ContactDiscoveryApi {
  _RecordingDirectoryApi({this.reject = false});

  final bool reject;
  List<String>? phoneHashes;
  String? accessToken;
  String? ownPhoneHash;
  String? ownUserId;

  @override
  Future<List<RegisteredUserMatch>> checkUsers(
    List<String> phoneHashes,
    String accessToken, {
    String? ownPhoneHash,
    String? ownUserId,
  }) async {
    if (reject) {
      // The hardened route deliberately conflates malformed and already-owned
      // directory tokens. It does not disclose a recoverable account/email.
      throw const AuthApiException('invalid_directory_token', statusCode: 400);
    }
    this.phoneHashes = List<String>.of(phoneHashes);
    this.accessToken = accessToken;
    this.ownPhoneHash = ownPhoneHash;
    this.ownUserId = ownUserId;
    return const [];
  }
}

/// Kayit akisi testleri anahtar yayinini degil kayit mantigini olcuyor.
class _RecordingOlmKeyPublisher implements RecoveryIdentity {
  int calls = 0;
  int clears = 0;
  bool failPublish = false;
  String? _pending;

  @override
  Future<void> publishIfNeeded() async {
    calls++;
    if (failPublish) {
      throw const AuthApiException('prekey_store_unavailable', statusCode: 503);
    }
  }

  @override
  Future<void> clearLocalCryptoState() async {
    clears++;
    _pending = null;
  }

  @override
  Future<void> republishAfterIdentityReset() async => calls++;

  // Bu testler kurtarmayi olcmuyor: kimlik yok, imza istenirse hata.
  @override
  Future<String?> recoverySigningPublicKey() async => null;

  @override
  Future<String> signRecoveryProof(String message) async =>
      throw StateError('kurtarma kimligi bu testte yok');

  @override
  Future<String?> readPendingRecovery() async => _pending;

  @override
  Future<void> writePendingRecovery(String record) async => _pending = record;

  @override
  Future<void> clearPendingRecovery() async => _pending = null;
}

/// Yenilemesi her zaman basarisiz olan API.
class _FailingRefreshApi extends AuthApi {
  _FailingRefreshApi() : super(baseUrl: 'http://unused.invalid');

  int refreshCalls = 0;

  @override
  Future<TokenPair> refresh(String refreshToken) async {
    refreshCalls++;
    throw StateError('refresh reddedildi');
  }
}

/// Yenilemeyi verilen hatayla reddeder.
class _StatusRefreshApi extends AuthApi {
  _StatusRefreshApi(int statusCode)
    : failure = AuthApiException('rejected', statusCode: statusCode),
      super(baseUrl: 'http://unused.invalid');

  _StatusRefreshApi.failing(this.failure)
    : super(baseUrl: 'http://unused.invalid');

  final AuthApiException failure;
  int refreshCalls = 0;

  @override
  Future<TokenPair> refresh(String refreshToken) async {
    refreshCalls++;
    throw failure;
  }
}

/// Refresh her zaman 401; cihaz yolu ayarlanabilir.
class _DeviceReauthApi extends AuthApi {
  _DeviceReauthApi.success()
    : failure = null,
      super(baseUrl: 'http://unused.invalid');

  _DeviceReauthApi.failing(AuthApiException this.failure)
    : super(baseUrl: 'http://unused.invalid');

  final AuthApiException? failure;
  int deviceCalls = 0;
  String? lastUserId;
  String? lastRefreshToken;

  @override
  Future<TokenPair> refresh(String refreshToken) async =>
      throw const AuthApiException('rejected', statusCode: 401);

  @override
  Future<TokenPair> reauthenticateWithDevice({
    required String userId,
    required String refreshToken,
    required Future<String> Function(String message) sign,
  }) async {
    deviceCalls++;
    lastUserId = userId;
    lastRefreshToken = refreshToken;
    await sign('soru');
    final error = failure;
    if (error != null) throw error;
    return const TokenPair(
      accessToken: 'cihaz-access',
      refreshToken: 'cihaz-refresh',
    );
  }
}

class _DeviceKeyPublisher extends _RecordingOlmKeyPublisher {
  final signed = <String>[];

  @override
  Future<String?> recoverySigningPublicKey() async => 'cihaz-acik-anahtar';

  @override
  Future<String> signRecoveryProof(String message) async {
    signed.add(message);
    return 'imza';
  }
}

/// Her cagride farkli bir token dondurur; yenileme sayisini sayar.
class _CountingRefreshApi extends AuthApi {
  _CountingRefreshApi() : super(baseUrl: 'http://unused.invalid');

  int refreshCalls = 0;

  @override
  Future<TokenPair> refresh(String refreshToken) async {
    refreshCalls++;
    return TokenPair(
      accessToken: 'yeni-$refreshCalls',
      refreshToken: 'yeni-refresh-$refreshCalls',
    );
  }
}

/// Diskten tazelemenin baska bir token getirip getirmedigini taklit eder.
class _FakeSession extends SessionStore {
  _FakeSession({
    required String access,
    required String refresh,
    this.onReload,
  }) {
    accessToken = access;
    refreshToken = refresh;
  }

  /// Tazelemede okunacak token; null ise hic degismez.
  ///
  /// Yenileme kilidin ICINDE tazeliyor, yani bu "kilidi beklerken baska
  /// bir isolate yeniledi" durumunu temsil eder.
  final String? onReload;

  @override
  Future<void> reloadFromDisk() async {
    if (onReload != null) accessToken = onReload;
  }
}
