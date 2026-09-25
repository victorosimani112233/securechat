import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

import '../config/app_config.dart';
import '../chat/private_chat_control.dart';
import '../contacts/contact_service.dart';
import '../contacts/private_contact_discovery.dart';
import '../contacts/phone_number_sharing_service.dart';
import '../core/signal_message.dart';
import '../crypto/crypto_protocol_store.dart';
import '../crypto/libsignal_protocol_store.dart';
import '../crypto/pre_key_maintenance_service.dart';
import '../crypto/pre_key_manager.dart';
import '../crypto/signal_protocol_crypto_service.dart';
import '../domain/send_message_use_case.dart';
import '../incoming/incoming_message_handler.dart';
import '../l10n/service_strings.dart';
import '../network/network_resilience.dart';
import '../network/tls_pinning.dart';
import '../notifications/message_notification_service.dart';
import '../services/crypto_service.dart';
import '../services/app_resource_scope.dart';
import '../services/async_operation_tracker.dart';
import '../services/key_material_store.dart';
import '../services/session_store.dart';
import '../services/signaling_service.dart';
import '../storage/secure_chat_database.dart';
import '../storage/storage_entities.dart';
import 'background_scheduler.dart';
import 'scheduled_message_service.dart';

typedef BackgroundTaskExecutor =
    Future<bool> Function(String task, Map<String, dynamic>? input);

BackgroundTaskExecutor? backgroundTaskExecutorOverride;

@pragma('vm:entry-point')
void secureChatBackgroundCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    final override = backgroundTaskExecutorOverride;
    if (override != null) return override(task, inputData);
    if (!Platform.isAndroid && !Platform.isIOS) return true;
    final runtime = await SecureChatBackgroundRuntime.open(
      executingPlanId:
          task == WorkmanagerBackgroundScheduler.scheduledMessageTask
          ? (inputData?['planId'] as String?)
          : null,
    );
    try {
      return await runtime.execute(task, inputData);
    } finally {
      await runtime.close();
    }
  });
}

class SecureChatBackgroundRuntime {
  SecureChatBackgroundRuntime._({
    required this.database,
    required this.signaling,
    required this.scheduledMessages,
    required this.timerUpdates,
    required this.senderKeyRotation,
    required this.stuckRecovery,
    required this.session,
    required this.incomingMessages,
    required this.notifications,
    required this.preKeyMaintenance,
    required this.outbox,
    required AppResourceScope resources,
  }) : _resources = resources;

  final SecureChatDatabase database;
  final SignalingService signaling;
  final ScheduledMessageService scheduledMessages;
  final PendingTimerUpdateService timerUpdates;
  final SenderKeyRotationService senderKeyRotation;
  final StuckMessageRecovery stuckRecovery;
  final SessionStore session;
  final IncomingMessageHandler incomingMessages;
  final MessageNotificationCoordinator notifications;
  final PreKeyMaintenanceService preKeyMaintenance;
  final OfflineMessageQueue outbox;
  final AppResourceScope _resources;
  bool _closed = false;

