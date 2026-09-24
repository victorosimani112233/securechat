import 'dart:async';
import '../notifications/message_notification_service.dart';
import '../platform/native_bridge.dart';
import 'dart:io';

import 'package:flutter/services.dart';

import '../background/scheduled_message_service.dart';
import '../core/signal_message.dart';
import '../media/media_attachment.dart';
import '../services/session_store.dart';
import '../services/signaling_service.dart';

enum AppThemePreference { system, light, dark }

enum AppLanguagePreference { system, tr, en, de, ar }

/// Bildirim sesi secenegi.
///
/// `asset` paketlenmis ses dosyasinin adi (uzantisiz). Ayni dosya iki
/// platformda da kullaniliyor: iOS `ios/Runner/Sounds/<asset>.wav`,
/// Android `res/raw/<asset>.wav`.
///
/// `silent` ve `system` disa bir dosya tasimaz: birincisi ses calmaz,
/// ikincisi cihazin varsayilan bildirim sesini kullanir.
enum NotificationSoundPreference {
  silent(null),
  system(null),
  chime('elcim_chime'),
  bell('elcim_bell'),
  tap('elcim_tap'),
  warm('elcim_warm'),
  soft('elcim_soft'),
  melody('elcim_melody'),
  flow('elcim_flow'),
  sparkle('elcim_sparkle'),
  beep('elcim_beep'),
  ding('elcim_ding');

  const NotificationSoundPreference(this.asset);

  /// Uygulamanin varsayilan sesi.
  ///
  /// Tek yerde tanimli: saklama varsayilani, sifirlama ve taninmayan deger
  /// hepsi buna bakiyor. Ayri ayri yazilsalardi varsayilan degistiginde
  /// biri atlanirdi.
  static const defaultSound = flow;

  /// Paketlenmis dosyanin adi; `silent` ve `system` icin null.
  final String? asset;

  /// Kalici saklamada kullanilan ad. Eski kayitlarda 'default' yaziyordu.
  static NotificationSoundPreference fromStorage(String value) {
    for (final option in values) {
      if (option.name == value) return option;
    }
    // Eski kayitlarda 'default' yaziyordu ve "uygulamanin varsayilani"
    // demekti; varsayilan degistigi icin yeni varsayilana esleniyor.
    // Taninmayan bir deger de buraya duser: bildirim hic calmamaktansa
    // varsayilan sesle calsin.
    return defaultSound;
  }
}

class AppSettingsState {
  const AppSettingsState({
    required this.theme,
    required this.language,
    required this.showNotificationContent,
    required this.notificationSound,
    required this.useDoodleBackground,
    required this.fullscreenMode,
    required this.scheduledMessagesEnabled,
    required this.shareLastSeen,
    this.shareOnline = true,
    this.shareReadReceipts = true,
    this.sharePhoneNumber = false,
    required this.profilePhotoPath,
  });

  final AppThemePreference theme;
  final AppLanguagePreference language;
  final bool showNotificationContent;
  final NotificationSoundPreference notificationSound;
  final bool useDoodleBackground;
  final bool fullscreenMode;
  final bool scheduledMessagesEnabled;
  final bool shareLastSeen;
  final bool shareOnline;
  final bool shareReadReceipts;
  final bool sharePhoneNumber;
  final String? profilePhotoPath;
}

abstract interface class FullscreenController {
  Future<void> setEnabled(bool enabled);
}

class FlutterFullscreenController implements FullscreenController {
  const FlutterFullscreenController();

  @override
  Future<void> setEnabled(bool enabled) async {
    // Android supports a persistent immersive mode. iOS reserves the system
    // status areas and does not expose an equivalent app-wide toggle.
    if (Platform.isAndroid && enabled) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }
}

class SettingsService {
  SettingsService({
    required SessionStore session,
    required SignalingService signaling,
    required ScheduledMessageService scheduledMessages,
    required Directory profileDirectory,
    FullscreenController fullscreen = const FlutterFullscreenController(),
    Future<void> Function()? clearNotifications,
  }) : _session = session,
       _signaling = signaling,
       _scheduledMessages = scheduledMessages,
       _profileDirectory = profileDirectory,
       _fullscreen = fullscreen,
       _clearNotifications = clearNotifications;

  static const maximumProfilePhotoBytes = 10 * 1024 * 1024;

  final SessionStore _session;
  final SignalingService _signaling;
  final ScheduledMessageService _scheduledMessages;
  final Directory _profileDirectory;
  final FullscreenController _fullscreen;
  final Future<void> Function()? _clearNotifications;
  final NativeBridge _bridge = const NativeBridge();
  final _changes = StreamController<AppSettingsState>.broadcast();

  AppSettingsState get current => AppSettingsState(
    theme: switch (_session.themePreference) {
      'light' => AppThemePreference.light,
      'dark' => AppThemePreference.dark,
      _ => AppThemePreference.system,
    },
    language: switch (_session.languagePreference) {
      'tr' => AppLanguagePreference.tr,
      'en' => AppLanguagePreference.en,
      'de' => AppLanguagePreference.de,
      'ar' => AppLanguagePreference.ar,
      _ => AppLanguagePreference.system,
    },
    showNotificationContent: _session.showNotificationContent,
    notificationSound: NotificationSoundPreference.fromStorage(
      _session.notificationSound,
    ),
    useDoodleBackground: _session.useDoodleBackground,
    fullscreenMode: _session.fullscreenMode,
    scheduledMessagesEnabled: _session.scheduledMessagesEnabled,
    shareLastSeen: _session.shareLastSeen,
    shareOnline: _session.shareOnline,
    shareReadReceipts: _session.shareReadReceipts,
    sharePhoneNumber: _session.sharePhoneNumber,
    profilePhotoPath: _session.profilePhotoUri,
  );

