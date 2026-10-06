import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'pre_key_manager.dart';

typedef AccessTokenProvider = Future<String?> Function();

/// Yenileme sirasinda olusan hatayi cagirana bildirir.
///
/// Onceki surumde butun hatalar sessizce yutuluyordu; sunucu tarafinda havuz
/// tukenirken istemcide hicbir iz kalmiyordu.
typedef PreKeyMaintenanceFailureReporter =
    void Function(String operation, Object error, StackTrace stackTrace);

/// Access token suresi dolmus; cagiran yenileyip tekrar denemeli.
class _PreKeyUnauthorizedException implements Exception {
  const _PreKeyUnauthorizedException(this.operation);

  final String operation;

  @override
  String toString() => 'Prekey $operation unauthorized (HTTP 401)';
}

/// Keeps the server-side one-time Signal prekey pool populated.
///
/// This is the Flutter counterpart of Kotlin `PreKeyUploader` and uses the
/// exact `/api/v1/prekeys/refresh` list payload expected by Ktor.
class PreKeyMaintenanceService {
  PreKeyMaintenanceService({
    required PreKeyManager manager,
    required Uri apiBaseUrl,
    required HttpClient httpClient,
    required AccessTokenProvider accessTokenProvider,
    AccessTokenProvider? refreshAccessToken,
    PreKeyMaintenanceFailureReporter? onFailure,
  }) : _manager = manager,
       _apiBaseUrl = apiBaseUrl,
       _httpClient = httpClient,
       _accessTokenProvider = accessTokenProvider,
       _refreshAccessToken = refreshAccessToken,
       _onFailure = onFailure;

  final PreKeyManager _manager;
  final Uri _apiBaseUrl;
  final HttpClient _httpClient;
  final AccessTokenProvider _accessTokenProvider;
  final AccessTokenProvider? _refreshAccessToken;
  final PreKeyMaintenanceFailureReporter? _onFailure;
  Future<bool>? _activeRefresh;

  Future<bool> replenishIfNeeded() {
    final active = _activeRefresh;
    if (active != null) return active;
    final operation = _replenish();
    _activeRefresh = operation;
    return operation.whenComplete(() {
      if (identical(_activeRefresh, operation)) _activeRefresh = null;
    });
  }

  Future<bool> _replenish() async {
    var token = await _accessTokenProvider();
    if (token == null || token.isEmpty) return false;
    List<int>? generatedKeyIds;
    try {
      int serverRemaining;
      try {
        serverRemaining = await _loadServerRemaining(token);
      } on _PreKeyUnauthorizedException {
        // Access token TTL'i bir saat; background isolate 15 dakikada bir
        // kosuyor ve cihaz bir saatten uzun arka planda kalirsa saklanan
        // token olmus olur. Bir kez yenileyip tekrar denemek, yenilemenin
        // olmadigi durumda sessiz basarisizliga dusen tek yoldu.
        final refreshed = await _refreshAccessToken?.call();
        if (refreshed == null || refreshed.isEmpty) rethrow;
        token = refreshed;
        serverRemaining = await _loadServerRemaining(token);
      }
      final batch = await _manager.buildSerializedReplenishBatch(
        serverRemaining: serverRemaining,
      );
      if (batch == null) return true;
      generatedKeyIds = batch.map((key) => key.keyId).toList(growable: false);
      await _uploadBatch(batch, token);
      return true;
    } catch (error, stackTrace) {
      if (generatedKeyIds != null) {
        await _manager.discardOneTimePreKeys(generatedKeyIds);
      }
      _onFailure?.call('replenish', error, stackTrace);
      return false;
    }
  }

  Future<void> _uploadBatch(
    List<SerializedOneTimePreKey> batch,
    String token,
  ) async {
    final request = await _httpClient
        .postUrl(_apiBaseUrl.resolve('/api/v1/prekeys/refresh'))
        .timeout(const Duration(seconds: 20));
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    request.write(jsonEncode(batch.map((key) => key.toJson()).toList()));
    final response = await request.close().timeout(
      const Duration(seconds: 20),
    );
    await response.drain<void>();
    if (response.statusCode == HttpStatus.unauthorized) {
      throw const _PreKeyUnauthorizedException('refresh');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Prekey refresh HTTP ${response.statusCode}');
    }
  }

  Future<int> _loadServerRemaining(String token) async {
    final request = await _httpClient
        .getUrl(_apiBaseUrl.resolve('/api/v1/prekeys/status'))
        .timeout(const Duration(seconds: 20));
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    final response = await request.close().timeout(const Duration(seconds: 20));
    final raw = await utf8.decoder
        .bind(response)
        .join()
        .timeout(const Duration(seconds: 20));
    if (response.statusCode == HttpStatus.unauthorized) {
      throw const _PreKeyUnauthorizedException('status');
    }
    if (response.statusCode != HttpStatus.ok || raw.length > 4096) {
      throw HttpException('Prekey status HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw const FormatException('Invalid prekey status');
    final remaining = (decoded['remaining'] as num?)?.toInt();
    if (remaining == null || remaining < 0) {
      throw const FormatException('Invalid prekey remaining count');
    }
    return remaining;
  }
}
