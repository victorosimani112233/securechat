import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'pre_key_manager.dart';

typedef AccessTokenProvider = Future<String?> Function();

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
  }) : _manager = manager,
       _apiBaseUrl = apiBaseUrl,
       _httpClient = httpClient,
       _accessTokenProvider = accessTokenProvider;

  final PreKeyManager _manager;
  final Uri _apiBaseUrl;
  final HttpClient _httpClient;
  final AccessTokenProvider _accessTokenProvider;
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
    final token = await _accessTokenProvider();
    if (token == null || token.isEmpty) return false;
    final batch = await _manager.buildSerializedReplenishBatch();
    if (batch == null) return true;
    final keyIds = batch.map((key) => key.keyId).toList(growable: false);
    try {
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
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Prekey refresh HTTP ${response.statusCode}');
      }
      return true;
    } catch (_) {
      await _manager.discardOneTimePreKeys(keyIds);
      return false;
    }
  }
}
