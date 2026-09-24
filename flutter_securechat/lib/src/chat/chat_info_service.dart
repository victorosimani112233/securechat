import '../core/signal_message.dart';
import '../l10n/service_strings.dart';
import '../services/crypto_service.dart';
import '../services/session_store.dart';
import '../services/signaling_service.dart';
import '../storage/secure_chat_database.dart';
import '../storage/storage_entities.dart';
import 'disappearing_timer_notice.dart';
import 'private_chat_control.dart';

typedef DisappearingTimerUpdateSender =
    Future<void> Function({
      required String targetUserId,
      required String conversationId,
      required int durationMs,
    });

class ChatInfoService {
  ChatInfoService({
    required SecureChatDatabase database,
    required SessionStore session,
    required SignalingService signaling,
    required CryptoService crypto,
    ServiceStrings? strings,
    DisappearingTimerUpdateSender? timerUpdateSender,
  }) : _database = database,
       _session = session,
       _signaling = signaling,
       _crypto = crypto,
       _strings = strings ?? ServiceStrings.fixed('tr'),
       _timerUpdateSender = timerUpdateSender;
  final SecureChatDatabase _database;
  final SessionStore _session;
  final SignalingService _signaling;
  final CryptoService _crypto;
  final ServiceStrings _strings;
  final DisappearingTimerUpdateSender? _timerUpdateSender;

  Stream<ConversationEntity?> watchConversation(String id) =>
      _database.conversations.observeById(id);
  Stream<List<MessageEntity>> watchMedia(String id) =>
      _database.messages.getMediaMessages(id);
  Stream<List<MessageEntity>> watchDocuments(String id) =>
      _database.messages.getDocumentMessages(id);
  Stream<List<MessageEntity>> watchStarred(String id) =>
      _database.messages.getStarredMessages(id);
  Stream<List<MessageEntity>> watchAllStarred() =>
      _database.messages.getAllStarredMessages();
  Stream<List<MessageEntity>> search(String id, String query) =>
      _database.messages.searchMessages(id, query);
  Future<void> updateNote(String id, String note) =>
      _database.conversations.updateContactNote(id, note.trim());

  /// Sohbete ozel bildirim sesi. null verilince uygulama genelindeki ses
  /// kullanilir.
  ///
  /// Alan `customNotificationUri` adini eski Kotlin uygulamasindan tasiyor;
  /// orada sistem ses URI'si saklaniyordu. Burada paketlenmis bir sesin
  /// ADI tutuluyor (`NotificationSoundPreference.name`), cunku ses artik
  /// uygulamayla birlikte geliyor ve iki platformda da ayni adla
  /// bulunuyor.
  Future<void> setNotificationSound(String id, String? sound) =>
      _database.conversations.updateCustomNotification(id, sound);

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
    final changedAt = DateTime.now();
    final l10n = await _strings.load();
    final notice = localDisappearingTimerNotice(l10n, milliseconds);
    await _database.messages.insert(
      MessageEntity(
        id: 'timer:${changedAt.microsecondsSinceEpoch}:$userId',
        conversationId: conversation.id,
        senderId: 'SYSTEM',
        content: notice,
        contentType: StorageMessageContentType.system,
        timestamp: changedAt.millisecondsSinceEpoch,
        status: StorageMessageStatus.read,
        isOutgoing: true,
      ),
    );
    await _database.conversations.updateLastMessageById(
      conversation.id,
      notice,
      changedAt.millisecondsSinceEpoch,
      type: StorageMessageContentType.system,
      outgoing: true,
      status: StorageMessageStatus.read,
    );
    final recipients = conversation.isGroup
        ? conversation.groupMembers
                  ?.split(',')
                  .where((id) => id.isNotEmpty && id != userId) ??
              const <String>[]
        : <String>[conversation.peerId];
    for (final recipient in recipients) {
      final queuedSender = _timerUpdateSender;
      if (queuedSender != null) {
        await queuedSender(
          targetUserId: recipient,
          conversationId: conversation.id,
          durationMs: milliseconds,
        );
      } else {
        await sendPrivateChatControl(
          crypto: _crypto,
          signaling: _signaling,
          control: DisappearingTimerSignal(
            senderId: userId,
            recipientId: recipient,
            timestamp: changedAt,
            durationMs: milliseconds,
            conversationId: conversation.id,
          ),
        );
      }
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