  static Future<SecureChatBackgroundRuntime> open({
    String? executingPlanId,
  }) async {
    final resources = AppResourceScope();
    var bootstrapComplete = false;
    try {
      WidgetsFlutterBinding.ensureInitialized();
      final support = await getApplicationSupportDirectory();
      final keyBytes = await PlatformKeyMaterialStore().readOrCreateMasterKey();
      final storageCrypto = LocalAeadCryptoService(SecretKey(keyBytes));
      final session = await PersistentSessionStore.open(
        file: File('${support.path}/session.securejson'),
        crypto: storageCrypto,
      );
      resources.register('background-session', session.close);
      final database = await SecureChatDatabase.open(
        file: File('${support.path}/securechat_storage.securejson'),
        crypto: storageCrypto,
      );
      resources.register('background-database', database.close);
      final config = AppConfig.current;
      config.validateNetworkSecurity();
      final httpClients = SecureHttpClientFactory(
        TlsPinPolicy.fromConfig(config),
      );
      resources.register('background-http-clients', httpClients.close);
      final signaling = WebSocketSignalingService(
        httpClient: httpClients.create(),
        callCapable: false,
      );
      resources.register('background-signaling', signaling.dispose);
      final outbox = OfflineMessageQueue(
        database: database,
        signaling: signaling,
        onAsyncFailure: (operation, error, stackTrace) async {
          _logBackgroundFailure('BG-OUTBOX', operation, error, stackTrace);
        },
      )..start();
      resources.register('background-outbox', outbox.close);
      final protocolStore = DatabaseCryptoProtocolStore(database);
      final preKeyMaintenance = PreKeyMaintenanceService(
        manager: PreKeyManager(protocolStore),
        apiBaseUrl: Uri.parse(config.apiBaseUrl),
        httpClient: httpClients.create(),
        accessTokenProvider: () async => session.accessToken,
      );
      final crypto = SignalProtocolCryptoService(
        store: PersistentSignalProtocolStore(protocolStore),
        preKeyBundles: HttpPreKeyBundleProvider(
          apiBaseUrl: Uri.parse(config.apiBaseUrl),
          httpClient: httpClients.create(),
          accessTokenProvider: () async => session.accessToken,
        ),
      );
      final contactIdentityResolver = ContactIdentityResolver(
        database: database,
      );
      final phoneSharing = PhoneNumberSharingService(
        session: session,
        crypto: crypto,
        signaling: signaling,
        database: database,
        discovery: PrivateContactDiscoveryApi(
          baseUrl: config.apiBaseUrl,
          client: httpClients.create(),
        ),
        onAsyncFailure: (operation, error, stackTrace) async {
          _logBackgroundFailure('BG-PHONE', operation, error, stackTrace);
        },
      );
      final serviceStrings = ServiceStrings(
        languageCode: () async => session.languagePreference,
      );
      final incomingMessages = IncomingMessageHandler(
        signaling: signaling,
        crypto: crypto,
        database: database,
        session: session,
        strings: serviceStrings,
        identityResolver: contactIdentityResolver,
        phoneSharing: phoneSharing,
        onAsyncFailure: (operation, error, stackTrace) async {
          _logBackgroundFailure('BG-INCOMING', operation, error, stackTrace);
        },
      )..start();
      resources.register(
        'background-incoming-messages',
        incomingMessages.close,
      );
      final notificationPresenter = PluginLocalNotificationPresenter();
      resources.register(
        'background-notification-presenter',
        notificationPresenter.dispose,
      );
      final notifications = MessageNotificationCoordinator(
        incomingMessages: incomingMessages.acceptedMessages,
        session: session,
        presenter: notificationPresenter,
        unreadCounts: database.conversations.unreadCounts,
        onAsyncFailure: (operation, error, stackTrace) async {
          _logBackgroundFailure('BG-NOTIF', operation, error, stackTrace);
        },
      );
      await notifications.start();
      // A background isolate never has a visible conversation. Leaving the
      // coordinator in its foreground default would make notifications silent.
      notifications.setAppForeground(false);
      resources.register('background-notifications', notifications.close);
      final sender = SendMessageUseCase(
        database: database,
        signaling: signaling,
        session: session,
        crypto: crypto,
        reliableQueue: outbox,
        phoneSharing: phoneSharing,
        onAsyncFailure: (operation, error, stackTrace) async {
          _logBackgroundFailure('BG-SEND', operation, error, stackTrace);
        },
      );
      final scheduler = WorkmanagerBackgroundScheduler(
        callbackDispatcher: secureChatBackgroundCallbackDispatcher,
        executingPlanId: executingPlanId,
      );
      final runtime = SecureChatBackgroundRuntime._(
        database: database,
        signaling: signaling,
        scheduledMessages: ScheduledMessageService(
          dao: database.scheduledMessages,
          sender: sender,
          signaling: signaling,
          session: session,
          scheduler: scheduler,
        ),
        timerUpdates: PendingTimerUpdateService(
          dao: database.pendingTimerUpdates,
          signaling: signaling,
          session: session,
          crypto: crypto,
        ),
        senderKeyRotation: SenderKeyRotationService(
          database: database,
          store: protocolStore,
          crypto: crypto,
          signaling: signaling,
          session: session,
        ),
        stuckRecovery: StuckMessageRecovery(database),
        session: session,
        incomingMessages: incomingMessages,
        notifications: notifications,
        preKeyMaintenance: preKeyMaintenance,
        outbox: outbox,
        resources: resources,
      );
      bootstrapComplete = true;
      return runtime;
    } finally {
      if (!bootstrapComplete) await resources.dispose();
    }
  }

