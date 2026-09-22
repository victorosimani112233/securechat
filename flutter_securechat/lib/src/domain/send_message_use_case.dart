import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../chat/conversation_preview.dart';
import '../contacts/phone_number_sharing_service.dart';
import '../core/signal_message.dart';
import '../crypto/signal_protocol_crypto_service.dart';
import '../groups/private_group_control.dart';
import '../groups/private_group_route.dart';
import '../network/network_resilience.dart';
import '../services/crypto_service.dart';
import '../services/session_store.dart';
import '../services/signaling_service.dart';
import '../storage/secure_chat_database.dart';
import '../storage/storage_entities.dart';

enum SendMessageOutcome { sent, encryptionFailed, deliveryFailed }

class SendMessageRequest {
  const SendMessageRequest({
    required this.conversationId,
    required this.content,
    this.replyToId,
    this.contentType = StorageMessageContentType.text,
    this.isViewOnce = false,
    this.mentionedUserIds = const [],
  });

  final String conversationId;
  final String content;
  final String? replyToId;
  final StorageMessageContentType contentType;
  final bool isViewOnce;
  final List<String> mentionedUserIds;
}

class SendMessageUseCase {
  SendMessageUseCase({
    required SecureChatDatabase database,
    required SignalingService signaling,
    required SessionStore session,
    required CryptoService crypto,
    PrivateGroupControlSender? groupControls,
    this.maxRetryCount = 3,
    this.retryDelay = const Duration(seconds: 2),
    Random? random,
    OfflineMessageQueue? reliableQueue,
    PhoneNumberSharingService? phoneSharing,
  }) : _database = database,
       _signaling = signaling,
       _session = session,
       _crypto = crypto,
       _groupControls =
           groupControls ??
           PrivateGroupControlSender(crypto: crypto, signaling: signaling),
       _reliableQueue = reliableQueue,
       _phoneSharing = phoneSharing,
       _random = random ?? Random.secure();

  final SecureChatDatabase _database;
  final SignalingService _signaling;
  final SessionStore _session;
  final CryptoService _crypto;
  final PrivateGroupControlSender _groupControls;
  final OfflineMessageQueue? _reliableQueue;
  final PhoneNumberSharingService? _phoneSharing;
  final Random _random;
  final int maxRetryCount;
  final Duration retryDelay;

  Future<SendMessageOutcome> call(SendMessageRequest request) async {
    final senderId = _session.userId;
    if (senderId == null || senderId.isEmpty) {
      throw StateError('Authenticated sender is required');
    }
    final now = DateTime.now();
    final conversation = await _database.conversations.getById(
      request.conversationId,
    );
    final isGroup = conversation?.isGroup ?? false;
    final expiresAt =
        conversation != null && conversation.disappearingDuration > 0
        ? now.millisecondsSinceEpoch + conversation.disappearingDuration
        : null;
    final messageId = _newMessageId(now);
    final message = MessageEntity(
      id: messageId,
      conversationId: request.conversationId,
      senderId: senderId,
      content: request.content,
      contentType: request.contentType,
      timestamp: now.millisecondsSinceEpoch,
      status: StorageMessageStatus.sending,
      isOutgoing: true,
      replyToId: request.replyToId,
      expiresAt: expiresAt,
      isViewOnce: request.isViewOnce,
    );
    await _database.messages.insert(message);
    if (conversation == null) {
      await _database.conversations.insert(
        ConversationEntity(
          id: request.conversationId,
          peerId: request.conversationId,
          peerName: request.conversationId,
          peerPhone: '',
          lastMessage: conversationPreview(
            content: request.content,
            isViewOnce: request.isViewOnce,
            contentType: request.contentType,
          ),
          lastMessageTimestamp: now.millisecondsSinceEpoch,
        ),
      );
    } else {
      await _database.conversations.updateLastMessageById(
        request.conversationId,
        conversationPreview(
          content: request.content,
          isViewOnce: request.isViewOnce,
          contentType: request.contentType,
        ),
        now.millisecondsSinceEpoch,
        type: request.contentType,
        outgoing: true,
        status: StorageMessageStatus.sending,
      );
    }

    final envelopeContent = _buildEnvelopeContent(
      messageId: messageId,
      request: request,
      isGroup: isGroup,
      expiresAt: expiresAt,
    );

    await _signaling.ensureConnected(timeout: const Duration(seconds: 8));

    late final List<SignalMessage> signals;
    try {
      if (!isGroup) {
        await _phoneSharing?.shareWith(
          request.conversationId,
          send: (signal) =>
              _sendEncryptedDependency(signal, messageId: messageId),
        );
      }
      if (isGroup && _crypto is SignalProtocolCryptoService) {
        final members = _members(conversation?.groupMembers);
        await _groupControls.send(
          senderId: senderId,
          groupId: request.conversationId,
          groupName: conversation?.peerName ?? '',
          memberIds: {senderId, ...members},
          recipients: members,
          action: 'CREATE',
          timestamp: now,
          sendSignal: (signal) =>
              _sendEncryptedDependency(signal, messageId: messageId),
        );
        await _distributeSenderKey(
          crypto: _crypto,
          senderId: senderId,
          groupId: request.conversationId,
          members: members,
          timestamp: now,
          messageId: messageId,
        );
      } else if (isGroup) {
        final members = _members(conversation?.groupMembers);
        await _groupControls.send(
          senderId: senderId,
          groupId: request.conversationId,
          groupName: conversation?.peerName ?? '',
          memberIds: {senderId, ...members},
          recipients: members,
          action: 'CREATE',
          timestamp: now,
          sendSignal: (signal) =>
              _sendEncryptedDependency(signal, messageId: messageId),
        );
      }
      final wireEnvelope = isGroup && _crypto is SignalProtocolCryptoService
          ? await _crypto.encryptGroupWire(
              senderId: senderId,
              groupId: request.conversationId,
              plaintext: envelopeContent,
            )
          : isGroup
          ? await _crypto.encryptGroup(
              senderId: senderId,
              groupId: request.conversationId,
              plaintext: envelopeContent,
            )
          : await _crypto.encryptDirect(
              recipientId: request.conversationId,
              plaintext: envelopeContent,
            );
      if (isGroup) {
        final recipients = _members(
          conversation?.groupMembers,
        ).where((member) => member != senderId).toSet();
        if (recipients.isEmpty) {
          throw StateError('Group message has no recipient');
        }
        final routePlaintext = encodePrivateGroupRoute(
          groupId: request.conversationId,
          groupEnvelope: wireEnvelope,
        );
        final routed = <SignalMessage>[];
        for (final recipientId in recipients) {
          routed.add(
            EncryptedSignalMessage(
              senderId: senderId,
              recipientId: recipientId,
              timestamp: now,
              envelope: await _crypto.encryptDirect(
                recipientId: recipientId,
                plaintext: routePlaintext,
              ),
              deliveryId: _newDeliveryId(),
            ),
          );
        }
        signals = routed;
      } else {
        signals = [
          EncryptedSignalMessage(
            senderId: senderId,
            recipientId: request.conversationId,
            timestamp: now,
            envelope: wireEnvelope,
            deliveryId: _newDeliveryId(),
          ),
        ];
      }
    } catch (_) {
      await _database.pendingSignals.deleteForMessage(messageId);
      await _database.messages.updateStatusIfSending(
        messageId,
        StorageMessageStatus.failed,
      );
      return SendMessageOutcome.encryptionFailed;
    }

    for (var attempt = 0; attempt <= maxRetryCount; attempt++) {
      var allSent = true;
      for (final signal in signals) {
        final sent = await _sendEncryptedDependency(
          signal as EncryptedSignalMessage,
          messageId: messageId,
        );
        if (!sent) allSent = false;
      }
      if (allSent) {
        await _database.messages.updateStatusIfSending(
          messageId,
          StorageMessageStatus.sent,
        );
        return SendMessageOutcome.sent;
      }
      if (attempt < maxRetryCount) {
        await Future<void>.delayed(retryDelay);
        await _signaling.ensureConnected(timeout: const Duration(seconds: 3));
      }
    }

    await _database.messages.updateStatusIfSending(
      messageId,
      StorageMessageStatus.failed,
    );
    return SendMessageOutcome.deliveryFailed;
  }

