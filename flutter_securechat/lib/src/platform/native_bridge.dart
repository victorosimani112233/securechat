import 'package:flutter/services.dart';

class NativeBridge {
  const NativeBridge({MethodChannel? channel}) : _instanceChannel = channel;

  static const _channel = MethodChannel('com.securechat/native');
  final MethodChannel? _instanceChannel;
  MethodChannel get _methods => _instanceChannel ?? _channel;

  static const videoThumbnailMaxSize = 320;

  /// Returns an in-memory JPEG only for ordinary retained local media.
  Future<Uint8List?> localVideoThumbnail({
    required String path,
    required bool isViewOnce,
    int maxSize = videoThumbnailMaxSize,
  }) async {
    if (isViewOnce || path.trim().isEmpty) return null;
    try {
      final bytes = await _methods
          .invokeMethod<Uint8List>('localVideoThumbnail', {
            'path': path,
            'isViewOnce': false,
            'maxSize': maxSize.clamp(1, videoThumbnailMaxSize),
          });
      return bytes == null || bytes.isEmpty || bytes.length > 512 * 1024
          ? null
          : bytes;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

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

  /// Secilen bildirim kanalinin SISTEM ayarlarini acar.
  ///
  /// Neden gerekli: paketlenmis sesler sinirli bir liste. Kullanicinin
  /// cihazindaki HER sesi secebilmesinin tek yolu sistemin kendi secicisi.
  /// Android 8'den beri kanalin sesi zaten yalnizca oradan degistirilebiliyor
  /// — uygulama kodu bir kanalin sesini olusturulduktan sonra degistiremiyor.
  ///
  /// iOS'ta kanal kavrami yok; orada uygulamanin bildirim ayarlari aciliyor.
  /// Ses secimi iOS'ta paketlenmis listeden yapilmaya devam ediyor.
  Future<bool> openNotificationChannelSettings(String channelId) async =>
      await _methods.invokeMethod<bool>('openNotificationChannelSettings', {
        'channelId': channelId,
      }) ??
      false;

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
