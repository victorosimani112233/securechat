import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'async_operation_tracker.dart';
import 'crypto_service.dart';

class SessionStore {
  SessionStore({
    this.userId,
    this.displayName,
    this.phoneNumber,
    this.accessToken,
    this.refreshToken,
    this.pushToken,
    this.profilePhotoUri,
    this.shareLastSeen = false,
    this.shareOnline = true,
    this.shareReadReceipts = true,
    this.sharePhoneNumber = false,
    this.shareProfileName = true,
    this.themePreference = 'system',
    this.languagePreference = 'system',
    this.showNotificationContent = false,
    this.notificationSound = 'flow',
    this.useDoodleBackground = true,
    this.fullscreenMode = false,
    this.scheduledMessagesEnabled = true,
  });

  String? userId;
  String? displayName;
  String? phoneNumber;
  String? accessToken;
  String? refreshToken;
  String? pushToken;
  String? profilePhotoUri;
  bool shareLastSeen;
  bool shareOnline;
  bool shareReadReceipts;
  bool sharePhoneNumber;

  /// Kendi gorunen adini birebir yazdigin kisilere sifreli paylasir.
  bool shareProfileName;
  String themePreference;
  String languagePreference;
  bool showNotificationContent;
  String notificationSound;
  bool useDoodleBackground;
  bool fullscreenMode;
  bool scheduledMessagesEnabled;

  /// Sunucu refresh token'i kalici olarak reddetti (QA 2026-10-12 R1).
  ///
  /// Hesap ve profil cihazda kalir; yalniz tokenlar silinir. Giris ekrani
  /// bunu gorup "oturumun sona erdi" der; ayni hesapla yeniden giriste
  /// yerel veri korunur.
  bool credentialsExpired = false;

  bool get isLoggedIn =>
      userId != null && accessToken != null && accessToken!.isNotEmpty;

  void login({
    required String userId,
    required String displayName,
    required String phoneNumber,
    required String accessToken,
    required String refreshToken,
  }) {
    if (this.userId != userId) sharePhoneNumber = false;
    this.userId = userId;
    this.displayName = displayName;
    this.phoneNumber = phoneNumber;
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
    credentialsExpired = false;
  }

  /// Tokenlari siler, hesabi ve ayarlari birakir.
  void expireCredentials() {
    accessToken = null;
    refreshToken = null;
    credentialsExpired = true;
  }

  Future<void> expireCredentialsAndPersist() async => expireCredentials();

  void clear() {
    userId = null;
    displayName = null;
    phoneNumber = null;
    accessToken = null;
    refreshToken = null;
    pushToken = null;
    profilePhotoUri = null;
    shareLastSeen = false;
    shareOnline = true;
    shareReadReceipts = true;
    sharePhoneNumber = false;
    shareProfileName = true;
    themePreference = 'system';
    languagePreference = 'system';
    showNotificationContent = false;
    notificationSound = 'flow';
    useDoodleBackground = true;
    fullscreenMode = false;
    scheduledMessagesEnabled = true;
    credentialsExpired = false;
  }

