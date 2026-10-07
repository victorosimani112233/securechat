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
class OlmPreKeyPublisher implements OlmKeyPublisher {
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

    if (status == HttpStatus.ok) return true;
    if (status == HttpStatus.tooManyRequests) {
      // 429 bir hata degil: sunucu "cok sik" diyor. Anahtarlar zaten
      // yerinde olabilir ve bir sonraki yayin denemesi basarili olur.
      // Istisna firlatmak bunu gercek bir ariza gibi gosterirdi.
      debugPrint('SC-PREKEY rate limited; sonraki yayinda denenecek');
      return false;
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
    await response.drain<void>();
    return response.statusCode;
  }
}

/// Prekey yuklemesi sunucu tarafindan kabul edilmedi.
class OlmPreKeyPublishException implements Exception {
  const OlmPreKeyPublishException(this.message, {required this.statusCode});

  final String message;
  final int statusCode;

  @override
  String toString() => 'OlmPreKeyPublishException($statusCode): $message';
}
