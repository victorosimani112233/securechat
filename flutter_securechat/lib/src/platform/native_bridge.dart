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

  /// Sistemin kisi ekleme ekranini ad ve numara dolu acar. Ekran
  /// acilamazsa (ya da platform desteklemiyorsa) `false` doner.
  Future<bool> addDeviceContact({
    required String phone,
    String name = '',
  }) async {
    try {
      return await _methods.invokeMethod<bool>('addDeviceContact', {
            'phone': phone,
            'name': name,
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Davet metnini sistemin SMS ekraninda acar; mesaji kullanici gonderir.
  Future<bool> composeInviteSms({
    required String phone,
    required String body,
  }) async {
    try {
      return await _methods.invokeMethod<bool>('composeInviteSms', {
            'phone': phone,
            'body': body,
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Davet metnini sistemin paylasim ekraniyla baska bir uygulamaya verir.
  Future<bool> shareInviteText({
    required String text,
    String title = '',
  }) async {
    try {
      return await _methods.invokeMethod<bool>('shareInviteText', {
            'text': text,
            'title': title,
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> enableScreenProtection() {
    return _methods.invokeMethod<void>('enableScreenProtection');
  }

  /// Ekran korumasini debug istisnasina ragmen zorlar (tek gosterim
  /// ekranlari). Her cagri [releaseForcedScreenProtection] ile eslenir.
  Future<void> enableScreenProtectionForced() => _optional(
    () => _methods.invokeMethod<void>('enableScreenProtectionForced'),
  );

  Future<void> releaseForcedScreenProtection() => _optional(
    () => _methods.invokeMethod<void>('releaseForcedScreenProtection'),
  );

  /// Uygulama penceresi acikken ekranin kararmasini engeller ya da serbest
  /// birakir. Cihazin ekran zaman asimi ayari degismez.
  Future<void> setKeepScreenOn(bool on) => _optional(
    () => _methods.invokeMethod<void>('setKeepScreenOn', {'on': on}),
  );

  Future<void> _optional(Future<void> Function() call) async {
    try {
      await call();
    } on MissingPluginException {
      // Masaustu/test ortaminda native kanal yok.
    } on PlatformException {
      // Koruma istegi ekrani acmayi engellememeli; release FLAG_SECURE
      // varsayilan olarak zaten acik.
    }
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

  /// Yalniz https adreslerini sistem tarayicisinda acar.
  Future<bool> openExternalUrl(Uri url) async {
    if (url.scheme != 'https' || url.host.isEmpty) return false;
    return await _methods.invokeMethod<bool>('openExternalUrl', {
          'url': url.toString(),
        }) ??
        false;
  }

  /// Izinlerin mevcut durumu; soru sormaz. Kanal yoksa (iOS, test) bos.
  Future<Map<String, bool>> getPermissionStatus() async {
    try {
      final result = await _methods.invokeMapMethod<String, Object?>(
        'getPermissionStatus',
      );
      return {
        for (final entry in (result ?? const {}).entries)
          if (entry.value is bool) entry.key: entry.value! as bool,
      };
    } on MissingPluginException {
      return const {};
    } on PlatformException {
      return const {};
    }
  }

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