  Future<void> loginAndPersist({
    required String userId,
    required String displayName,
    required String phoneNumber,
    required String accessToken,
    required String refreshToken,
  }) async {
    login(
      userId: userId,
      displayName: displayName,
      phoneNumber: phoneNumber,
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
  }

  Future<void> updateTokensAndPersist({
    required String accessToken,
    required String refreshToken,
  }) async {
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
  }

  /// Kalici depodan tazeler. Bellekte tutan uygulamalarda bos gecer.
  Future<void> reloadFromDisk() async {}

  /// Token yenilemesini isolate'ler ARASI sirali kosar.
  ///
  /// Refresh token tek kullanimlik: sunucu her yenilemede generation'i
  /// donduruyor. On plan ve arka plan ayri isolate'ler ve ayni oturum
  /// dosyasini paylasiyor, dolayisiyla ikisi ayni anda yenilerse biri 401
  /// alir ve elindeki token BIR DAHA gecerli olmaz — kullanicinin
  /// yapabilecegi tek sey yeniden giris olur. Sadece "once diskten tazele"
  /// demek yetmiyor: kaybeden, kazanan diske yazmadan once tazelerse yine
  /// olu token'la kalir.
  ///
  /// Bellekte tutan uygulamada tek isolate varsayildigi icin dogrudan
  /// kosar.
  Future<T> withRefreshLock<T>(Future<T> Function() action) => action();

  Future<void> clearAndPersist() async => clear();

  /// Persists in-memory changes when this is a disk-backed session store.
  /// The base implementation deliberately remains a no-op for isolated tests
  /// and the in-memory demo container.
  Future<void> persist() async {}

  Future<void> restoreProfileAndPersist({
    required String userId,
    required String displayName,
    required String phoneNumber,
    String? profilePhotoUri,
  }) async {
    if (this.userId != userId) sharePhoneNumber = false;
    this.userId = userId;
    this.displayName = displayName;
    this.phoneNumber = phoneNumber;
    this.profilePhotoUri = profilePhotoUri;
  }

  Map<String, Object?> toJson() => {
    'userId': userId,
    'displayName': displayName,
    'phoneNumber': phoneNumber,
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'pushToken': pushToken,
    'profilePhotoUri': profilePhotoUri,
    'shareLastSeen': shareLastSeen,
    'shareOnline': shareOnline,
    'shareReadReceipts': shareReadReceipts,
    'sharePhoneNumber': sharePhoneNumber,
    'shareProfileName': shareProfileName,
    'themePreference': themePreference,
    'languagePreference': languagePreference,
    'showNotificationContent': showNotificationContent,
    'notificationSound': notificationSound,
    'useDoodleBackground': useDoodleBackground,
    'fullscreenMode': fullscreenMode,
    'scheduledMessagesEnabled': scheduledMessagesEnabled,
    'credentialsExpired': credentialsExpired,
  };

  void loadJson(Map<String, Object?> json) {
    userId = json['userId'] as String?;
    displayName = json['displayName'] as String?;
    phoneNumber = json['phoneNumber'] as String?;
    accessToken = json['accessToken'] as String?;
    refreshToken = json['refreshToken'] as String?;
    pushToken = json['pushToken'] as String?;
    profilePhotoUri = json['profilePhotoUri'] as String?;
    shareLastSeen = json['shareLastSeen'] as bool? ?? false;
    shareOnline = json['shareOnline'] as bool? ?? true;
    shareReadReceipts = json['shareReadReceipts'] as bool? ?? true;
    sharePhoneNumber = json['sharePhoneNumber'] as bool? ?? false;
    shareProfileName = json['shareProfileName'] as bool? ?? true;
    themePreference = _allowed(json['themePreference'], const {
      'system',
      'light',
      'dark',
    }, 'system');
    languagePreference = _allowed(json['languagePreference'], const {
      'system',
      'tr',
      'en',
      'de',
      'ar',
    }, 'system');
    showNotificationContent = json['showNotificationContent'] as bool? ?? false;
    // Ses adlari `NotificationSoundPreference` ile ayni; burada liste
    // tekrar edilmiyor. Taninmayan deger (eski kayitlardaki 'default' ya da
    // kaldirilmis bir ses) varsayilana duser — bkz. `fromStorage`.
    notificationSound = (json['notificationSound'] as String?) ?? 'flow';
    useDoodleBackground = json['useDoodleBackground'] as bool? ?? true;
    fullscreenMode = json['fullscreenMode'] as bool? ?? false;
    scheduledMessagesEnabled =
        json['scheduledMessagesEnabled'] as bool? ?? true;
    credentialsExpired = json['credentialsExpired'] as bool? ?? false;
  }
}

String _allowed(Object? value, Set<String> allowed, String fallback) {
  final text = value?.toString();
  return text != null && allowed.contains(text) ? text : fallback;
}

class PersistentSessionStore extends SessionStore {
  PersistentSessionStore._({
    required File file,
    required LocalAeadCryptoService crypto,
    AsyncOperationFailureHandler? onAsyncFailure,
  }) : _file = file,
       _crypto = crypto,
       _onAsyncFailure = onAsyncFailure;

  final File _file;
  final LocalAeadCryptoService _crypto;
  final AsyncOperationFailureHandler? _onAsyncFailure;
  Future<void> _writeTail = Future<void>.value();
  Future<void>? _closeTask;
  bool _closed = false;

  static Future<PersistentSessionStore> open({
    required File file,
    required LocalAeadCryptoService crypto,
    AsyncOperationFailureHandler? onAsyncFailure,
  }) async {
    final store = PersistentSessionStore._(
      file: file,
      crypto: crypto,
      onAsyncFailure: onAsyncFailure,
    );
    if (await file.exists()) {
      final envelope = await file.readAsString();
      if (envelope.trim().isNotEmpty) {
        final plaintext = await crypto.decryptStorageJson(envelope);
        store.loadJson(jsonDecode(plaintext) as Map<String, Object?>);
      }
    }
    return store;
  }

