import 'dart:async';

import '../l10n/service_strings.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';

import '../incoming/incoming_message_handler.dart';
import '../media/call_models.dart';
import '../services/session_store.dart';
import '../settings/settings_service.dart';
import '../services/async_operation_tracker.dart';

class LocalMessageNotification {
  const LocalMessageNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.payload,
    required this.conversationId,
    required this.count,
    required this.silent,
    required this.hideOnLockScreen,
    this.sound,
  });

  final int id;
  final String title;
  final String body;
  final String? payload;
  final String conversationId;
  final int count;
  final bool silent;
  final bool hideOnLockScreen;

  /// Paketlenmis ses dosyasinin adi (uzantisiz), ya da null.
  ///
  /// null iki durumda gelir: bildirim sessiz, ya da kullanici cihazin
  /// varsayilan sesini secmis.
  final String? sound;
}

class NotificationDismissal {
  const NotificationDismissal.conversation(this.conversationId)
    : dismissAll = false;
  const NotificationDismissal.all() : conversationId = null, dismissAll = true;

  final String? conversationId;
  final bool dismissAll;
}

class MissedCallAction {
  const MissedCallAction({required this.peerId, required this.callType});
  final String peerId;
  final CallType callType;
}

class MissedCallNotification {
  const MissedCallNotification({
    required this.id,
    required this.callId,
    required this.peerId,
    required this.peerName,
    required this.callType,
    this.silent = false,
    this.isGroupCall = false,
  });
  final int id;
  final String callId;
  final String peerId;
  final String peerName;
  final CallType callType;
  final bool silent;
  final bool isGroupCall;
}

abstract interface class LocalNotificationPresenter {
  Stream<String> get taps;
  Stream<NotificationDismissal> get dismissals;
  Future<void> initialize();
  Future<void> show(LocalMessageNotification notification);
  Future<void> reconcileDismissals();
  Future<void> cancelAll();
}

abstract interface class MissedCallNotificationPresenter {
  Stream<MissedCallAction> get missedCallCallbacks;
  Future<void> showMissedCall(MissedCallNotification notification);
}

typedef NotificationShowCallback =
    Future<void> Function({
      required int id,
      String? title,
      String? body,
      NotificationDetails? notificationDetails,
      String? payload,
    });

