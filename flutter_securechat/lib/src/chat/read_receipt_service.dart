import 'dart:async';

import '../core/signal_message.dart';
import '../services/crypto_service.dart';
import '../services/session_store.dart';
import '../services/signaling_service.dart';
import '../storage/secure_chat_database.dart';
import '../storage/storage_entities.dart';
import 'private_chat_control.dart';

class ReadReceiptService {
  ReadReceiptService({
    required SecureChatDatabase database,
    required SessionStore session,
    required SignalingService signaling,
    required CryptoService crypto,
    this.deliveredVisibilityDelay = const Duration(milliseconds: 800),
  }) : _database = database,
       _session = session,
       _signaling = signaling,
       _crypto = crypto;

  final SecureChatDatabase _database;
  final SessionStore _session;
  final SignalingService _signaling;
  final CryptoService _crypto;
  final Duration deliveredVisibilityDelay;
  final Set<String> _reservedMessageIds = {};
  final Set<String> _markedConversationIds = {};
  final Map<String, Future<int>> _operations = {};

  Future<int> markConversationRead(String conversationId) {
    final existing = _operations[conversationId];
    if (existing != null) return existing;
    final completer = Completer<int>();
    _operations[conversationId] = completer.future;
    unawaited(() async {
      try {
        completer.complete(await _markConversationRead(conversationId));
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      } finally {
        _operations.remove(conversationId);
      }
    }());
    return completer.future;
  }

  Future<int> _markConversationRead(String conversationId) async {
    final userId = _session.userId;
    if (userId == null || userId.isEmpty) return 0;
    final messages = await _database.messages.getMessagesImmediate(
      conversationId,
    );
    final unread = messages
        .where(
          (message) =>
              !message.isOutgoing &&
              message.status != StorageMessageStatus.read &&
              !_reservedMessageIds.contains(message.id),
        )
        .toList(growable: false);
    _reservedMessageIds.addAll(unread.map((message) => message.id));
    if (_markedConversationIds.add(conversationId) || unread.isNotEmpty) {
      await _database.conversations.markAsRead(conversationId);
    }
    if (unread.isEmpty) return 0;

    if (deliveredVisibilityDelay > Duration.zero) {
      await Future<void>.delayed(deliveredVisibilityDelay);
    }
    var sentCount = 0;
    for (final message in unread) {
      await _database.messages.updateStatus(
        message.id,
        StorageMessageStatus.read,
      );
      if (await sendPrivateChatControl(
        crypto: _crypto,
        signaling: _signaling,
        control: DeliveryReceiptSignal(
          senderId: userId,
          recipientId: message.senderId,
          timestamp: DateTime.now(),
          messageId: message.id,
          status: 'READ',
        ),
      )) {
        sentCount++;
      }
    }
    return sentCount;
  }
}
