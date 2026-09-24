import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../chat/conversation_preview.dart';
import '../chat/disappearing_timer_notice.dart';
import '../chat/message_interaction_service.dart';
import '../chat/poll_service.dart';
import '../chat/private_chat_control.dart';
import '../contacts/contact_service.dart';
import '../contacts/phone_number_sharing_service.dart';
import '../core/signal_message.dart';
import '../crypto/signal_protocol_crypto_service.dart';
import '../groups/private_group_control.dart';
import '../groups/private_group_route.dart';
import '../l10n/service_strings.dart';
import '../media/call_media_key.dart';
import '../services/crypto_service.dart';
import '../services/async_operation_tracker.dart';
import '../services/session_store.dart';
import '../services/signaling_service.dart';
import '../storage/secure_chat_database.dart';
import '../storage/storage_entities.dart';
import 'message_envelope_parser.dart';

class PresenceInfo {
  const PresenceInfo({required this.isOnline, required this.lastSeen});
  final bool isOnline;
  final DateTime? lastSeen;
}

class IncomingMessageEvent {
  const IncomingMessageEvent({
    required this.messageId,
    required this.conversationId,
    required this.title,
    required this.preview,
    required this.timestamp,
    required this.isMuted,
    required this.isMention,
    this.customSound,
  });

  final String messageId;
  final String conversationId;
  final String title;
  final String preview;
  final DateTime timestamp;
  final bool isMuted;
  final bool isMention;

  /// Sohbete ozel bildirim sesinin adi; yoksa null ve uygulama genelindeki
  /// ses kullanilir.
  final String? customSound;
}

/// Cozulmus bir cagri medya anahtarini cagri yoneticisine ulastiran sinir.
///
/// Anahtar bir sohbet mesaji degildir; veritabanina yazilmaz.
typedef CallMediaKeyReceiver =
    Future<void> Function({required String senderId, required String payload});

class _EncryptedProcessingResult {
  const _EncryptedProcessingResult({
    required this.processed,
    this.messageId,
    this.deliveryReceiptRequired = false,
  });

  const _EncryptedProcessingResult.rejected()
    : processed = false,
      messageId = null,
      deliveryReceiptRequired = false;

  final bool processed;
  final String? messageId;
  final bool deliveryReceiptRequired;
}

class _ProcessedDelivery {
  const _ProcessedDelivery({
    required this.senderId,
    required this.expiresAt,
    this.messageId,
  });

  final String senderId;
  final String? messageId;
  final int expiresAt;
}

class IncomingMessageHandler {
  IncomingMessageHandler({
    required SignalingService signaling,
    required CryptoService crypto,
    required SecureChatDatabase database,
    required SessionStore session,
    ContactIdentityResolver? identityResolver,
    PhoneNumberSharingService? phoneSharing,
    ServiceStrings? strings,
    CallMediaKeyReceiver? applyCallMediaKey,
    AsyncOperationFailureHandler? onAsyncFailure,
    Future<void> Function(String conversationId)? onUndecryptableMessage,
  }) : _signaling = signaling,
       _crypto = crypto,
       _database = database,
       _session = session,
       _strings = strings ?? ServiceStrings.fixed('tr'),
       _identityResolver = identityResolver,
       _phoneSharing = phoneSharing,
       _applyCallMediaKey = applyCallMediaKey,
       _onUndecryptableMessage = onUndecryptableMessage,
       _operations = AsyncOperationTracker(onFailure: onAsyncFailure);

  final SignalingService _signaling;
  final CryptoService _crypto;
  final SecureChatDatabase _database;
  final SessionStore _session;
  final ServiceStrings _strings;
  final ContactIdentityResolver? _identityResolver;
  final PhoneNumberSharingService? _phoneSharing;
  final CallMediaKeyReceiver? _applyCallMediaKey;
  final Future<void> Function(String conversationId)? _onUndecryptableMessage;
  final AsyncOperationTracker _operations;
  final _typingController = StreamController<Map<String, bool>>.broadcast();
  final _presenceController =
      StreamController<Map<String, PresenceInfo>>.broadcast();
  final _messageController = StreamController<IncomingMessageEvent>.broadcast();
  final _typing = <String, bool>{};
  final _presence = <String, PresenceInfo>{};
  final _typingTimers = <String, Timer>{};
  final _seenMessageIds = <String>{};
  var _processedDeliveriesSincePrune = 0;
  StreamSubscription<SignalMessage>? _subscription;
  Future<void> _handleTail = Future<void>.value();
  Future<void>? _closeTask;
  bool _closed = false;

  Stream<Map<String, bool>> get typingStates async* {
    yield Map.unmodifiable(_typing);
    yield* _typingController.stream;
  }

  Stream<Map<String, PresenceInfo>> get presenceStates async* {
    yield Map.unmodifiable(_presence);
    yield* _presenceController.stream;
  }

  Stream<IncomingMessageEvent> get acceptedMessages =>
      _messageController.stream;

  void start() {
    if (_closed) throw StateError('Incoming message handler is closed');
    _operations.run(
      'incoming-message.prune-delivery-dedup',
      _pruneProcessedDeliveries(),
    );
    _subscription ??= _signaling.incoming.listen(
      (signal) {
        final operation = _handleTail.then((_) => _handle(signal));
        _handleTail = operation.then<void>((_) {}, onError: (_, _) {});
        _operations.run('incoming-message.handle', operation);
      },
      // Cozulemeyen/gecersiz cerceveler burada hata olarak gelir. onError
      // verilmezse hata islenmemis sayilip root zone'da olumcul crash raporu
      // uretiyor ve kullaniciya da hicbir iz kalmiyordu.
      onError: (Object error, StackTrace stackTrace) {
        if (_closed || _operations.isClosed) return;
        _operations.run(
          'incoming-message.signal-stream',
          Future<void>.error(error, stackTrace),
        );
      },
    );
  }