class PluginLocalNotificationPresenter
    implements LocalNotificationPresenter, MissedCallNotificationPresenter {
  PluginLocalNotificationPresenter({
    FlutterLocalNotificationsPlugin? plugin,
    ServiceStrings? strings,
    NotificationShowCallback? showNotification,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
       // Bildirim metinleri servis katmaninda uretiliyor ve burada
       // BuildContext yok; yerellestirme icin ServiceStrings kullanilir.
       _strings = strings ?? ServiceStrings.fixed('tr'),
       _showNotificationOverride = showNotification;

  static const highChannelId = 'elcim_messages_v4';
  static const lowChannelId = 'elcim_messages_low_v1';
  static const groupKey = 'elcim_messages';
  static const quietMissedCallChannelId = 'missed_call_quiet_v1';

  /// Her ses icin AYRI kanal.
  ///
  /// Android 8'den beri bir kanalin sesi olusturulduktan SONRA kodla
  /// degistirilemiyor. Tek kanal kullanilsaydi ses degistirmek icin kanali
  /// silip yeniden kurmak gerekirdi — ustelik ayni kimlikle degil, cunku
  /// Android silinen kanalin ayarlarini hatirliyor ve eski sesle geri
  /// getiriyor. Ses basina kalici bir kanal bu dansi tamamen gereksiz
  /// kiliyor: kullanici sesi degistirdiginde yalnizca hedef kanal degisiyor.
  ///
  /// Yan faydasi: kullanici her sesi sistem ayarlarindan ayrica
  /// ozellestirebiliyor ve o ayar kaliciligini koruyor.
  static String _channelFor(LocalMessageNotification notification) =>
      notification.silent ? lowChannelId : channelForSound(notification.sound);

  /// Bir sesin kanal kimligi.
  ///
  /// Ayarlar ekrani da bunu kullaniyor: sistem ses secicisini acarken hangi
  /// kanalin ayarlarina gidilecegini bilmesi gerekiyor. Iki yerde ayri
  /// hesaplanirsa kullanici yanlis kanalin ayarina duser.
  static String channelForSound(String? sound) =>
      sound == null ? highChannelId : 'elcim_messages_$sound';

  final FlutterLocalNotificationsPlugin _plugin;
  final ServiceStrings _strings;
  final NotificationShowCallback? _showNotificationOverride;
  final _tapController = StreamController<String>.broadcast();
  final _dismissController =
      StreamController<NotificationDismissal>.broadcast();
  final _callbackController = StreamController<MissedCallAction>.broadcast();
  final Map<int, String?> _shownMessages = {};
  String? _initialTap;
  bool _disposed = false;

  @override
  Stream<String> get taps async* {
    final initial = _initialTap;
    _initialTap = null;
    if (initial != null) yield initial;
    yield* _tapController.stream;
  }

  @override
  Stream<NotificationDismissal> get dismissals => _dismissController.stream;

  @override
  Stream<MissedCallAction> get missedCallCallbacks =>
      _callbackController.stream;

  @override
  Future<void> initialize() async {
    final settings = InitializationSettings(
      android: const AndroidInitializationSettings('notification_icon'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
        notificationCategories: [
          DarwinNotificationCategory(
            'securechat_missed_call',
            actions: [
              DarwinNotificationAction.plain(
                'call_back',
                'Geri Ara',
                options: {DarwinNotificationActionOption.foreground},
              ),
            ],
          ),
        ],
      ),
    );
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) {
        if (_disposed) return;
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        final missed = _decodeMissedCall(payload);
        if (missed != null) {
          if (response.actionId == 'call_back') {
            _callbackController.add(missed);
          } else {
            _tapController.add(missed.peerId);
          }
          return;
        }
        _tapController.add(payload);
      },
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      final payload = launch?.notificationResponse?.payload;
      if (payload != null && payload.isNotEmpty) {
        _initialTap = _decodeMissedCall(payload)?.peerId ?? payload;
      }
    }
  }

  @override
  Future<void> show(LocalMessageNotification notification) async {
    final channelId = _channelFor(notification);
    final l10n = await _strings.load();
    NotificationDetails details({
      required bool customSound,
    }) => NotificationDetails(
      android: AndroidNotificationDetails(
        customSound ? channelId : '${channelId}_sound_fallback_v1',
        notification.silent
            ? l10n.messages_channel_silent
            : l10n.messages_channel,
        channelDescription: notification.silent
            ? l10n.messages_channel_silent_desc
            : l10n.messages_channel_desc,
        icon: 'notification_icon',
        importance: notification.silent ? Importance.low : Importance.high,
        priority: notification.silent ? Priority.low : Priority.high,
        playSound: !notification.silent,
        sound: !customSound || notification.silent || notification.sound == null
            ? null
            : RawResourceAndroidNotificationSound(notification.sound),
        enableVibration: !notification.silent,
        silent: notification.silent,
        groupKey: groupKey,
        category: AndroidNotificationCategory.message,
        visibility: notification.hideOnLockScreen
            ? NotificationVisibility.secret
            : NotificationVisibility.private,
        number: notification.count,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBanner: true,
        presentList: true,
        presentBadge: true,
        presentSound: !notification.silent,
        // iOS'ta ses dosya adiyla verilir; uzanti sart.
        sound: !customSound || notification.silent || notification.sound == null
            ? null
            : '${notification.sound}.wav',
        threadIdentifier: notification.conversationId,
        categoryIdentifier: 'securechat_message',
      ),
    );
    try {
      await _showMessage(notification, details(customSound: true));
    } on PlatformException catch (error) {
      // Eksik ya da paketlenmemis bir ses kaynagi bildirimin tamamini
      // dusurmemeli. Ayrı kanal kimligi, Android'in hatali kanal ayarini
      // gelecekteki duzeltilmis bildirimlere kalici olarak tasimasini engeller.
      if (error.code != 'invalid_sound') rethrow;
      await _showMessage(notification, details(customSound: false));
    }
    _shownMessages[notification.id] = notification.hideOnLockScreen
        ? null
        : notification.conversationId;
  }

  Future<void> _showMessage(
    LocalMessageNotification notification,
    NotificationDetails details,
  ) {
    final showNotification = _showNotificationOverride ?? _plugin.show;
    return showNotification(
      id: notification.id,
      title: notification.title,
      body: notification.body,
      notificationDetails: details,
      payload: notification.payload,
    );
  }

  @override
  Future<void> showMissedCall(MissedCallNotification notification) async {
    // Group calls cannot use the direct-call callback handler.
    final payload = notification.isGroupCall
        ? notification.peerId
        : _encodeMissedCall(notification);
    final l10n = await _strings.load();
    final showNotification = _showNotificationOverride ?? _plugin.show;
    await showNotification(
      id: notification.id,
      title: notification.callType == CallType.video
          ? l10n.missed_video_call
          : l10n.missed_voice_call,
      body: l10n.missed_call_from(notification.peerName),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          notification.silent
              ? quietMissedCallChannelId
              : 'missed_call_channel',
          l10n.missed_calls_channel,
          channelDescription: l10n.missed_calls_channel_desc,
          icon: 'notification_icon',
          importance: notification.silent
              ? Importance.low
              : Importance.defaultImportance,
          priority: notification.silent
              ? Priority.low
              : Priority.defaultPriority,
          playSound: !notification.silent,
          enableVibration: !notification.silent,
          silent: notification.silent,
          category: AndroidNotificationCategory.missedCall,
          visibility: NotificationVisibility.secret,
          actions: notification.isGroupCall
              ? const []
              : const [
                  AndroidNotificationAction(
                    'call_back',
                    'Geri Ara',
                    showsUserInterface: true,
                  ),
                ],
        ),
        iOS: DarwinNotificationDetails(
          categoryIdentifier: notification.isGroupCall
              ? 'securechat_message'
              : 'securechat_missed_call',
          presentAlert: true,
          presentSound: !notification.silent,
        ),
      ),
      payload: payload,
    );
  }

  @override
  Future<void> reconcileDismissals() async {
    final active = await _plugin.getActiveNotifications();
    final activeIds = active.map((item) => item.id).toSet();
    final removed = _shownMessages.keys
        .where((id) => !activeIds.contains(id))
        .toList();
    for (final id in removed) {
      final conversationId = _shownMessages.remove(id);
      _dismissController.add(
        conversationId == null
            ? const NotificationDismissal.all()
            : NotificationDismissal.conversation(conversationId),
      );
    }
  }

  @override
  Future<void> cancelAll() async {
    _shownMessages.clear();
    await _plugin.cancelAll();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _shownMessages.clear();
    await _tapController.close();
    await _dismissController.close();
    await _callbackController.close();
  }
}