  /// Oturumu diskten yeniden okur.
  ///
  /// On plan ve arka plan AYRI isolate'ler ve her biri oturumu yalnizca
  /// acilista bellege aliyor. Refresh token TEK KULLANIMLIK (sunucu her
  /// yenilemede `rotateRefreshGeneration` cagiriyor), dolayisiyla biri
  /// yeniledigi anda digerinin elindeki token oluyor. Tazelemeden yenilemek,
  /// kaybeden tarafi kalici 401'e sokuyordu.
  /// Ayni isolate icindeki es zamanli yenilemeleri siraya alir.
  ///
  /// POSIX dosya kilitleri SURECE ait: ayni surecten ikinci bir kilit
  /// istegi beklemeden basarili olur. Dosya kilidi tek basina isolate ici
  /// es zamanlilige karsi koruma saglamaz.
  Future<void> _refreshTail = Future<void>.value();

  @override
  Future<T> withRefreshLock<T>(Future<T> Function() action) {
    final result = _refreshTail.then<T>((_) => _withFileLock(action));
    _refreshTail = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }

  Future<T> _withFileLock<T>(Future<T> Function() action) async {
    final lockFile = File('${_file.path}.refresh.lock');
    RandomAccessFile? handle;
    try {
      handle = await lockFile.open(mode: FileMode.write);
      await handle.lock(FileLock.exclusive);
      return await action();
    } on FileSystemException {
      // Kilit alinamazsa yenilemeyi ENGELLEMEK yanlis olur: tek sonucu
      // oturumun hic yenilenememesi olurdu. Sirasiz kosmak, hic
      // kosmamaktan iyi.
      return action();
    } finally {
      if (handle != null) {
        try {
          await handle.unlock();
        } catch (_) {
          // Kilit zaten birakilmis olabilir.
        }
        await handle.close();
      }
    }
  }

  @override
  Future<void> reloadFromDisk() async {
    if (_closed) return;
    if (!await _file.exists()) return;
    final envelope = await _file.readAsString();
    if (envelope.trim().isEmpty) return;
    final plaintext = await _crypto.decryptStorageJson(envelope);
    loadJson(jsonDecode(plaintext) as Map<String, Object?>);
  }

  @override
  void login({
    required String userId,
    required String displayName,
    required String phoneNumber,
    required String accessToken,
    required String refreshToken,
  }) {
    super.login(
      userId: userId,
      displayName: displayName,
      phoneNumber: phoneNumber,
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
    _schedulePersist('session.login');
  }

  @override
  void clear() {
    super.clear();
    _schedulePersist('session.clear');
  }

  void _schedulePersist(String operation) {
    unawaited(_persistAndReport(operation));
  }

  Future<void> _persistAndReport(String operation) async {
    try {
      await persist();
    } catch (error, stackTrace) {
      final handler = _onAsyncFailure;
      if (handler == null) return;
      try {
        await handler(operation, error, stackTrace);
      } catch (_) {
        // Persistence and diagnostics failures are both contained. Explicit
        // loginAndPersist/clearAndPersist callers still receive write errors.
      }
    }
  }

  @override
  Future<void> persist() {
    if (_closed) throw StateError('Persistent session store is closed');
    final snapshot = jsonEncode(toJson());
    final operation = _writeTail.then<void>((_) async {
      await _file.parent.create(recursive: true);
      final envelope = await _crypto.encryptStorageJson(snapshot);
      final tmp = File('${_file.path}.tmp');
      await tmp.writeAsString(envelope, flush: true);
      if (await _file.exists()) {
        await _file.delete();
      }
      await tmp.rename(_file.path);
    });
    _writeTail = operation.then<void>((_) {}, onError: (_, _) {});
    return operation;
  }

  Future<void> close() {
    final active = _closeTask;
    if (active != null) return active;
    _closed = true;
    final operation = _writeTail;
    _closeTask = operation;
    return operation;
  }

  @override
  Future<void> loginAndPersist({
    required String userId,
    required String displayName,
    required String phoneNumber,
    required String accessToken,
    required String refreshToken,
  }) async {
    super.login(
      userId: userId,
      displayName: displayName,
      phoneNumber: phoneNumber,
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
    await persist();
  }

  @override
  Future<void> updateTokensAndPersist({
    required String accessToken,
    required String refreshToken,
  }) async {
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
    await persist();
  }

  @override
  Future<void> clearAndPersist() async {
    super.clear();
    await persist();
  }

  @override
  Future<void> expireCredentialsAndPersist() async {
    expireCredentials();
    await persist();
  }

  @override
  Future<void> restoreProfileAndPersist({
    required String userId,
    required String displayName,
    required String phoneNumber,
    String? profilePhotoUri,
  }) async {
    await super.restoreProfileAndPersist(
      userId: userId,
      displayName: displayName,
      phoneNumber: phoneNumber,
      profilePhotoUri: profilePhotoUri,
    );
    await persist();
  }
}
