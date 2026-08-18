import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import '../auth/auth_api.dart';
import '../auth/auth_coordinator.dart';
import '../background/background_scheduler.dart';
import '../background/background_tasks.dart';
import '../background/scheduled_message_service.dart';
import '../backup/backup_service.dart';
import '../bulk/bulk_message_service.dart';
import '../chat/chat_info_service.dart';
import '../chat/chat_activity_service.dart';
import '../chat/message_forwarding_service.dart';
import '../chat/read_receipt_service.dart';
import '../calls/call_readiness_service.dart';
import '../calls/call_history_service.dart';
import '../chat/poll_service.dart';
import '../chat/message_interaction_service.dart';
import '../config/app_config.dart';
import '../contacts/contact_service.dart';
import '../contacts/private_contact_discovery.dart';
import '../crypto/call_crypto_manager.dart';
import '../crypto/crypto_protocol_store.dart';
import '../crypto/libsignal_protocol_store.dart';
import '../crypto/pre_key_manager.dart';
import '../crypto/pre_key_maintenance_service.dart';
import '../crypto/signal_protocol_crypto_service.dart';
import '../domain/send_message_use_case.dart';
import '../diagnostics/crash_reporter.dart';
import '../debug/notification_debug_harness.dart';
import '../export/export_audit_service.dart';
import '../groups/group_management_service.dart';
import '../groups/private_group_control.dart';
import '../media/call_manager.dart';
import '../media/file_transfer_manager.dart';
import '../media/group_media_engine.dart';
import '../media/ice_server_fetcher.dart';
import '../media/janus_client.dart';
import '../media/local_file_actions.dart';
import '../media/media_engine.dart';
import '../media/media_attachment.dart';
import '../media/media_message_service.dart';
import '../media/native_call_integration.dart';
import '../media/voice_note_service.dart';
import '../incoming/incoming_message_handler.dart';
import '../network/network_resilience.dart';
import '../network/network_monitor.dart';
import '../network/socket_diagnostics.dart';
import '../network/tls_pinning.dart';
import '../notifications/message_notification_service.dart';
import '../notifications/missed_call_tracker.dart';
import '../onboarding/onboarding_service.dart';
import '../onboarding/permission_service.dart';
import '../platform/mobile_permission_platform.dart';
import '../push/push_service.dart';
import '../settings/settings_service.dart';
import '../settings/account_data_service.dart';
import '../security/chat_access_service.dart';
import '../storage/secure_chat_database.dart';
import '../storage/legacy_room_importer.dart';
import '../storage/storage_management_service.dart';
import 'conversation_repository.dart';
import 'app_connection_status.dart';
import 'peer_activity_source.dart';
import 'app_lifecycle_coordinator.dart';
import 'app_resource_scope.dart';
import 'crypto_service.dart';
import 'key_material_store.dart';
import 'session_store.dart';
import 'signaling_service.dart';

class AppContainer {
  AppContainer._({
    required this.session,
    required this.conversations,
    required this.crypto,
    required this.signaling,
    this.cryptoRuntime,
    this.networkRuntime,
    this.auth,
    this.contacts,
    this.mediaRuntime,
    this.backgroundRuntime,
    this.pushRuntime,
    this.backupRuntime,
    this.auditRuntime,
    this.groupRuntime,
    this.storageRuntime,
    this.chatInfoRuntime,
    this.forwardRuntime,
    this.readReceiptRuntime,
    this.onboardingRuntime,
    this.bulkRuntime,
    this.lifecycleRuntime,
    this.settingsRuntime,
    this.accountDataRuntime,
    this.notificationRuntime,
    this.diagnosticsRuntime,
    this.debugRuntime,
    required this.chatAccessRuntime,
    required this.callReadinessRuntime,
    this.resources,
  });

