import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_securechat/src/network/pinned_web_socket.dart';
import 'package:flutter_securechat/src/network/tls_pinning.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pinlenmis WebSocket baglantisi.
///
/// Bu dosyanin varlik sebebi olculmus bir hata: pinleme
/// `HttpClient.connectionFactory` ile yapiliyordu ve o yol WebSocket
/// yukseltmesiyle uyusmuyor. Ayni pinlenmis istemciyle HTTPS 200 donerken
/// WebSocket sessizce zaman asimina dusuyor ve sunucu istegi hic gormuyordu.
/// Testler hem baglantinin kuruldugunu hem de pinin GERCEKTEN zorlandigini
/// olcuyor; ikincisi olmadan ilki guvenlik acisindan anlamsiz olurdu.
void main() {
  final certificate = File('qa/mock/tls/primary.cert.pem');
  final privateKey = File('qa/mock/tls/primary.key.pem');
  if (!certificate.existsSync() || !privateKey.existsSync()) {
    test('pinlenmis WebSocket (atlandi: mock TLS sertifikasi yok)', () {
      markTestSkipped('qa/mock/tls altinda sertifika bulunamadi');
    }, skip: true);
    return;
  }

  late HttpServer server;
  late Uri wsUri;
  late String correctPin;

  // Sunucunun 101'den HEMEN sonra gonderecegi cerceve; bos birakilirsa
  // gondermez.
  late String immediateFrame;
  late int Function() statusFor;

  setUp(() async {
    immediateFrame = '';
    statusFor = () => 101;
    final context = SecurityContext()
      ..useCertificateChain(certificate.path)
      ..usePrivateKey(privateKey.path);
    server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      context,
    );
    wsUri = Uri.parse('wss://127.0.0.1:${server.port}/ws?userId=test');
    correctPin = base64Encode(
      sha256
          .convert(
            extractSubjectPublicKeyInfo(_firstCertificateDer(certificate)),
          )
          .bytes,
    );
    server.listen((request) async {
      if (statusFor() != 101) {
        request.response.statusCode = statusFor();
        await request.response.close();
        return;
      }
      final socket = await WebSocketTransformer.upgrade(request);
      if (immediateFrame.isNotEmpty) socket.add(immediateFrame);
    });
    addTearDown(() => server.close(force: true));
  });

  PinnedWebSocketConnector connectorWith(List<String> pins) =>
      PinnedWebSocketConnector(TlsPinPolicy({'127.0.0.1': pins}));

  test('dogru pin ile baglanti kurulur', () async {
    final socket = await connectorWith([
      correctPin,
      _otherPin,
    ]).connect(wsUri, headers: {'Authorization': 'Bearer t'});

    expect(socket.readyState, WebSocket.open);
    await socket.close();
  });

  test('yanlis pin REDDEDILIR', () async {
    // Bu testin olmamasi, baglantinin kurulmasini "calisiyor" saymak
    // olurdu; pin zorlanmiyorsa pinleme yok demektir.
    await expectLater(
      connectorWith([_otherPin, _anotherPin]).connect(wsUri),
      throwsA(isA<HandshakeException>()),
    );
  });

  test('yedek pin de kabul edilir', () async {
    // Anahtar donusunun calisabilmesi icin yedek pin gercekten gecerli
    // olmali; yalniz birincil pin kabul edilseydi donus her kurulumu
    // koparirdi.
    final socket = await connectorWith([
      _otherPin,
      correctPin,
    ]).connect(wsUri);

    expect(socket.readyState, WebSocket.open);
    await socket.close();
  });

  test('101 sonrasi HEMEN gelen cerceve kaybolmaz', () async {
    // El sikisma basligindan sonra ayni TCP okumasinda gelen baytlar
    // atilirsa, sunucunun hemen gonderdigi cerceve (ornegin gecersiz token
    // icin kapatma) kaybolur ve baglanti sebepsiz sessiz kalir.
    immediateFrame = 'ilk-cerceve';

    final socket = await connectorWith([correctPin, _otherPin]).connect(wsUri);

    expect(await socket.first, 'ilk-cerceve');
    await socket.close();
  });

  test('101 disinda bir cevap reddedilir', () async {
    statusFor = () => 403;

    await expectLater(
      connectorWith([correctPin, _otherPin]).connect(wsUri),
      throwsA(isA<WebSocketException>()),
    );
  });

  test('pin gerektiren host icin sifresiz ws reddedilir', () async {
    // Pinli bir endpointe sifresiz baglanmak pinlemeyi tumuyle atlardi.
    await expectLater(
      connectorWith([correctPin, _otherPin]).connect(
        Uri.parse('ws://127.0.0.1:${server.port}/ws'),
      ),
      throwsA(isA<TlsPinException>()),
    );
  });

  test('baslik degerine satir sonu sizdirilamaz', () async {
    // CRLF tasiyan bir deger isteğe yeni baslik ya da govde ekleyebilirdi.
    await expectLater(
      connectorWith([correctPin, _otherPin]).connect(
        wsUri,
        headers: {'X-Test': 'deger\r\nX-Enjekte: evet'},
      ),
      throwsA(isA<WebSocketException>()),
    );
  });
}

const _otherPin = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
const _anotherPin = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=';

/// PEM zincirinden ilk sertifikanin DER baytlari.
Uint8List _firstCertificateDer(File pem) {
  final text = pem.readAsStringSync();
  final begin = text.indexOf('-----BEGIN CERTIFICATE-----');
  final end = text.indexOf('-----END CERTIFICATE-----');
  final body = text
      .substring(begin + '-----BEGIN CERTIFICATE-----'.length, end)
      .replaceAll(RegExp(r'\s'), '');
  return Uint8List.fromList(base64Decode(body));
}
