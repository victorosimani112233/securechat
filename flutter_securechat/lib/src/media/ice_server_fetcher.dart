import 'dart:convert';
import 'dart:io';

import 'call_models.dart';

typedef MediaAccessTokenProvider = Future<String?> Function();

abstract interface class IceServerProvider {
  Future<List<IceServerConfig>> fetch();
}

class HttpIceServerProvider implements IceServerProvider {
  HttpIceServerProvider({
    required this.apiBaseUrl,
    required this.accessTokenProvider,
    this.fallbackStunUrl = 'stun:stun.l.google.com:19302',
    HttpClient? client,
  }) : _client = client ?? HttpClient();

  final String apiBaseUrl;
  final MediaAccessTokenProvider accessTokenProvider;
  final String fallbackStunUrl;
  final HttpClient _client;

  @override
  Future<List<IceServerConfig>> fetch() async {
    try {
      final token = await accessTokenProvider();
      if (token == null || token.isEmpty) return _fallback;
      final base = Uri.parse(apiBaseUrl);
      final uri = base.replace(path: _joinPath(base.path, 'api/v1/ice/config'));
      final request = await _client.getUrl(uri);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode != HttpStatus.ok) return _fallback;
      final json = jsonDecode(body) as Map<String, Object?>;
      final values = json['iceServers'];
      if (values is! List) return _fallback;
      final servers = values
          .whereType<Map>()
          .map((raw) {
            final map = raw.cast<String, Object?>();
            final urlsValue = map['urls'];
            final urls = urlsValue is List
                ? urlsValue.whereType<String>().toList(growable: false)
                : [if (urlsValue is String) urlsValue];
            return IceServerConfig(
              urls: urls,
              username: map['username'] as String?,
              credential: map['credential'] as String?,
            );
          })
          .where((server) => server.urls.isNotEmpty)
          .toList(growable: false);
      return servers.isEmpty ? _fallback : servers;
    } catch (_) {
      return _fallback;
    }
  }

  List<IceServerConfig> get _fallback => [
    IceServerConfig(urls: [fallbackStunUrl]),
  ];

  static String _joinPath(String base, String child) =>
      '${base.replaceAll(RegExp(r'/+$'), '')}/${child.replaceAll(RegExp(r'^/+'), '')}';
}

class StaticIceServerProvider implements IceServerProvider {
  const StaticIceServerProvider(this.servers);
  final List<IceServerConfig> servers;

  @override
  Future<List<IceServerConfig>> fetch() async => servers;
}
