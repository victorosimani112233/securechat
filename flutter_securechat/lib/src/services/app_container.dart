import 'dart:async';
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
import '../bulk/broadcast_lists.dart';
import '../bulk/bulk_message_service.dart';
import '../calls/call_history_service.dart';
import '../calls/call_readiness_service.dart';
import '../chat/chat_activity_service.dart';
import '../chat/chat_info_service.dart';
import '../chat/message_forwarding_service.dart';
import '../chat/message_interaction_service.dart';
import '../chat/poll_service.dart';
import '../chat/read_receipt_service.dart';
import '../chat/security_notice_service.dart';
import '../chat/view_once_receipts.dart';
import '../config/app_config.dart';
import '../contacts/contact_service.dart';
import '../contacts/phone_number_sharing_service.dart';
import '../contacts/private_contact_discovery.dart';
import '../contacts/profile_name_sharing_service.dart';
import '../core/peer_display_name.dart';
import '../core/signal_message.dart';
import '../crypto/call_crypto_manager.dart';
import '../crypto/vodozemac/olm_pre_key_bundle_api.dart';
import '../crypto/vodozemac/olm_pre_key_publisher.dart';
import '../crypto/vodozemac/securechat_crypto_ffi.dart';
import '../crypto/vodozemac/vodozemac_crypto_service.dart';
import '../crypto/vodozemac/vodozemac_migration.dart';
import '../crypto/vodozemac/vodozemac_protocol_store.dart';
import '../debug/notification_debug_harness.dart';
import '../diagnostics/crash_reporter.dart';
import '../domain/send_message_use_case.dart';
import '../export/export_audit_service.dart';
import '../groups/group_management_service.dart';
import '../groups/private_group_call_routes.dart';
import '../groups/private_group_control.dart';
import '../incoming/incoming_message_handler.dart';
import '../l10n/service_strings.dart';
import '../media/call_manager.dart';
import '../media/call_tone_service.dart';
import '../media/file_transfer_manager.dart';
import '../media/group_media_engine.dart';
import '../media/ice_server_fetcher.dart';
import '../media/local_file_actions.dart';
import '../media/media_attachment.dart';
import '../media/media_engine.dart';
import '../media/media_message_service.dart';
import '../media/media_vault.dart';
import '../media/native_call_integration.dart';
import '../media/voice_note_service.dart';
import '../network/network_monitor.dart';
import '../network/network_resilience.dart';
import '../network/pinned_web_socket.dart';
import '../network/socket_diagnostics.dart';
import '../network/tls_pinning.dart';
import '../notifications/message_notification_service.dart';
import '../notifications/missed_call_tracker.dart';
import '../onboarding/onboarding_service.dart';
import '../onboarding/permission_service.dart';
import '../platform/mobile_permission_platform.dart';
import '../push/push_service.dart';
import '../safety/abuse_report.dart';
import '../safety/block_list.dart';
import '../security/chat_access_service.dart';
import '../security/chat_lock_credential_service.dart';
import '../settings/account_data_service.dart';
import '../settings/local_data_owner_guard.dart';
import '../settings/settings_service.dart';
import '../storage/legacy_room_importer.dart';
import '../storage/secure_chat_database.dart';
import '../storage/storage_management_service.dart';
import 'app_connection_status.dart';
import 'app_lifecycle_coordinator.dart';
import 'app_resource_scope.dart';
import 'conversation_repository.dart';
import 'crypto_service.dart';
import 'key_material_store.dart';
import 'peer_activity_source.dart';
import 'session_store.dart';
import 'signaling_service.dart';
import '../media/attachment_transport.dart';
import '../media/peer_capabilities.dart';

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
    this.safety,
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
    AbuseReportService? safety,
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
    safety: safety,
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
    required AbuseReportService safety,
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
      safety: safety,
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
      : IncomingPeerActivitySource(
          networkRuntime!.incomingMessages,
          signaling: signaling,
          session: session,
        );
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

  /// Engelleme ve kotuye kullanim bildirimi.
  final AbuseReportService? safety;
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
      'safety': safety,
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
        // WebSocket pinlemesi ayri bir yoldan yapilmak ZORUNDA; bkz.
        // `PinnedWebSocketConnector`.
        webSocketConnector: PinnedWebSocketConnector(httpClients.policy),
      );
      resources.register('websocket-signaling', signaling.dispose);
      final networkMonitor = SystemNetworkMonitor();
      resources.register('network-monitor', networkMonitor.dispose);

      // libsignal -> vodozemac gecisi. Isaret EN SON yazildigi icin yarida
      // kesilirse tekrar kosar; mesaj gecmisi KORUNUR, yalniz kripto
      // durumu temizlenir ve oturumlar yeniden kurulur.
      await VodozemacMigration(database).runIfNeeded();
      final vodozemacStore = VodozemacProtocolStore(
        database: database,
        crypto: SecureChatCrypto.open(),
        pickleKey: await VodozemacProtocolStore.derivePickleKey(keyBytes),
      );
      final preKeyPublisher = OlmPreKeyPublisher(
        database: database,
        store: vodozemacStore,
        apiBaseUrl: Uri.parse(config.apiBaseUrl),
        httpClient: httpClients.create(),
        accessTokenProvider: () async => session.accessToken,
        // Olm hesabini YALNIZ bu yol yaratir. Arka plan gorevi de yayin
        // yapiyor ama kendi veritabani anlik goruntusuyle calisiyor;
        // ikisi de yaratabilseydi birbirinin hesabini ezer ve her yayin
        // farkli bir kimlik gonderirdi.
        createAccountIfMissing: true,
        // Cagiran taraf butun bakim hatalarini yutuyor; yayin hatasinin
        // diagnostics'e dusmesi bu yuzden sart.
        onFailure: reportAsyncFailure,
      );
      final contactIdentityResolver = ContactIdentityResolver(
        database: database,
      );
      final privateDirectory = PrivateContactDiscoveryApi(
        baseUrl: config.apiBaseUrl,
        client: httpClients.create(),
      );
      // Servis katmani metinleri BuildContext olmadan yerellestirilir.
      final serviceStrings = ServiceStrings(
        languageCode: () async => session.languagePreference,
      );
      final securityNotices = SecurityNoticeService(
        database: database,
        strings: serviceStrings,
      );
      final crypto = VodozemacCryptoService(
        database: database,
        store: vodozemacStore,
        preKeyBundles: HttpOlmPreKeyBundleProvider(
          apiBaseUrl: Uri.parse(config.apiBaseUrl),
          httpClient: httpClients.create(),
          accessTokenProvider: () async => session.accessToken,
        ),
        // Karsi tarafin kimlik anahtari degistiginde yeni kimlik otomatik
        // kabul edilmez. Olay teshise ve kullaniciya bildirilir; oturum
        // kullanici onayi/key-transparency olmadan fail-closed kalir.
        onPeerIdentityRotated: (peerId) async {
          diagnostics.log(
            'peer-identity-rotated',
            metadata: const {'component': 'signal-session-recovery'},
          );
          await securityNotices.peerIdentityRotated(peerId);
        },
      );
      final phoneSharing = PhoneNumberSharingService(
        session: session,
        crypto: crypto,
        signaling: signaling,
        database: database,
        discovery: privateDirectory,
        onAsyncFailure: reportAsyncFailure,
      );
      final profileNames = ProfileNameSharingService(
        session: session,
        crypto: crypto,
        signaling: signaling,
        database: database,
        onAsyncFailure: reportAsyncFailure,
      );
      final offlineQueue = OfflineMessageQueue(
        database: database,
        signaling: signaling,
        onAsyncFailure: reportAsyncFailure,
      )..start();
      resources.register('offline-message-queue', offlineQueue.close);
      late final CallManager callManager;
      final incomingMessages = IncomingMessageHandler(
        signaling: signaling,
        crypto: crypto,
        database: database,
        session: session,
        strings: serviceStrings,
        identityResolver: contactIdentityResolver,
        phoneSharing: phoneSharing,
        profileNames: profileNames,
        // Cozulemeyen mesaj sessizce dusmez: sohbete gorunur bir iz birakir.
        onUndecryptableMessage: (conversationId) async {
          diagnostics.log(
            'message-undecryptable',
            metadata: const {'component': 'incoming-message'},
          );
          await securityNotices.messageUnreadable(conversationId);
        },
        // Cagri medya anahtari sohbete yazilmaz; dogrudan cagri yoneticisine
        // gider. Yonetici bu noktadan sonra kuruldugu icin gec baglanir.
        applyCallMediaKey:
            ({required String senderId, required String payload}) async {
              await callManager.applyIncomingMediaKey(
                senderId: senderId,
                payload: payload,
              );
            },
        onAsyncFailure: reportAsyncFailure,
      )..start();
      resources.register('incoming-message-handler', incomingMessages.close);
      final scheduledOutboxRecovery = ScheduledOutboxRecovery(
        scheduledMessages: database.scheduledMessages,
        outbox: offlineQueue,
        signaling: signaling,
        onAsyncFailure: reportAsyncFailure,
      );
      resources.register(
        'scheduled-outbox-recovery',
        scheduledOutboxRecovery.close,
      );
      final messageSender = SendMessageUseCase(
        database: database,
        signaling: signaling,
        session: session,
        crypto: crypto,
        reliableQueue: offlineQueue,
        phoneSharing: phoneSharing,
        profileNames: profileNames,
        onAsyncFailure: reportAsyncFailure,
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
      if (pushCoordinator != null) {
        // Dinleyiciler hemen kurulur; jeton alma ve sunucu kaydi ilk ekrani
        // bekletmez. Hata kendi kanalindan raporlanir.
        unawaited(
          pushCoordinator.initialize().catchError(
            (Object error, StackTrace stackTrace) =>
                reportAsyncFailure('push.initialize', error, stackTrace),
          ),
        );
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
      final groupCallRoutes = PrivateGroupCallRoutes(database, session);

      // Arama ekrani, Telecom bildirimi, cevapsiz arama ve arama kaydi bu
      // adi kullanir: ic kimlik (UUID) asla ad olarak donmez.
      Future<String> resolvePeerName(String peerId) async {
        final conversation = await database.conversations.getById(peerId);
        if (conversation != null && conversation.isGroup) {
          return conversation.peerName;
        }
        final contact = await database.contacts.getById(peerId);
        final name =
            !isOpaquePeerName(conversation?.peerName ?? '', peerId: peerId)
            ? conversation!.peerName
            : contact?.displayName ?? '';
        return peerDisplayName(
          name,
          peerId: peerId,
          phone: conversation?.peerPhone ?? contact?.phoneNumber ?? '',
          unknown: (await serviceStrings.load()).unknown_contact,
        );
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
        await groupCallRoutes.remember(callRoutingToken, group.id);
        return callRoutingToken;
      }

      /// Cagri medya anahtarini tek aliciya E2EE olarak ulastirir.
      ///
      /// Anahtar sunucudan gecmez: grup kontrolleriyle ayni yolu kullanir ve
      /// sunucu ordinary bir `encrypted_message` gorur. Teslim edilemezse
      /// `false` doner; cagri yoneticisi o durumda frame sifrelemesini
      /// acmaz ve arama mesh'te kalir.
      Future<bool> distributeCallMediaKey({
        required String recipientId,
        required String payload,
      }) async {
        final localUserId = session.userId;
        if (localUserId == null) return false;
        try {
          final envelope = await crypto.encryptDirect(
            recipientId: recipientId,
            plaintext: payload,
          );
          return await signaling.send(
            EncryptedSignalMessage(
              senderId: localUserId,
              recipientId: recipientId,
              timestamp: DateTime.now(),
              envelope: envelope,
            ),
          );
        } catch (_) {
          return false;
        }
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
        peerNameResolver: resolvePeerName,
        groupLocalIdResolver: groupCallRoutes.resolve,
        groupCallTokens: groupCallRoutes.tokensForGroup,
        groupMemberValidator: groupCallRoutes.containsMember,
        preparePrivateGroupCall: preparePrivateGroupCall,
        distributeCallMediaKey: distributeCallMediaKey,
        missedCalls: missedCalls,
        isBlocked: BlockList(database.cryptoState).isBlockedNow,
        onAsyncFailure: reportAsyncFailure,
      );
      resources.register('call-manager', callManager.dispose);
      final callTones = CallToneCoordinator(
        sessions: callManager.sessions,
        player: PlatformCallTonePlayer(),
        onAsyncFailure: reportAsyncFailure,
      )..start();
      resources.register('call-tone-coordinator', callTones.close);
      final mediaDirectory = Directory('${support.path}/media');
      // Medya diskte sifreli durur (QA 2026-10-12 Bulgu 11). Onceki
      // calismadan kalan gecici duz kopyalar UI kurulmadan silinir; eski
      // surumden kalan duz dosyalar arka planda muhurlenir.
      final mediaVault = MediaVault(
        keyBytes: await storageCrypto.deriveMediaKeyBytes(),
        mediaDirectory: mediaDirectory,
      );
      try {
        await mediaVault.purgeOpened();
      } catch (error, stackTrace) {
        await reportAsyncFailure('media-vault.purge', error, stackTrace);
      }
      unawaited(() async {
        try {
          await mediaVault.sealExisting([
            Directory('${mediaDirectory.path}/received_files'),
            Directory('${mediaDirectory.path}/sent'),
          ]);
        } catch (error, stackTrace) {
          await reportAsyncFailure('media-vault.migrate', error, stackTrace);
        }
      }());
      final storageManagement = StorageManagementService(
        database,
        mediaDirectory: mediaDirectory,
        vault: mediaVault,
      );
      // Oturum yenileme asagida kurulan AuthCoordinator'dan gelir.
      Future<String?> Function()? refreshForAttachments;
      final peerCapabilities = PeerCapabilities(database.cryptoState);
      final fileTransfers = FileTransferManager(
        signaling: signaling,
        crypto: crypto,
        filesDirectory: mediaDirectory,
        metadataCrypto: storageCrypto,
        groupRoutingResolver: groupCallRoutes.resolve,
        beforeReceive: incomingMessages.waitForIdle,
        onAsyncFailure: reportAsyncFailure,
        vault: mediaVault,
        attachments: HttpAttachmentTransport(
          baseUri: Uri.parse(config.apiBaseUrl),
          client: httpClients.create(),
          accessToken: () async => session.accessToken,
          refreshAccessToken: () async => refreshForAttachments?.call(),
        ),
        canReceiveBlobs: (recipients) =>
            peerCapabilities.allSupport(recipients, blobAttachmentCapability),
      );
      resources.register('file-transfer-manager', fileTransfers.dispose);
      final mediaMessages = MediaMessageService(
        viewOnceReceipts: ViewOnceReceipts(
          session: session,
          crypto: crypto,
          signaling: signaling,
        ),
        database: database,
        transfers: fileTransfers,
        session: session,
        localMediaDirectory: mediaDirectory,
        storageManagement: storageManagement,
        vault: mediaVault,
        networkKindProvider: networkMonitor,
        groupControls: privateGroupControls,
        phoneSharing: phoneSharing,
        profileNames: profileNames,
        identityResolver: contactIdentityResolver,
        onAsyncFailure: reportAsyncFailure,
      )..start();
      resources.register('media-message-service', mediaMessages.close);
      final voiceNotes = VoiceNoteRecorder(
        backend: PluginVoiceRecorderBackend(),
        recordingDirectory: Directory('${mediaDirectory.path}/voice_drafts'),
        onAsyncFailure: reportAsyncFailure,
      );
      resources.register('voice-note-recorder', voiceNotes.dispose);
      // Cikis ve hesap silme ile ayni dizinler: onceki hesaba ait medya,
      // profil fotografi ve yedekler yeni hesapta kalmamali.
      final managedDirectories = [
        mediaDirectory,
        Directory('${support.path}/profile'),
        Directory('${support.path}/backups'),
      ];
      final localDataOwner = LocalDataOwnerGuard(
        database: database,
        managedDirectories: managedDirectories,
        forgetDiagnostics: diagnostics.forgetAccount,
      );
      final authCoordinator = AuthCoordinator(
        api: AuthApi(baseUrl: config.apiBaseUrl, client: httpClients.create()),
        session: session,
        olmPreKeys: preKeyPublisher,
        signaling: signaling,
        signalingUrl: config.signalingUrl,
        privateDirectory: privateDirectory,
        claimLocalData: (userId) async {
          await localDataOwner.claim(userId);
          diagnostics.setUserId(userId);
        },
      );
      refreshForAttachments = authCoordinator.refreshAccessToken;
      final contacts = ContactService(
        deviceContacts: NativeDeviceContactsGateway(),
        api: privateDirectory,
        database: database,
        session: session,
        groupControls: privateGroupControls,
        offlineQueue: offlineQueue,
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
          crypto: crypto,
          signaling: signaling,
          session: session,
        ),
        messages: database.messages,
        stuckMessageRecovery: stuckMessageRecovery,
        signaling: signaling,
        preKeyPublisher: preKeyPublisher,
        mediaVault: mediaVault,
        onStepFailure: reportAsyncFailure,
      );
      final messageNotifications = MessageNotificationCoordinator(
        incomingMessages: incomingMessages.acceptedMessages,
        mediaMessages: mediaMessages.acceptedMessages,
        session: session,
        presenter: notificationPresenter,
        unreadCounts: database.conversations.unreadCounts,
        onAsyncFailure: reportAsyncFailure,
      );
      await messageNotifications.start();
      resources.register(
        'message-notification-coordinator',
        messageNotifications.close,
      );
      resources.register('media-notification-drain', () async {
        try {
          await fileTransfers.dispose();
        } finally {
          await mediaMessages.close();
          await messageNotifications.waitForIdle();
        }
      });
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
        callActivity: callManager.sessions.map(
          (call) => call != null && !call.isTerminal,
        ),
        transferActivity: fileTransfers.activity,
        foregroundMaintenance: backgroundRuntime.runForegroundMaintenance,
        publishCryptoKeys: preKeyPublisher.publishIfNeeded,
        refreshLocalState: database.refreshFromDisk,
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
          session: session,
        ),
        crypto: crypto,
        signaling: signaling,
        cryptoRuntime: AppCryptoRuntime(callCrypto: CallCryptoManager()),
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
            strings: serviceStrings,
            timerUpdateSender: timerUpdates.sendOrQueue,
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
          lists: StorageBroadcastListStore(database),
        ),
        lifecycleRuntime: lifecycle,
        settingsRuntime: AppSettingsRuntime(service: settingsService),
        accountDataRuntime: AppAccountDataRuntime(
          service: AccountDataService(
            auth: authCoordinator,
            database: database,
            scheduledMessages: scheduledMessages,
            managedDirectories: managedDirectories,
            unregisterPush: pushCoordinator?.unregister,
            forgetDiagnostics: diagnostics.forgetAccount,
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
        chatAccessRuntime: AppChatAccessRuntime(
          service: const ChatAccessService(
            authenticator: NativeDeviceOwnerAuthenticator(),
          ),
          credentials: ChatLockCredentialService(
            store: DatabaseChatLockCredentialStore(database.cryptoState),
          ),
        ),
        callReadinessRuntime: const AppCallReadinessRuntime(
          service: CallReadinessService(
            platform: NativeCallReadinessPlatform(),
          ),
        ),
        safety: AbuseReportService(
          submit: authCoordinator.submitAbuseReport,
          blockList: BlockList(database.cryptoState),
          localUserId: () => session.userId,
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
  const AppCryptoRuntime({required this.callCrypto});

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
    required this.preKeyPublisher,
    this.mediaVault,
    this.onStepFailure,
  });

  final ScheduledMessageService scheduledMessages;
  final PendingTimerUpdateService timerUpdates;
  final SenderKeyRotationService senderKeyRotation;
  final MessageDao messages;
  final StuckMessageRecovery stuckMessageRecovery;
  final SignalingService signaling;

  /// Olm acik anahtarlarinin yayini.
  ///
  /// Eskiden `PreKeyMaintenanceService` idi ve libsignal havuzunu
  /// tamamliyordu. libsignal tamamen kaldirildi; mesajlasma da hesap
  /// kurtarma da bu Olm hesabini kullaniyor.
  final OlmPreKeyPublisher preKeyPublisher;

  /// Gecici duz medya kopyalarini yasina gore temizler (Bulgu 11).
  final MediaVault? mediaVault;

  /// On plana donuste bu sureden eski gecici duz kopyalar silinir. Dis bir
  /// uygulamaya verilen kopya hemen silinmesin diye sifir degil.
  static const openedMediaLifetime = Duration(minutes: 10);

  /// Tek bir bakim adiminin hatasinin bildirilecegi yer.
  final void Function(String operation, Object error, StackTrace stackTrace)?
  onStepFailure;

  Future<int> expireMessages([DateTime? at]) => messages.deleteExpiredMessages(
    (at ?? DateTime.now()).millisecondsSinceEpoch,
  );

  /// Bakim adimlari BIRBIRINDEN BAGIMSIZ kosar.
  ///
  /// Onceden hepsi tek bir `await` zinciriydi ve cagiran taraf
  /// (`AppLifecycleCoordinator._runMaintenance`) butun hatalari
  /// `catch (_) {}` ile yutuyordu. Tek bir adimin patlamasi, kendisinden
  /// SONRAKI butun adimlari sessizce iptal ediyordu.
  ///
  /// Bu teorik bir risk degil: takilmis mesajlari kurtarma adimi anahtar
  /// yayinindan once geliyor. Oturumlar temizlendikten sonra takilmis bir
  /// mesaj kurtarilamayip hata firlatirsa, anahtar yayini hic kosmuyor;
  /// anahtar olmadigi icin mesajlar da hic gonderilemiyor. Dairesel bir
  /// kilitlenme, ustelik hicbir iz birakmadan.
  Future<void> runForegroundMaintenance() async {
    await _step('expire-messages', expireMessages);
    await _step(
      'stuck-message-recovery',
      stuckMessageRecovery.recoverStuckMessages,
    );
    await _step('publish-crypto-keys', preKeyPublisher.publishIfNeeded);
    if (signaling.currentStatus.isConnected) {
      await _step('timer-updates-flush', timerUpdates.flush);
    }
    await _step('scheduled-messages', scheduledMessages.processDue);
    final vault = mediaVault;
    if (vault != null) {
      await _step(
        'media-open-purge',
        () => vault.purgeOpened(olderThan: openedMediaLifetime),
      );
    }
  }

  Future<void> _step(String name, Future<void> Function() action) async {
    try {
      await action();
    } catch (error, stackTrace) {
      // Yutulmaz: hangi adimin patladigi bilinmeli, ve digerleri kosmaya
      // devam etmeli.
      onStepFailure?.call('maintenance:$name', error, stackTrace);
    }
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
  const AppBulkRuntime({required this.service, this.lists});
  final BulkMessageSender service;

  /// Kayitli alici listeleri; yoksa listeler gizlenir.
  final BroadcastListStore? lists;
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
  const AppChatAccessRuntime({required this.service, this.credentials});
  final ChatAccessService service;
  final ChatLockCredentialService? credentials;
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