  /// Waits until every signal already delivered by the socket stream has been
  /// handled in wire order.
  ///
  /// Stream delivery itself is asynchronous, so the first event-loop turn is
  /// intentionally yielded before observing the tail. This gives tests,
  /// foreground catch-up and controlled shutdown a deterministic completion
  /// boundary without relying on timing guesses.
  Future<void> waitForIdle() async {
    if (_closed) return;
    await Future<void>.delayed(Duration.zero);
    while (true) {
      final observedTail = _handleTail;
      await observedTail;
      await Future<void>.delayed(Duration.zero);
      if (identical(observedTail, _handleTail)) return;
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
    await _subscription?.cancel();
    _subscription = null;
    await _operations.close();
    for (final timer in _typingTimers.values) {
      timer.cancel();
    }
    await _typingController.close();
    await _presenceController.close();
    await _messageController.close();
  }

  Future<void> _handle(
    SignalMessage signal, {
    bool privateChatControl = false,
  }) async {
    switch (signal) {
      case EncryptedSignalMessage():
        await _encryptedWithTransportAck(signal);
      case DeliveryReceiptSignal() when privateChatControl:
        await _receipt(signal);
      case MessageDeleteSignal()
          when privateChatControl &&
              signal is! MessageEditSignal &&
              signal is! MessageReactionSignal &&
              signal is! MessagePinSignal:
        await _delete(signal);
      case MessageEditSignal() when privateChatControl:
        await _edit(signal);
      case MessageReactionSignal() when privateChatControl:
        await _reaction(signal);
      case MessagePinSignal() when privateChatControl:
        await _pin(signal);
      case DisappearingTimerSignal() when privateChatControl:
        await _timer(signal);
      case TypingIndicatorSignal() when privateChatControl:
        await _typingIfAllowed(signal);
      case SharedPhoneSignal() when privateChatControl:
        await _phoneSharing?.accept(signal);
      case PresenceUpdateSignal():
        _presenceSignal(signal);
      case AdminEncryptedLogSignal():
        await _adminEncryptedLog(signal);
      case GroupNotificationSignal():
        await _groupNotification(signal);
      case SessionResetRequestSignal():
        await _sessionResetRequest(signal);
      default:
        break;
    }
  }

  Future<void> _encryptedWithTransportAck(EncryptedSignalMessage signal) async {
    final token = signal.deliveryToken;
    if (token == null) {
      final result = await _encrypted(signal);
      if (result.processed &&
          result.deliveryReceiptRequired &&
          result.messageId != null) {
        await _sendDeliveredReceipt(signal.senderId, result.messageId!);
      }
      return;
    }
    if (!_deliveryTokenPattern.hasMatch(token)) return;

    final previous = await _processedDelivery(token);
    if (previous != null) {
      if (previous.senderId != signal.senderId) return;
      final receiptSent = previous.messageId == null
          ? true
          : await _sendDeliveredReceipt(signal.senderId, previous.messageId!);
      if (receiptSent) await _sendTransportAck(token);
      return;
    }

    final result = await _encrypted(signal);
    if (!result.processed) return;
    await _rememberProcessedDelivery(
      token: token,
      senderId: signal.senderId,
      messageId: result.messageId,
    );
    final receiptSent =
        !result.deliveryReceiptRequired ||
        result.messageId == null ||
        await _sendDeliveredReceipt(signal.senderId, result.messageId!);
    if (receiptSent) await _sendTransportAck(token);
  }

  Future<bool> _sendTransportAck(String token) async {
    final localUserId = _session.userId;
    if (localUserId == null) return false;
    return _signaling.send(
      DeliveryTransportAckSignal(
        senderId: localUserId,
        timestamp: DateTime.now(),
        deliveryToken: token,
      ),
    );
  }

  Future<bool> _sendDeliveredReceipt(
    String recipientId,
    String messageId,
  ) async {
    final localUserId = _session.userId;
    if (localUserId == null) return false;
    return sendPrivateChatControl(
      crypto: _crypto,
      signaling: _signaling,
      control: DeliveryReceiptSignal(
        senderId: localUserId,
        recipientId: recipientId,
        timestamp: DateTime.now(),
        messageId: messageId,
        status: 'DELIVERED',
      ),
    );
  }

  Future<_ProcessedDelivery?> _processedDelivery(String token) async {
    final key = '$_processedDeliveryPrefix$token';
    final encoded = await _database.cryptoState.get(key);
    if (encoded == null) return null;
    try {
      final json = (jsonDecode(encoded) as Map).cast<String, Object?>();
      final expiresAt = (json['expiresAt'] as num?)?.toInt() ?? 0;
      if (expiresAt <= DateTime.now().millisecondsSinceEpoch) {
        await _database.cryptoState.delete(key);
        return null;
      }
      final senderId = json['senderId'] as String?;
      if (senderId == null || senderId.isEmpty) return null;
      return _ProcessedDelivery(
        senderId: senderId,
        messageId: json['messageId'] as String?,
        expiresAt: expiresAt,
      );
    } catch (_) {
      await _database.cryptoState.delete(key);
      return null;
    }
  }

  Future<void> _rememberProcessedDelivery({
    required String token,
    required String senderId,
    required String? messageId,
  }) async {
    final expiresAt = DateTime.now()
        .add(_processedDeliveryRetention)
        .millisecondsSinceEpoch;
    await _database.cryptoState.put(
      '$_processedDeliveryPrefix$token',
      jsonEncode({
        'senderId': senderId,
        if (messageId != null) 'messageId': messageId,
        'expiresAt': expiresAt,
      }),
    );
    _processedDeliveriesSincePrune++;
    if (_processedDeliveriesSincePrune >= 128) {
      _processedDeliveriesSincePrune = 0;
      await _pruneProcessedDeliveries();
    }
  }

  Future<void> _pruneProcessedDeliveries() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final entries = await _database.cryptoState.getByPrefix(
      _processedDeliveryPrefix,
    );
    final retained = <MapEntry<String, int>>[];
    for (final entry in entries.entries) {
      try {
        final json = (jsonDecode(entry.value) as Map).cast<String, Object?>();
        final expiresAt = (json['expiresAt'] as num?)?.toInt() ?? 0;
        if (expiresAt <= now) {
          await _database.cryptoState.delete(entry.key);
        } else {
          retained.add(MapEntry(entry.key, expiresAt));
        }
      } catch (_) {
        await _database.cryptoState.delete(entry.key);
      }
    }
    if (retained.length <= _maxProcessedDeliveries) return;
    retained.sort((a, b) => a.value.compareTo(b.value));
    for (final entry in retained.take(
      retained.length - _maxProcessedDeliveries,
    )) {
      await _database.cryptoState.delete(entry.key);
    }
  }

