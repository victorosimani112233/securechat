import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../storage/secure_chat_database.dart';
import 'vodozemac_protocol_store.dart';

/// Olm acik anahtarlarini yayinlama yetenegi.
///
/// `AuthCoordinator` ve arka plan bakimi yalniz bu davranisa ihtiyac
/// duyuyor. Somut sinif native kutuphane, veritabani ve HTTP istemcisi
/// istiyor; kayit akisi testlerinin ucunu da kurmasi gerekmesin diye
/// bagimlilik arayuz uzerinden veriliyor.
abstract interface class OlmKeyPublisher {
  Future<void> publishIfNeeded();
}

/// Hesap kurtarmanin istemci tarafi kripto ihtiyaclari: vodozemac Ed25519
/// kimligi, kurtarma kaniti imzasi, devam eden kurtarma kaydi, ve kurtarma
/// sonrasi Olm anahtar yayini (`publishIfNeeded`).
///
/// [OlmKeyPublisher]'i genisletir ki `AuthCoordinator` kurtarma
/// koordinatorune TEK bagimlilik gecebilsin. Uretimde `OlmPreKeyPublisher`
/// uygular (store'a delege eder); testler kendi sahtesini verir.
abstract interface class RecoveryIdentity implements OlmKeyPublisher {
  /// base64 Ed25519 imzalama acik anahtari, ya da hesap yoksa null.
  Future<String?> recoverySigningPublicKey();

  /// Cihazda Olm hesabi yoksa olusturur ve Ed25519 imzalama anahtarini
  /// doner. Cikis hesabi siler; uygulama yeniden baslamadan yapilan e-posta
  /// kurtarmasi yeni cihaz gibi kimlik uretmeli (QA 2026-10-13 T10).
  Future<String> ensureRecoverySigningKey();

  /// Kurtarma kanitini hesabin Ed25519 anahtariyla imzalar (base64).
  Future<String> signRecoveryProof(String message);

  Future<String?> readPendingRecovery();
  Future<void> writePendingRecovery(String record);
  Future<void> clearPendingRecovery();

  /// Sunucu bu hesabin Olm anahtarlarini sildikten sonra (kurtarmada kimlik
  /// degisimi) kimligi + taze anahtarlari YENIDEN yayinlar. Duz
  /// [publishIfNeeded] yerel "zaten yayinlandi" bilgisine guvenip hic
  /// yuklemeyebilir.
  Future<void> republishAfterIdentityReset();

  /// Cikista / hesap degisiminde yerel kripto durumunu siler: Olm hesabi,
  /// oturumlar, pinler ve devam eden kurtarma kaydi. Silinmezse sonraki
  /// hesap oncekinin Olm kimligini kullanir ve yarim kalmis bir kurtarma
  /// yetkisi cihazda kalir. Mesaj/sohbet verisi KORUNUR.
  Future<void> clearLocalCryptoState();
}

/// Hesabin Olm acik anahtarlarini sunucuya yayinlar.
///
/// libsignal tarafindaki `PreKeyManager` + `PreKeyMaintenanceService`
/// ciftinin karsiligi, ama Olm'un uc farkiyla:
///
///  * **Kimlik iki anahtardir.** Curve25519 oturum kurar, Ed25519 imzalar;
///    karsi taraf ikisini BIRLIKTE pinler. Biri olmadan digeri gonderilmez.
///  * **Signed prekey yok, fallback key var.** Tek kullanimlik havuz
///    bosaldiginda oturum kurulumu fallback ile surer. Bu yol olmasa havuz
///    bosken bundle bos doner ve gonderen hic oturum kuramaz.
///  * **`registrationId` yok.** Olm'da karsiligi olmayan bir kavram.
class OlmPreKeyPublisher implements OlmKeyPublisher, RecoveryIdentity {
  OlmPreKeyPublisher({
    required SecureChatDatabase database,
    required VodozemacProtocolStore store,
    required Uri apiBaseUrl,
    required HttpClient httpClient,
    required Future<String?> Function() accessTokenProvider,
    Future<String?> Function()? refreshAccessToken,
    void Function(String operation, Object error, StackTrace stackTrace)?
    onFailure,
    this.createAccountIfMissing = false,
    this.targetOneTimeKeys = 50,
    this.replenishThreshold = 20,
    this.fallbackRotationInterval = const Duration(days: 7),
    DateTime Function()? now,
  }) : _database = database,
       _store = store,
       _apiBaseUrl = apiBaseUrl,
       _httpClient = httpClient,
       _accessTokenProvider = accessTokenProvider,
       _refreshAccessToken = refreshAccessToken,
       _onFailure = onFailure,
       _now = now ?? DateTime.now;