  @visibleForTesting
  factory AppContainer.testing({
    required SessionStore session,
    required ConversationRepository conversations,
    required CryptoService crypto,
    required SignalingService signaling,
    AppCryptoRuntime? cryptoRuntime,
    AppNetworkRuntime? networkRuntime,
    AuthCoordinator? auth,
    ContactService? contacts,
    AppMediaRuntime? mediaRuntime,
    AppBackgroundRuntime? backgroundRuntime,
    AppPushRuntime? pushRuntime,
    AppBackupRuntime? backupRuntime,
    AppAuditRuntime? auditRuntime,
    AppGroupRuntime? groupRuntime,
    AppStorageRuntime? storageRuntime,
    AppChatInfoRuntime? chatInfoRuntime,
    AppForwardRuntime? forwardRuntime,
    AppReadReceiptRuntime? readReceiptRuntime,
    AppOnboardingRuntime? onboardingRuntime,
    AppBulkRuntime? bulkRuntime,
    AppLifecycleCoordinator? lifecycleRuntime,
    AppSettingsRuntime? settingsRuntime,
    AppAccountDataRuntime? accountDataRuntime,
    AppNotificationRuntime? notificationRuntime,
    AppDiagnosticsRuntime? diagnosticsRuntime,
    AppDebugRuntime? debugRuntime,
    required AppChatAccessRuntime chatAccessRuntime,
    required AppCallReadinessRuntime callReadinessRuntime,
  }) => AppContainer._(
    session: session,
    conversations: conversations,
    crypto: crypto,
    signaling: signaling,
    cryptoRuntime: cryptoRuntime,
    networkRuntime: networkRuntime,
    auth: auth,
    contacts: contacts,
    mediaRuntime: mediaRuntime,
    backgroundRuntime: backgroundRuntime,
    pushRuntime: pushRuntime,
    backupRuntime: backupRuntime,
    auditRuntime: auditRuntime,
    groupRuntime: groupRuntime,
    storageRuntime: storageRuntime,
    chatInfoRuntime: chatInfoRuntime,
    forwardRuntime: forwardRuntime,
    readReceiptRuntime: readReceiptRuntime,
    onboardingRuntime: onboardingRuntime,
    bulkRuntime: bulkRuntime,
    lifecycleRuntime: lifecycleRuntime,
    settingsRuntime: settingsRuntime,
    accountDataRuntime: accountDataRuntime,
    notificationRuntime: notificationRuntime,
    diagnosticsRuntime: diagnosticsRuntime,
    debugRuntime: debugRuntime,
    chatAccessRuntime: chatAccessRuntime,
    callReadinessRuntime: callReadinessRuntime,
    resources: null,
  );

  factory AppContainer.production({
    required SessionStore session,
    required ConversationRepository conversations,
    required CryptoService crypto,
    required SignalingService signaling,
    required AppCryptoRuntime cryptoRuntime,
    required AppNetworkRuntime networkRuntime,
    required AuthCoordinator auth,
    required ContactService contacts,
    required AppMediaRuntime mediaRuntime,
    required AppBackgroundRuntime backgroundRuntime,
    AppPushRuntime? pushRuntime,
    required AppBackupRuntime backupRuntime,
    required AppAuditRuntime auditRuntime,
    required AppGroupRuntime groupRuntime,
    required AppStorageRuntime storageRuntime,
    required AppChatInfoRuntime chatInfoRuntime,
    required AppForwardRuntime forwardRuntime,
    required AppReadReceiptRuntime readReceiptRuntime,
    required AppOnboardingRuntime onboardingRuntime,
    required AppBulkRuntime bulkRuntime,
    required AppLifecycleCoordinator lifecycleRuntime,
    required AppSettingsRuntime settingsRuntime,
    required AppAccountDataRuntime accountDataRuntime,
    required AppNotificationRuntime notificationRuntime,
    required AppDiagnosticsRuntime diagnosticsRuntime,
    AppDebugRuntime? debugRuntime,
    required AppChatAccessRuntime chatAccessRuntime,
    required AppCallReadinessRuntime callReadinessRuntime,
    required AppResourceScope resources,
  }) {
    final container = AppContainer._(
      session: session,
      conversations: conversations,
      crypto: crypto,
      signaling: signaling,
      cryptoRuntime: cryptoRuntime,
      networkRuntime: networkRuntime,
      auth: auth,
      contacts: contacts,
      mediaRuntime: mediaRuntime,
      backgroundRuntime: backgroundRuntime,
      pushRuntime: pushRuntime,
      backupRuntime: backupRuntime,
      auditRuntime: auditRuntime,
      groupRuntime: groupRuntime,
      storageRuntime: storageRuntime,
      chatInfoRuntime: chatInfoRuntime,
      forwardRuntime: forwardRuntime,
      readReceiptRuntime: readReceiptRuntime,
      onboardingRuntime: onboardingRuntime,
      bulkRuntime: bulkRuntime,
      lifecycleRuntime: lifecycleRuntime,
      settingsRuntime: settingsRuntime,
      accountDataRuntime: accountDataRuntime,
      notificationRuntime: notificationRuntime,
      diagnosticsRuntime: diagnosticsRuntime,
      debugRuntime: debugRuntime,
      chatAccessRuntime: chatAccessRuntime,
      callReadinessRuntime: callReadinessRuntime,
      resources: resources,
    );
    container._validateProductionGraph();
    return container;
  }

