import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../background/background_scheduler.dart';
import '../background/background_tasks.dart';
import '../config/app_config.dart';
import '../services/session_store.dart';
import '../services/async_operation_tracker.dart';
import '../services/signaling_service.dart';

class PushWakeEvent {
  const PushWakeEvent({required this.type});

  final String type;

  factory PushWakeEvent.fromMap(Map<String, dynamic> data) =>
      PushWakeEvent(type: data['type']?.toString() ?? '');

  bool get isWakeUp => type == 'securechat_wake_v2';
}

abstract interface class PushTransport {
  Stream<String> get tokenRefreshes;
  Stream<PushWakeEvent> get foregroundMessages;
  Future<bool> requestPermission();
  Future<String?> getToken();
  Future<void> deleteToken();
}

class FirebasePushTransport implements PushTransport {
  FirebasePushTransport(this._messaging);

  final FirebaseMessaging _messaging;

  static Future<FirebasePushTransport?> create() async {
    final options = SecureChatFirebaseOptions.current;
    if (options == null) return null;
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: options);
    }
    FirebaseMessaging.onBackgroundMessage(firebasePushBackgroundHandler);
    return FirebasePushTransport(FirebaseMessaging.instance);
  }

  @override
  Stream<PushWakeEvent> get foregroundMessages => FirebaseMessaging.onMessage
      .map((message) => PushWakeEvent.fromMap(message.data));

  @override
  Stream<String> get tokenRefreshes => _messaging.onTokenRefresh;

  @override
  Future<String?> getToken() => _messaging.getToken();

  @override
  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<void> deleteToken() => _messaging.deleteToken();
}

class SecureChatFirebaseOptions {
  static const _apiKey = String.fromEnvironment(
    'SECURECHAT_FIREBASE_API_KEY',
    defaultValue: 'AIzaSyAu1GrkhnKgiI7eNcsXDG-mZ4tudmrN6u0',
  );
  static const _senderId = String.fromEnvironment(
    'SECURECHAT_FIREBASE_SENDER_ID',
    defaultValue: '791820453236',
  );
  static const _projectId = String.fromEnvironment(
    'SECURECHAT_FIREBASE_PROJECT_ID',
    defaultValue: 'chat-3e219',
  );
  static const _bucket = String.fromEnvironment(
    'SECURECHAT_FIREBASE_STORAGE_BUCKET',
    defaultValue: 'chat-3e219.firebasestorage.app',
  );

  static FirebaseOptions? get current {
    if (kIsWeb) return null;
    if (Platform.isAndroid) {
      return const FirebaseOptions(
        apiKey: _apiKey,
        appId: String.fromEnvironment(
          'SECURECHAT_FIREBASE_ANDROID_APP_ID',
          defaultValue: '1:791820453236:android:d570570ff740a58e685821',
        ),
        messagingSenderId: _senderId,
        projectId: _projectId,
        storageBucket: _bucket,
      );
    }
    if (Platform.isIOS) {
      // Android tarafinda varsayilan gomulu oldugu icin kutudan calisiyordu;
      // iOS'ta varsayilan yoktu ve define verilmeyince FirebaseOptions null
      // donuyordu. Sonuc: iOS'ta push SESSIZCE devre disi kaliyordu. Ayni
      // Firebase projesindeki (chat-3e219) iOS uygulamasinin app id'si
      // varsayilan yapildi; ozel dagitimlar define ile ezebilir.
      const appId = String.fromEnvironment(
        'SECURECHAT_FIREBASE_IOS_APP_ID',
        defaultValue: '1:791820453236:ios:989a9c79e4e79ec3685821',
      );
      if (appId.isEmpty) return null;
      return const FirebaseOptions(
        apiKey: _apiKey,
        appId: appId,
        messagingSenderId: _senderId,
        projectId: _projectId,
        storageBucket: _bucket,
        iosBundleId: 'com.securechat.app',
      );
    }
    return null;
  }
}

class PushTokenApi {
  PushTokenApi({required this.baseUrl, HttpClient? client})
    : _client = client ?? HttpClient();
  final String baseUrl;
  final HttpClient _client;
  static const requestTimeout = Duration(seconds: 15);
  static const responseTimeout = Duration(seconds: 20);

  Future<bool> register({
    required String userId,
    required String token,
    required String accessToken,
    String? pushHintKey,
  }) => _post('/api/v1/fcm/register', {
    'userId': userId,
    'fcmToken': token,
    if (pushHintKey != null) 'pushHintKey': pushHintKey,
  }, accessToken);

  Future<bool> unregister({
    required String userId,
    required String accessToken,
  }) => _post('/api/v1/fcm/unregister', {'userId': userId}, accessToken);

  Future<bool> _post(
    String path,
    Map<String, Object?> body,
    String accessToken,
  ) async {
    final request = await _client
        .postUrl(Uri.parse('$baseUrl$path'))
        .timeout(requestTimeout);
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $accessToken');
    request.write(jsonEncode(body));
    final response = await request.close().timeout(responseTimeout);
    final statusCode = response.statusCode;
    await response.drain<void>().timeout(responseTimeout);
    return statusCode >= 200 && statusCode < 300;
  }
}

abstract interface class PushHintKeyProvider {
  Future<String?> getOrCreateKey();
}