  static const _processedDeliveryPrefix = 'processed-delivery:';
  static const _processedDeliveryRetention = Duration(days: 30);
  static const _maxProcessedDeliveries = 50000;
  static final _deliveryTokenPattern = RegExp(r'^[A-Za-z0-9_-]{43}$');

  /// Cozulemeyen bir zarfin ardindan calisir.
  ///
  /// Iki is yapar: (1) hatayi sahipli async sinirina vererek teshis kaydina
  /// dusurur, (2) oturum kullanilamaz durumdaysa yerel oturumu atar ve karsi
  /// tarafa `session_reset_request` gonderir. Ikinci adim olmadan karsi taraf
  /// bizim olu oturumumuzla sifrelemeye devam eder ve sohbet kalici olarak
  /// olur.
  Future<void> _recoverFromDecryptFailure(
    EncryptedSignalMessage signal,
    Object error,
    StackTrace stackTrace, {
    required String conversationId,
  }) async {
    // Kullanici mesajin dustugunu GORMELI. Aksi halde gonderen "gonderdim",
    // alan "gelmedi" der ve kimse kaybi fark etmez.
    await _onUndecryptableMessage?.call(conversationId);
    if (!_closed && !_operations.isClosed) {
      _operations.run(
        'incoming-message.decrypt',
        Future<void>.error(error, stackTrace),
      );
    }
    if (error is! SignalSessionUnusableException) return;
    final peerId = error.peerId;
    if (_crypto case final PeerSessionRecovery recovery) {
      // Oturum atilir, fakat TOFU ile sabitlenen kimlik korunur. Sonraki
      // gonderim taze bundle ceker; kimlik degismisse otomatik kabul edilmez.
      await recovery.resetPeerSession(peerId);
    }
    final localUserId = _session.userId;
    if (localUserId == null) return;
    // Karsi tarafin da bizimle olan oturumunu atmasini iste; boylece bir
    // sonraki gonderiminde taze bir X3DH kurulur.
    await _signaling.send(
      SessionResetRequestSignal(
        senderId: localUserId,
        recipientId: peerId,
        timestamp: DateTime.now(),
        reason: 'undecryptable-envelope',
      ),
    );
  }

  /// Karsi taraf oturumun bozuldugunu bildirdi: yerel oturumu atiyoruz ki
  /// bir sonraki gonderim yeni prekey bundle ile bastan kurulsun.
  Future<void> _sessionResetRequest(SessionResetRequestSignal signal) async {
    final localUserId = _session.userId;
    if (localUserId == null || localUserId != signal.recipientId) return;
    if (_crypto case final PeerSessionRecovery recovery) {
      // Bu kontrol signaling katmanindadir ve kotucul sunucu tarafindan
      // uretilebilir. Yalniz oturumu sifirlayabilir; pinli kimligi silemez veya
      // yeni bundle'i guvenilir ilan edemez.
      await recovery.resetPeerSession(signal.senderId);
    }
  }

  /// Karsi tarafin gonderdigi zaman damgasini makul bir pencereye kirpar.
  ///
  /// Mesaj siralamasi bu damgaya dayaniyor. Kirpilmazsa kotu niyetli bir peer
  /// cok ileri tarihli bir damga gondererek mesajini sohbet listesinin ve
  /// konusmanin tepesine KALICI olarak sabitleyebilir; ayni sekilde cok geri
  /// tarihli damga mesaji gecmise gomer.
  ///
  /// Ileri yonde kucuk bir tolerans birakilir cunku iki cihazin saati birkac
  /// dakika kayabilir. Geri yonde kirpma yapilmaz: eski bir mesajin gecikmeli
  /// teslimi mesrudur.
  static const peerClockTolerance = Duration(minutes: 5);

  int _boundedTimestamp(DateTime peerTimestamp) {
    final now = DateTime.now();
    final ceiling = now.add(peerClockTolerance);
    return peerTimestamp.isAfter(ceiling)
        ? now.millisecondsSinceEpoch
        : peerTimestamp.millisecondsSinceEpoch;
  }