  Stream<AppSettingsState> get states async* {
    yield current;
    yield* _changes.stream;
  }

  Future<void> applyPlatformPreferences() =>
      _fullscreen.setEnabled(_session.fullscreenMode);

  Future<void> reloadFromSession() async {
    await applyPlatformPreferences();
    _emit();
  }

  Future<void> setTheme(AppThemePreference value) async {
    _session.themePreference = value.name;
    await _persistAndEmit();
  }

  Future<void> setLanguage(AppLanguagePreference value) async {
    _session.languagePreference = value.name;
    await _persistAndEmit();
  }

  Future<void> setShowNotificationContent(bool value) async {
    final changed = _session.showNotificationContent != value;
    _session.showNotificationContent = value;
    await _persistAndEmit();
    if (changed) await _clearNotifications?.call();
  }

  /// Secili sesin SISTEM ayarlarini acar.
  ///
  /// Paketlenmis sesler sinirli bir liste; cihazdaki her sesi secebilmenin
  /// tek yolu sistemin kendi secicisi. Android 8'den beri bir kanalin sesi
  /// zaten yalnizca oradan degistirilebiliyor.
  ///
  /// Kanal kimligi burada hesaplaniyor, arayuzde degil: arayuzun bildirim
  /// altyapisini tanimasi gerekmiyor (bkz. architecture_boundaries_test).
  Future<bool> openSystemSoundSettings() =>
      _bridge.openNotificationChannelSettings(
        PluginLocalNotificationPresenter.channelForSound(
          NotificationSoundPreference.fromStorage(
            _session.notificationSound,
          ).asset,
        ),
      );

  Future<void> setNotificationSound(NotificationSoundPreference value) async {
    _session.notificationSound = value.name;
    await _persistAndEmit();
  }

  Future<void> setUseDoodleBackground(bool value) async {
    _session.useDoodleBackground = value;
    await _persistAndEmit();
  }

  Future<void> setFullscreenMode(bool value) async {
    await _fullscreen.setEnabled(value);
    _session.fullscreenMode = value;
    await _persistAndEmit();
  }

  Future<void> setScheduledMessagesEnabled(bool value) async {
    _session.scheduledMessagesEnabled = value;
    await _session.persist();
    await _scheduledMessages.setGloballyEnabled(value);
    _emit();
  }

  Future<void> setShareLastSeen(bool value) async {
    _session.shareLastSeen = value;
    await _persistAndEmit();
    await _publishPresence();
  }

  Future<void> setShareOnline(bool value) async {
    _session.shareOnline = value;
    await _persistAndEmit();
    await _publishPresence();
  }

  Future<void> setShareReadReceipts(bool value) async {
    _session.shareReadReceipts = value;
    await _persistAndEmit();
  }

  Future<void> _publishPresence() async {
    final userId = _session.userId;
    if (userId != null && _signaling.currentStatus.isConnected) {
      await _signaling.send(
        PresenceUpdateSignal(
          senderId: userId,
          recipientId: 'server',
          timestamp: DateTime.now(),
          isOnline: _session.shareOnline,
          lastSeen: DateTime.now(),
          hideLastSeen: !_session.shareLastSeen,
        ),
      );
    }
  }

  Future<void> setSharePhoneNumber(bool value) async {
    _session.sharePhoneNumber = value;
    try {
      await _persistAndEmit();
    } catch (_) {
      // A failed opt-in must not authorize disclosure in this process.
      _session.sharePhoneNumber = false;
      _emit();
      rethrow;
    }
  }

  Future<String> updateProfilePhoto(MediaAttachment attachment) async {
    if (!attachment.isImage) {
      throw const SettingsException('Profil fotoğrafı bir görsel olmalıdır.');
    }
    if (attachment.fileSize <= 0 ||
        attachment.fileSize > maximumProfilePhotoBytes) {
      throw const SettingsException('Profil fotoğrafı 10 MB sınırını aşamaz.');
    }
    final source = File(attachment.path);
    if (!await source.exists()) {
      throw const SettingsException('Seçilen profil fotoğrafı bulunamadı.');
    }
    await _profileDirectory.create(recursive: true);
    final extension = _safeImageExtension(attachment.fileName);
    final destination = File(
      '${_profileDirectory.path}/profile_${DateTime.now().microsecondsSinceEpoch}$extension',
    );
    final temporary = File('${destination.path}.tmp');
    await source.openRead().pipe(temporary.openWrite());
    await temporary.rename(destination.path);

    final previous = _session.profilePhotoUri;
    _session.profilePhotoUri = destination.path;
    await _session.persist();
    await _deleteManagedPhoto(previous, except: destination.path);
    _emit();
    return destination.path;
  }

  Future<void> removeProfilePhoto() async {
    final previous = _session.profilePhotoUri;
    _session.profilePhotoUri = null;
    await _session.persist();
    await _deleteManagedPhoto(previous);
    _emit();
  }

  Future<void> close() => _changes.close();

  Future<void> _persistAndEmit() async {
    await _session.persist();
    _emit();
  }

  void _emit() {
    if (!_changes.isClosed) _changes.add(current);
  }

  Future<void> _deleteManagedPhoto(String? path, {String? except}) async {
    if (path == null || path == except) return;
    final file = File(path).absolute;
    if (file.parent.path != _profileDirectory.absolute.path) return;
    if (await file.exists()) await file.delete();
  }
}

class SettingsException implements Exception {
  const SettingsException(this.message);
  final String message;

  @override
  String toString() => message;
}

String _safeImageExtension(String fileName) {
  final lower = fileName.toLowerCase();
  for (final extension in const ['.jpg', '.jpeg', '.png', '.webp', '.heic']) {
    if (lower.endsWith(extension)) return extension;
  }
  return '.jpg';
}