  final SessionStore session;
  final ConversationRepository conversations;
  final CryptoService crypto;
  final SignalingService signaling;
  late final AppConnectionStatusSource connectionStatus =
      SignalingConnectionStatusSource(signaling);
  late final AppPeerActivitySource? peerActivity = networkRuntime == null
      ? null
      : IncomingPeerActivitySource(networkRuntime!.incomingMessages);
  final AppCryptoRuntime? cryptoRuntime;
  final AppNetworkRuntime? networkRuntime;
  final AuthCoordinator? auth;
  final ContactService? contacts;
  final AppMediaRuntime? mediaRuntime;
  final AppBackgroundRuntime? backgroundRuntime;
  final AppPushRuntime? pushRuntime;
  final AppBackupRuntime? backupRuntime;
  final AppAuditRuntime? auditRuntime;
  final AppGroupRuntime? groupRuntime;
  final AppStorageRuntime? storageRuntime;
  final AppChatInfoRuntime? chatInfoRuntime;
  final AppForwardRuntime? forwardRuntime;
  final AppReadReceiptRuntime? readReceiptRuntime;
  final AppOnboardingRuntime? onboardingRuntime;
  final AppBulkRuntime? bulkRuntime;
  final AppLifecycleCoordinator? lifecycleRuntime;
  final AppSettingsRuntime? settingsRuntime;
  final AppAccountDataRuntime? accountDataRuntime;
  final AppNotificationRuntime? notificationRuntime;
  final AppDiagnosticsRuntime? diagnosticsRuntime;
  final AppDebugRuntime? debugRuntime;
  final AppChatAccessRuntime chatAccessRuntime;
  final AppCallReadinessRuntime callReadinessRuntime;
  final AppResourceScope? resources;
  Future<void>? _disposeTask;

  bool get ownsProductionResources => resources != null;

  Future<void> dispose() {
    final active = _disposeTask;
    if (active != null) return active;
    final operation =
        resources?.dispose() ??
        lifecycleRuntime?.dispose() ??
        Future<void>.value();
    _disposeTask = operation;
    return operation;
  }

  void _validateProductionGraph() {
    final requiredFeatures = <String, Object?>{
      'crypto': cryptoRuntime,
      'network': networkRuntime,
      'auth': auth,
      'contacts': contacts,
      'media': mediaRuntime,
      'background': backgroundRuntime,
      'backup': backupRuntime,
      'audit': auditRuntime,
      'groups': groupRuntime,
      'storage': storageRuntime,
      'chat-info': chatInfoRuntime,
      'forwarding': forwardRuntime,
      'read-receipts': readReceiptRuntime,
      'onboarding': onboardingRuntime,
      'bulk-messages': bulkRuntime,
      'lifecycle': lifecycleRuntime,
      'settings': settingsRuntime,
      'account-data': accountDataRuntime,
      'notifications': notificationRuntime,
      'diagnostics': diagnosticsRuntime,
    };
    final missing = requiredFeatures.entries
        .where((entry) => entry.value == null)
        .map((entry) => entry.key)
        .toList(growable: false);
    if (missing.isNotEmpty) {
      throw StateError(
        'Production dependency graph is incomplete: ${missing.join(', ')}',
      );
    }
  }