  Future<_EncryptedProcessingResult> _encrypted(
    EncryptedSignalMessage signal,
  ) async {
    String plaintext;
    String conversationId = signal.senderId;
    var isGroup = false;
    try {
      if (signal.envelope.startsWith('GROUPMETA:v1:') ||
          signal.envelope.startsWith('GROUPSK:v1:') ||
          signal.envelope.startsWith('GROUPSK:v2:')) {
        final groupId = await _localGroupId(signal.envelope);
        if (groupId == null) return const _EncryptedProcessingResult.rejected();
        conversationId = groupId;
        isGroup = true;
        plaintext = await _crypto.decryptGroup(
          senderId: signal.senderId,
          groupId: groupId,
          envelope: signal.envelope,
        );
      } else {
        plaintext = await _crypto.decryptDirect(
          senderId: directDecryptionPeer(
            envelope: signal.envelope,
            authenticatedSenderId: signal.senderId,
            localRecipientId: signal.recipientId,
          ),
          envelope: signal.envelope,
        );
        if (isPrivateGroupRoute(plaintext)) {
          final route = await decodePrivateGroupRoute(plaintext);
          final group = await _database.conversations.getById(route.groupId);
          final members = _csv(group?.groupMembers);
          if (group == null ||
              !group.isGroup ||
              !members.contains(signal.senderId) ||
              !members.contains(_session.userId)) {
            return const _EncryptedProcessingResult.rejected();
          }
          conversationId = route.groupId;
          isGroup = true;
          plaintext = await _crypto.decryptGroup(
            senderId: signal.senderId,
            groupId: route.groupId,
            envelope: route.groupEnvelope,
          );
        }
      }
    } catch (error, stackTrace) {
      // Onceden burada sessiz `return` vardi: cozulemeyen her mesaj hicbir iz
      // birakmadan dusuyordu (ne log, ne teshis kaydi, ne kullanici uyarisi).
      // Artik hata teshis sinirina gidiyor ve oturum bozuksa kurtarma
      // baslatiliyor.
      await _recoverFromDecryptFailure(
        signal,
        error,
        stackTrace,
        conversationId: conversationId,
      );
      return const _EncryptedProcessingResult.rejected();
    }
    // Cagri medya anahtari mesaj degildir: sohbete yazilmaz, dogrudan cagri
    // yoneticisine gider. Yalniz bize gonderilmis ve authenticated bir
    // zarftan cikmis olabilir.
    if (plaintext.startsWith('${CallMediaKey.prefix}:')) {
      final localUserId = _session.userId;
      if (localUserId == null || localUserId != signal.recipientId) {
        return const _EncryptedProcessingResult.rejected();
      }
      final receiver = _applyCallMediaKey;
      if (receiver == null) return const _EncryptedProcessingResult.rejected();
      await receiver(senderId: signal.senderId, payload: plaintext);
      return const _EncryptedProcessingResult(processed: true);
    }
    if (isPrivateGroupControl(plaintext)) {
      final localUserId = _session.userId;
      if (localUserId == null || localUserId != signal.recipientId) {
        return const _EncryptedProcessingResult.rejected();
      }
      try {
        final control = await decodePrivateGroupControl(
          plaintext: plaintext,
          authenticatedSenderId: signal.senderId,
          localRecipientId: localUserId,
        );
        if (control.action == privateGroupCallPreparationAction) {
          await _preparePrivateGroupCall(control);
          return const _EncryptedProcessingResult(processed: true);
        }
        await _groupNotification(control);
      } catch (_) {
        // Malformed, mis-bound or unauthenticated control data is fail-closed.
        return const _EncryptedProcessingResult.rejected();
      }
      return const _EncryptedProcessingResult(processed: true);
    }
    if (isPrivateChatControl(plaintext)) {
      final localUserId = _session.userId;
      if (isGroup ||
          localUserId == null ||
          localUserId != signal.recipientId ||
          signal.senderId == localUserId) {
        return const _EncryptedProcessingResult.rejected();
      }
      try {
        final control = decodePrivateChatControl(
          plaintext: plaintext,
          authenticatedSenderId: signal.senderId,
          localRecipientId: localUserId,
        );
        await _handle(control, privateChatControl: true);
      } catch (_) {
        // Kimlige baglanamayan veya bozuk kontrol verisi fail-closed yutulur.
        return const _EncryptedProcessingResult.rejected();
      }
      return const _EncryptedProcessingResult(processed: true);
    }
    if (plaintext.startsWith('SKDM:')) {
      await _acceptSenderKey(signal.senderId, plaintext);
      return const _EncryptedProcessingResult(processed: true);
    }
    final parsed = parseMessageEnvelope(plaintext);
    if (parsed.pollVote != null) {
      await _applyPollVote(parsed.pollVote!, signal.senderId, conversationId);
      return const _EncryptedProcessingResult(processed: true);
    }
    final messageId =
        parsed.messageId ??
        '${signal.timestamp.microsecondsSinceEpoch}-${signal.senderId.hashCode.abs()}';
    if (!_seenMessageIds.add(messageId) ||
        await _database.messages.getById(messageId) != null) {
      return _EncryptedProcessingResult(
        processed: true,
        messageId: parsed.messageId == null ? null : messageId,
        deliveryReceiptRequired:
            parsed.messageId != null && signal.deliveryToken != null,
      );
    }
    final identity = isGroup
        ? null
        : await _identityResolver?.resolve(signal.senderId);
    final conversation = await _database.conversations.getById(conversationId);
    if (conversation == null) {
      await _database.conversations.insert(
        ConversationEntity(
          id: conversationId,
          peerId: conversationId,
          peerName: isGroup
              ? conversationId
              : (identity?.displayName ?? signal.senderId),
          peerPhone: identity?.phoneNumber ?? '',
          isGroup: isGroup,
          groupMembers: isGroup ? signal.senderId : null,
        ),
      );
    }
    await _database.messages.insert(
      MessageEntity(
        id: messageId,
        conversationId: conversationId,
        senderId: signal.senderId,
        content: parsed.content,
        contentType: parsed.contentType,
        timestamp: _boundedTimestamp(signal.timestamp),
        status: StorageMessageStatus.delivered,
        replyToId: parsed.replyToId,
        isOutgoing: false,
        expiresAt: parsed.absoluteExpiresAt,
        isViewOnce: parsed.isViewOnce,
      ),
    );
    await _database.conversations.updateLastMessageById(
      conversationId,
      // Tek-gosterimlik icerik onizlemeye girmemeli; bildirim yolunda zaten
      // korunuyordu, ayni kural sohbet listesine de uygulanir.
      conversationPreview(
        content: parsed.content,
        isViewOnce: parsed.isViewOnce,
        contentType: parsed.contentType,
      ),
      _boundedTimestamp(signal.timestamp),
      type: parsed.contentType,
      outgoing: false,
    );
    await _database.conversations.incrementUnreadCount(conversationId);
    final storedConversation = await _database.conversations.getById(
      conversationId,
    );
    final isMention = parsed.mentionedUserIds.contains(_session.userId);
    final title = isGroup
        ? '${await _groupMemberName(signal.senderId)} (${storedConversation?.peerName ?? conversationId})'
        : (storedConversation?.peerName.isNotEmpty == true
              ? storedConversation!.peerName
              : signal.senderId);
    _messageController.add(
      IncomingMessageEvent(
        messageId: messageId,
        conversationId: conversationId,
        title: title,
        preview: _notificationPreview(parsed),
        timestamp: signal.timestamp,
        isMuted: storedConversation?.isMuted == true,
        isMention: isMention,
        customSound: storedConversation?.customNotificationUri,
      ),
    );
    return _EncryptedProcessingResult(
      processed: true,
      messageId: parsed.messageId == null ? null : messageId,
      deliveryReceiptRequired: parsed.messageId != null,
    );
  }

