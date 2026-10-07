import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/crypto/vodozemac/olm_pre_key_bundle_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// 32 baytlik sahte bir acik anahtar.
String _key(int seed) =>
    base64Encode(List<int>.generate(32, (index) => (seed + index) & 0xFF));

/// libsignal'in tur onekli 33 baytlik kodlamasi.
String _prefixedKey(int seed) => base64Encode([
  0x05,
  ...List<int>.generate(32, (index) => (seed + index) & 0xFF),
]);

void main() {
  // Provider yalniz ayristirma ve dogrulama icin kuruluyor; HTTP tasimasi
  // bu testlerde kullanilmiyor, bu yuzden token saglayici bos.
  late HttpOlmPreKeyBundleProvider provider;

  setUp(() {
    provider = HttpOlmPreKeyBundleProvider(
      apiBaseUrl: Uri.parse('https://example.invalid'),
      httpClient: HttpClient(),
      accessTokenProvider: () async => null,
    );
  });

  String body(Map<String, Object?> fields) => jsonEncode({
    'protocolVersion': HttpOlmPreKeyBundleProvider.expectedProtocolVersion,
    ...fields,
  });

  group('tek kullanimlik anahtar', () {
    test('gecerli bundle ayristirilir', () async {
      final bundle = await provider.parseBundle(
        body({
          'identityKey': _key(1),
          'signingKey': _key(2),
          'oneTimeKey': _key(3),
        }),
      );

      expect(bundle, isNotNull);
      expect(bundle!.identityKey, _key(1));
      expect(bundle.signingKey, _key(2));
      expect(bundle.oneTimeKey, _key(3));
    });

    test('kimlik baytlari Ed25519 ve Curve25519 anahtarlarini '
        'BIRLIKTE tasir', () async {
      final bundle = await provider.parseBundle(
        body({
          'identityKey': _key(1),
          'signingKey': _key(2),
          'oneTimeKey': _key(3),
        }),
      );

      // 64 bayt: once imza anahtari, sonra kimlik anahtari. Yalniz birini
      // pinlemek digerini degistirilebilir birakirdi.
      expect(bundle!.identityBytes, hasLength(64));
      expect(
        bundle.identityBytes.sublist(0, 32),
        base64Decode(_key(2)),
      );
      expect(bundle.identityBytes.sublist(32), base64Decode(_key(1)));
    });
  });

  group('sekil dogrulamasi', () {
    test('farkli protokol surumu reddedilir', () async {
      await expectLater(
        provider.parseBundle(
          jsonEncode({
            'protocolVersion': 2,
            'identityKey': _key(1),
            'signingKey': _key(2),
            'oneTimeKey': _key(3),
          }),
        ),
        throwsA(isA<OlmPreKeyBundleFormatException>()),
      );
    });

    test('protokol surumu hic yoksa reddedilir', () async {
      await expectLater(
        provider.parseBundle(
          jsonEncode({
            'identityKey': _key(1),
            'signingKey': _key(2),
            'oneTimeKey': _key(3),
          }),
        ),
        throwsA(isA<OlmPreKeyBundleFormatException>()),
      );
    });

    test('imza anahtari eksikse reddedilir', () async {
      // Bu goc sirasindaki en olasi hata: eski sunucu Ed25519 imza
      // anahtarini hic dondurmez.
      await expectLater(
        provider.parseBundle(
          body({'identityKey': _key(1), 'oneTimeKey': _key(3)}),
        ),
        throwsA(
          isA<OlmPreKeyBundleFormatException>().having(
            (error) => error.message,
            'message',
            contains('signingKey'),
          ),
        ),
      );
    });

    test('33 baytlik libsignal onekli anahtar ayri ve anlasilir bir hata '
        'verir', () async {
      // Oneki sessizce kirpmak YANLIS olurdu: eski sekilde imza anahtari
      // zaten yok, yani kirpilmis anahtarla kurulan oturum cozulemeyen
      // mesaj uretir. Hata sunucunun hala eski sekli dondurdugunu soylemeli.
      await expectLater(
        provider.parseBundle(
          body({
            'identityKey': _prefixedKey(1),
            'signingKey': _key(2),
            'oneTimeKey': _key(3),
          }),
        ),
        throwsA(
          isA<OlmPreKeyBundleFormatException>().having(
            (error) => error.message,
            'message',
            allOf(contains('33 bayt'), contains('libsignal')),
          ),
        ),
      );
    });

    test('yanlis uzunlukta anahtar reddedilir', () async {
      await expectLater(
        provider.parseBundle(
          body({
            'identityKey': base64Encode(List.filled(16, 7)),
            'signingKey': _key(2),
            'oneTimeKey': _key(3),
          }),
        ),
        throwsA(isA<OlmPreKeyBundleFormatException>()),
      );
    });

    test('gecersiz base64 reddedilir', () async {
      await expectLater(
        provider.parseBundle(
          body({
            'identityKey': 'bu base64 degil!!',
            'signingKey': _key(2),
            'oneTimeKey': _key(3),
          }),
        ),
        throwsA(isA<OlmPreKeyBundleFormatException>()),
      );
    });

    test('govde JSON degilse reddedilir', () async {
      await expectLater(
        provider.parseBundle('<html>bir hata sayfasi</html>'),
        throwsA(isA<OlmPreKeyBundleFormatException>()),
      );
    });

    test('govde JSON nesnesi degilse reddedilir', () async {
      await expectLater(
        provider.parseBundle('[1, 2, 3]'),
        throwsA(isA<OlmPreKeyBundleFormatException>()),
      );
    });
  });

  group('fallback anahtari', () {
    late SimpleKeyPair signingPair;
    late String signingKeyBase64;
    final ed25519 = Ed25519();

    setUp(() async {
      signingPair = await ed25519.newKeyPair();
      final publicKey = await signingPair.extractPublicKey();
      signingKeyBase64 = base64Encode(publicKey.bytes);
    });

    Future<String> sign(String keyBase64) async {
      final signature = await ed25519.sign(
        base64Decode(keyBase64),
        keyPair: signingPair,
      );
      return base64Encode(signature.bytes);
    }

    test('tek kullanimlik anahtar yoksa imzali fallback kullanilir', () async {
      // Bu yol OLMASA, havuz bosken bundle bos donerdi ve gonderen hic
      // oturum kuramazdi — "No valid sessions" dongusunun sinifi tam budur.
      final fallback = _key(9);
      final bundle = await provider.parseBundle(
        body({
          'identityKey': _key(1),
          'signingKey': signingKeyBase64,
          'fallbackKey': fallback,
          'fallbackKeySignature': await sign(fallback),
        }),
      );

      expect(bundle, isNotNull);
      expect(bundle!.oneTimeKey, fallback);
    });

    test('tek kullanimlik anahtar varsa fallback kullanilmaz', () async {
      final bundle = await provider.parseBundle(
        body({
          'identityKey': _key(1),
          'signingKey': signingKeyBase64,
          'oneTimeKey': _key(3),
          'fallbackKey': _key(9),
          'fallbackKeySignature': await sign(_key(9)),
        }),
      );

      expect(bundle!.oneTimeKey, _key(3));
    });

    test('imzasiz fallback REDDEDILIR', () async {
      // Imzasiz fallback bir MITM araci degil — sunucu alicinin kimlik
      // ozel anahtarina sahip olmadigi icin mesaji okuyamaz. Ama alici da
      // cozemez: sessiz ve kalici teslim reddi. Sahada en pahali hata.
      await expectLater(
        provider.parseBundle(
          body({
            'identityKey': _key(1),
            'signingKey': signingKeyBase64,
            'fallbackKey': _key(9),
          }),
        ),
        throwsA(
          isA<OlmPreKeyBundleFormatException>().having(
            (error) => error.message,
            'message',
            contains('imzasiz'),
          ),
        ),
      );
    });

    test('baska bir anahtarla imzalanmis fallback REDDEDILIR', () async {
      final impostor = await ed25519.newKeyPair();
      final fallback = _key(9);
      final forged = await ed25519.sign(
        base64Decode(fallback),
        keyPair: impostor,
      );

      await expectLater(
        provider.parseBundle(
          body({
            'identityKey': _key(1),
            'signingKey': signingKeyBase64,
            'fallbackKey': fallback,
            'fallbackKeySignature': base64Encode(forged.bytes),
          }),
        ),
        throwsA(isA<OlmPreKeyBundleSignatureException>()),
      );
    });

    test('baska bir anahtar icin uretilmis gecerli imza REDDEDILIR', () async {
      // Imza dogru anahtarla atilmis ama BASKA bir fallback anahtari icin.
      // Yeniden oynatma: sunucu eski bir imzayi yeni bir anahtarla
      // eslestirmeye calisirsa yakalanmali.
      await expectLater(
        provider.parseBundle(
          body({
            'identityKey': _key(1),
            'signingKey': signingKeyBase64,
            'fallbackKey': _key(9),
            'fallbackKeySignature': await sign(_key(42)),
          }),
        ),
        throwsA(isA<OlmPreKeyBundleSignatureException>()),
      );
    });

    test('yanlis uzunlukta imza reddedilir', () async {
      await expectLater(
        provider.parseBundle(
          body({
            'identityKey': _key(1),
            'signingKey': signingKeyBase64,
            'fallbackKey': _key(9),
            'fallbackKeySignature': base64Encode(List.filled(32, 1)),
          }),
        ),
        throwsA(isA<OlmPreKeyBundleFormatException>()),
      );
    });
  });

  test('hicbir anahtar yoksa null doner', () async {
    // Hata degil: karsi taraf henuz anahtar yuklememis olabilir. Cagiran
    // bunu "oturum kurulamaz" olarak ele alir.
    final bundle = await provider.parseBundle(
      body({'identityKey': _key(1), 'signingKey': _key(2)}),
    );

    expect(bundle, isNull);
  });

  group('HTTP tasimasi', () {
    late HttpServer server;
    late Uri baseUrl;
    late List<String?> seenTokens;
    late int Function() statusFor;
    late String Function() bodyFor;

    setUp(() async {
      seenTokens = [];
      statusFor = () => HttpStatus.ok;
      bodyFor = () => jsonEncode({
        'protocolVersion':
            HttpOlmPreKeyBundleProvider.expectedProtocolVersion,
        'identityKey': _key(1),
        'signingKey': _key(2),
        'oneTimeKey': _key(3),
      });
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      baseUrl = Uri.parse('http://127.0.0.1:${server.port}');
      server.listen((request) async {
        seenTokens.add(request.headers.value(HttpHeaders.authorizationHeader));
        request.response.statusCode = statusFor();
        request.response.write(bodyFor());
        await request.response.close();
      });
    });

    tearDown(() async => server.close(force: true));

    HttpOlmPreKeyBundleProvider build({
      Future<String?> Function()? refresh,
      String? token = 'ilk-token',
    }) => HttpOlmPreKeyBundleProvider(
      apiBaseUrl: baseUrl,
      httpClient: HttpClient(),
      accessTokenProvider: () async => token,
      refreshAccessToken: refresh,
    );

    test('200 bundle dondurur ve token basligi gonderilir', () async {
      final bundle = await build().fetch('peer-1');

      expect(bundle!.oneTimeKey, _key(3));
      expect(seenTokens, ['Bearer ilk-token']);
    });

    test('404 null dondurur', () async {
      statusFor = () => HttpStatus.notFound;

      expect(await build().fetch('peer-1'), isNull);
    });

    test('401 token yenilenip BIR KEZ tekrar denenir', () async {
      // Arka plan isolate'i 1 saatlik access token ile 15 dakikada bir
      // uyaniyor; yenileme yolu olmadan token bayatladiginda prekey
      // cekimi sessizce olurdu.
      var attempt = 0;
      statusFor = () => ++attempt == 1 ? HttpStatus.unauthorized : HttpStatus.ok;

      final bundle = await build(refresh: () async => 'yeni-token').fetch('p');

      expect(bundle!.oneTimeKey, _key(3));
      expect(seenTokens, ['Bearer ilk-token', 'Bearer yeni-token']);
    });

    test('401 ve yenileme yolu yoksa hata yukselir', () async {
      statusFor = () => HttpStatus.unauthorized;

      await expectLater(build().fetch('peer-1'), throwsA(isA<Exception>()));
      expect(seenTokens, hasLength(1));
    });

    test('401 surerse ikinci kez denenmez', () async {
      // Sonsuz yenileme dongusu olmamali.
      statusFor = () => HttpStatus.unauthorized;

      await expectLater(
        build(refresh: () async => 'yeni-token').fetch('peer-1'),
        throwsA(isA<Exception>()),
      );
      expect(seenTokens, ['Bearer ilk-token', 'Bearer yeni-token']);
    });

    test('500 HttpException yukseltir', () async {
      statusFor = () => HttpStatus.internalServerError;

      await expectLater(
        build().fetch('peer-1'),
        throwsA(isA<HttpException>()),
      );
    });
  });
}
