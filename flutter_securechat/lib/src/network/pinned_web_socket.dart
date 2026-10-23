import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'tls_pinning.dart';

/// SPKI pinlemesi uygulanmis bir WebSocket baglantisi acar.
///
/// **Neden `HttpClient` kullanilmiyor.** Pinleme `HttpClient.connectionFactory`
/// ile yapiliyor ve bu, WebSocket yukseltmesiyle UYUSMUYOR: `WebSocket.connect`
/// yukseltmeden sonra ham sokete `detachSocket()` ile el koyuyor ve
/// `connectionFactory`'den gelen baglantida bu yol sessizce asili kaliyor.
/// Olculdu: ayni pinlenmis istemciyle HTTPS `/health` 200 donerken WebSocket
/// 8 saniyede zaman asimina dusuyor, sunucu istegi hic gormuyor. Pinleme
/// bicimini degistirmek (bos guven deposu, `.then()` sarmalayicisini
/// kaldirmak) sonucu degistirmedi; uyusmazlik `connectionFactory`'nin
/// kendisinde.
///
/// **Neden `badCertificateCallback` kullanilmiyor.** Kolay cozum o olurdu ama
/// sessiz bir guvenlik gerilemesi: o geri cagri yalniz sertifika BASKA bir
/// sebeple gecersizken tetiklenir. Sunucu bugun kendinden imzali oldugu icin
/// calisiyor gorunur, CA imzali gercek bir sertifikaya gecildigi gun geri
/// cagri hic calismaz ve pinleme sessizce devre disi kalir.
///
/// Burada guven tamamen pine dayanir: `SecurityContext(withTrustedRoots:
/// false)` ile hicbir kok sertifika guvenilmez, dolayisiyla [onBadCertificate]
/// HER ZAMAN calisir ve tek otorite pin olur. CA deposunun durumu sonucu
/// degistiremez.
class PinnedWebSocketConnector {
  PinnedWebSocketConnector(this.policy, {Random? random})
    : _random = random ?? Random.secure();

  final TlsPinPolicy policy;
  final Random _random;

  /// RFC 6455 el sikisma sabiti.
  static const _handshakeGuid = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

  /// El sikisma basliklarinin ust siniri.
  ///
  /// Sinirsiz okumak, cevabi hic bitirmeyen bir karsi tarafin belleği
  /// tuketmesine izin verirdi.
  static const _maxHandshakeBytes = 16 * 1024;