  /// Hesap yoksa olusturulsun mu.
  ///
  /// Varsayilan `false` ve bu KRITIK. `withAccount` hesap yoksa sessizce
  /// yenisini uretir; yayinci iki ayri isolate'den (on plan ve arka plan
  /// gorevi) cagriliyor ve her isolate'in kendi veritabani anlik goruntusu
  /// var. Ikisi de yaratabilseydi birbirlerinin hesabini ezer, her yayin
  /// FARKLI bir kimlik gonderir ve sunucu —dogru olarak— "Explicit identity
  /// recovery required" ile reddederdi. Kimligin sessizce degismesi zaten
  /// reddedilmesi gereken bir sey.
  ///
  /// libsignal yolu bu tuzaktan kimligi yalniz kayitta uretip bakimi
  /// salt anahtar ekleme ile sinirlayarak kaciniyordu. Ayni ayrim burada
  /// da korunuyor: hesabi YALNIZ on plan yolu yaratir.
  final bool createAccountIfMissing;

  /// Havuz bu sayiya kadar doldurulur.
  final int targetOneTimeKeys;

  /// Havuz bu sayinin altina dusunce tamamlama yapilir.
  ///
  /// Her yayinda tamamlamak gereksiz yazma uretir; hic tamamlamamak havuzu
  /// tuketir ve karsi taraf fallback'e duser.
  final int replenishThreshold;

  /// Fallback anahtari bu araliktan once YENIDEN URETILMEZ.
  ///
  /// `generate_fallback_key` mevcut anahtari dondurur. Her yayinda cagirmak,
  /// onbelleginde eski bir bundle tutan gonderenin artik gecerli olmayan bir
  /// anahtarla oturum kurmaya calismasi demektir — fallback'in varlik sebebi
  /// olan teslim guvencesini bizzat bozar.
  final Duration fallbackRotationInterval;

  final SecureChatDatabase _database;
  final VodozemacProtocolStore _store;
  final Uri _apiBaseUrl;
  String _lastBody = '';

  /// Sunucu cihaz kimligini reddettiginde yazilan isaret; basarili yayinda
  /// silinir. Sohbet listesi buna bakarak kurtarma seridini gosterir.
  static const identityRecoveryRequiredKey = 'olm_identity_recovery_required';

  /// Ayni bilginin on plan sureci icin canli hali; sohbet listesi dinler.
  static final identityRecoveryNeeded = ValueNotifier<bool>(false);
  final HttpClient _httpClient;
  final Future<String?> Function() _accessTokenProvider;
  final Future<String?> Function()? _refreshAccessToken;

  /// Yayin hatasinin bildirilecegi yer.
  ///
  /// Bu kanal ZORUNLU olmali gibi gorunmese de kritik: cagiran taraf
  /// (`AppLifecycleCoordinator._runMaintenance`) butun hatalari
  /// `catch (_) {}` ile yutuyor. Yayinci yalniz firlatirsa, anahtarlar hic
  /// yuklenmez, hicbir iz kalmaz ve hesaba kimse mesaj gonderemez. Hata
  /// gorunur olmak zorunda.
  final void Function(String operation, Object error, StackTrace stackTrace)?
  _onFailure;
  final DateTime Function() _now;

