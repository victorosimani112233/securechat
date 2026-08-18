import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../incoming/incoming_message_handler.dart';
import '../media/call_models.dart';
import '../services/session_store.dart';
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
  });

  final int id;
  final String title;
  final String body;
  final String? payload;
  final String conversationId;
  final int count;
  final bool silent;
  final bool hideOnLockScreen;
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
  });
  final int id;
  final String callId;
  final String peerId;
  final String peerName;
  final CallType callType;
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

class PluginLocalNotificationPresenter
    implements LocalNotificationPresenter, MissedCallNotificationPresenter {
  PluginLocalNotificationPresenter({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const highChannelId = 'elcim_messages_v4';
  static const lowChannelId = 'elcim_messages_low_v1';
  static const groupKey = 'elcim_messages';

  final FlutterLocalNotificationsPlugin _plugin;
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
    final channelId = notification.silent ? lowChannelId : highChannelId;
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        notification.silent ? 'Elçim Mesajlar (Sessiz)' : 'Elçim Mesajlar',
        channelDescription: notification.silent
            ? 'Sessize alınmış veya uygulama içi mesajlar'
            : 'Gelen güvenli mesaj bildirimleri',
        icon: 'notification_icon',
        importance: notification.silent ? Importance.low : Importance.high,
        priority: notification.silent ? Priority.low : Priority.high,
        playSound: !notification.silent,
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
        threadIdentifier: notification.conversationId,
        categoryIdentifier: 'securechat_message',
      ),
    );
    await _plugin.show(
      id: notification.id,
      title: notification.title,
      body: notification.body,
      notificationDetails: details,
      payload: notification.payload,
    );
    _shownMessages[notification.id] = notification.hideOnLockScreen
        ? null
        : notification.conversationId;
  }

  @override
  Future<void> showMissedCall(MissedCallNotification notification) async {
    final payload = _encodeMissedCall(notification);
    await _plugin.show(
      id: notification.id,
      title: notification.callType == CallType.video
          ? 'Kaçırılan Görüntülü Arama'
          : 'Kaçırılan Sesli Arama',
      body: '${notification.peerName} tarafından',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'missed_call_channel',
          'Kaçırılan Aramalar',
          channelDescription: 'Cevaplanmayan arama bildirimleri',
          icon: 'notification_icon',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          category: AndroidNotificationCategory.missedCall,
          visibility: NotificationVisibility.secret,
          actions: const [
            AndroidNotificationAction(
              'call_back',
              'Geri Ara',
              showsUserInterface: true,
            ),
          ],
        ),
        iOS: const DarwinNotificationDetails(
          categoryIdentifier: 'securechat_missed_call',
          presentAlert: true,
          presentSound: true,
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
    AsyncOperationFailureHandler? onAsyncFailure,
  }) : _incomingMessages = incomingMessages,
       _session = session,
       _presenter = presenter,
       _operations = AsyncOperationTracker(onFailure: onAsyncFailure);

  static const privacyNotificationId = 104729;

  final Stream<IncomingMessageEvent> _incomingMessages;
  final SessionStore _session;
  final LocalNotificationPresenter _presenter;
  final AsyncOperationTracker _operations;
  final _counts = <String, int>{};
  StreamSubscription<IncomingMessageEvent>? _messageSubscription;
  StreamSubscription<NotificationDismissal>? _dismissSubscription;
  bool _isForeground = true;
  String? _activeConversationId;
  bool _disposed = false;

  Stream<String> get taps => _presenter.taps;

  Future<void> start() async {
    if (_disposed) {
      throw StateError('Message notification coordinator is disposed');
    }
    await _presenter.initialize();
    _dismissSubscription ??= _presenter.dismissals.listen(_onDismissed);
    _messageSubscription ??= _incomingMessages.listen((event) {
      _operations.run('notification.present-message', _onMessage(event));
    });
  }

  void setAppForeground(bool foreground) {
    _isForeground = foreground;
    if (foreground && !_disposed) {
      _operations.run(
        'notification.reconcile-dismissals',
        _presenter.reconcileDismissals(),
      );
    }
  }

  void setActiveConversation(String? conversationId) {
    _activeConversationId = conversationId;
  }

  Future<void> _onMessage(IncomingMessageEvent event) async {
    if (_isForeground && _activeConversationId == event.conversationId) return;
    _counts[event.conversationId] = (_counts[event.conversationId] ?? 0) + 1;
    final total = _counts.values.fold<int>(0, (sum, value) => sum + value);
    final privacy = !_session.showNotificationContent;
    final conversationSilent = event.isMuted && !event.isMention;
    final silent =
        _isForeground ||
        conversationSilent ||
        _session.notificationSound == 'silent';
    await _presenter.show(
      LocalMessageNotification(
        id: privacy ? privacyNotificationId : _stableId(event.conversationId),
        title: privacy ? 'Elçim' : event.title,
        body: privacy
            ? (_counts.length > 1
                  ? '${_counts.length} sohbetten $total yeni mesaj'
                  : '$total yeni mesaj')
            : event.preview,
        payload: privacy ? null : event.conversationId,
        conversationId: event.conversationId,
        count: privacy ? total : _counts[event.conversationId]!,
        silent: silent,
        hideOnLockScreen: privacy,
      ),
    );
  }

  Future<void> clear() async {
    _counts.clear();
    await _presenter.cancelAll();
  }

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