  Future<WebSocket> connect(
    Uri uri, {
    Map<String, Object> headers = const {},
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final secure = uri.scheme == 'wss' || uri.scheme == 'https';
    if (!secure && policy.requiresPin(uri.host)) {
      throw TlsPinException(
        'Pin gerektiren ${uri.host} icin sifresiz WebSocket acilamaz.',
      );
    }
    if (secure && !policy.requiresPin(uri.host)) {
      // Kok deposu bos oldugu icin guven yalniz pinden gelir. Pin tanimsiz
      // bir hostta `verifyDer` her sertifikayi kabul eder; baglanti kurulsa
      // CA dogrulamasi da olmayacagi icin araya giren herkes kabul edilirdi.
      // HTTP yolu bu hostlari CA ile dogrular; WebSocket yolu hic acmaz.
      throw TlsPinException(
        'Pin tanimsiz ${uri.host} icin guvenli WebSocket acilamaz.',
      );
    }
    final port = uri.hasPort ? uri.port : (secure ? 443 : 80);

    final socket = secure
        ? await SecureSocket.connect(
            uri.host,
            port,
            // Kok sertifika deposu BILEREK bos: guven yalniz pinden gelir.
            context: SecurityContext(withTrustedRoots: false),
            onBadCertificate: (certificate) =>
                policy.verifyCertificate(uri.host, certificate),
            timeout: timeout,
          )
        : await Socket.connect(uri.host, port, timeout: timeout);

    try {
      final key = base64Encode(
        List<int>.generate(16, (_) => _random.nextInt(256)),
      );
      socket.add(utf8.encode(_request(uri, port, key, headers)));
      await socket.flush();

      // Soket akisi TEK ABONELI. El sikismayi okumak icin ayri bir
      // dinleyici acip sonra WebSocket'e devretmek "Stream has already been
      // listened to" ile patliyor; bu yuzden tek bir abonelik acilip
      // duraklatilarak devrediliyor.
      final subscription = socket.listen(null);
      final leftover = await _readHandshake(subscription, key).timeout(timeout);
      return WebSocket.fromUpgradedSocket(
        _UpgradedSocket(socket, subscription, leftover),
        serverSide: false,
      );
    } catch (_) {
      socket.destroy();
      rethrow;
    }
  }

  String _request(Uri uri, int port, String key, Map<String, Object> headers) {
    final path = uri.path.isEmpty ? '/' : uri.path;
    final target = uri.hasQuery ? '$path?${uri.query}' : path;
    final defaultPort = uri.scheme == 'wss' || uri.scheme == 'https' ? 443 : 80;
    final host = port == defaultPort ? uri.host : '${uri.host}:$port';
    final buffer = StringBuffer()
      ..write('GET $target HTTP/1.1\r\n')
      ..write('Host: $host\r\n')
      ..write('Upgrade: websocket\r\n')
      ..write('Connection: Upgrade\r\n')
      ..write('Sec-WebSocket-Key: $key\r\n')
      ..write('Sec-WebSocket-Version: 13\r\n');
    for (final entry in headers.entries) {
      // Baslik enjeksiyonu: bir deger CRLF tasirsa istege yeni bir baslik
      // ya da govde eklenebilirdi.
      final value = entry.value.toString();
      if (entry.key.contains(RegExp(r'[\r\n]')) ||
          value.contains(RegExp(r'[\r\n]'))) {
        throw const WebSocketException('Baslikta satir sonu tasinamaz');
      }
      buffer.write('${entry.key}: $value\r\n');
    }
    return (buffer..write('\r\n')).toString();
  }

  /// El sikisma cevabini dogrular ve basliktan SONRA gelen baytlari dondurur.
  ///
  /// Artan baytlar atilmamali: sunucu 101'in hemen ardindan bir cerceve
  /// gonderebilir (ornegin gecersiz token icin kapatma) ve o cerceve
  /// kaybedilirse baglanti sebepsiz sessiz kalir.
  Future<Uint8List> _readHandshake(
    StreamSubscription<Uint8List> subscription,
    String key,
  ) {
    final completer = Completer<Uint8List>();
    final buffer = BytesBuilder(copy: false);

    void fail(Object error) {
      if (!completer.isCompleted) completer.completeError(error);
    }

    subscription
      ..onData((chunk) {
        if (completer.isCompleted) return;
        buffer.add(chunk);
        final collected = buffer.toBytes();
        if (collected.length > _maxHandshakeBytes) {
          fail(const WebSocketException('El sikisma basliklari cok buyuk'));
          return;
        }
        final headerEnd = _indexOfHeaderEnd(collected);
        if (headerEnd < 0) return;
        try {
          _verify(
            utf8.decode(collected.sublist(0, headerEnd), allowMalformed: true),
            key,
          );
        } catch (error) {
          fail(error);
          return;
        }
        // Duraklat: kalan akis WebSocket'e devredilecek.
        subscription.pause();
        // Basliktan SONRA gelen baytlar atilamaz; sunucu 101'in hemen
        // ardindan bir cerceve gonderebilir (ornegin gecersiz token icin
        // kapatma) ve o cerceve kaybolursa baglanti sebepsiz sessiz kalir.
        completer.complete(Uint8List.sublistView(collected, headerEnd + 4));
      })
      ..onError(fail)
      ..onDone(() {
        fail(
          const WebSocketException(
            'Sunucu el sikismayi tamamlamadan baglantiyi kapatti',
          ),
        );
      });

    return completer.future;
  }

  static int _indexOfHeaderEnd(Uint8List bytes) {
    for (var i = 0; i + 3 < bytes.length; i++) {
      if (bytes[i] == 13 &&
          bytes[i + 1] == 10 &&
          bytes[i + 2] == 13 &&
          bytes[i + 3] == 10) {
        return i;
      }
    }
    return -1;
  }

  void _verify(String header, String key) {
    final lines = header.split('\r\n');
    final status = lines.isEmpty ? '' : lines.first;
    if (!status.contains(' 101')) {
      throw WebSocketException('Yukseltme reddedildi: $status');
    }
    String? accept;
    var upgrade = false;
    var connection = false;
    for (final line in lines.skip(1)) {
      final separator = line.indexOf(':');
      if (separator < 0) continue;
      final name = line.substring(0, separator).trim().toLowerCase();
      final value = line.substring(separator + 1).trim();
      switch (name) {
        case 'sec-websocket-accept':
          accept = value;
        case 'upgrade':
          upgrade = value.toLowerCase() == 'websocket';
        case 'connection':
          connection = value.toLowerCase().contains('upgrade');
      }
    }
    if (!upgrade || !connection) {
      throw const WebSocketException('Yukseltme basliklari eksik');
    }
    // Accept dogrulamasi, cevabin istegimize ait oldugunu kanitlar; onsuz
    // onbellege alinmis ya da baska bir istege ait bir 101 kabul edilirdi.
    final expected = base64Encode(
      sha1.convert(utf8.encode('$key$_handshakeGuid')).bytes,
    );
    if (accept != expected) {
      throw const WebSocketException('Sec-WebSocket-Accept eslesmedi');
    }
  }
}

/// El sikismadan artan baytlari one ekleyip var olan abonelige devreden
/// soket sarmalayicisi.
///
/// Soket akisi tek aboneli oldugu icin el sikismayi okuyan abonelik
/// kapatilip yenisi acilamaz; duraklatilan abonelik burada devralinir.
class _UpgradedSocket extends Stream<Uint8List> implements Socket {
  _UpgradedSocket(this._inner, this._subscription, this._prefix);

