import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../chat/message_interaction_service.dart';
import '../chat/poll_service.dart';
import '../chat/private_chat_control.dart';
import '../contacts/contact_service.dart';
import '../core/signal_message.dart';
import '../crypto/signal_protocol_crypto_service.dart';
import '../groups/private_group_control.dart';
import '../groups/private_group_route.dart';
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
  });

  final String messageId;
  final String conversationId;
  final String title;
  final String preview;
  final DateTime timestamp;
  final bool isMuted;
  final bool isMention;
}

class IncomingMessageHandler {
  IncomingMessageHandler({
    required SignalingService signaling,
    required CryptoService crypto,
    required SecureChatDatabase database,
    required SessionStore session,
    ContactIdentityResolver? identityResolver,
    AsyncOperationFailureHandler? onAsyncFailure,
  }) : _signaling = signaling,
       _crypto = crypto,
       _database = database,
       _session = session,
       _identityResolver = identityResolver,
       _operations = AsyncOperationTracker(onFailure: onAsyncFailure);

  final SignalingService _signaling;
  final CryptoService _crypto;
  final SecureChatDatabase _database;
  final SessionStore _session;
  final ContactIdentityResolver? _identityResolver;
  final AsyncOperationTracker _operations;
  final _typingController = StreamController<Map<String, bool>>.broadcast();
  final _presenceController =
      StreamController<Map<String, PresenceInfo>>.broadcast();
  final _messageController = StreamController<IncomingMessageEvent>.broadcast();
  final _typing = <String, bool>{};
  final _presence = <String, PresenceInfo>{};
  final _typingTimers = <String, Timer>{};
  final _seenMessageIds = <String>{};
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
    _subscription ??= _signaling.incoming.listen((signal) {
      final operation = _handleTail.then((_) => _handle(signal));
      _handleTail = operation.then<void>((_) {}, onError: (_, _) {});
      _operations.run('incoming-message.handle', operation);
    });
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
        await _encrypted(signal);
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
      case PresenceUpdateSignal():
        _presenceSignal(signal);
      case AdminEncryptedLogSignal():
        await _adminEncryptedLog(signal);
      case GroupNotificationSignal():
        await _groupNotification(signal);
      default:
        break;
    }
  }

  Future<void> _encrypted(EncryptedSignalMessage signal) async {
    String plaintext;
    String conversationId = signal.senderId;
    var isGroup = false;
    try {
      if (signal.envelope.startsWith('GROUPMETA:v1:') ||
          signal.envelope.startsWith('GROUPSK:v1:') ||
          signal.envelope.startsWith('GROUPSK:v2:')) {
        final groupId = await _localGroupId(signal.envelope);
        if (groupId == null) return;
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
            return;
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
    } catch (_) {
      return;
    }
    if (isPrivateGroupControl(plaintext)) {
      final localUserId = _session.userId;
      if (localUserId == null || localUserId != signal.recipientId) return;
      try {
        final control = await decodePrivateGroupControl(
          plaintext: plaintext,
          authenticatedSenderId: signal.senderId,
          localRecipientId: localUserId,
        );
        if (control.action == privateGroupCallPreparationAction) {
          await _preparePrivateGroupCall(control);
          return;
        }
        await _groupNotification(control);
      } catch (_) {
        // Malformed, mis-bound or unauthenticated control data is fail-closed.
      }
      return;
    }
    if (isPrivateChatControl(plaintext)) {
      final localUserId = _session.userId;
      if (isGroup ||
          localUserId == null ||
          localUserId != signal.recipientId ||
          signal.senderId == localUserId) {
        return;
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
      }
      return;
    }
    if (plaintext.startsWith('SKDM:')) {
      await _acceptSenderKey(signal.senderId, plaintext);
      return;
    }
    final parsed = parseMessageEnvelope(plaintext);
    if (parsed.pollVote != null) {
      await _applyPollVote(parsed.pollVote!, signal.senderId, conversationId);
      return;
    }
    final messageId =
        parsed.messageId ??
        '${signal.timestamp.microsecondsSinceEpoch}-${signal.senderId.hashCode.abs()}';
    if (!_seenMessageIds.add(messageId)) return;
    if (await _database.messages.getById(messageId) != null) return;
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
        timestamp: signal.timestamp.millisecondsSinceEpoch,
        status: StorageMessageStatus.delivered,
        replyToId: parsed.replyToId,
        isOutgoing: false,
        expiresAt: parsed.absoluteExpiresAt,
        isViewOnce: parsed.isViewOnce,
      ),
    );
    await _database.conversations.updateLastMessageById(
      conversationId,
      parsed.content,
      signal.timestamp.millisecondsSinceEpoch,
    );
    await _database.conversations.incrementUnreadCount(conversationId);
    final storedConversation = await _database.conversations.getById(
      conversationId,
    );
    final isMention = parsed.mentionedUserIds.contains(_session.userId);
    final title = isGroup
        ? '${await _memberName(signal.senderId)} (${storedConversation?.peerName ?? conversationId})'
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
      ),
    );
    final localUserId = _session.userId;
    if (localUserId != null && parsed.messageId != null) {
      await sendPrivateChatControl(
        crypto: _crypto,
        signaling: _signaling,
        control: DeliveryReceiptSignal(
          senderId: localUserId,
          recipientId: signal.senderId,
          timestamp: DateTime.now(),
          messageId: messageId,
          status: 'DELIVERED',
        ),
      );
    }
  }

  Future<void> _receipt(DeliveryReceiptSignal signal) async {
    final current = await _database.messages.getById(signal.messageId);
    if (current == null || !current.isOutgoing) return;
    final conversation = await _database.conversations.getById(
      current.conversationId,
    );
    if (!_senderAllowed(conversation, signal.senderId)) return;
    final next = switch (signal.status.toUpperCase()) {
      'READ' => StorageMessageStatus.read,
      'DELIVERED' => StorageMessageStatus.delivered,
      _ => null,
    };
    if (next == null || _statusRank(next) <= _statusRank(current.status))
      return;
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
      signal.timestamp.millisecondsSinceEpoch,
      jsonEncode([message.content]),
    );
  }

  Future<void> _reaction(MessageReactionSignal signal) async {
    final message = await _database.messages.getById(signal.messageId);
    final conversation = message == null
        ? null
        : await _database.conversations.getById(message.conversationId);
    if (message == null ||
        !allowedMessageReactions.contains(signal.emoji) ||
        !_senderAllowed(conversation, signal.senderId)) {
      return;
    }
    final reactions = parseReactions(message.reactions);
    final voters = reactions.putIfAbsent(signal.emoji, () => <String>{});
    if (signal.remove) {
      voters.remove(signal.senderId);
      if (voters.isEmpty) reactions.remove(signal.emoji);
    } else {
      voters.add(signal.senderId);
    }
    await _database.messages.updateReactions(
      signal.messageId,
      reactions.isEmpty
          ? null
          : jsonEncode({
              for (final entry in reactions.entries)
                entry.key: entry.value.toList(growable: false),
            }),
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
              signal.timestamp.millisecondsSinceEpoch,
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
        await _database.conversations.insert(
          ConversationEntity(
            id: signal.groupId,
            peerId: signal.groupId,
            peerName: signal.groupName,
            peerPhone: '',
            lastMessage:
                '${await _memberName(signal.senderId)} grubu oluşturdu',
            lastMessageTimestamp: signal.timestamp.millisecondsSinceEpoch,
            unreadCount: signal.senderId == localUserId ? 0 : 1,
            isGroup: true,
            groupMembers: signal.groupMembers.join(','),
            groupAdmins: signal.senderId,
          ),
        );
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
            '${await _memberName(signal.senderId)}, '
            '${await _memberName(target)} adlı kişiyi gruba ekledi',
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
            '${await _memberName(signal.senderId)}, '
            '${await _memberName(target)} adlı kişiyi gruptan çıkardı',
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
          '${await _memberName(signal.senderId)} gruptan ayrıldı',
        );
      case 'UPDATE_ADMIN':
        if (target == null || !members.contains(target)) return;
        await _database.conversations.updateGroupAdmins(
          signal.groupId,
          {...admins, target}.join(','),
        );
        await _systemMessage(
          signal,
          '${await _memberName(signal.senderId)}, '
          '${await _memberName(target)} adlı kişiyi yönetici yaptı',
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
          '${await _memberName(signal.senderId)} grup adını '
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
          '${await _memberName(signal.senderId)} sohbet dışa aktarmayı '
          '${enabled ? 'açtı' : 'kapattı'}',
        );
      case 'SET_READ_ONLY':
        final enabled = _strictBool(target);
        if (enabled == null) return;
        await _database.conversations.updateReadOnly(signal.groupId, enabled);
        await _systemMessage(
          signal,
          enabled
              ? '${await _memberName(signal.senderId)} grubu duyuru kanalına çevirdi'
              : '${await _memberName(signal.senderId)} duyuru kanalı ayarını kapattı',
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
        timestamp: signal.timestamp.millisecondsSinceEpoch,
        status: StorageMessageStatus.delivered,
        isOutgoing: false,
      ),
    );
    await _database.conversations.updateLastMessageById(
      signal.groupId,
      content,
      signal.timestamp.millisecondsSinceEpoch,
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
      } catch (_) {}
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
    } catch (_) {}
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

String _notificationPreview(ParsedMessageEnvelope parsed) {
  if (parsed.isViewOnce) return 'Tek gösterimlik mesaj';
  return switch (parsed.contentType) {
    StorageMessageContentType.poll => 'Anket: ${parsed.content}',
    StorageMessageContentType.image => 'Fotoğraf',
    StorageMessageContentType.file => 'Dosya',
    StorageMessageContentType.voiceNote => 'Sesli mesaj',
    _ => parsed.content,
  };
}

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