  /// Gerekiyorsa anahtar uretir ve yukler.
  ///
  /// Yukleme basarisiz olursa hicbir sey "yayinlandi" olarak isaretlenmez;
  /// cagri yeniden denendiginde ayni anahtarlar tekrar gonderilir. Sunucu
  // RecoveryIdentity: kurtarma kriptosunu sahip olunan store'a delege eder.
  // Kurtarma kimligi mesaj kriptosuyla AYNI Olm hesabi oldugu icin ayri bir
  // kimlik tutulmaz.
  @override
  Future<String?> recoverySigningPublicKey() =>
      _store.recoverySigningPublicKey();

  @override
  Future<String> ensureRecoverySigningKey() async {
    // Ilk withAccount cagrisi hesabi olusturup saklar.
    await _store.withAccount((_) async {});
    final key = await _store.recoverySigningPublicKey();
    if (key == null) throw StateError('Olm hesabi olusturulamadi');
    return key;
  }

  @override
  Future<String> signRecoveryProof(String message) =>
      _store.signRecoveryProof(message);

  @override
  Future<String?> readPendingRecovery() => _store.readPendingRecovery();

  @override
  Future<void> writePendingRecovery(String record) =>
      _store.writePendingRecovery(record);

  @override
  Future<void> clearPendingRecovery() => _store.clearPendingRecovery();

  @override
  Future<void> clearLocalCryptoState() => _database.clearCryptoProtocolState();

  @override
  Future<void> republishAfterIdentityReset() async {
    // Sunucu havuzu bosaltti ve kimligi NULL'a cekti. Yerel "yayinlandi"
    // isareti ve markKeysAsPublished ile isaretlenmis anahtarlar artik
    // yalan: fallback isaretini sil (yeni fallback + kimlik yuklensin) ve
    // yeni bir tek kullanimlik parti uret (sunucu havuzu bos). Yayin
    // basarisiz olursa isaret null kaldigi icin sonraki bakim tekrar dener.
    await _database.vodozemacAccount.clearFallbackPublished();
    if (await _store.hasAccount()) {
      await _store.withAccount((account) async {
        account.generateOneTimeKeys(targetOneTimeKeys);
      });
    }
    await publishIfNeeded();
  }

  /// ayni kimlik + ayni materyali idempotent kabul eder.
  @override
  Future<void> publishIfNeeded() async {
    try {
      await _publish();
    } catch (error, stackTrace) {
      _onFailure?.call('olm-prekey-publish', error, stackTrace);
      rethrow;
    }
  }

