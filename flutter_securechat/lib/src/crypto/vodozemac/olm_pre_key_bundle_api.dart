import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'vodozemac_crypto_service.dart';

/// Sunucudan Olm prekey bundle'i ceken HTTP istemcisi.
///
/// libsignal'daki bundle'dan uc noktada ayrilir ve ucu de kasitli:
///
///  * **Ed25519 imza anahtari zorunlu.** libsignal bundle'i yalnizca
///    Curve25519 kimlik anahtarini tasiyordu. Olm'da kimlik iki anahtardan
///    olusur ve [OlmPreKeyBundle.identityBytes] ikisini birlikte pinler;
///    yalniz birini pinlemek digerini degistirilebilir birakir.
///  * **`registrationId` yok.** Olm'da karsiligi olmayan bir libsignal
///    kavramiydi.
///  * **Signed prekey yerine fallback key.** Tek kullanimlik anahtarlar
///    tukendiginde oturum kurulumu fallback ile surer. Bu, "No valid
///    sessions" dongusune yol acan sinifin basligidir: OTPK havuzu bosken
///    bundle'in bos donmesi, gonderenin hic oturum kuramamasi demektir.
///
/// Fallback anahtari **imzali olmak zorunda** ve imza burada dogrulanir.
/// Tehdit modeli tam olarak sudur: sunucu kendi fallback anahtarini
/// koyarsa mesaji okuyamaz — oturum kurulumu alicinin kimlik anahtariyla
/// da DH yapar ve ona ait ozel anahtar sunucuda yok — ama alici da
/// cozemez. Yani imzasiz fallback bir MITM degil, **sessiz ve kalici bir
/// teslim reddi** aracidir; sahada teshisi en pahali hata sinifi. Tek
/// kullanimlik anahtarin imzalanmasina gerek yoktur, cunku havuz
/// tukendiginde en kotu sonuc bundle'in bos donmesidir ve o gorulebilir.
class HttpOlmPreKeyBundleProvider implements OlmPreKeyBundleProvider {
  HttpOlmPreKeyBundleProvider({
    required Uri apiBaseUrl,
    required HttpClient httpClient,
    required Future<String?> Function() accessTokenProvider,
    Future<String?> Function()? refreshAccessToken,
    Ed25519? signatureVerifier,
  }) : _apiBaseUrl = apiBaseUrl,
       _httpClient = httpClient,
       _accessTokenProvider = accessTokenProvider,
       _refreshAccessToken = refreshAccessToken,
       _ed25519 = signatureVerifier ?? Ed25519();

  /// Istemcinin konustugu bundle surumu.
  ///
  /// Sunucu farkli bir surum dondururse bundle **kullanilmaz**. Sessizce
  /// eski sekli ayristirmaya calismak, yanlis uzunlukta bir anahtarla
  /// oturum kurup cozulemeyen mesaj uretmekten daha iyi degil.
  static const int expectedProtocolVersion = 3;

  /// Curve25519 ve Ed25519 acik anahtarlari 32 bayt.
  ///
  /// libsignal 33 bayt dondururdu: bastaki bayt anahtar turu onekiydi.
  /// Goc sirasinda sunucunun eski sekli dondurmesi somut bir risk, bu
  /// yuzden 33 bayt ayri ve anlasilir bir hata verir.
  static const int _keyLength = 32;
  static const int _signatureLength = 64;

  final Uri _apiBaseUrl;
  final HttpClient _httpClient;
  final Future<String?> Function() _accessTokenProvider;
  final Future<String?> Function()? _refreshAccessToken;
  final Ed25519 _ed25519;

  @override
  Future<OlmPreKeyBundle?> fetch(String recipientId) async {
    try {
      return await _fetchOnce(recipientId, await _accessTokenProvider());
    } on _BundleUnauthorizedException {
      // Arka plan isolate'i 1 saatlik access token ile 15 dakikada bir
      // uyanir; token bayatlamis olabilir. Bir kez yenilemeyi dene.
      final refresher = _refreshAccessToken;
      if (refresher == null) rethrow;
      final refreshed = await refresher();
      if (refreshed == null || refreshed.isEmpty) rethrow;
      return _fetchOnce(recipientId, refreshed);
    }
  }