  Future<bool> execute(String task, Map<String, dynamic>? input) async {
    if (_closed) throw StateError('Background runtime is closed');
    if (task == WorkmanagerBackgroundScheduler.pushDrainTask) {
      if (!await _connect()) return false;
      await _drainUntilIdle();
      return true;
    }
    if (task == WorkmanagerBackgroundScheduler.scheduledMessageTask) {
      final id = input?['planId'] as String?;
      if (id == null) return false;
      final processed = await processScheduledBackgroundPlan(
        planId: id,
        dao: database.scheduledMessages,
        service: scheduledMessages,
      );
      await _drainOutgoing();
      return processed;
    }
    if (task == WorkmanagerBackgroundScheduler.senderKeyRotationTask) {
      if (!await _connect()) return false;
      return senderKeyRotation.rotateAll();
    }
    if (task == WorkmanagerBackgroundScheduler.maintenanceTask ||
        task == Workmanager.iOSBackgroundTask) {
      await database.messages.deleteExpiredMessages(
        DateTime.now().millisecondsSinceEpoch,
      );
      await stuckRecovery.recoverStuckMessages();
      await preKeyMaintenance.replenishIfNeeded();
      if (await _connect()) {
        await timerUpdates.flush();
        await scheduledMessages.processDue();
        await _drainOutgoing();
      }
      return true;
    }
    return true;
  }

  Future<bool> _connect() async {
    if (signaling.currentStatus.isConnected) return true;
    final userId = session.userId;
    final token = session.accessToken;
    if (userId == null || token == null || token.isEmpty) return false;
    try {
      await signaling.connect(
        userId: userId,
        url: AppConfig.current.signalingUrl,
        accessToken: token,
        tokenProvider: () async => session.accessToken,
      );
      return signaling.ensureConnected(timeout: const Duration(seconds: 8));
    } catch (_) {
      return false;
    }
  }

  Future<void> _drainOutgoing() async {
    await outbox.flushEnqueuedSignals();
    final pending = await waitForBackgroundOutboxReceipts(
      outbox: outbox,
      signaling: signaling,
    );
    await incomingMessages.waitForIdle();
    await notifications.waitForIdle();
    // Local enqueue and a bounded wait are not remote delivery confirmation.
    if (pending > 0) debugPrint('BG-OUTBOX pending=$pending');
  }

  Future<void> _drainUntilIdle({
    Duration idleFor = const Duration(seconds: 3),
    Duration maxWait = const Duration(seconds: 25),
  }) async {
    await waitForBackgroundDrainIdle(
      incomingMessages.acceptedMessages,
      idleFor: idleFor,
      maxWait: maxWait,
    );
    // An accepted-message event is emitted after persistence but before every
    // listener has necessarily finished. Drain both owned async pipelines so
    // runtime teardown cannot cancel notification presentation in flight.
    await incomingMessages.waitForIdle();
    await notifications.waitForIdle();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _resources.dispose();
  }
}

/// Obsolete work is complete, not a retryable send failure. Foreground execution
/// or a user edit may remove/disable the plan before Workmanager invokes it.
Future<bool> processScheduledBackgroundPlan({
  required String planId,
  required ScheduledMessageDao dao,
  required ScheduledMessageService service,
}) async {
  final plan = await dao.getById(planId);
  if (plan == null || !plan.isEnabled) return true;
  return service.processPlan(planId);
}

/// Observes persisted receipts, including commits from another runtime. A
/// timeout/disconnect leaves ciphertext available for the next outbox flush.
Future<int> waitForBackgroundOutboxReceipts({
  required OfflineMessageQueue outbox,
  required SignalingService signaling,
  Duration maxWait = const Duration(seconds: 5),
  Duration pollInterval = const Duration(milliseconds: 100),
}) async {
  if (maxWait.isNegative || pollInterval <= Duration.zero) {
    throw ArgumentError('Invalid outbox receipt wait duration');
  }
  final elapsed = Stopwatch()..start();
  while (true) {
    final pending = await outbox.getPendingCount();
    final remaining = maxWait - elapsed.elapsed;
    if (pending == 0 ||
        !signaling.currentStatus.isConnected ||
        remaining <= Duration.zero) {
      return pending;
    }
    await Future<void>.delayed(
      remaining < pollInterval ? remaining : pollInterval,
    );
  }
}

