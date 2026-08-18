import '../domain/send_message_use_case.dart';
import '../storage/secure_chat_database.dart';
import '../storage/storage_entities.dart';

class BulkSendResult {
  const BulkSendResult({required this.sent, required this.failed});
  final int sent;
  final Map<String, SendMessageOutcome> failed;
}

class BulkMessageService {
  const BulkMessageService({
    required SecureChatDatabase database,
    required SendMessageUseCase sender,
  }) : _database = database,
       _sender = sender;
  final SecureChatDatabase _database;
  final SendMessageUseCase _sender;

  Stream<List<ConversationEntity>> watchConversations() =>
      _database.conversations.getAll();

  Future<BulkSendResult> send(
    String content,
    Iterable<String> recipients,
  ) async {
    final clean = content.trim();
    final ids = recipients.where((id) => id.isNotEmpty).toSet();
    if (clean.isEmpty || ids.isEmpty)
      throw ArgumentError('Mesaj ve alıcı gerekli.');
    var sent = 0;
    final failed = <String, SendMessageOutcome>{};
    for (final id in ids) {
      final outcome = await _sender(
        SendMessageRequest(conversationId: id, content: clean),
      );
      if (outcome == SendMessageOutcome.sent) {
        sent++;
      } else {
        failed[id] = outcome;
      }
    }
    return BulkSendResult(sent: sent, failed: failed);
  }
}