  Future<OlmPreKeyBundle?> _fetchOnce(String recipientId, String? token) async {
    final uri = _apiBaseUrl.resolve(
      '/api/v1/users/${Uri.encodeComponent(recipientId)}/prekeys',
    );
    final request = await _httpClient
        .getUrl(uri)
        .timeout(const Duration(seconds: 15));
    if (token != null && token.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    final response = await request.close().timeout(const Duration(seconds: 20));
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode == HttpStatus.notFound) return null;
    if (response.statusCode == HttpStatus.unauthorized) {
      throw const _BundleUnauthorizedException();
    }
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Prekey bundle fetch failed: HTTP ${response.statusCode}',
        uri: uri,
      );
    }
    return parseBundle(body, uri: uri);
  }

  /// Govdeyi bundle'a cevirir.
  ///
  /// Testten dogrudan cagrilabilmesi icin ayri: ayristirma ve dogrulama
  /// kurallari HTTP tasimasindan bagimsiz olarak sinanabilir olmali.
  Future<OlmPreKeyBundle?> parseBundle(String body, {Uri? uri}) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException catch (error) {
      throw OlmPreKeyBundleFormatException(
        'Bundle govdesi JSON degil: ${error.message}',
      );
    }
    if (decoded is! Map) {
      throw const OlmPreKeyBundleFormatException(
        'Bundle govdesi bir JSON nesnesi degil',
      );
    }
    final json = decoded.cast<String, Object?>();

    final version = json['protocolVersion'];
    if (version is! num || version.toInt() != expectedProtocolVersion) {
      throw OlmPreKeyBundleFormatException(
        'Desteklenmeyen bundle surumu: $version '
        '(beklenen $expectedProtocolVersion)',
      );
    }

    final identityKey = _requireKey(json, 'identityKey');
    final signingKey = _requireKey(json, 'signingKey');

    final oneTimeKey = json['oneTimeKey'];
    if (oneTimeKey is String && oneTimeKey.isNotEmpty) {
      _checkKeyBytes('oneTimeKey', oneTimeKey);
      return OlmPreKeyBundle(
        identityKey: identityKey,
        signingKey: signingKey,
        oneTimeKey: oneTimeKey,
      );
    }

    // Havuz bos: fallback'e dus, ama imzasiz kabul etme.
    final fallbackKey = json['fallbackKey'];
    if (fallbackKey is! String || fallbackKey.isEmpty) {
      // Tek kullanimlik anahtar da fallback da yok. Bu bir hata degil,
      // karsi taraf henuz anahtar yuklememis olabilir; cagiran null'i
      // "oturum kurulamaz" olarak ele alir.
      return null;
    }
    _checkKeyBytes('fallbackKey', fallbackKey);

    final signature = json['fallbackKeySignature'];
    if (signature is! String || signature.isEmpty) {
      throw const OlmPreKeyBundleFormatException(
        'Fallback anahtari imzasiz geldi; imzasiz fallback kabul edilmez',
      );
    }
    final signatureBytes = _decode('fallbackKeySignature', signature);
    if (signatureBytes.length != _signatureLength) {
      throw OlmPreKeyBundleFormatException(
        'Fallback imzasi $_signatureLength bayt olmali, '
        '${signatureBytes.length} bayt geldi',
      );
    }

    final verified = await _ed25519.verify(
      _decode('fallbackKey', fallbackKey),
      signature: Signature(
        signatureBytes,
        publicKey: SimplePublicKey(
          _decode('signingKey', signingKey),
          type: KeyPairType.ed25519,
        ),
      ),
    );
    if (!verified) {
      throw const OlmPreKeyBundleSignatureException(
        'Fallback anahtarinin imzasi peer imza anahtariyla dogrulanmadi',
      );
    }

    return OlmPreKeyBundle(
      identityKey: identityKey,
      signingKey: signingKey,
      oneTimeKey: fallbackKey,
    );
  }

  String _requireKey(Map<String, Object?> json, String field) {
    final value = json[field];
    if (value is! String || value.isEmpty) {
      throw OlmPreKeyBundleFormatException('Bundle alani eksik: $field');
    }
    _checkKeyBytes(field, value);
    return value;
  }

  void _checkKeyBytes(String field, String encoded) {
    final bytes = _decode(field, encoded);
    if (bytes.length == _keyLength) return;
    if (bytes.length == _keyLength + 1) {
      throw OlmPreKeyBundleFormatException(
        '$field 33 bayt geldi. Bu libsignal\'in tur onekli kodlamasi; '
        'sunucu hala eski bundle seklini donduruyor demektir. Oneki '
        'kirpmak YANLIS olur, cunku eski sekilde Ed25519 imza anahtari '
        'hic bulunmaz.',
      );
    }
    throw OlmPreKeyBundleFormatException(
      '$field $_keyLength bayt olmali, ${bytes.length} bayt geldi',
    );
  }

  Uint8List _decode(String field, String encoded) {
    try {
      return base64Decode(base64.normalize(encoded));
    } on FormatException {
      throw OlmPreKeyBundleFormatException(
        '$field gecerli base64 degil',
      );
    }
  }
}

/// Bundle beklenen sekilde degil.
class OlmPreKeyBundleFormatException implements Exception {
  const OlmPreKeyBundleFormatException(this.message);

  final String message;

  @override
  String toString() => 'OlmPreKeyBundleFormatException: $message';
}

/// Fallback anahtarinin imzasi dogrulanmadi.
class OlmPreKeyBundleSignatureException implements Exception {
  const OlmPreKeyBundleSignatureException(this.message);

  final String message;

  @override
  String toString() => 'OlmPreKeyBundleSignatureException: $message';
}

class _BundleUnauthorizedException implements Exception {
  const _BundleUnauthorizedException();

  @override
  String toString() => 'Prekey bundle fetch unauthorized (HTTP 401)';
}