/// A worker can commit a scheduled send while the main socket stays connected.
/// History is committed after its outbox entries; only new history snapshots
/// trigger a flush, not the receipt/attempt writes made by that flush itself.
class ScheduledOutboxRecovery {
  ScheduledOutboxRecovery({
    required ScheduledMessageDao scheduledMessages,
    required OfflineMessageQueue outbox,
    required SignalingService signaling,
    AsyncOperationFailureHandler? onAsyncFailure,
  }) : _operations = AsyncOperationTracker(onFailure: onAsyncFailure) {
    _subscription = scheduledMessages
        .watchHistory()
        .map((history) => history.map((entry) => entry.id).toList())
        .distinct((previous, next) => listEquals(previous, next))
        .listen(
          (_) {
            if (signaling.currentStatus.isConnected) {
              _operations.run(
                'scheduled-outbox.flush',
                outbox.flushEnqueuedSignals(),
              );
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            _operations.run(
              'scheduled-outbox.history',
              Future<void>.error(error, stackTrace),
            );
          },
        );
  }

  final AsyncOperationTracker _operations;
  late final StreamSubscription<List<String>> _subscription;
  Future<void>? _closeTask;

  Future<void> close() => _closeTask ??= _close();

  Future<void> _close() async {
    await _subscription.cancel();
    await _operations.close();
  }
}

void _logBackgroundFailure(
  String scope,
  String operation,
  Object error,
  StackTrace stackTrace,
) {
  debugPrint('$scope FAIL [$operation]: $error');
  debugPrintStack(label: '$scope STACK [$operation]', stackTrace: stackTrace);
}

/// Waits for a quiet period after the server queue starts draining.
///
/// The hard cap keeps the FCM background callback bounded even if messages
/// continue arriving. Exposed for deterministic timing tests.
Future<void> waitForBackgroundDrainIdle(
  Stream<Object?> activity, {
  Duration idleFor = const Duration(seconds: 3),
  Duration maxWait = const Duration(seconds: 25),
}) async {
  final done = Completer<void>();
  Timer? idle;

  void restartIdleWindow() {
    idle?.cancel();
    idle = Timer(idleFor, () {
      if (!done.isCompleted) done.complete();
    });
  }

  final subscription = activity.listen((_) => restartIdleWindow());
  restartIdleWindow();
  final cap = Timer(maxWait, () {
    if (!done.isCompleted) done.complete();
  });
  try {
    await done.future;
  } finally {
    idle?.cancel();
    cap.cancel();
    await subscription.cancel();
  }
}

class PendingTimerUpdateService {
  PendingTimerUpdateService({
    required PendingTimerUpdateDao dao,
    required SignalingService signaling,
    required SessionStore session,
    required CryptoService crypto,
  }) : _dao = dao,
       _signaling = signaling,
       _session = session,
       _crypto = crypto;

  final PendingTimerUpdateDao _dao;
  final SignalingService _signaling;
  final SessionStore _session;
  final CryptoService _crypto;

  Future<void> sendOrQueue({
    required String targetUserId,
    required String conversationId,
    required int durationMs,
  }) async {
    if (_session.userId == null) return;
    if (!await _send(targetUserId, conversationId, durationMs)) {
      await _dao.insert(
        PendingTimerUpdateEntity(
          id: '${DateTime.now().microsecondsSinceEpoch}-$targetUserId',
          conversationId: conversationId,
          targetUserId: targetUserId,
          duration: durationMs,
        ),
      );
    }
  }

  Future<int> flush() async {
    var sent = 0;
    for (final entry in await _dao.getAll()) {
      if (!await _send(
        entry.targetUserId,
        entry.conversationId,
        entry.duration,
      )) {
        break;
      }
      await _dao.deleteById(entry.id);
      sent++;
    }
    return sent;
  }