  Future<void> _publish() async {
    if (!createAccountIfMissing && !await _store.hasAccount()) {
      // Hesap henuz yok ve bu cagri onu yaratmamali. Sessizce gecmek
      // dogru: yaratma yetkisi olan yol kisa sure icinde kosacak.
      return;
    }
    // Oturum yoksa yayinlanacak bir sunucu hesabi da yok. Cikis yapilmis
    // cihazda bakim dongusu yayinciyi yine cagiriyor; eskiden token'siz bir
    // yukleme gidiyor, sunucu reddediyor ve her acilista bir hata raporu
    // dusuyordu. Hesap ise (yetki varsa) yine OLUSTURULUR: yeni kurulumda
    // hesap kurtarma kaniti bu Olm hesabinin Ed25519 anahtariyla imzalanir.
    final token = await _accessTokenProvider();
    if (token == null || token.isEmpty) {
      if (createAccountIfMissing && !await _store.hasAccount()) {
        await _store.withAccount((_) async {});
      }
      return;
    }
    final fallbackPublishedAt = await _database.vodozemacAccount
        .readFallbackPublishedAt();
    final now = _now();
    final shouldRotateFallback =
        fallbackPublishedAt == null ||
        now
                .difference(
                  DateTime.fromMillisecondsSinceEpoch(fallbackPublishedAt),
                )
                .compareTo(fallbackRotationInterval) >=
            0;

    final published = await _store.withAccount((account) async {
      final identity = account.identityKeys();
      final identityKey = identity['curve25519'];
      final signingKey = identity['ed25519'];
      if (identityKey == null || signingKey == null) {
        throw StateError('Olm kimlik anahtarlari okunamadi');
      }

      if (account.storedOneTimeKeyCount < replenishThreshold) {
        account.generateOneTimeKeys(
          targetOneTimeKeys - account.storedOneTimeKeyCount,
        );
      }
      final oneTimeKeys = account.unpublishedOneTimeKeys();

      String? fallbackKey;
      String? fallbackSignature;
      if (shouldRotateFallback) {
        final generated = account.generateFallbackKey();
        final entry = generated.entries.firstOrNull;
        if (entry != null) {
          fallbackKey = entry.value;
          // Fallback anahtari hesabin KENDI Ed25519 anahtariyla imzalanir.
          // Sunucu imzayi dogrulamaz ve dogrulayamaz da — imzanin anlami
          // aliciya degil, bundle'i cekene yoneliktir: sunucu kendi
          // fallback anahtarini koyarsa mesaji okuyamaz ama alicinin
          // cozmesini de engelleyebilir. Imza bunu gorunur kilar.
          fallbackSignature = account.sign(
            base64Decode(base64.normalize(entry.value)),
          );
        }
      }

      // Yayinlanacak YENI bir sey yoksa sunucuya hic gidilmez.
      //
      // Onceden her on plana gecis, yalniz kimligi tasiyan bos bir yukleme
      // gonderiyordu. Sunucunun hesap basina 30 yazma/saat siniri var ve bu
      // bos yuklemeler kotayi tuketip gercek bir tamamlama gerektiginde
      // 429'a carpilmasina yol aciyordu. Ilk yayin yapilmissa
      // (`fallbackPublishedAt` yalniz sunucu kabul ettikten sonra yazilir)
      // ve ne yeni anahtar ne de fallback donusu varsa, gonderilecek bir
      // sey de yoktur.
      if (oneTimeKeys.isEmpty &&
          fallbackKey == null &&
          fallbackPublishedAt != null) {
        return null;
      }

      final accepted = await _upload(
        identityKey: identityKey,
        signingKey: signingKey,
        oneTimeKeys: oneTimeKeys,
        fallbackKey: fallbackKey,
        fallbackSignature: fallbackSignature,
      );

      // Yayin basarisi GORUNUR olmali. Oncesinde basarili bir yayin hicbir
      // iz birakmiyordu ve "bu cihaz anahtarlarini yukledi mi" sorusu
      // ancak sunucu veritabanina bakarak cevaplanabiliyordu. Yalniz
      // sayilar yazilir; anahtar materyali loga ASLA girmez.
      debugPrint(
        'SC-PREKEY published one_time=${oneTimeKeys.length} '
        'fallback=${fallbackKey != null} accepted=$accepted',
      );

      // SIRALAMA KRITIK: isaretleme yalniz sunucu kabul ettikten SONRA.
      // Once isaretlenseydi ve yukleme basarisiz olsaydi, anahtarlar
      // "yayinlanmamis" kumesinden duser ve bir daha hic gonderilmezdi;
      // karsi taraf o hesapla hicbir zaman oturum kuramazdi.
      if (accepted) account.markKeysAsPublished();
      return accepted ? fallbackKey != null : null;
    });

    if (published == true) {
      await _database.vodozemacAccount.markFallbackPublished(
        now.millisecondsSinceEpoch,
      );
    }
  }

