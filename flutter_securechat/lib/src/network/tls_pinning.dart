import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../config/app_config.dart';

class TlsPinException implements IOException {
  const TlsPinException(this.message);
  final String message;

  @override
  String toString() => 'TlsPinException: $message';
}

class TlsPinPolicy {
  TlsPinPolicy(Map<String, Iterable<String>> pinsByHost)
    : _pinsByHost = pinsByHost.map(
        (host, pins) => MapEntry(
          host.trim().toLowerCase(),
          pins.map(_normalizePin).where((pin) => pin.isNotEmpty).toSet(),
        ),
      ) {
    for (final entry in _pinsByHost.entries) {
      if (entry.key.isEmpty || entry.value.length < 2) {
        throw ArgumentError(
          'Her TLS hostu için birincil ve yedek SPKI pin gerekir.',
        );
      }
    }
  }

  factory TlsPinPolicy.fromConfig(AppConfig config) {
    config.validateNetworkSecurity();
    return TlsPinPolicy({config.certificatePinHost: config.certificatePins});
  }

  final Map<String, Set<String>> _pinsByHost;

  bool requiresPin(String host) => _pinsByHost.containsKey(host.toLowerCase());

  bool verifyCertificate(String host, X509Certificate certificate) =>
      verifyDer(host, certificate.der);

  bool verifyDer(String host, Uint8List certificateDer) {
    final expected = _pinsByHost[host.toLowerCase()];
    if (expected == null) return true;
    final spki = extractSubjectPublicKeyInfo(certificateDer);
    final actual = base64Encode(sha256.convert(spki).bytes);
    return expected.contains(actual);
  }

  static String _normalizePin(String pin) {
    final clean = pin.trim();
    return clean.startsWith('sha256/') ? clean.substring(7) : clean;
  }
}

class SecureHttpClientFactory {
  SecureHttpClientFactory(this.policy);

  final TlsPinPolicy policy;
  final Set<HttpClient> _clients = {};
  bool _closed = false;

  bool get isClosed => _closed;
  int get activeClientCount => _clients.length;

  HttpClient create() {
    if (_closed) {
      throw StateError('Secure HTTP client factory is closed');
    }
    final client = HttpClient();
    client.connectionFactory = _connect;
    _clients.add(client);
    return client;
  }

  void close({bool force = true}) {
    if (_closed) return;
    _closed = true;
    for (final client in _clients) {
      client.close(force: force);
    }
    _clients.clear();
  }

  Future<ConnectionTask<Socket>> _connect(
    Uri uri,
    String? proxyHost,
    int? proxyPort,
  ) async {
    if (proxyHost != null) {
      if (policy.requiresPin(uri.host)) {
        throw const TlsPinException(
          'Pin doğrulaması etkin bir TLS endpointi proxy üzerinden açılamaz.',
        );
      }
      return Socket.startConnect(proxyHost, proxyPort!);
    }
    final secure = uri.scheme == 'https' || uri.scheme == 'wss';
    if (!secure) return Socket.startConnect(uri.host, uri.port);
    final task = await SecureSocket.startConnect(
      uri.host,
      uri.port,
      onBadCertificate: (certificate) =>
          policy.requiresPin(uri.host) &&
          policy.verifyCertificate(uri.host, certificate),
    );
    final verified = task.socket.then<Socket>((socket) {
      final certificate = socket.peerCertificate;
      if (certificate == null ||
          !policy.verifyCertificate(uri.host, certificate)) {
        socket.destroy();
        throw TlsPinException('SPKI pini ${uri.host} için eşleşmedi.');
      }
      return socket;
    });
    return ConnectionTask.fromSocket(verified, task.cancel);
  }
}

Uint8List extractSubjectPublicKeyInfo(Uint8List certificateDer) {
  final certificate = _DerElement.read(certificateDer, 0);
  if (certificate.tag != 0x30 || certificate.end != certificateDer.length) {
    throw const FormatException('Geçersiz X.509 certificate sequence');
  }
  final certificateChildren = certificate.children(certificateDer);
  if (certificateChildren.isEmpty || certificateChildren.first.tag != 0x30) {
    throw const FormatException('X.509 TBSCertificate bulunamadı');
  }
  final tbs = certificateChildren.first.children(certificateDer);
  final hasVersion = tbs.isNotEmpty && tbs.first.tag == 0xa0;
  final spkiIndex = hasVersion ? 6 : 5;
  if (tbs.length <= spkiIndex || tbs[spkiIndex].tag != 0x30) {
    throw const FormatException('X.509 SubjectPublicKeyInfo bulunamadı');
  }
  final spki = tbs[spkiIndex];
  return Uint8List.fromList(certificateDer.sublist(spki.start, spki.end));
}

class _DerElement {
  const _DerElement({
    required this.tag,
    required this.start,
    required this.contentStart,
    required this.end,
  });

  final int tag;
  final int start;
  final int contentStart;
  final int end;

  static _DerElement read(Uint8List bytes, int offset) {
    if (offset < 0 || offset + 2 > bytes.length) {
      throw const FormatException('Eksik DER elementi');
    }
    final tag = bytes[offset];
    var cursor = offset + 1;
    final firstLength = bytes[cursor++];
    late final int length;
    if ((firstLength & 0x80) == 0) {
      length = firstLength;
    } else {
      final count = firstLength & 0x7f;
      if (count == 0 || count > 4 || cursor + count > bytes.length) {
        throw const FormatException('Geçersiz DER uzunluğu');
      }
      var decoded = 0;
      for (var i = 0; i < count; i++) {
        decoded = (decoded << 8) | bytes[cursor++];
      }
      length = decoded;
    }
    final end = cursor + length;
    if (end < cursor || end > bytes.length) {
      throw const FormatException('DER uzunluğu veri sınırını aşıyor');
    }
    return _DerElement(tag: tag, start: offset, contentStart: cursor, end: end);
  }

  List<_DerElement> children(Uint8List bytes) {
    final result = <_DerElement>[];
    var cursor = contentStart;
    while (cursor < end) {
      final child = read(bytes, cursor);
      if (child.end > end) {
        throw const FormatException('DER child parent sınırını aşıyor');
      }
      result.add(child);
      cursor = child.end;
    }
    if (cursor != end) throw const FormatException('Bozuk DER sequence');
    return result;
  }
}