  final Socket _inner;
  final StreamSubscription<Uint8List> _subscription;
  final Uint8List _prefix;

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final controller = StreamController<Uint8List>();
    controller.onCancel = _subscription.cancel;
    _subscription
      ..onData(controller.add)
      ..onError(controller.addError)
      ..onDone(controller.close);
    if (_prefix.isNotEmpty) controller.add(_prefix);
    // Dinleyici baglandiktan SONRA devam ettirilir; once devam ettirmek
    // artan baytlardan onceki veriyi kaybettirebilirdi.
    scheduleMicrotask(_subscription.resume);
    return controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  Encoding get encoding => _inner.encoding;
  @override
  set encoding(Encoding value) => _inner.encoding = value;
  @override
  void add(List<int> data) => _inner.add(data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _inner.addError(error, stackTrace);
  @override
  Future<void> addStream(Stream<List<int>> stream) => _inner.addStream(stream);
  @override
  Future<void> close() => _inner.close();
  @override
  Future<void> get done => _inner.done;
  @override
  Future<void> flush() => _inner.flush();
  @override
  void write(Object? object) => _inner.write(object);
  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      _inner.writeAll(objects, separator);
  @override
  void writeCharCode(int charCode) => _inner.writeCharCode(charCode);
  @override
  void writeln([Object? object = '']) => _inner.writeln(object);
  @override
  void destroy() => _inner.destroy();
  @override
  Uint8List getRawOption(RawSocketOption option) => _inner.getRawOption(option);
  @override
  bool setOption(SocketOption option, bool enabled) =>
      _inner.setOption(option, enabled);
  @override
  void setRawOption(RawSocketOption option) => _inner.setRawOption(option);
  @override
  InternetAddress get address => _inner.address;
  @override
  int get port => _inner.port;
  @override
  InternetAddress get remoteAddress => _inner.remoteAddress;
  @override
  int get remotePort => _inner.remotePort;
}