  Future<bool> _upload({
    required String identityKey,
    required String signingKey,
    required Map<String, String> oneTimeKeys,
    String? fallbackKey,
    String? fallbackSignature,
  }) async {
    final body = jsonEncode({
      'olmIdentityKey': identityKey,
      'olmSigningKey': signingKey,
      'olmOneTimeKeys': [
        for (final entry in oneTimeKeys.entries)
          {'keyId': entry.key, 'publicKey': entry.value},
      ],
      if (fallbackKey != null) 'olmFallbackKey': fallbackKey,
      if (fallbackSignature != null)
        'olmFallbackKeySignature': fallbackSignature,
    });

    var token = await _accessTokenProvider();
    var status = await _post(body, token);
    if (status == HttpStatus.unauthorized) {
      // Arka plan isolate'i 1 saatlik access token ile 15 dakikada bir
      // uyaniyor; token bayatlamis olabilir. Bir kez yenile.
      final refreshed = await _refreshAccessToken?.call();
      if (refreshed != null && refreshed.isNotEmpty) {
        token = refreshed;
        status = await _post(body, token);
      }
    }

    if (status == HttpStatus.ok) {
      await _database.cryptoState.delete(identityRecoveryRequiredKey);
      identityRecoveryNeeded.value = false;
      return true;
    }
    if (status == HttpStatus.tooManyRequests) {
      // 429 bir hata degil: sunucu "cok sik" diyor. Anahtarlar zaten
      // yerinde olabilir ve bir sonraki yayin denemesi basarili olur.
      // Istisna firlatmak bunu gercek bir ariza gibi gosterirdi.
      debugPrint('SC-PREKEY rate limited; sonraki yayinda denenecek');
      return false;
    }
    if (status == HttpStatus.conflict &&
        _lastBody.contains('identity_recovery_required')) {
      // Bu cihazin kimligi hesaptakinden farkli. Sessiz kalirsa hesap mesaj
      // alamaz hale gelir ve kullanici nedenini hic ogrenemez; isaret sohbet
      // listesinde kurtarma seridini acar (QA 2026-10-13 T5 madde 3).
      await _database.cryptoState.put(
        identityRecoveryRequiredKey,
        '${DateTime.now().millisecondsSinceEpoch}',
      );
      identityRecoveryNeeded.value = true;
      throw OlmPreKeyPublishException(
        'Cihaz kimligi hesaptakinden farkli; kurtarma gerekli (409)',
        statusCode: status,
        identityRecoveryRequired: true,
      );
    }
    if (status == HttpStatus.conflict) {
      // Sunucu ayni keyId'yi farkli materyalle gormus ya da havuz dolu.
      // Sessizce basarili saymak, istemcinin yuklendigini sandigi anahtarin
      // karsi tarafa hic gitmemesi demek olurdu.
      throw OlmPreKeyPublishException(
        'Sunucu prekey yuklemesini reddetti (409)',
        statusCode: status,
      );
    }
    throw OlmPreKeyPublishException(
      'Prekey yuklemesi basarisiz: HTTP $status',
      statusCode: status,
    );
  }

  Future<int> _post(String body, String? token) async {
    final uri = _apiBaseUrl.resolve('/api/v1/prekeys/upload');
    final request = await _httpClient
        .postUrl(uri)
        .timeout(const Duration(seconds: 15));
    request.headers.contentType = ContentType.json;
    if (token != null && token.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    request.write(body);
    final response = await request.close().timeout(const Duration(seconds: 20));
    // Hata govdesi kucuk; yalniz hata kodunu ayirt etmek icin okunur.
    _lastBody = response.statusCode == HttpStatus.conflict
        ? await utf8.decodeStream(response).timeout(const Duration(seconds: 10))
        : '';
    if (_lastBody.isEmpty) await response.drain<void>();
    return response.statusCode;
  }
}

/// Prekey yuklemesi sunucu tarafindan kabul edilmedi.
class OlmPreKeyPublishException implements Exception {
  const OlmPreKeyPublishException(
    this.message, {
    required this.statusCode,
    this.identityRecoveryRequired = false,
  });

  final String message;
  final int statusCode;

  /// Sunucu bu cihazin kimligini hesaba ait saymiyor; kurtarma gerekli.
  final bool identityRecoveryRequired;

  @override
  String toString() => 'OlmPreKeyPublishException($statusCode): $message';
}
