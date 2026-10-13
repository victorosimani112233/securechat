import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/crypto/vodozemac/olm_pre_key_publisher.dart';
import 'package:flutter_securechat/src/crypto/vodozemac/securechat_crypto_ffi.dart';
import 'package:flutter_securechat/src/crypto/vodozemac/vodozemac_protocol_store.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/services/identity_recovery_status.dart';
import 'package:flutter_test/flutter_test.dart';

/// Olm acik anahtarlarinin yayinlanmasi.
///
/// Testlerin cogu tek bir soruyu soruyor: **bir anahtar sessizce
/// kaybolabilir mi?** Kaybolabildigi her yol, karsi tarafin o hesapla hic
/// oturum kuramamasi demek.
void main() {
  final libraryPath = _resolveHostLibrary();
  if (libraryPath == null) {
    test('Olm prekey yayini (atlandi: native kutuphane derlenmemis)', () {
      markTestSkipped(
        'Derlemek icin: cd native/securechat_crypto && cargo build --release',
      );
    }, skip: true);
    return;
  }

  late SecureChatDatabase database;
  late SecureChatCrypto crypto;
  late VodozemacProtocolStore store;
  late HttpServer server;
  late String responseBody;
  late Uri baseUrl;

  // Sunucu davranisini test icinde yonlendirmek icin.
  late List<Map<String, Object?>> uploads;
  late List<String?> seenTokens;
  late int Function() statusFor;
  late DateTime fakeNow;

  setUp(() async {
    final directory = await Directory.systemTemp.createTemp('olm-publish');
    final masterKey = List<int>.generate(32, (index) => index * 5 + 2);
    database = await SecureChatDatabase.open(
      file: File('${directory.path}/database.securejson'),
      crypto: LocalAeadCryptoService(SecretKey(masterKey)),
    );
    crypto = SecureChatCrypto.open(libraryPath: libraryPath);
    store = VodozemacProtocolStore(
      database: database,
      crypto: crypto,
      pickleKey: await VodozemacProtocolStore.derivePickleKey(masterKey),
    );

    uploads = [];
    seenTokens = [];
    statusFor = () => HttpStatus.ok;
    responseBody = '{"status":"ok"}';
    fakeNow = DateTime.utc(2026, 10, 7, 12);

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = Uri.parse('http://127.0.0.1:${server.port}');
    server.listen((request) async {
      seenTokens.add(request.headers.value(HttpHeaders.authorizationHeader));
      final body = await utf8.decoder.bind(request).join();
      uploads.add((jsonDecode(body) as Map).cast<String, Object?>());
      request.response.statusCode = statusFor();
      request.response.write(responseBody);
      await request.response.close();
    });

    addTearDown(() async {
      await server.close(force: true);
      await database.close();
      await directory.delete(recursive: true);
    });
  });

  OlmPreKeyPublisher build({
    Future<String?> Function()? refresh,
    String? token = 'ilk-token',
    Duration rotation = const Duration(days: 7),
    bool createAccount = true,
  }) => OlmPreKeyPublisher(
    database: database,
    store: store,
    apiBaseUrl: baseUrl,
    httpClient: HttpClient(),
    accessTokenProvider: () async => token,
    refreshAccessToken: refresh,
    createAccountIfMissing: createAccount,
    fallbackRotationInterval: rotation,
    now: () => fakeNow,
  );

  group('hesap yaratma yetkisi', () {
    test('yetki yoksa hesap YARATILMAZ ve hicbir sey yuklenmez', () async {
      // Yayinci iki ayri isolate'den cagriliyor ve her birinin kendi
      // veritabani anlik goruntusu var. Ikisi de hesap yaratabilseydi
      // birbirlerininkini ezer, her yayin FARKLI bir kimlik gonderir ve
      // sunucu "Explicit identity recovery required" ile reddeder.
      // Cihazda olculen hata tam olarak buydu.
      await build(createAccount: false).publishIfNeeded();

      expect(uploads, isEmpty);
      expect(await store.hasAccount(), isFalse);
    });

    test('yetki varsa hesap yaratilir ve yayinlanir', () async {
      await build(createAccount: true).publishIfNeeded();

      expect(uploads, hasLength(1));
      expect(await store.hasAccount(), isTrue);
    });

    test('hesap kurulduktan sonra yetkisiz cagri da yayinlar', () async {
      // Yetkisiz olan sey YARATMAK; var olan hesabi yayinlamak degil.
      await build(createAccount: true).publishIfNeeded();
      // Gonderilecek bir sey olmasi icin fallback donus penceresini gec;
      // aksi halde ikinci cagri hic istek atmaz.
      fakeNow = fakeNow.add(const Duration(days: 8));

      await build(createAccount: false).publishIfNeeded();

      expect(uploads, hasLength(2));
      // Kimlik AYNI kalmali.
      expect(uploads[1]['olmIdentityKey'], uploads[0]['olmIdentityKey']);
      expect(uploads[1]['olmSigningKey'], uploads[0]['olmSigningKey']);
    });
  });

  group('ilk yayin', () {
    test('kimligin IKI anahtari da gonderilir', () async {
      await build().publishIfNeeded();

      expect(uploads, hasLength(1));
      // Curve25519 oturum kurar, Ed25519 imzalar; karsi taraf ikisini
      // birlikte pinler. Biri eksik gonderilse pinleme anlamsiz olurdu.
      expect(uploads.single['olmIdentityKey'], isA<String>());
      expect(uploads.single['olmSigningKey'], isA<String>());
      expect(
        uploads.single['olmIdentityKey'],
        isNot(uploads.single['olmSigningKey']),
      );
    });

    test('tek kullanimlik anahtarlar dize kimlikle gonderilir', () async {
      await build().publishIfNeeded();

      final keys = (uploads.single['olmOneTimeKeys'] as List)
          .cast<Map<String, Object?>>();
      expect(keys, isNotEmpty);
      // Olm anahtar kimligi vodozemac tarafindan uretilir ve base64 bir
      // dizedir; libsignal'daki gibi tamsayi DEGIL.
      expect(keys.first['keyId'], isA<String>());
      expect(keys.first['publicKey'], isA<String>());
    });

    test('imzali fallback anahtari gonderilir', () async {
      await build().publishIfNeeded();

      expect(uploads.single['olmFallbackKey'], isA<String>());
      expect(uploads.single['olmFallbackKeySignature'], isA<String>());
    });

    test('fallback imzasi hesabin kendi Ed25519 anahtarina ait', () async {
      await build().publishIfNeeded();

      final upload = uploads.single;
      final verified = await Ed25519().verify(
        base64Decode(
          base64.normalize(upload['olmFallbackKey']! as String),
        ),
        signature: Signature(
          base64Decode(
            base64.normalize(upload['olmFallbackKeySignature']! as String),
          ),
          publicKey: SimplePublicKey(
            base64Decode(base64.normalize(upload['olmSigningKey']! as String)),
            type: KeyPairType.ed25519,
          ),
        ),
      );

      expect(verified, isTrue);
    });

    test('registrationId gonderilmez', () async {
      // Olm'da karsiligi olmayan bir libsignal kavrami.
      await build().publishIfNeeded();

      expect(uploads.single.containsKey('registrationId'), isFalse);
    });
  });

  group('fallback donusu', () {
    test('aralik gecmeden fallback YENIDEN URETILMEZ', () async {
      // `generate_fallback_key` mevcut anahtari dondurur. Her yayinda
      // cagirmak, onbelleginde eski bundle tutan gonderenin artik gecerli
      // olmayan bir anahtarla oturum kurmaya calismasi demek — fallback'in
      // varlik sebebi olan teslim guvencesini bizzat bozar.
      final publisher = build();
      await publisher.publishIfNeeded();
      fakeNow = fakeNow.add(const Duration(days: 1));

      await publisher.publishIfNeeded();

      // Donus penceresi icinde ve yeni anahtar da yokken gonderilecek bir
      // sey kalmiyor; sunucuya hic gidilmemeli. Bos yuklemeler hesap
      // basina 30 yazma/saat sinirini tuketiyordu.
      expect(uploads, hasLength(1));
      expect(uploads.single['olmFallbackKey'], isA<String>());
    });

    test('aralik gectikten sonra fallback donur', () async {
      final publisher = build();
      await publisher.publishIfNeeded();
      fakeNow = fakeNow.add(const Duration(days: 8));

      await publisher.publishIfNeeded();

      expect(uploads[1]['olmFallbackKey'], isA<String>());
      expect(uploads[1]['olmFallbackKey'], isNot(uploads[0]['olmFallbackKey']));
    });
  });

  group('oturum yokken', () {
    // Cikis yapilmis cihazda bakim dongusu yayinciyi yine cagiriyor.
    // Eskiden token'siz bir yukleme gidiyor, sunucu reddediyor ve her
    // acilista bir hata raporu dusuyordu. Hesap ise OLUSTURULMALI: yeni
    // kurulumda hesap kurtarma kaniti bu Olm hesabiyla imzalaniyor.
    test('yukleme yapilmaz ama hesap olusturulur', () async {
      await build(token: null).publishIfNeeded();

      expect(uploads, isEmpty);
      expect(await store.hasAccount(), isTrue);
    });

    test('olusturma yetkisi yoksa hesap da olusturulmaz', () async {
      await build(token: null, createAccount: false).publishIfNeeded();

      expect(uploads, isEmpty);
      expect(await store.hasAccount(), isFalse);
    });

    test('giris yapilinca anahtarlar normal yayinlanir', () async {
      await build(token: null).publishIfNeeded();
      await build().publishIfNeeded();

      expect(uploads, hasLength(1));
      expect(uploads.single['olmIdentityKey'], isA<String>());
    });
  });

  group('cikista yerel kripto silme', () {
    // Eskiden libsignal store'u uzerinden test ediliyordu
    // (recovery_key_material_test). Degismez ayni: cikis Olm kimligini ve
    // yarim kalmis kurtarma yetkisini cihazdan siler, sohbet verisini korur.
    test('Olm hesabi ve devam eden kurtarma silinir', () async {
      final publisher = build();
      await publisher.publishIfNeeded();
      await publisher.writePendingRecovery('{"capability":"secret"}');
      expect(await store.hasAccount(), isTrue);

      await publisher.clearLocalCryptoState();

      expect(await store.hasAccount(), isFalse);
      expect(await publisher.readPendingRecovery(), isNull);
      expect(await publisher.recoverySigningPublicKey(), isNull);
    });
  });

  group('kurtarmada kimlik sifirlamasi', () {
    // Kurtarma "replace" modunda sunucu bu hesabin Olm kimligini NULL'a
    // ceker ve havuzlari siler. Yerel durum ise "her sey yayinlandi" der.
    test('duz yayin sunucu sifirlamasini GORMEZ (duzeltilen hata)', () async {
      final publisher = build();
      await publisher.publishIfNeeded();
      fakeNow = fakeNow.add(const Duration(days: 1));

      // Sunucu tarafinda kimlik silindi; yerel durum degismedi.
      await publisher.publishIfNeeded();

      // Hicbir sey yuklenmedi: kurtarilan hesap sunucuda kimliksiz kalirdi
      // ve kimse bu hesaba mesaj atamazdi.
      expect(uploads, hasLength(1));
    });

    test('republishAfterIdentityReset kimlik + fallback + yeni anahtar yukler', () async {
      final publisher = build();
      await publisher.publishIfNeeded();
      fakeNow = fakeNow.add(const Duration(days: 1));
      final firstKeys = (uploads.single['olmOneTimeKeys'] as List)
          .cast<Map<String, Object?>>()
          .map((entry) => entry['keyId'])
          .toSet();

      await publisher.republishAfterIdentityReset();

      expect(uploads, hasLength(2));
      final second = uploads[1];
      // Ayni Olm hesabi: kimlik degismez, sunucu setIdentity ile yeniden pinler.
      expect(second['olmIdentityKey'], uploads[0]['olmIdentityKey']);
      expect(second['olmSigningKey'], uploads[0]['olmSigningKey']);
      expect(second['olmFallbackKey'], isA<String>());
      final secondKeys = (second['olmOneTimeKeys'] as List)
          .cast<Map<String, Object?>>()
          .map((entry) => entry['keyId'])
          .toSet();
      // Sunucu havuzu bos: taze anahtarlar gitmeli, eskiler tekrar degil.
      expect(secondKeys, isNotEmpty);
      expect(secondKeys.intersection(firstKeys), isEmpty);
    });

    test('yeniden yayin basarisiz olursa bakim kendini iyilestirir', () async {
      final publisher = build();
      await publisher.publishIfNeeded();
      fakeNow = fakeNow.add(const Duration(days: 1));

      statusFor = () => HttpStatus.internalServerError;
      await expectLater(
        publisher.republishAfterIdentityReset(),
        throwsA(isA<OlmPreKeyPublishException>()),
      );
      statusFor = () => HttpStatus.ok;

      // Fallback isareti yuklemeden ONCE silindi; siradan bakim yayini artik
      // "yeni bir sey yok" demez.
      await publisher.publishIfNeeded();

      expect(uploads, hasLength(3));
      expect(uploads[2]['olmFallbackKey'], isA<String>());
      expect(uploads[2]['olmOneTimeKeys'] as List, isNotEmpty);
    });
  });

  group('basarisizlik', () {
    test('yukleme basarisiz olursa anahtarlar YAYINLANDI SAYILMAZ', () async {
      // Bu testin tasidigi degismez en onemlisi. `markKeysAsPublished`
      // basarisiz bir yuklemeden once cagrilsaydi, anahtarlar
      // "yayinlanmamis" kumesinden duser ve bir daha hic gonderilmezdi;
      // karsi taraf o hesapla hicbir zaman oturum kuramazdi.
      statusFor = () => HttpStatus.internalServerError;
      await expectLater(
        build().publishIfNeeded(),
        throwsA(isA<OlmPreKeyPublishException>()),
      );
      final firstKeys = (uploads.single['olmOneTimeKeys'] as List)
          .cast<Map<String, Object?>>()
          .map((entry) => entry['keyId'])
          .toSet();

      // Simdi basarili olsun: AYNI anahtarlar yeniden gonderilmeli.
      statusFor = () => HttpStatus.ok;
      await build().publishIfNeeded();

      final secondKeys = (uploads[1]['olmOneTimeKeys'] as List)
          .cast<Map<String, Object?>>()
          .map((entry) => entry['keyId'])
          .toSet();
      expect(secondKeys.containsAll(firstKeys), isTrue);
    });

    test('basarisiz yukleme fallback yayin zamanini isaretlemez', () async {
      statusFor = () => HttpStatus.internalServerError;
      await expectLater(
        build().publishIfNeeded(),
        throwsA(isA<OlmPreKeyPublishException>()),
      );

      expect(await database.vodozemacAccount.readFallbackPublishedAt(), isNull);
    });

    test('409 sessizce basarili sayilmaz', () async {
      // Sunucu ayni keyId'yi farkli materyalle gormus olabilir. Sessizce
      // gecmek, istemcinin yuklendigini sandigi anahtarin karsi tarafa hic
      // gitmemesi demek olurdu.
      statusFor = () => HttpStatus.conflict;

      await expectLater(
        build().publishIfNeeded(),
        throwsA(
          isA<OlmPreKeyPublishException>().having(
            (error) => error.statusCode,
            'statusCode',
            HttpStatus.conflict,
          ),
        ),
      );
    });
  });

  // QA 2026-10-13 T5 madde 3: kimlik sapmasi sessiz bir teshis satirinda
  // kaliyordu; kullanici mesaj alamadigini hic ogrenmiyordu.
  test('rejected identity raises the recovery flag until a publish succeeds', () async {
    statusFor = () => HttpStatus.conflict;
    responseBody = '{"error":"identity_recovery_required"}';
    await expectLater(
      build().publishIfNeeded(),
      throwsA(
        isA<OlmPreKeyPublishException>().having(
          (error) => error.identityRecoveryRequired,
          'identityRecoveryRequired',
          isTrue,
        ),
      ),
    );
    expect(identityRecoveryNeeded.value, isTrue);
    expect(
      await database.cryptoState.get(
        OlmPreKeyPublisher.identityRecoveryRequiredKey,
      ),
      isNotNull,
    );

    statusFor = () => HttpStatus.ok;
    responseBody = '{"status":"ok"}';
    await build().publishIfNeeded();
    expect(identityRecoveryNeeded.value, isFalse);
    expect(
      await database.cryptoState.get(
        OlmPreKeyPublisher.identityRecoveryRequiredKey,
      ),
      isNull,
    );
  });

  group('kimlik dogrulama', () {
    test('401 token yenilenip BIR KEZ tekrar denenir', () async {
      var attempt = 0;
      statusFor = () =>
          ++attempt == 1 ? HttpStatus.unauthorized : HttpStatus.ok;

      await build(refresh: () async => 'yeni-token').publishIfNeeded();

      expect(seenTokens, ['Bearer ilk-token', 'Bearer yeni-token']);
    });

    test('401 surerse ikinci kez denenmez', () async {
      statusFor = () => HttpStatus.unauthorized;

      await expectLater(
        build(refresh: () async => 'yeni-token').publishIfNeeded(),
        throwsA(isA<OlmPreKeyPublishException>()),
      );
      expect(seenTokens, hasLength(2));
    });

    test('yenileme yolu yoksa tek deneme yapilir', () async {
      statusFor = () => HttpStatus.unauthorized;

      await expectLater(
        build().publishIfNeeded(),
        throwsA(isA<OlmPreKeyPublishException>()),
      );
      expect(seenTokens, hasLength(1));
    });
  });

  test('havuz esigin uzerindeyse yeni anahtar uretilmez', () async {
    final publisher = build();
    await publisher.publishIfNeeded();
    final firstCount = (uploads.single['olmOneTimeKeys'] as List).length;

    // Ikinci yayinda havuz hala dolu; yayinlanmamis anahtar kalmadigi icin
    // liste bos gelmeli. Her yayinda yeniden uretmek gereksiz yazma ve
    // gereksiz sunucu yazmasi uretirdi.
    await publisher.publishIfNeeded();

    expect(firstCount, greaterThan(0));
    // Yayinlanacak yeni anahtar yok: istek hic gonderilmemeli.
    expect(uploads, hasLength(1));
  });
}

String? _resolveHostLibrary() {
  for (final candidate in const [
    'native/securechat_crypto/target/release/libsecurechat_crypto.so',
    'native/securechat_crypto/target/debug/libsecurechat_crypto.so',
  ]) {
    if (File(candidate).existsSync()) return File(candidate).absolute.path;
  }
  return null;
}
