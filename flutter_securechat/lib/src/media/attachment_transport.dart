import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Sifreli eklerin sunucuya yuklenmesi ve indirilmesi.
///
/// Sunucu yalniz istemcide muhurlenmis baytlari ve rastgele kimligi gorur;
/// anahtar ve dosya bilgisi uctan uca sifreli isaretcide gider.
abstract interface class AttachmentTransport {
  /// Muhurlu dosyayi yukler; sunucunun verdigi kimligi dondurur.
  Future<String> upload(File sealed);

  /// Eki [target]'a indirir; [maxBytes]'tan buyukse vazgecer.
  Future<void> download(String id, File target, {required int maxBytes});
}

class AttachmentTransportException implements Exception {
  const AttachmentTransportException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  /// Sunucu bu yolu desteklemiyor ya da eki kabul etmiyor (eski sunucu,
  /// cok buyuk dosya). Gonderen eski parcali yola donebilir.
  bool get unsupported =>
      statusCode == HttpStatus.notFound ||
      statusCode == HttpStatus.methodNotAllowed ||
      statusCode == HttpStatus.requestEntityTooLarge ||
      statusCode == HttpStatus.lengthRequired;

  @override
  String toString() => 'AttachmentTransportException($statusCode): $message';
}

/// Uctan uca sifreli mesajin icinde giden ek isaretcisinin oneki.
///
/// Isaretci metin mesajlariyla ayni yoldan gider: sunucu alici onaylayana
/// kadar tutar, gonderen teslim makbuzu gelene kadar yeniden gonderir.
const blobPointerPrefix = 'BLOBPTR:v1:';

/// Ek kimligi: sunucunun urettigi 256 bitlik base64url deger.
bool isAttachmentId(String value) =>
    RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(value);

class HttpAttachmentTransport implements AttachmentTransport {
  HttpAttachmentTransport({
    required Uri baseUri,
    required HttpClient client,
    required Future<String?> Function() accessToken,
    Future<String?> Function()? refreshAccessToken,
  }) : _baseUri = baseUri,
       _client = client,
       _accessToken = accessToken,
       _refreshAccessToken = refreshAccessToken;

  final Uri _baseUri;
  final HttpClient _client;
  final Future<String?> Function() _accessToken;
  final Future<String?> Function()? _refreshAccessToken;

  static const _timeout = Duration(seconds: 30);

  @override
  Future<String> upload(File sealed) => _withAuth((token) async {
    final length = await sealed.length();
    final request = await _client
        .postUrl(_baseUri.resolve('/api/v1/attachments'))
        .timeout(_timeout);
    request.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
      ..contentType = ContentType.binary
      ..contentLength = length;
    await request.addStream(sealed.openRead());
    final response = await request.close().timeout(const Duration(minutes: 5));
    final body = await utf8.decoder.bind(response).join().timeout(_timeout);
    if (response.statusCode != HttpStatus.created) {
      throw AttachmentTransportException(
        'upload rejected',
        statusCode: response.statusCode,
      );
    }
    final id = (jsonDecode(body) as Map)['id'];
    if (id is! String || !isAttachmentId(id)) {
      throw const AttachmentTransportException('invalid upload response');
    }
    return id;
  });

  @override
  Future<void> download(String id, File target, {required int maxBytes}) {
    if (!isAttachmentId(id)) {
      throw const AttachmentTransportException('invalid attachment id');
    }
    return _withAuth((token) async {
      final request = await _client
          .getUrl(_baseUri.resolve('/api/v1/attachments/$id'))
          .timeout(_timeout);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      final response = await request.close().timeout(_timeout);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw AttachmentTransportException(
          'download rejected',
          statusCode: response.statusCode,
        );
      }
      if (response.contentLength > maxBytes) {
        await response.drain<void>();
        throw const AttachmentTransportException('attachment too large');
      }
      final partial = File('${target.path}.download');
      final sink = partial.openWrite();
      var received = 0;
      try {
        await for (final chunk in response.timeout(_timeout)) {
          received += chunk.length;
          if (received > maxBytes) {
            throw const AttachmentTransportException('attachment too large');
          }
          sink.add(chunk);
        }
        await sink.close();
      } catch (_) {
        await sink.close();
        if (await partial.exists()) await partial.delete();
        rethrow;
      }
      await partial.rename(target.path);
    });
  }

  /// Gecersiz erisim jetonunda bir kez yenileyip tekrar dener.
  Future<T> _withAuth<T>(Future<T> Function(String token) send) async {
    final token = await _accessToken();
    if (token == null || token.isEmpty) {
      throw const AttachmentTransportException('not signed in');
    }
    try {
      return await send(token);
    } on AttachmentTransportException catch (error) {
      final refresh = _refreshAccessToken;
      if (error.statusCode != HttpStatus.unauthorized || refresh == null) {
        rethrow;
      }
      final renewed = await refresh();
      if (renewed == null || renewed.isEmpty) rethrow;
      return send(renewed);
    }
  }
}
