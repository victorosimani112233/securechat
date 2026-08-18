import '../core/signal_message.dart';
import '../services/crypto_service.dart';
import '../services/session_store.dart';
import '../services/signaling_service.dart';
import '../storage/secure_chat_database.dart';
import '../storage/storage_entities.dart';
import 'private_chat_control.dart';

class ChatInfoService {
  ChatInfoService({
    required SecureChatDatabase database,
    required SessionStore session,
    required SignalingService signaling,
    required CryptoService crypto,
  }) : _database = database,
       _session = session,
       _signaling = signaling,
       _crypto = crypto;
  final SecureChatDatabase _database;
  final SessionStore _session;
  final SignalingService _signaling;
  final CryptoService _crypto;

  Stream<ConversationEntity?> watchConversation(String id) =>
      _database.conversations.observeById(id);
  Stream<List<MessageEntity>> watchMedia(String id) =>
      _database.messages.getMediaMessages(id);
  Stream<List<MessageEntity>> watchDocuments(String id) =>
      _database.messages.getDocumentMessages(id);
  Stream<List<MessageEntity>> watchStarred(String id) =>
      _database.messages.getStarredMessages(id);
  Stream<List<MessageEntity>> search(String id, String query) =>
      _database.messages.searchMessages(id, query);
  Future<void> updateNote(String id, String note) =>
      _database.conversations.updateContactNote(id, note.trim());
  Future<void> setMuted(String id, bool value) =>
      _database.conversations.updateMuted(id, value);
  Future<void> setLocked(String id, bool value) =>
      _database.conversations.updateLocked(id, value);
  Future<void> clearMessages(String id) async {
    await _database.messages.deleteByConversation(id);
    await _database.conversations.clearLastMessage(id);
  }

  Future<void> setDisappearingTimer(
    ConversationEntity conversation,
    Duration duration,
  ) async {
    final userId = _session.userId;
    if (userId == null) return;
    final milliseconds = duration.inMilliseconds;
    await _database.conversations.updateDisappearingDuration(
      conversation.id,
      milliseconds,
    );
    final recipients = conversation.isGroup
        ? conversation.groupMembers
                  ?.split(',')
                  .where((id) => id.isNotEmpty && id != userId) ??
              const <String>[]
        : <String>[conversation.peerId];
    for (final recipient in recipients) {
      await sendPrivateChatControl(
        crypto: _crypto,
        signaling: _signaling,
        control: DisappearingTimerSignal(
          senderId: userId,
          recipientId: recipient,
          timestamp: DateTime.now(),
          durationMs: milliseconds,
          conversationId: conversation.id,
        ),
      );
    }
  }

  Future<void> setDisappearingTimerForConversation(
    String conversationId,
    Duration duration,
  ) async {
    final conversation = await _database.conversations.getById(conversationId);
    if (conversation == null) return;
    await setDisappearingTimer(conversation, duration);
  }
}
