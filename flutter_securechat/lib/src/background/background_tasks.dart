import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

import '../config/app_config.dart';
import '../chat/private_chat_control.dart';
import '../contacts/contact_service.dart';
import '../core/signal_message.dart';
import '../crypto/crypto_protocol_store.dart';
import '../crypto/libsignal_protocol_store.dart';
import '../crypto/pre_key_maintenance_service.dart';
import '../crypto/pre_key_manager.dart';
import '../crypto/signal_protocol_crypto_service.dart';
import '../domain/send_message_use_case.dart';
import '../incoming/incoming_message_handler.dart';
import '../network/network_resilience.dart';
import '../network/tls_pinning.dart';
import '../services/crypto_service.dart';
import '../services/app_resource_scope.dart';
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
    final runtime = await SecureChatBackgroundRuntime.open();
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
    required this.preKeyMaintenance,
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
  final PreKeyMaintenanceService preKeyMaintenance;
  final AppResourceScope _resources;
  bool _closed = false;

  static Future<SecureChatBackgroundRuntime> open() async {
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
      );
      resources.register('background-signaling', signaling.dispose);
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
      final incomingMessages = IncomingMessageHandler(
        signaling: signaling,
        crypto: crypto,
        database: database,
        session: session,
        identityResolver: contactIdentityResolver,
      )..start();
      resources.register(
        'background-incoming-messages',
        incomingMessages.close,
      );
      final sender = SendMessageUseCase(
        database: database,
        signaling: signaling,
        session: session,
        crypto: crypto,
      );
      const scheduler = WorkmanagerBackgroundScheduler(
        callbackDispatcher: secureChatBackgroundCallbackDispatcher,
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
        preKeyMaintenance: preKeyMaintenance,
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
      await Future<void>.delayed(const Duration(seconds: 5));
      return true;
    }
    if (task == WorkmanagerBackgroundScheduler.scheduledMessageTask) {
      final id = input?['planId'] as String?;
      return id != null && await scheduledMessages.processPlan(id);
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

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _resources.dispose();
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