  Future<bool> _send(String target, String conversation, int duration) async {
    final senderId = _session.userId;
    if (senderId == null || !_signaling.currentStatus.isConnected) return false;
    return sendPrivateChatControl(
      crypto: _crypto,
      signaling: _signaling,
      control: DisappearingTimerSignal(
        senderId: senderId,
        recipientId: target,
        timestamp: DateTime.now(),
        durationMs: duration,
        conversationId: conversation,
      ),
    );
  }
}

class SenderKeyRotationService {
  SenderKeyRotationService({
    required SecureChatDatabase database,
    required CryptoSenderKeyStore store,
    required CryptoService crypto,
    required SignalingService signaling,
    required SessionStore session,
    Random? random,
  }) : _database = database,
       _store = store,
       _crypto = crypto,
       _signaling = signaling,
       _session = session,
       _random = random ?? Random.secure();

  final SecureChatDatabase _database;
  final CryptoSenderKeyStore _store;
  final CryptoService _crypto;
  final SignalingService _signaling;
  final SessionStore _session;
  final Random _random;

  Future<bool> rotateAll() async {
    var allSucceeded = true;
    for (final group in await _database.conversations.getAllGroups()) {
      if (!await rotate(group.id)) allSucceeded = false;
    }
    return allSucceeded;
  }

  Future<bool> rotate(String groupId) async {
    final senderId = _session.userId;
    final group = await _database.conversations.getById(groupId);
    if (senderId == null || group == null || !group.isGroup) return false;
    final members = _members(group.groupMembers, senderId);
    final stateKey = 'pending_sender_key_rotation:$groupId:$senderId';
    final existing = await _database.cryptoState.get(stateKey);
    final signalCrypto = _crypto;
    final pending = existing == null
        ? await _newPendingKey(signalCrypto, groupId, senderId)
        : _PendingSenderKey.decode(existing);
    await _database.cryptoState.put(stateKey, pending.encode());

    for (final member in members) {
      if (pending.delivered.contains(member)) continue;
      final payload = signalCrypto is SignalProtocolCryptoService
          ? utf8.decode(pending.key)
          : 'SKDM:$groupId:${base64Encode(pending.key)}';
      try {
        final envelope = await _crypto.encryptDirect(
          recipientId: member,
          plaintext: payload,
        );
        final sent = await _signaling.send(
          EncryptedSignalMessage(
            senderId: senderId,
            recipientId: member,
            timestamp: DateTime.now(),
            envelope: envelope,
          ),
        );
        if (!sent) return false;
        pending.delivered.add(member);
        await _database.cryptoState.put(stateKey, pending.encode());
      } catch (_) {
        return false;
      }
    }
    if (signalCrypto is! SignalProtocolCryptoService) {
      await _store.storeSenderKey(groupId, senderId, 1, pending.key);
    }
    await _database.cryptoState.delete(stateKey);
    return true;
  }

  Future<_PendingSenderKey> _newPendingKey(
    CryptoService crypto,
    String groupId,
    String senderId,
  ) async {
    if (crypto is SignalProtocolCryptoService) {
      await crypto.resetLocalSenderKey(groupId, senderId);
      final distribution = await crypto.createSenderKeyDistribution(
        groupId: groupId,
        senderId: senderId,
      );
      return _PendingSenderKey(
        key: utf8.encode(distribution),
        delivered: <String>{},
      );
    }
    return _PendingSenderKey(
      key: List.generate(32, (_) => _random.nextInt(256)),
      delivered: <String>{},
    );
  }
}

class _PendingSenderKey {
  _PendingSenderKey({required this.key, required this.delivered});

  final List<int> key;
  final Set<String> delivered;

  String encode() =>
      jsonEncode({'key': base64Encode(key), 'delivered': delivered.toList()});

  factory _PendingSenderKey.decode(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return _PendingSenderKey(
      key: base64Decode(json['key'] as String),
      delivered: (json['delivered'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toSet(),
    );
  }
}

List<String> _members(String? csv, String localUserId) => csv == null
    ? const []
    : csv
          .split(',')
          .map((member) => member.trim())
          .where((member) => member.isNotEmpty && member != localUserId)
          .toSet()
          .toList(growable: false);
