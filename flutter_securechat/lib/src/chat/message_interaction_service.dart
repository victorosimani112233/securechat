import 'dart:convert';

import '../core/signal_message.dart';
import '../services/crypto_service.dart';
import '../services/session_store.dart';
import '../services/signaling_service.dart';
import '../storage/secure_chat_database.dart';
import '../storage/storage_entities.dart';
import 'private_chat_control.dart';

class MessageInteractionService {
  MessageInteractionService({
    required SecureChatDatabase database,
    required SignalingService signaling,
    required SessionStore session,
    required CryptoService crypto,
  }) : _database = database,
       _signaling = signaling,
       _session = session,
       _crypto = crypto;

  final SecureChatDatabase _database;
  final SignalingService _signaling;
  final SessionStore _session;
  final CryptoService _crypto;

  Future<void> setStarred(String messageId, bool value) =>
      _database.messages.updateStarred(messageId, value);

  Future<void> deleteLocally(String messageId) async {
    final message = await _database.messages.getById(messageId);
    if (message == null) return;
    await _database.messages.delete(messageId);
    await _refreshLastMessage(message.conversationId);
  }

  Future<bool> deleteForEveryone(String messageId) async {
    final context = await _context(messageId);
    if (context == null || !context.message.isOutgoing) return false;
    final sent = await _fanout(
      context,
      (recipient) => MessageDeleteSignal(
        senderId: context.userId,
        recipientId: recipient,
        timestamp: DateTime.now(),
        messageId: messageId,
      ),
    );
    if (!sent) return false;
    await _database.messages.updateContent(
      messageId,
      'Bu mesaj silindi',
      StorageMessageContentType.deleted,
    );
    await _refreshLastMessage(context.message.conversationId);
    return true;
  }

  Future<bool> edit(String messageId, String newContent) async {
    final clean = newContent.trim();
    final context = await _context(messageId);
    if (context == null ||
        clean.isEmpty ||
        clean.length > 10000 ||
        !context.message.isOutgoing ||
        context.message.contentType != StorageMessageContentType.text ||
        context.message.isViewOnce ||
        DateTime.now().millisecondsSinceEpoch - context.message.timestamp >
            const Duration(minutes: 15).inMilliseconds) {
      return false;
    }
    final editedAt = DateTime.now();
    final sent = await _fanout(
      context,
      (recipient) => MessageEditSignal(
        senderId: context.userId,
        recipientId: recipient,
        timestamp: editedAt,
        messageId: messageId,
        newContent: clean,
      ),
    );
    if (!sent) return false;
    await _database.messages.updateContentEdited(
      messageId,
      clean,
      editedAt.millisecondsSinceEpoch,
      jsonEncode([context.message.content]),
    );
    await _refreshLastMessage(context.message.conversationId);
    return true;
  }

  Future<bool> toggleReaction(String messageId, String emoji) async {
    if (!allowedMessageReactions.contains(emoji)) return false;
    final context = await _context(messageId);
    if (context == null ||
        context.message.contentType == StorageMessageContentType.deleted) {
      return false;
    }
    final reactions = parseReactions(context.message.reactions);
    final voters = reactions.putIfAbsent(emoji, () => <String>{});
    final removing = !voters.add(context.userId);
    if (removing) {
      voters.remove(context.userId);
      if (voters.isEmpty) reactions.remove(emoji);
    }
    final sent = await _fanout(
      context,
      (recipient) => MessageReactionSignal(
        senderId: context.userId,
        recipientId: recipient,
        timestamp: DateTime.now(),
        messageId: messageId,
        emoji: emoji,
        remove: removing,
      ),
    );
    if (!sent) return false;
    await _database.messages.updateReactions(
      messageId,
      reactions.isEmpty
          ? null
          : jsonEncode({
              for (final entry in reactions.entries)
                entry.key: entry.value.toList(growable: false),
            }),
    );
    return true;
  }

  Future<bool> setPinned(String messageId, bool value) async {
    final context = await _context(messageId);
    if (context == null) return false;
    if (context.conversation.isGroup &&
        !_csv(context.conversation.groupAdmins).contains(context.userId)) {
      return false;
    }
    final pinnedAt = value ? DateTime.now() : null;
    final sent = await _fanout(
      context,
      (recipient) => MessagePinSignal(
        senderId: context.userId,
        recipientId: recipient,
        timestamp: DateTime.now(),
        messageId: messageId,
        isPinned: value,
        pinnedAt: pinnedAt,
        groupId: context.conversation.isGroup ? context.conversation.id : null,
      ),
    );
    if (!sent) return false;
    await _database.messages.updatePinned(
      messageId,
      value,
      pinnedAt?.millisecondsSinceEpoch,
    );
    return true;
  }

  Future<_InteractionContext?> _context(String messageId) async {
    final userId = _session.userId;
    final message = await _database.messages.getById(messageId);
    if (userId == null || userId.isEmpty || message == null) return null;
    final conversation = await _database.conversations.getById(
      message.conversationId,
    );
    if (conversation == null) return null;
    return _InteractionContext(userId, message, conversation);
  }

  Future<bool> _fanout(
    _InteractionContext context,
    SignalMessage Function(String recipient) build,
  ) async {
    final recipients = context.conversation.isGroup
        ? _csv(
            context.conversation.groupMembers,
          ).where((id) => id != context.userId).toList(growable: false)
        : [context.conversation.peerId];
    if (recipients.isEmpty) return false;
    await _signaling.ensureConnected(timeout: const Duration(seconds: 8));
    var allSent = true;
    for (final recipient in recipients) {
      var sent = false;
      for (var attempt = 0; attempt < 3 && !sent; attempt++) {
        sent = await sendPrivateChatControl(
          crypto: _crypto,
          signaling: _signaling,
          control: build(recipient),
        );
      }
      allSent = allSent && sent;
    }
    return allSent;
  }

  Future<void> _refreshLastMessage(String conversationId) async {
    final latest = await _database.messages.getMessagesPaginated(
      conversationId,
      1,
      0,
    );
    if (latest.isEmpty) {
      await _database.conversations.clearLastMessage(conversationId);
      return;
    }
    final message = latest.single;
    await _database.conversations.updateLastMessageById(
      conversationId,
      message.contentType == StorageMessageContentType.deleted
          ? 'Bu mesaj silindi'
          : message.content,
      message.timestamp,
    );
  }
}

Map<String, Set<String>> parseReactions(String? raw) {
  if (raw == null || raw.isEmpty) return {};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return {};
    return {
      for (final entry in decoded.entries)
        if (entry.value is List)
          entry.key.toString(): (entry.value as List)
              .whereType<String>()
              .where((id) => id.isNotEmpty)
              .toSet(),
    };
  } catch (_) {
    return {};
  }
}

class _InteractionContext {
  const _InteractionContext(this.userId, this.message, this.conversation);
  final String userId;
  final MessageEntity message;
  final ConversationEntity conversation;
}

Set<String> _csv(String? raw) => raw == null
    ? <String>{}
    : raw
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet();

const allowedMessageReactions = {'👍', '❤️', '😂', '😮', '😢', '🙏'};