  Future<void> _receipt(DeliveryReceiptSignal signal) async {
    final current = await _database.messages.getById(signal.messageId);
    if (current == null || !current.isOutgoing) return;
    final conversation = await _database.conversations.getById(
      current.conversationId,
    );
    if (!_senderAllowed(conversation, signal.senderId)) return;
    final next = switch (signal.status.toUpperCase()) {
      'READ' =>
        _session.shareReadReceipts
            ? StorageMessageStatus.read
            : StorageMessageStatus.delivered,
      'DELIVERED' => StorageMessageStatus.delivered,
      _ => null,
    };
    if (next == null) return;
    await _database.pendingSignals.deleteDelivered(
      signal.messageId,
      signal.senderId,
    );
    if (_statusRank(next) <= _statusRank(current.status)) return;
    await _database.messages.updateStatus(signal.messageId, next);
  }

  Future<void> _delete(MessageDeleteSignal signal) async {
    final message = await _database.messages.getById(signal.messageId);
    final conversation = message == null
        ? null
        : await _database.conversations.getById(message.conversationId);
    if (message == null ||
        message.senderId != signal.senderId ||
        !_senderAllowed(conversation, signal.senderId)) {
      return;
    }
    await _database.messages.updateContent(
      signal.messageId,
      'Bu mesaj silindi',
      StorageMessageContentType.deleted,
    );
  }

  Future<void> _edit(MessageEditSignal signal) async {
    final content = signal.newContent.trim();
    final message = await _database.messages.getById(signal.messageId);
    final conversation = message == null
        ? null
        : await _database.conversations.getById(message.conversationId);
    if (message == null ||
        message.senderId != signal.senderId ||
        message.contentType != StorageMessageContentType.text ||
        content.isEmpty ||
        content.length > 10000 ||
        !_senderAllowed(conversation, signal.senderId)) {
      return;
    }
    await _database.messages.updateContentEdited(
      signal.messageId,
      content,
      _boundedTimestamp(signal.timestamp),
      jsonEncode([message.content]),
    );
  }

  Future<void> _reaction(MessageReactionSignal signal) async {
    final message = await _database.messages.getById(signal.messageId);
    final conversation = message == null
        ? null
        : await _database.conversations.getById(message.conversationId);
    if (message == null ||
        !isValidMessageReaction(signal.emoji) ||
        !_senderAllowed(conversation, signal.senderId)) {
      return;
    }
    await _database.messages.applyReaction(
      signal.messageId,
      userId: signal.senderId,
      emoji: signal.emoji,
      remove: signal.remove,
    );
  }

  Future<void> _pin(MessagePinSignal signal) async {
    final message = await _database.messages.getById(signal.messageId);
    final conversation = message == null
        ? null
        : await _database.conversations.getById(message.conversationId);
    if (message == null ||
        conversation == null ||
        !_senderAllowed(conversation, signal.senderId)) {
      return;
    }
    if (conversation.isGroup) {
      final admins = _csv(conversation.groupAdmins);
      if (!admins.contains(signal.senderId) ||
          (signal.groupId != null && signal.groupId != conversation.id)) {
        return;
      }
    }
    await _database.messages.updatePinned(
      signal.messageId,
      signal.isPinned,
      signal.pinnedAt?.millisecondsSinceEpoch,
    );
  }

  Future<void> _timer(DisappearingTimerSignal signal) async {
    final conversationId = signal.conversationId.isEmpty
        ? signal.senderId
        : signal.conversationId;
    final conversation = await _database.conversations.getById(conversationId);
    if (!_allowedTimerDurations.contains(signal.durationMs) ||
        !_senderAllowed(conversation, signal.senderId)) {
      return;
    }
    await _database.conversations.updateDisappearingDuration(
      conversationId,
      signal.durationMs,
    );
    final timestamp = _boundedTimestamp(signal.timestamp);
    final l10n = await _strings.load();
    final content = remoteDisappearingTimerNotice(
      l10n,
      sender: conversation?.isGroup == true
          ? await _groupMemberName(signal.senderId)
          : await _memberName(signal.senderId),
      durationMs: signal.durationMs,
    );
    final rawId =
        '$conversationId:${signal.senderId}:${signal.durationMs}:'
        '${signal.timestamp.microsecondsSinceEpoch}';
    final messageId = base64UrlEncode(
      (await Sha256().hash(utf8.encode('disappearing-timer:$rawId'))).bytes,
    );
    if (await _database.messages.getById(messageId) == null) {
      await _database.messages.insert(
        MessageEntity(
          id: messageId,
          conversationId: conversationId,
          senderId: 'SYSTEM',
          content: content,
          contentType: StorageMessageContentType.system,
          timestamp: timestamp,
          status: StorageMessageStatus.delivered,
          isOutgoing: false,
        ),
      );
      await _database.conversations.updateLastMessageById(
        conversationId,
        content,
        timestamp,
        type: StorageMessageContentType.system,
        outgoing: false,
        status: StorageMessageStatus.delivered,
      );
    }
    if (signal.durationMs > 0) {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _database.messages.applyRetroactiveExpiry(
        conversationId,
        signal.durationMs,
        now - 60000,
        now,
      );
    }
  }