class MessageNotificationCoordinator {
  MessageNotificationCoordinator({
    required Stream<IncomingMessageEvent> incomingMessages,
    required SessionStore session,
    required LocalNotificationPresenter presenter,
    ServiceStrings? strings,
    Future<Map<String, int>> Function()? unreadCounts,
    AsyncOperationFailureHandler? onAsyncFailure,
  }) : _incomingMessages = incomingMessages,
       _session = session,
       _presenter = presenter,
       _unreadCounts = unreadCounts,
       _strings =
           strings ??
           ServiceStrings(languageCode: () async => session.languagePreference),
       _operations = AsyncOperationTracker(onFailure: onAsyncFailure);

  static const privacyNotificationId = 104729;

  final Stream<IncomingMessageEvent> _incomingMessages;
  final SessionStore _session;
  final LocalNotificationPresenter _presenter;
  final ServiceStrings _strings;
  final Future<Map<String, int>> Function()? _unreadCounts;
  final AsyncOperationTracker _operations;
  Future<void> _operationTail = Future<void>.value();
  final _counts = <String, int>{};
  StreamSubscription<IncomingMessageEvent>? _messageSubscription;
  StreamSubscription<NotificationDismissal>? _dismissSubscription;
  bool _isForeground = true;
  String? _activeConversationId;
  Object? _activeConversationOwner;
  bool _disposed = false;

  Stream<String> get taps => _presenter.taps;

  Future<void> start() async {
    if (_disposed) {
      throw StateError('Message notification coordinator is disposed');
    }
    await _presenter.initialize();
    _dismissSubscription ??= _presenter.dismissals.listen(_onDismissed);
    _messageSubscription ??= _incomingMessages.listen((event) {
      // Visibility belongs to arrival time, not the time a queued show runs.
      if (_isForeground && _activeConversationId == event.conversationId)
        return;
      _enqueue('notification.present-message', () => _onMessage(event));
    });
  }