  Future<void> _distributeSenderKey({
    required SignalProtocolCryptoService crypto,
    required String senderId,
    required String groupId,
    required List<String> members,
    required DateTime timestamp,
    required String messageId,
  }) async {
    final distribution = await crypto.createSenderKeyDistribution(
      groupId: groupId,
      senderId: senderId,
    );
    for (final member in members.where((id) => id != senderId)) {
      final encrypted = await crypto.encryptDirect(
        recipientId: member,
        plaintext: distribution,
      );
      final sent = await _sendEncryptedDependency(
        EncryptedSignalMessage(
          senderId: senderId,
          recipientId: member,
          timestamp: timestamp,
          envelope: encrypted,
        ),
        messageId: messageId,
      );
      if (!sent) {
        throw StateError('SenderKey distribution failed for $member');
      }
    }
  }

  Future<bool> _sendEncryptedDependency(
    EncryptedSignalMessage signal, {
    required String messageId,
  }) {
    final identified = signal.deliveryId == null
        ? EncryptedSignalMessage(
            senderId: signal.senderId,
            recipientId: signal.recipientId,
            timestamp: signal.timestamp,
            envelope: signal.envelope,
            deliveryId: _newDeliveryId(),
          )
        : signal;
    final reliableQueue = _reliableQueue;
    return reliableQueue == null
        ? _signaling.send(identified)
        : reliableQueue.sendReliably(identified, messageId: messageId);
  }

  String _newMessageId(DateTime now) {
    final randomPart = List.generate(
      12,
      (_) => _random.nextInt(16).toRadixString(16),
    ).join();
    return '${now.microsecondsSinceEpoch}-$randomPart';
  }

  String _newDeliveryId() => base64UrlEncode(
    List<int>.generate(32, (_) => _random.nextInt(256), growable: false),
  ).replaceAll('=', '');
}

String _buildEnvelopeContent({
  required String messageId,
  required SendMessageRequest request,
  required bool isGroup,
  required int? expiresAt,
}) {
  final reply = request.replyToId == null ? '' : 'REPLY:${request.replyToId}:';
  final expiry = expiresAt == null ? '' : 'EXP:$expiresAt:';
  final viewOnce = request.isViewOnce ? 'VIEWONCE:' : '';
  final mentions = isGroup
      ? request.mentionedUserIds
            .map((id) => id.replaceAll(',', '').replaceAll(':', '').trim())
            .where((id) => id.isNotEmpty)
            .toSet()
            .join(',')
      : '';
  final mentionPrefix = mentions.isEmpty ? '' : 'MENTION:$mentions:';
  final type = request.contentType == StorageMessageContentType.poll
      ? 'POLL:'
      : '';
  return 'MSGID:$messageId:$reply$expiry$viewOnce$mentionPrefix$type${request.content}';
}

List<String> _members(String? csv) => csv == null
    ? const []
    : csv
          .split(',')
          .map((member) => member.trim())
          .where((member) => member.isNotEmpty)
          .toSet()
          .toList(growable: false);