  Future<void> _typingIfAllowed(TypingIndicatorSignal signal) async {
    final conversation = await _database.conversations.getByPeerId(
      signal.senderId,
    );
    if (conversation == null ||
        conversation.isGroup ||
        !_senderAllowed(conversation, signal.senderId)) {
      return;
    }
    _typingSignal(signal);
  }

  bool _senderAllowed(
    ConversationEntity? conversation,
    String authenticatedSenderId,
  ) {
    final localUserId = _session.userId;
    if (conversation == null ||
        localUserId == null ||
        authenticatedSenderId.isEmpty ||
        authenticatedSenderId == localUserId) {
      return false;
    }
    if (!conversation.isGroup) {
      return conversation.peerId == authenticatedSenderId;
    }
    final members = _csv(conversation.groupMembers);
    return members.contains(localUserId) &&
        members.contains(authenticatedSenderId);
  }

  void _typingSignal(TypingIndicatorSignal signal) {
    _typingTimers.remove(signal.senderId)?.cancel();
    if (signal.isTyping) {
      _typing[signal.senderId] = true;
      _typingTimers[signal.senderId] = Timer(const Duration(seconds: 10), () {
        if (_closed) return;
        _typing.remove(signal.senderId);
        _typingController.add(Map.unmodifiable(_typing));
      });
    } else {
      _typing.remove(signal.senderId);
    }
    _typingController.add(Map.unmodifiable(_typing));
  }

  void _presenceSignal(PresenceUpdateSignal signal) {
    _presence[signal.senderId] = PresenceInfo(
      isOnline: signal.isOnline,
      lastSeen: signal.hideLastSeen ? null : signal.lastSeen,
    );
    _presenceController.add(Map.unmodifiable(_presence));
  }

  Future<void> _adminEncryptedLog(AdminEncryptedLogSignal signal) async {
    final localUserId = _session.userId;
    if (localUserId == null) return;
    final envelope = signal.adminPayloads[localUserId];
    if (envelope == null) return;
    try {
      final plaintext = await _crypto.decryptDirect(
        senderId: directDecryptionPeer(
          envelope: envelope,
          authenticatedSenderId: signal.senderId,
          localRecipientId: localUserId,
        ),
        envelope: envelope,
      );
      final decoded = jsonDecode(plaintext);
      if (decoded is! Map) return;
      final payload = decoded.cast<String, Object?>();
      final groupId = payload['groupId'];
      final protectedToken = payload['groupToken'];
      final routeNonce = payload['routeNonce'];
      if (groupId is! String ||
          groupId.isEmpty ||
          protectedToken is! String ||
          routeNonce is! String ||
          routeNonce != signal.groupId ||
          !isOpaqueGroupRoutingToken(routeNonce) ||
          await groupRoutingToken(groupId) != protectedToken) {
        return;
      }
      final digest = base64UrlEncode(
        (await Sha256().hash(utf8.encode('$groupId:$plaintext'))).bytes,
      );
      await _database.exportLogs.insert(
        ExportLogEntity(
          id: digest,
          groupId: groupId,
          actorUserId: payload['actorUserId'] as String? ?? signal.senderId,
          actorDisplayName:
              payload['actorDisplayName'] as String? ?? signal.senderId,
          eventType: payload['eventType'] as String? ?? signal.eventType,
          timestamp:
              (payload['timestamp'] as num?)?.toInt() ??
              _boundedTimestamp(signal.timestamp),
          messageCount: (payload['messageCount'] as num?)?.toInt() ?? 0,
          firstMsgTs: (payload['firstMsgTs'] as num?)?.toInt(),
          lastMsgTs: (payload['lastMsgTs'] as num?)?.toInt(),
        ),
      );
    } catch (_) {
      // Non-recipient and malformed audit payloads are intentionally silent.
    }
  }