class PlatformPushHintKeyProvider implements PushHintKeyProvider {
  const PlatformPushHintKeyProvider({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('com.securechat/native');

  final MethodChannel _channel;

  @override
  Future<String?> getOrCreateKey() async {
    if (kIsWeb || !Platform.isAndroid) return null;
    final value = await _channel.invokeMethod<String>('getOrCreatePushHintKey');
    if (value == null || value.isEmpty) {
      throw StateError('Android push hint key is unavailable');
    }
    return value;
  }
}

class PushCoordinator {
  PushCoordinator({
    required PushTransport transport,
    required PushTokenApi api,
    required SessionStore session,
    required SignalingService signaling,
    PushHintKeyProvider? pushHintKeys,
    AsyncOperationFailureHandler? onAsyncFailure,
  }) : _transport = transport,
       _api = api,
       _session = session,
       _signaling = signaling,
       _pushHintKeys = pushHintKeys ?? const PlatformPushHintKeyProvider(),
       _onAsyncFailure = onAsyncFailure,
       _operations = AsyncOperationTracker(onFailure: onAsyncFailure);

  final PushTransport _transport;
  final PushTokenApi _api;
  final SessionStore _session;
  final SignalingService _signaling;
  final PushHintKeyProvider _pushHintKeys;
  final AsyncOperationFailureHandler? _onAsyncFailure;
  final AsyncOperationTracker _operations;
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<PushWakeEvent>? _messageSubscription;
  Future<void>? _closeTask;
  bool _closed = false;

  Future<void> initialize() async {
    if (_closed) throw StateError('Push coordinator is closed');
    _tokenSubscription ??= _transport.tokenRefreshes.listen((token) {
      _operations.run('push.register-refreshed-token', _registerSafely(token));
    });
    _messageSubscription ??= _transport.foregroundMessages.listen((event) {
      _operations.run('push.foreground-wake', _wakeSafely(event));
    });
    await refreshRegistration();
  }

  Future<bool> requestPermissionAndRegister() async {
    final granted = await _transport.requestPermission();
    if (!granted) return false;
    await refreshRegistration();
    return true;
  }

  Future<bool> registerToken(String token) async {
    _session.pushToken = token;
    if (_session is PersistentSessionStore) {
      await _session.persist();
    }
    final userId = _session.userId;
    final accessToken = _session.accessToken;
    if (userId == null || accessToken == null || accessToken.isEmpty)
      return false;
    final pushHintKey = await _pushHintKeys.getOrCreateKey();
    final registered = await _api.register(
      userId: userId,
      token: token,
      accessToken: accessToken,
      pushHintKey: pushHintKey,
    );
    if (!kIsWeb && Platform.isAndroid) {
      debugPrint(
        registered
            ? 'PUSH-REGISTRATION hint_submitted'
            : 'PUSH-REGISTRATION request_rejected',
      );
    }
    return registered;
  }

  Future<bool> refreshRegistration() async {
    try {
      final token = await _transport.getToken();
      if (token == null || token.isEmpty) return false;
      return await registerToken(token);
    } catch (error, stackTrace) {
      await _reportFailure('push.register-current-token', error, stackTrace);
      return false;
    }
  }

  Future<bool> _registerSafely(String token) async {
    try {
      return await registerToken(token);
    } catch (error, stackTrace) {
      await _reportFailure('push.register-refreshed-token', error, stackTrace);
      return false;
    }
  }

  Future<bool> unregister() async {
    final userId = _session.userId;
    final accessToken = _session.accessToken;
    if (userId == null || accessToken == null || accessToken.isEmpty)
      return false;
    final removed = await _api.unregister(
      userId: userId,
      accessToken: accessToken,
    );
    if (removed) {
      await _transport.deleteToken();
      _session.pushToken = null;
      if (_session is PersistentSessionStore) {
        await _session.persist();
      }
    }
    return removed;
  }

  Future<void> _wake(PushWakeEvent event) async {
    if (!event.isWakeUp || !_session.isLoggedIn) return;
    if (!_signaling.currentStatus.isConnected) {
      await _signaling.connect(
        userId: _session.userId!,
        url: AppConfig.current.signalingUrl,
        accessToken: _session.accessToken!,
        tokenProvider: () async => _session.accessToken,
      );
    }
    await _signaling.ensureConnected(timeout: const Duration(seconds: 10));
  }

  Future<void> _wakeSafely(PushWakeEvent event) async {
    try {
      await _wake(event);
    } catch (error, stackTrace) {
      await _reportFailure('push.foreground-wake', error, stackTrace);
      // Foreground/lifecycle reconciliation retries the same encrypted queue.
    }
  }

  Future<void> _reportFailure(
    String operation,
    Object error,
    StackTrace stackTrace,
  ) async {
    debugPrint('PUSH-FAIL [$operation]: ${error.runtimeType}');
    final handler = _onAsyncFailure;
    if (handler == null) return;
    try {
      await handler(operation, error, stackTrace);
    } catch (_) {
      // Diagnostics must never replace the original recoverable push failure.
    }
  }

  Future<void> close() {
    final active = _closeTask;
    if (active != null) return active;
    _closed = true;
    final operation = _close();
    _closeTask = operation;
    return operation;
  }

  Future<void> _close() async {
    await _tokenSubscription?.cancel();
    await _messageSubscription?.cancel();
    _tokenSubscription = null;
    _messageSubscription = null;
    await _operations.close();
  }
}

@pragma('vm:entry-point')
Future<void> firebasePushBackgroundHandler(RemoteMessage message) async {
  final event = PushWakeEvent.fromMap(message.data);
  if (!event.isWakeUp) return;
  SecureChatBackgroundRuntime? runtime;
  try {
    final options = SecureChatFirebaseOptions.current;
    if (options != null && Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: options);
    }
    runtime = await SecureChatBackgroundRuntime.open();
    await runtime.execute(
      WorkmanagerBackgroundScheduler.pushDrainTask,
      message.data,
    );
  } catch (error, stackTrace) {
    debugPrint('BG-RUNTIME FAIL: $error');
    debugPrintStack(label: 'BG-RUNTIME STACK', stackTrace: stackTrace);
  } finally {
    await runtime?.close();
  }
}