  void setAppForeground(bool foreground) {
    _isForeground = foreground;
    if (foreground && !_disposed) {
      _enqueue(
        'notification.reconcile-dismissals',
        _presenter.reconcileDismissals,
      );
    }
  }

  void setActiveConversation(String? conversationId, {Object? owner}) {
    _activeConversationId = conversationId;
    _activeConversationOwner = owner;
  }

  void clearActiveConversation(Object owner) {
    if (!identical(_activeConversationOwner, owner)) return;
    _activeConversationId = null;
    _activeConversationOwner = null;
  }

  Future<void> _onMessage(IncomingMessageEvent event) async {
    final unreadCounts = _unreadCounts;
    if (unreadCounts != null) {
      // Background isolates are recreated between pushes; their counters cannot
      // be the source of truth for an aggregate across different conversations.
      final unread = await unreadCounts();
      _counts
        ..clear()
        ..addEntries(unread.entries.where((entry) => entry.value > 0));
      if (!_counts.containsKey(event.conversationId)) return;
    } else {
      _counts[event.conversationId] = (_counts[event.conversationId] ?? 0) + 1;
    }
    final conversationCount = _counts[event.conversationId]!;
    final total = _counts.values.fold<int>(0, (sum, value) => sum + value);
    final chatCount = _counts.length;
    final privacy = !_session.showNotificationContent;
    final conversationSilent = event.isMuted && !event.isMention;
    // Sohbete ozel ses, uygulama genelindeki ayari EZER. Sessize alinmis bir
    // sohbet yine sessiz kalir: susturma daha guclu bir karar.
    final custom = event.customSound;
    final preference = custom == null
        ? NotificationSoundPreference.fromStorage(_session.notificationSound)
        : NotificationSoundPreference.fromStorage(custom);
    final silent =
        conversationSilent || preference == NotificationSoundPreference.silent;
    final body = privacy
        ? (await _strings.load()).notification_private_summary(total, chatCount)
        : event.preview;
    await _presenter.show(
      LocalMessageNotification(
        id: privacy ? privacyNotificationId : _stableId(event.conversationId),
        title: privacy ? 'Elçim' : event.title,
        body: body,
        payload: privacy ? null : event.conversationId,
        conversationId: privacy
            ? PluginLocalNotificationPresenter.groupKey
            : event.conversationId,
        count: privacy ? total : conversationCount,
        silent: silent,
        hideOnLockScreen: privacy,
        sound: preference.asset,
      ),
    );
  }

  Future<void> clear() async {
    await _enqueue('notification.clear', () async {
      _counts.clear();
      await _presenter.cancelAll();
    });
  }

  Future<void> _enqueue(String name, FutureOr<void> Function() action) {
    if (_disposed) {
      throw StateError('Message notification coordinator is disposed');
    }
    final operation = _operationTail.then<void>((_) => action());
    // Keep the queue usable after a failure; the tracker owns its reporting.
    _operationTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _operations.run(name, operation);
    return operation;
  }

  /// Waits until notification work already accepted from the message stream
  /// has completed without closing the coordinator.
  Future<void> waitForIdle() => _operations.waitForIdle();

  void _onDismissed(NotificationDismissal dismissal) {
    if (dismissal.dismissAll) {
      _counts.clear();
    } else {
      _counts.remove(dismissal.conversationId);
    }
  }

  Future<void> close() async {
    if (_disposed) return;
    _disposed = true;
    await _messageSubscription?.cancel();
    await _dismissSubscription?.cancel();
    _messageSubscription = null;
    _dismissSubscription = null;
    await _operations.close();
  }
}

String _encodeMissedCall(MissedCallNotification notification) =>
    'missed_call|${notification.peerId}|${notification.callType.name}';

MissedCallAction? _decodeMissedCall(String payload) {
  final parts = payload.split('|');
  if (parts.length != 3 || parts.first != 'missed_call') return null;
  return MissedCallAction(
    peerId: parts[1],
    callType: parts[2] == CallType.video.name ? CallType.video : CallType.voice,
  );
}

int _stableId(String value) {
  var hash = 0x811c9dc5;
  for (final codeUnit in value.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash == 0 ? 1 : hash;
}