  Future<void> _groupNotification(GroupNotificationSignal signal) async {
    final localUserId = _session.userId;
    final group = await _database.conversations.getById(signal.groupId);
    if (signal.action == 'CREATE') {
      if (group == null) {
        if (localUserId == null ||
            !signal.groupMembers.contains(localUserId) ||
            !signal.groupMembers.contains(signal.senderId)) {
          return;
        }
        final preview = (await _strings.load()).group_added_notification;
        final timestamp = _boundedTimestamp(signal.timestamp);
        await _database.conversations.insert(
          ConversationEntity(
            id: signal.groupId,
            peerId: signal.groupId,
            peerName: signal.groupName,
            peerPhone: '',
            lastMessage:
                '${await _groupMemberName(signal.senderId)} grubu oluşturdu',
            lastMessageTimestamp: timestamp,
            unreadCount: signal.senderId == localUserId ? 0 : 1,
            isGroup: true,
            groupMembers: signal.groupMembers.join(','),
            groupAdmins: signal.senderId,
          ),
        );
        if (signal.senderId != localUserId) {
          _messageController.add(
            IncomingMessageEvent(
              messageId: 'group-created:${signal.groupId}',
              conversationId: signal.groupId,
              title: signal.groupName,
              preview: preview,
              timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp),
              isMuted: false,
              isMention: false,
            ),
          );
        }
      } else {
        final members = _csv(group.groupMembers);
        final storedAdmins = _csv(group.groupAdmins);
        final admins = storedAdmins.isEmpty && members.isNotEmpty
            ? <String>{members.first}
            : storedAdmins;
        if (!admins.contains(signal.senderId)) return;
        await _database.conversations.updateGroupMembers(
          signal.groupId,
          {..._csv(group.groupMembers), ...signal.groupMembers}.join(','),
        );
      }
      return;
    }
    if (group == null || !group.isGroup) return;
    final members = _csv(group.groupMembers);
    final admins = _csv(group.groupAdmins);
    final effectiveAdmins = admins.isEmpty && members.isNotEmpty
        ? <String>{members.first}
        : admins;
    const privileged = {
      'ADD_MEMBER',
      'REMOVE_MEMBER',
      'UPDATE_ADMIN',
      'UPDATE_NAME',
      'UPDATE_EXPORT_POLICY',
      'SET_READ_ONLY',
    };
    if (privileged.contains(signal.action) &&
        !effectiveAdmins.contains(signal.senderId)) {
      return;
    }
    final target = signal.targetMemberId;
    switch (signal.action) {
      case 'ADD_MEMBER':
        await _database.conversations.updateGroupMembers(
          signal.groupId,
          signal.groupMembers.join(','),
        );
        if (target != null) {
          await _systemMessage(
            signal,
            '${await _groupMemberName(signal.senderId)}, '
            '${await _groupMemberName(target)} adlı kişiyi gruba ekledi',
          );
        }
      case 'REMOVE_MEMBER':
        if (target == null) return;
        await _database.conversations.updateGroupMembers(
          signal.groupId,
          signal.groupMembers.join(','),
        );
        if (admins.contains(target)) {
          await _database.conversations.updateGroupAdmins(
            signal.groupId,
            admins.where((id) => id != target).join(','),
          );
        }
        if (target == localUserId) {
          await _database.conversations.updateArchived(signal.groupId, true);
          await _systemMessage(signal, 'Bu gruptan çıkarıldınız');
        } else {
          await _systemMessage(
            signal,
            '${await _groupMemberName(signal.senderId)}, '
            '${await _groupMemberName(target)} adlı kişiyi gruptan çıkardı',
          );
          await _database.senderKeys.deleteAllForGroup(signal.groupId);
        }
      case 'LEAVE_GROUP':
        if (!members.contains(signal.senderId)) return;
        final updated = members.where((id) => id != signal.senderId).toList();
        await _database.conversations.updateGroupMembers(
          signal.groupId,
          updated.join(','),
        );
        await _database.conversations.updateGroupAdmins(
          signal.groupId,
          admins.where((id) => id != signal.senderId).join(','),
        );
        await _database.senderKeys.deleteAllForGroup(signal.groupId);
        await _systemMessage(
          signal,
          '${await _groupMemberName(signal.senderId)} gruptan ayrıldı',
        );
      case 'UPDATE_ADMIN':
        if (target == null || !members.contains(target)) return;
        await _database.conversations.updateGroupAdmins(
          signal.groupId,
          {...admins, target}.join(','),
        );
        await _systemMessage(
          signal,
          '${await _groupMemberName(signal.senderId)}, '
          '${await _groupMemberName(target)} adlı kişiyi yönetici yaptı',
        );
      case 'UPDATE_NAME':
        if (signal.groupName.trim().isEmpty) return;
        final previous = group.peerName;
        await _database.conversations.updatePeerName(
          signal.groupId,
          signal.groupName.trim(),
        );
        await _systemMessage(
          signal,
          '${await _groupMemberName(signal.senderId)} grup adını '
          '“$previous” → “${signal.groupName.trim()}” olarak değiştirdi',
        );
      case 'UPDATE_EXPORT_POLICY':
        final enabled = _strictBool(target);
        if (enabled == null) return;
        await _database.conversations.updateExportEnabled(
          signal.groupId,
          enabled,
        );
        await _systemMessage(
          signal,
          '${await _groupMemberName(signal.senderId)} sohbet dışa aktarmayı '
          '${enabled ? 'açtı' : 'kapattı'}',
        );
      case 'SET_READ_ONLY':
        final enabled = _strictBool(target);
        if (enabled == null) return;
        await _database.conversations.updateReadOnly(signal.groupId, enabled);
        await _systemMessage(
          signal,
          enabled
              ? '${await _groupMemberName(signal.senderId)} grubu duyuru kanalına çevirdi'
              : '${await _groupMemberName(signal.senderId)} duyuru kanalı ayarını kapattı',
        );
      default:
        return;
    }
  }

  Future<void> _preparePrivateGroupCall(GroupNotificationSignal control) async {
    final localUserId = _session.userId;
    final routingToken = control.targetMemberId;
    if (localUserId == null ||
        routingToken == null ||
        !isOpaqueGroupRoutingToken(routingToken)) {
      return;
    }
    var group = await _database.conversations.getById(control.groupId);
    if (group == null) {
      await _groupNotification(
        GroupNotificationSignal(
          senderId: control.senderId,
          recipientId: control.recipientId,
          timestamp: control.timestamp,
          groupId: control.groupId,
          groupName: control.groupName,
          action: 'CREATE',
          groupMembers: control.groupMembers,
        ),
      );
      group = await _database.conversations.getById(control.groupId);
    }
    final members = _csv(group?.groupMembers);
    if (group == null ||
        !group.isGroup ||
        !members.contains(localUserId) ||
        !members.contains(control.senderId)) {
      return;
    }
    final expiresAt = control.timestamp.add(const Duration(hours: 4));
    if (!expiresAt.isAfter(DateTime.now())) return;
    const prefix = 'private-group-call-route:';
    for (final entry in (await _database.cryptoState.getByPrefix(
      prefix,
    )).entries) {
      try {
        final value = jsonDecode(entry.value) as Map<String, Object?>;
        final expiry = (value['expiresAt'] as num?)?.toInt() ?? 0;
        if (expiry <= DateTime.now().millisecondsSinceEpoch) {
          await _database.cryptoState.delete(entry.key);
        }
      } catch (_) {
        await _database.cryptoState.delete(entry.key);
      }
    }
    await _database.cryptoState.put(
      privateGroupCallRouteStateKey(routingToken),
      jsonEncode(<String, Object?>{
        'groupId': control.groupId,
        'expiresAt': expiresAt.millisecondsSinceEpoch,
      }),
    );
  }

  Future<String> _memberName(String userId) async {
    final local = await _database.contacts.getById(userId);
    if (local?.displayName.isNotEmpty == true) return local!.displayName;
    return _identityResolver?.resolveDisplayName(userId) ?? userId;
  }

  Future<String> _groupMemberName(String userId) async {
    if (userId == _session.userId) return (await _strings.load()).you;
    final resolver =
        _identityResolver ?? ContactIdentityResolver(database: _database);
    final identity = await resolver.resolve(userId);
    final name = identity.displayName.trim();
    if (name.isNotEmpty && name != userId) return name;
    final phone = identity.phoneNumber.trim();
    return phone.isNotEmpty
        ? phone
        : (await _strings.load()).group_unknown_member;
  }

  Future<void> _systemMessage(
    GroupNotificationSignal signal,
    String content,
  ) async {
    final rawId =
        '${signal.groupId}:${signal.action}:'
        '${signal.timestamp.microsecondsSinceEpoch}:${signal.targetMemberId ?? ''}';
    final id = base64UrlEncode((await Sha256().hash(utf8.encode(rawId))).bytes);
    if (await _database.messages.getById(id) != null) return;
    await _database.messages.insert(
      MessageEntity(
        id: id,
        conversationId: signal.groupId,
        senderId: 'SYSTEM',
        content: content,
        contentType: StorageMessageContentType.system,
        timestamp: _boundedTimestamp(signal.timestamp),
        status: StorageMessageStatus.delivered,
        isOutgoing: false,
      ),
    );
    await _database.conversations.updateLastMessageById(
      signal.groupId,
      content,
      _boundedTimestamp(signal.timestamp),
    );
  }

  Future<void> _acceptSenderKey(String senderId, String plaintext) async {
    final signalCrypto = _crypto;
    if (signalCrypto is SignalProtocolCryptoService) {
      try {
        await signalCrypto.processSenderKeyDistribution(
          senderId: senderId,
          plaintext: plaintext,
        );
      } catch (error, stackTrace) {
        // Sessiz yutulursa o gondericinin grup mesajlari KALICI olarak
        // cozulemez hale gelir ve hicbir iz kalmaz: 1:1 oturum kurtarmasi
        // sender key'i geri getirmez, yeniden isteme mekanizmasi da yoktur.
        _reportSenderKeyFailure(error, stackTrace);
      }
      return;
    }
    final parts = plaintext.split(':');
    if (parts.length != 3) return;
    try {
      final key = base64Decode(parts[2]);
      if (key.length != 32) return;
      await _database.senderKeys.put(
        SenderKeyEntity(
          groupId: parts[1],
          senderId: senderId,
          deviceId: 1,
          record: key,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    } catch (error, stackTrace) {
      _reportSenderKeyFailure(error, stackTrace);
    }
  }

  void _reportSenderKeyFailure(Object error, StackTrace stackTrace) {
    if (_closed || _operations.isClosed) return;
    _operations.run(
      'incoming-message.sender-key',
      Future<void>.error(error, stackTrace),
    );
  }

  Future<void> _applyPollVote(
    PollVoteReference vote,
    String senderId,
    String authenticatedConversationId,
  ) async {
    final message = await _database.messages.getById(vote.pollMessageId);
    final conversation = message == null
        ? null
        : await _database.conversations.getById(message.conversationId);
    if (message == null ||
        message.conversationId != authenticatedConversationId ||
        message.contentType != StorageMessageContentType.poll ||
        !_senderAllowed(conversation, senderId)) {
      return;
    }
    try {
      final poll = PollData.parse(message.content);
      final updated = poll.toggleVote(senderId, vote.optionIndex);
      await _database.messages.updateContent(
        message.id,
        updated.encode(),
        StorageMessageContentType.poll,
      );
    } catch (_) {}
  }

  Future<String?> _localGroupId(String envelope) async {
    if (envelope.startsWith('GROUPSK:v1:')) {
      final parts = envelope.split(':');
      return parts.length == 5 && parts[2].isNotEmpty ? parts[2] : null;
    }
    final routingToken = groupRoutingTokenFromEnvelope(envelope);
    if (routingToken == null) return null;
    for (final group in await _database.conversations.getAllGroups()) {
      final candidate = await groupRoutingToken(group.id);
      if (candidate == routingToken) return group.id;
    }
    return null;
  }
}

String _notificationPreview(ParsedMessageEnvelope parsed) =>
    conversationPreview(
      content: parsed.content,
      isViewOnce: parsed.isViewOnce,
      contentType: parsed.contentType,
    );

int _statusRank(StorageMessageStatus status) => switch (status) {
  StorageMessageStatus.failed => -1,
  StorageMessageStatus.sending => 0,
  StorageMessageStatus.sent => 1,
  StorageMessageStatus.delivered => 2,
  StorageMessageStatus.read => 3,
};

Set<String> _csv(String? value) =>
    value?.split(',').where((id) => id.isNotEmpty).toSet() ?? <String>{};

const _allowedTimerDurations = <int>{
  0,
  60 * 60 * 1000,
  24 * 60 * 60 * 1000,
  7 * 24 * 60 * 60 * 1000,
  30 * 24 * 60 * 60 * 1000,
};

bool? _strictBool(String? value) => switch (value?.toLowerCase()) {
  'true' => true,
  'false' => false,
  _ => null,
};