  static Future<AppContainer> bootstrap({
    KeyMaterialStore? keyMaterial,
    BackgroundScheduler? backgroundScheduler,
    LegacyRoomGateway? legacyRoomGateway,
    PrivacyCrashReporter? crashReporter,
  }) async {
    final resources = AppResourceScope();
    var bootstrapComplete = false;
    try {
      final config = AppConfig.current;
      config.validateNetworkSecurity();
      final httpClients = SecureHttpClientFactory(
        TlsPinPolicy.fromConfig(config),
      );
      resources.register('secure-http-clients', httpClients.close);
      final support = await getApplicationSupportDirectory();
      final diagnostics =
          crashReporter ??
          await PrivacyCrashReporter.open(
            directory: Directory('${support.path}/crash_logs'),
          );
      Future<void> reportAsyncFailure(
        String operation,
        Object error,
        StackTrace stackTrace,
      ) => diagnostics
          .recordException(
            error,
            stackTrace,
            context: operation,
            metadata: const {'component': 'owned-async-operation'},
          )
          .then<void>((_) {});
      final keyBytes = await (keyMaterial ?? PlatformKeyMaterialStore())
          .readOrCreateMasterKey();
      final storageCrypto = LocalAeadCryptoService(SecretKey(keyBytes));
      final session = await PersistentSessionStore.open(
        file: File('${support.path}/session.securejson'),
        crypto: storageCrypto,
        onAsyncFailure: reportAsyncFailure,
      );
      resources.register('persistent-session', session.close);
      diagnostics.setUserId(session.userId);
      final database = await SecureChatDatabase.open(
        file: File('${support.path}/securechat_storage.securejson'),
        crypto: storageCrypto,
      );
      resources.register('secure-database', database.close);
      await LegacyRoomImporter(
        database: database,
        gateway: legacyRoomGateway ?? const MethodChannelLegacyRoomGateway(),
      ).run();
      final signaling = WebSocketSignalingService(
        httpClient: httpClients.create(),
      );
      resources.register('websocket-signaling', signaling.dispose);
      final networkMonitor = SystemNetworkMonitor();
      resources.register('network-monitor', networkMonitor.dispose);
      final protocolStore = DatabaseCryptoProtocolStore(database);
      final preKeyManager = PreKeyManager(protocolStore);
      final preKeyMaintenance = PreKeyMaintenanceService(
        manager: preKeyManager,
        apiBaseUrl: Uri.parse(config.apiBaseUrl),
        httpClient: httpClients.create(),
        accessTokenProvider: () async => session.accessToken,
      );
      final contactIdentityResolver = ContactIdentityResolver(
        database: database,
      );
      final signalStore = PersistentSignalProtocolStore(protocolStore);
      final crypto = SignalProtocolCryptoService(
        store: signalStore,
        preKeyBundles: HttpPreKeyBundleProvider(
          apiBaseUrl: Uri.parse(config.apiBaseUrl),
          httpClient: httpClients.create(),
          accessTokenProvider: () async => session.accessToken,
        ),
      );
      final offlineQueue = OfflineMessageQueue(
        database: database,
        signaling: signaling,
        onAsyncFailure: reportAsyncFailure,
      )..start();
      resources.register('offline-message-queue', offlineQueue.close);
      final incomingMessages = IncomingMessageHandler(
        signaling: signaling,
        crypto: crypto,
        database: database,
        session: session,
        identityResolver: contactIdentityResolver,
        onAsyncFailure: reportAsyncFailure,
      )..start();
      resources.register('incoming-message-handler', incomingMessages.close);
      final messageSender = SendMessageUseCase(
        database: database,
        signaling: signaling,
        session: session,
        crypto: crypto,
      );
      final chatActivity = ChatActivityService(
        session: session,
        signaling: signaling,
        crypto: crypto,
      );
      resources.register('chat-activity', chatActivity.dispose);
      final scheduler =
          backgroundScheduler ??
          const WorkmanagerBackgroundScheduler(
            callbackDispatcher: secureChatBackgroundCallbackDispatcher,
          );
      await scheduler.initialize();
      await scheduler.registerRecurringTasks();
      final scheduledMessages = ScheduledMessageService(
        dao: database.scheduledMessages,
        sender: messageSender,
        signaling: signaling,
        session: session,
        scheduler: scheduler,
      );
      final timerUpdates = PendingTimerUpdateService(
        dao: database.pendingTimerUpdates,
        signaling: signaling,
        session: session,
        crypto: crypto,
      );
      final pushTransport = await FirebasePushTransport.create();
      final pushCoordinator = pushTransport == null
          ? null
          : PushCoordinator(
              transport: pushTransport,
              api: PushTokenApi(
                baseUrl: config.apiBaseUrl,
                client: httpClients.create(),
              ),
              session: session,
              signaling: signaling,
              onAsyncFailure: reportAsyncFailure,
            );
      await pushCoordinator?.initialize();
      if (pushCoordinator != null) {
        resources.register('push-coordinator', pushCoordinator.close);
      }
      final mediaEngine = WebRtcMediaEngine();
      final nativeCalls = MethodChannelNativeCallIntegration(
        redactIdentity: () => !session.showNotificationContent,
      );
      await nativeCalls.initialize();
      resources.register('native-call-integration', nativeCalls.dispose);
      final notificationPresenter = PluginLocalNotificationPresenter();
      resources.register(
        'local-notification-presenter',
        notificationPresenter.dispose,
      );
      late final CallManager callManager;
      final missedCalls = MissedCallTracker(
        conversations: database.conversations,
        presenter: notificationPresenter,
        onCallback: (action) => callManager
            .initiateCall(
              peerId: action.peerId,
              peerName: action.peerId,
              callType: action.callType,
            )
            .then((_) {}),
        onAsyncFailure: reportAsyncFailure,
      );
      final privateGroupControls = PrivateGroupControlSender(
        crypto: crypto,
        signaling: signaling,
      );
      Future<String?> resolveLocalGroupId(String routingToken) async {
        final stored = await database.cryptoState.get(
          privateGroupCallRouteStateKey(routingToken),
        );
        if (stored != null) {
          try {
            final data = (jsonDecode(stored) as Map).cast<String, Object?>();
            final groupId = data['groupId'] as String?;
            final expiresAt = (data['expiresAt'] as num?)?.toInt() ?? 0;
            if (groupId != null &&
                expiresAt > DateTime.now().millisecondsSinceEpoch &&
                await database.conversations.getById(groupId) != null) {
              return groupId;
            }
          } catch (_) {
            // Invalid encrypted local route state is deleted below.
          }
          await database.cryptoState.delete(
            privateGroupCallRouteStateKey(routingToken),
          );
        }
        // A private CREATE control and its call invite are ordered on the wire,
        // but decryption/storage happens asynchronously. Briefly wait for the
        // authenticated local record instead of accepting an unknown token.
        for (var attempt = 0; attempt < 10; attempt++) {
          for (final group in await database.conversations.getAllGroups()) {
            if (await groupRoutingToken(group.id) == routingToken) {
              return group.id;
            }
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        return null;
      }

      Future<String> resolvePeerName(String peerId) async {
        final conversation = await database.conversations.getById(peerId);
        if (conversation != null) return conversation.peerName;
        final contact = await database.contacts.getById(peerId);
        return contact?.displayName ?? peerId;
      }

      Future<String> preparePrivateGroupCall({
        required String groupId,
        required String groupName,
        required List<String> peerIds,
      }) async {
        final localUserId = session.userId;
        final group = await database.conversations.getById(groupId);
        if (localUserId == null || group == null || !group.isGroup) {
          throw StateError('Private group call has no authenticated group');
        }
        final members = (group.groupMembers ?? '')
            .split(',')
            .map((id) => id.trim())
            .where((id) => id.isNotEmpty)
            .toSet();
        final requested = peerIds.where((id) => id != localUserId).toSet();
        if (!members.contains(localUserId) ||
            requested.any((id) => !members.contains(id))) {
          throw StateError('Private group call contains a non-member');
        }
        final callRoutingToken = newOpaqueRoutingNonce();
        await privateGroupControls.send(
          senderId: localUserId,
          groupId: group.id,
          groupName: group.peerName,
          memberIds: members,
          recipients: requested,
          action: privateGroupCallPreparationAction,
          targetMemberId: callRoutingToken,
        );
        return callRoutingToken;
      }

      callManager = CallManager(
        session: session,
        signaling: signaling,
        media: mediaEngine,
        groupMedia: WebRtcGroupMediaEngine(),
        iceServers: HttpIceServerProvider(
          apiBaseUrl: config.apiBaseUrl,
          accessTokenProvider: () async => session.accessToken,
          client: httpClients.create(),
        ),
        callLogs: database.callLogs,
        nativeCalls: nativeCalls,
        janusClientFactory: () => JanusClient(httpClient: httpClients.create()),
        peerNameResolver: resolvePeerName,
        groupLocalIdResolver: resolveLocalGroupId,
        preparePrivateGroupCall: preparePrivateGroupCall,
        missedCalls: missedCalls,
        onAsyncFailure: reportAsyncFailure,
      );
      resources.register('call-manager', callManager.dispose);
      final mediaDirectory = Directory('${support.path}/media');
      final storageManagement = StorageManagementService(database);
      final fileTransfers = FileTransferManager(
        signaling: signaling,
        crypto: crypto,
        filesDirectory: mediaDirectory,
        metadataCrypto: storageCrypto,
        groupRoutingResolver: resolveLocalGroupId,
        onAsyncFailure: reportAsyncFailure,
      );
      resources.register('file-transfer-manager', fileTransfers.dispose);
      final mediaMessages = MediaMessageService(
        database: database,
        transfers: fileTransfers,
        session: session,
        localMediaDirectory: mediaDirectory,
        storageManagement: storageManagement,
        networkKindProvider: networkMonitor,
        onAsyncFailure: reportAsyncFailure,
      )..start();
      resources.register('media-message-service', mediaMessages.close);
      final voiceNotes = VoiceNoteRecorder(
        backend: PluginVoiceRecorderBackend(),
        recordingDirectory: Directory('${mediaDirectory.path}/voice_drafts'),
        onAsyncFailure: reportAsyncFailure,
      );
      resources.register('voice-note-recorder', voiceNotes.dispose);
      final authCoordinator = AuthCoordinator(
        api: AuthApi(baseUrl: config.apiBaseUrl, client: httpClients.create()),
        session: session,
        preKeys: preKeyManager,
        signaling: signaling,
        signalingUrl: config.signalingUrl,
      );
      final contacts = ContactService(
        deviceContacts: NativeDeviceContactsGateway(),
        api: PrivateContactDiscoveryApi(
          baseUrl: config.apiBaseUrl,
          client: httpClients.create(),
        ),
        database: database,
        session: session,
      );
      final permissions = AppPermissionService(
        MobileAppPermissionPlatform(
          contacts: contacts,
          requestNotifications: pushCoordinator?.requestPermissionAndRegister,
        ),
      );
      final stuckMessageRecovery = StuckMessageRecovery(database);
      final backgroundRuntime = AppBackgroundRuntime(
        scheduledMessages: scheduledMessages,
        timerUpdates: timerUpdates,
        senderKeyRotation: SenderKeyRotationService(
          database: database,
          store: protocolStore,
          crypto: crypto,
          signaling: signaling,
          session: session,
        ),
        messages: database.messages,
        stuckMessageRecovery: stuckMessageRecovery,
        signaling: signaling,
        preKeyMaintenance: preKeyMaintenance,
      );
      final messageNotifications = MessageNotificationCoordinator(
        incomingMessages: incomingMessages.acceptedMessages,
        session: session,
        presenter: notificationPresenter,
        onAsyncFailure: reportAsyncFailure,
      );
      await messageNotifications.start();
      resources.register(
        'message-notification-coordinator',
        messageNotifications.close,
      );
      final settingsService = SettingsService(
        session: session,
        signaling: signaling,
        scheduledMessages: scheduledMessages,
        profileDirectory: Directory('${support.path}/profile'),
        clearNotifications: messageNotifications.clear,
      );
      await settingsService.applyPlatformPreferences();
      resources.register('settings-service', settingsService.close);
      final pollService = PollService(
        database: database,
        sender: messageSender,
        signaling: signaling,
        session: session,
        crypto: crypto,
      );
      final socketDiagnostics = ServerCompatibilityChecker(
        httpClient: httpClients.create(),
      );
      resources.register('socket-diagnostics', socketDiagnostics.dispose);
      final lifecycle = AppLifecycleCoordinator(
        session: session,
        signaling: signaling,
        signalingUrl: config.signalingUrl,
        foregroundMaintenance: backgroundRuntime.runForegroundMaintenance,
        refreshPushRegistration: () async {
          await pushCoordinator?.refreshRegistration();
        },
        refreshAccessToken: authCoordinator.refreshAccessToken,
        networkMonitor: networkMonitor,
        allowLoopbackWhenOffline: config.allowsDebugLoopbackTransport,
        onAsyncFailure: reportAsyncFailure,
      );
      resources.register('application-lifecycle', lifecycle.dispose);
      final container = AppContainer.production(
        session: session,
        conversations: StorageConversationRepository(
          database,
          sender: messageSender,
        ),
        crypto: crypto,
        signaling: signaling,
        cryptoRuntime: AppCryptoRuntime(
          protocolStore: protocolStore,
          preKeys: preKeyManager,
          callCrypto: CallCryptoManager(),
        ),
        networkRuntime: AppNetworkRuntime(
          offlineQueue: offlineQueue,
          stuckMessageRecovery: stuckMessageRecovery,
          incomingMessages: incomingMessages,
          monitor: networkMonitor,
          telemetry: signaling.telemetry,
          diagnostics: socketDiagnostics,
        ),
        auth: authCoordinator,
        contacts: contacts,
        mediaRuntime: AppMediaRuntime(
          calls: callManager,
          fileTransfers: fileTransfers,
          callHistory: CallHistoryService(database.callLogs),
          mediaSelection: PluginMediaSelectionService(),
          mediaMessages: mediaMessages,
          voiceNotes: voiceNotes,
          localFiles: const NativeLocalFileActions(),
        ),
        backgroundRuntime: backgroundRuntime,
        pushRuntime: pushCoordinator == null
            ? null
            : AppPushRuntime(coordinator: pushCoordinator),
        backupRuntime: AppBackupRuntime(
          service: BackupService(
            database: database,
            session: session,
            backupDirectory: Directory('${support.path}/backups'),
          ),
        ),
        auditRuntime: AppAuditRuntime(
          service: ExportAuditService(
            database: database,
            session: session,
            crypto: crypto,
            signaling: signaling,
          ),
        ),
        groupRuntime: AppGroupRuntime(
          service: GroupManagementService(
            database: database,
            session: session,
            signaling: signaling,
            crypto: crypto,
          ),
        ),
        storageRuntime: AppStorageRuntime(service: storageManagement),
        chatInfoRuntime: AppChatInfoRuntime(
          service: ChatInfoService(
            database: database,
            session: session,
            signaling: signaling,
            crypto: crypto,
          ),
          polls: pollService,
          interactions: MessageInteractionService(
            database: database,
            signaling: signaling,
            session: session,
            crypto: crypto,
          ),
          activity: chatActivity,
        ),
        forwardRuntime: AppForwardRuntime(
          service: MessageForwardingService(
            sender: messageSender,
            polls: pollService,
            media: mediaMessages,
          ),
        ),
        readReceiptRuntime: AppReadReceiptRuntime(
          service: ReadReceiptService(
            database: database,
            session: session,
            signaling: signaling,
            crypto: crypto,
          ),
        ),
        onboardingRuntime: AppOnboardingRuntime(
          service: OnboardingService(database),
          permissions: permissions,
        ),
        bulkRuntime: AppBulkRuntime(
          service: BulkMessageService(
            database: database,
            sender: messageSender,
          ),
        ),
        lifecycleRuntime: lifecycle,
        settingsRuntime: AppSettingsRuntime(service: settingsService),
        accountDataRuntime: AppAccountDataRuntime(
          service: AccountDataService(
            auth: authCoordinator,
            database: database,
            scheduledMessages: scheduledMessages,
            managedDirectories: [
              mediaDirectory,
              Directory('${support.path}/profile'),
              Directory('${support.path}/backups'),
            ],
            unregisterPush: pushCoordinator?.unregister,
            afterLocalCleanup: () async {
              await messageNotifications.clear();
              await settingsService.reloadFromSession();
            },
          ),
        ),
        notificationRuntime: AppNotificationRuntime(
          coordinator: messageNotifications,
        ),
        diagnosticsRuntime: AppDiagnosticsRuntime(reporter: diagnostics),
        debugRuntime: kDebugMode
            ? AppDebugRuntime(
                harness: NotificationDebugHarness(
                  nativeCalls: nativeCalls,
                  missedCalls: missedCalls,
                  notifications: notificationPresenter,
                ),
              )
            : null,
        chatAccessRuntime: const AppChatAccessRuntime(
          service: ChatAccessService(
            authenticator: NativeDeviceOwnerAuthenticator(),
          ),
        ),
        callReadinessRuntime: const AppCallReadinessRuntime(
          service: CallReadinessService(
            platform: NativeCallReadinessPlatform(),
          ),
        ),
        resources: resources,
      );
      bootstrapComplete = true;
      return container;
    } finally {
      if (!bootstrapComplete) await resources.dispose();
    }
  }
}

class AppCryptoRuntime {
  const AppCryptoRuntime({
    required this.protocolStore,
    required this.preKeys,
    required this.callCrypto,
  });

  final DatabaseCryptoProtocolStore protocolStore;
  final PreKeyManager preKeys;
  final CallCryptoManager callCrypto;
}

class AppNetworkRuntime {
  const AppNetworkRuntime({
    required this.offlineQueue,
    required this.stuckMessageRecovery,
    required this.incomingMessages,
    required this.monitor,
    required this.telemetry,
    required this.diagnostics,
  });

  final OfflineMessageQueue offlineQueue;
  final StuckMessageRecovery stuckMessageRecovery;
  final IncomingMessageHandler incomingMessages;
  final NetworkStatusMonitor monitor;
  final WebSocketTelemetry telemetry;
  final ServerCompatibilityChecker diagnostics;
}

class AppMediaRuntime {
  const AppMediaRuntime({
    required this.calls,
    required this.fileTransfers,
    required this.callHistory,
    required this.mediaSelection,
    required this.mediaMessages,
    required this.voiceNotes,
    required this.localFiles,
  });

  final CallManager calls;
  final FileTransferManager fileTransfers;
  final CallHistoryService callHistory;
  final MediaSelectionService mediaSelection;
  final MediaMessageService mediaMessages;
  final VoiceNoteRecorder voiceNotes;
  final LocalFileActions localFiles;
}

class AppBackgroundRuntime {
  const AppBackgroundRuntime({
    required this.scheduledMessages,
    required this.timerUpdates,
    required this.senderKeyRotation,
    required this.messages,
    required this.stuckMessageRecovery,
    required this.signaling,
    required this.preKeyMaintenance,
  });

  final ScheduledMessageService scheduledMessages;
  final PendingTimerUpdateService timerUpdates;
  final SenderKeyRotationService senderKeyRotation;
  final MessageDao messages;
  final StuckMessageRecovery stuckMessageRecovery;
  final SignalingService signaling;
  final PreKeyMaintenanceService preKeyMaintenance;

  Future<void> runForegroundMaintenance() async {
    await messages.deleteExpiredMessages(DateTime.now().millisecondsSinceEpoch);
    await stuckMessageRecovery.recoverStuckMessages();
    await preKeyMaintenance.replenishIfNeeded();
    if (signaling.currentStatus.isConnected) await timerUpdates.flush();
    await scheduledMessages.processDue();
  }
}

class AppPushRuntime {
  const AppPushRuntime({required this.coordinator});
  final PushCoordinator coordinator;
}

class AppBackupRuntime {
  const AppBackupRuntime({required this.service});
  final BackupService service;
}

class AppAuditRuntime {
  const AppAuditRuntime({required this.service});
  final ExportAuditService service;
}

class AppGroupRuntime {
  const AppGroupRuntime({required this.service});
  final GroupManagementService service;
}

class AppStorageRuntime {
  const AppStorageRuntime({required this.service});
  final StorageManagementService service;
}

class AppChatInfoRuntime {
  const AppChatInfoRuntime({
    required this.service,
    required this.polls,
    required this.interactions,
    required this.activity,
  });
  final ChatInfoService service;
  final PollService polls;
  final MessageInteractionService interactions;
  final ChatActivityService activity;
}

class AppForwardRuntime {
  const AppForwardRuntime({required this.service});
  final MessageForwardingService service;
}

class AppReadReceiptRuntime {
  const AppReadReceiptRuntime({required this.service});
  final ReadReceiptService service;
}

class AppOnboardingRuntime {
  const AppOnboardingRuntime({
    required this.service,
    required this.permissions,
  });
  final OnboardingService service;
  final AppPermissionService permissions;
}

class AppBulkRuntime {
  const AppBulkRuntime({required this.service});
  final BulkMessageService service;
}

class AppSettingsRuntime {
  const AppSettingsRuntime({required this.service});
  final SettingsService service;
}

class AppAccountDataRuntime {
  const AppAccountDataRuntime({required this.service});
  final AccountDataService service;
}

class AppNotificationRuntime {
  const AppNotificationRuntime({required this.coordinator});
  final MessageNotificationCoordinator coordinator;
}

class AppDiagnosticsRuntime {
  const AppDiagnosticsRuntime({required this.reporter});
  final PrivacyCrashReporter reporter;
}

class AppDebugRuntime {
  const AppDebugRuntime({required this.harness});
  final NotificationDebugHarness harness;
}

class AppChatAccessRuntime {
  const AppChatAccessRuntime({required this.service});
  final ChatAccessService service;
}

class AppCallReadinessRuntime {
  const AppCallReadinessRuntime({required this.service});
  final CallReadinessService service;
}

class AppContainerScope extends InheritedWidget {
  const AppContainerScope({
    super.key,
    required this.container,
    required super.child,
  });

  final AppContainer container;

  static AppContainer of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AppContainerScope>();
    assert(scope != null, 'AppContainerScope not found');
    return scope!.container;
  }

  @override
  bool updateShouldNotify(AppContainerScope oldWidget) =>
      container != oldWidget.container;
}
