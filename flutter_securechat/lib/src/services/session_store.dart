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
    this.themePreference = 'system',
    this.languagePreference = 'system',
    this.showNotificationContent = false,
    this.notificationSound = 'default',
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
  String themePreference;
  String languagePreference;
  bool showNotificationContent;
  String notificationSound;
  bool useDoodleBackground;
  bool fullscreenMode;
  bool scheduledMessagesEnabled;

  bool get isLoggedIn =>
      userId != null && accessToken != null && accessToken!.isNotEmpty;

  void login({
    required String userId,
    required String displayName,
    required String phoneNumber,
    required String accessToken,
    required String refreshToken,
  }) {
    this.userId = userId;
    this.displayName = displayName;
    this.phoneNumber = phoneNumber;
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
  }

  void clear() {
    userId = null;
    displayName = null;
    phoneNumber = null;
    accessToken = null;
    refreshToken = null;
    pushToken = null;
    profilePhotoUri = null;
    shareLastSeen = false;
    themePreference = 'system';
    languagePreference = 'system';
    showNotificationContent = false;
    notificationSound = 'default';
    useDoodleBackground = true;
    fullscreenMode = false;
    scheduledMessagesEnabled = true;
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
    'themePreference': themePreference,
    'languagePreference': languagePreference,
    'showNotificationContent': showNotificationContent,
    'notificationSound': notificationSound,
    'useDoodleBackground': useDoodleBackground,
    'fullscreenMode': fullscreenMode,
    'scheduledMessagesEnabled': scheduledMessagesEnabled,
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
    notificationSound = _allowed(json['notificationSound'], const {
      'default',
      'silent',
    }, 'default');
    useDoodleBackground = json['useDoodleBackground'] as bool? ?? true;
    fullscreenMode = json['fullscreenMode'] as bool? ?? false;
    scheduledMessagesEnabled =
        json['scheduledMessagesEnabled'] as bool? ?? true;
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
