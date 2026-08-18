import 'package:flutter/services.dart';

class NativeBridge {
  const NativeBridge({MethodChannel? channel}) : _instanceChannel = channel;

  static const _channel = MethodChannel('com.securechat/native');
  final MethodChannel? _instanceChannel;
  MethodChannel get _methods => _instanceChannel ?? _channel;

  Future<void> enableScreenProtection() {
    return _methods.invokeMethod<void>('enableScreenProtection');
  }

  Future<void> registerCallIntegration() {
    return _methods.invokeMethod<void>('registerCallIntegration');
  }

  Future<bool> authenticateLockedChat(String title) async {
    return await _methods.invokeMethod<bool>('authenticateLockedChat', {
          'title': title,
        }) ??
        false;
  }

  Future<Map<String, Object?>> getCallReadiness() async {
    final result = await _methods.invokeMapMethod<String, Object?>(
      'getCallReadiness',
    );
    return result ?? const {};
  }

  Future<bool> openCallReadinessSetting(String kind) async =>
      await _methods.invokeMethod<bool>('openCallReadinessSetting', {
        'kind': kind,
      }) ??
      false;

  Future<bool> requestContactsPermission() async =>
      await _methods.invokeMethod<bool>('requestContactsPermission') ?? false;

  Future<List<Map<String, Object?>>> readContacts() async {
    final result = await _methods.invokeListMethod<Object?>('readContacts');
    return (result ?? const [])
        .whereType<Map>()
        .map((item) => item.cast<String, Object?>())
        .toList(growable: false);
  }

  Future<void> openLocalFile({
    required String path,
    required String mimeType,
  }) => _methods.invokeMethod<void>('openLocalFile', {
    'path': path,
    'mimeType': mimeType,
  });

  Future<void> shareLocalFile({
    required String path,
    required String mimeType,
    required String fileName,
  }) => _methods.invokeMethod<void>('shareLocalFile', {
    'path': path,
    'mimeType': mimeType,
    'fileName': fileName,
  });
}
