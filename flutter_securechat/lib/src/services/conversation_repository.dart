import 'dart:async';

import '../core/models.dart';
import '../domain/send_message_use_case.dart';
import '../storage/secure_chat_database.dart';
import '../storage/storage_entities.dart' as storage;

abstract interface class ConversationRepository {
  Stream<List<Conversation>> watchConversations();
  Stream<List<LocalMessage>> watchMessages(String conversationId);
  Future<List<LocalMessage>> searchAllMessages(String query, {int limit = 100});
  Future<void> sendText(
    String conversationId,
    String text, {
    String? replyToId,
    bool isViewOnce = false,
  });
  Future<void> markConversationRead(String conversationId);
  Future<void> setArchived(String conversationId, bool archived);
  Future<void> setPinned(String conversationId, bool pinned);
  Future<void> setFavorite(String conversationId, bool favorite);
  Future<void> setManuallyUnread(String conversationId, bool unread);
  Future<void> deleteConversation(String conversationId);
}

class InMemoryConversationRepository implements ConversationRepository {
  InMemoryConversationRepository({
    required List<Conversation> conversations,
    required Map<String, List<LocalMessage>> messages,
  }) : _conversations = conversations,
       _messages = messages {
    _conversationController.add(List.unmodifiable(_conversations));
  }

  final List<Conversation> _conversations;
  final Map<String, List<LocalMessage>> _messages;
  final _conversationController =
      StreamController<List<Conversation>>.broadcast();
  final _messageControllers = <String, StreamController<List<LocalMessage>>>{};

  Future<void> persist() async {}

  @override
  Stream<List<Conversation>> watchConversations() async* {
    yield List.unmodifiable(_conversations);
    yield* _conversationController.stream;
  }

  @override
  Stream<List<LocalMessage>> watchMessages(String conversationId) async* {
    final controller = _messageControllers.putIfAbsent(
      conversationId,
      () => StreamController<List<LocalMessage>>.broadcast(),
    );
    yield List.unmodifiable(_messages[conversationId] ?? const []);
    yield* controller.stream;
  }

  @override
  Future<List<LocalMessage>> searchAllMessages(
    String query, {
    int limit = 100,
  }) async {
    final clean = query.trim().toLowerCase();
    if (clean.length < 2 || limit <= 0) return const [];
    final matches =
        _messages.values
            .expand((messages) => messages)
            .where((message) => message.content.toLowerCase().contains(clean))
            .toList(growable: false)
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return matches.take(limit).toList(growable: false);
  }

  @override
  Future<void> sendText(
    String conversationId,
    String text, {
    String? replyToId,
    bool isViewOnce = false,
  }) async {
    final message = LocalMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      conversationId: conversationId,
      senderId: 'me',
      peerId: conversationId,
      content: text,
      contentType: MessageContentType.text,
      timestamp: DateTime.now(),
      status: MessageStatus.sending,
      isOutgoing: true,
      replyToId: replyToId,
      isViewOnce: isViewOnce,
    );
    final list = _messages.putIfAbsent(conversationId, () => []);
    list.add(message);
    _touchConversation(conversationId, text, message.timestamp);
    _notifyMessages(conversationId);
    _notifyConversations();
    await persist();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final index = list.indexWhere((m) => m.id == message.id);
    if (index >= 0) {
      list[index] = message.copyWith(status: MessageStatus.sent);
      _notifyMessages(conversationId);
      await persist();
    }
  }

  @override
  Future<void> markConversationRead(String conversationId) async {
    final i = _conversations.indexWhere((c) => c.id == conversationId);
    if (i < 0) return;
    final c = _conversations[i];
    _conversations[i] = c.copyWith(unreadCount: 0, manuallyUnread: false);
    _notifyConversations();
    await persist();
  }

  @override
  Future<void> setArchived(String conversationId, bool archived) =>
      _updateConversation(
        conversationId,
        (conversation) => conversation.copyWith(isArchived: archived),
      );

  @override
  Future<void> setPinned(String conversationId, bool pinned) =>
      _updateConversation(
        conversationId,
        (conversation) => conversation.copyWith(isPinned: pinned),
      );

  @override
  Future<void> setFavorite(String conversationId, bool favorite) =>
      _updateConversation(
        conversationId,
        (conversation) => conversation.copyWith(isFavorite: favorite),
      );

  @override
  Future<void> setManuallyUnread(String conversationId, bool unread) =>
      _updateConversation(
        conversationId,
        (conversation) => conversation.copyWith(manuallyUnread: unread),
      );

  @override
  Future<void> deleteConversation(String conversationId) async {
    _conversations.removeWhere(
      (conversation) => conversation.id == conversationId,
    );
    _messages.remove(conversationId);
    _notifyConversations();
    _notifyMessages(conversationId);
    await persist();
  }

  Future<void> _updateConversation(
    String conversationId,
    Conversation Function(Conversation conversation) update,
  ) async {
    final index = _conversations.indexWhere(
      (conversation) => conversation.id == conversationId,
    );
    if (index < 0) return;
    _conversations[index] = update(_conversations[index]);
    _notifyConversations();
    await persist();
  }

  void _touchConversation(
    String conversationId,
    String lastMessage,
    DateTime timestamp,
  ) {
    final i = _conversations.indexWhere((c) => c.id == conversationId);
    if (i < 0) {
      _conversations.add(
        Conversation(
          id: conversationId,
          peerId: conversationId,
          peerName: conversationId,
          peerPhone: '',
          lastMessage: lastMessage,
          lastMessageTimestamp: timestamp,
        ),
      );
      return;
    }
    _conversations[i] = _conversations[i].copyWith(
      lastMessage: lastMessage,
      lastMessageTimestamp: timestamp,
    );
    _conversations.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      final at = a.lastMessageTimestamp?.millisecondsSinceEpoch ?? 0;
      final bt = b.lastMessageTimestamp?.millisecondsSinceEpoch ?? 0;
      return bt.compareTo(at);
    });
  }

  void _notifyConversations() {
    _conversationController.add(List.unmodifiable(_conversations));
  }

  void _notifyMessages(String conversationId) {
    _messageControllers[conversationId]?.add(
      List.unmodifiable(_messages[conversationId] ?? const []),
    );
  }

  Map<String, Object?> toJson() => {
    'schema': 1,
    'conversations': _conversations.map((c) => c.toJson()).toList(),
    'messages': _messages.map(
      (key, value) => MapEntry(key, value.map((m) => m.toJson()).toList()),
    ),
  };
}

class StorageConversationRepository implements ConversationRepository {
  StorageConversationRepository(this._db, {required SendMessageUseCase sender})
    : _sender = sender;

  final SecureChatDatabase _db;
  final SendMessageUseCase _sender;

  @override
  Stream<List<Conversation>> watchConversations() {
    return _db.conversations.getAll().map(
      (items) => items.map(_conversationFromEntity).toList(growable: false),
    );
  }

  @override
  Stream<List<LocalMessage>> watchMessages(String conversationId) {
    return _db.messages
        .getMessages(conversationId)
        .map((items) => items.map(_messageFromEntity).toList(growable: false));
  }

  @override
  Future<List<LocalMessage>> searchAllMessages(
    String query, {
    int limit = 100,
  }) async => (await _db.messages.searchAllMessages(
    query,
    limit: limit,
  )).map(_messageFromEntity).toList(growable: false);

  @override
  Future<void> sendText(
    String conversationId,
    String text, {
    String? replyToId,
    bool isViewOnce = false,
  }) async {
    await _sender(
      SendMessageRequest(
        conversationId: conversationId,
        content: text,
        replyToId: replyToId,
        isViewOnce: isViewOnce,
      ),
    );
  }

  @override
  Future<void> markConversationRead(String conversationId) {
    return _db.conversations.markAsRead(conversationId);
  }

  @override
  Future<void> setArchived(String conversationId, bool archived) =>
      _db.conversations.updateArchived(conversationId, archived);

  @override
  Future<void> setPinned(String conversationId, bool pinned) =>
      _db.conversations.updatePinned(conversationId, pinned);

  @override
  Future<void> setFavorite(String conversationId, bool favorite) =>
      _db.conversations.updateFavorite(conversationId, favorite);

  @override
  Future<void> setManuallyUnread(String conversationId, bool unread) =>
      _db.conversations.updateManuallyUnread(conversationId, unread);

  @override
  Future<void> deleteConversation(String conversationId) =>
      _db.conversations.delete(conversationId);
}

Conversation _conversationFromEntity(storage.ConversationEntity entity) {
  return Conversation(
    id: entity.id,
    peerId: entity.peerId,
    peerName: entity.peerName,
    peerPhone: entity.peerPhone,
    lastMessage: entity.lastMessage,
    lastMessageTimestamp: entity.lastMessageTimestamp == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(entity.lastMessageTimestamp!),
    unreadCount: entity.unreadCount,
    isMuted: entity.isMuted,
    isPinned: entity.isPinned,
    isGroup: entity.isGroup,
    groupMembers: _csv(entity.groupMembers),
    groupAdmins: _csv(entity.groupAdmins),
    isArchived: entity.isArchived,
    disappearingDuration: Duration(milliseconds: entity.disappearingDuration),
    isFavorite: entity.isFavorite,
    isLocked: entity.isLocked,
    manuallyUnread: entity.manuallyUnread,
    isReadOnly: entity.isReadOnly,
    isExportEnabled: entity.isExportEnabled,
  );
}

LocalMessage _messageFromEntity(storage.MessageEntity entity) {
  return LocalMessage(
    id: entity.id,
    conversationId: entity.conversationId,
    senderId: entity.senderId,
    peerId: entity.conversationId,
    content: entity.content,
    contentType: _contentTypeFromStorage(entity.contentType),
    timestamp: DateTime.fromMillisecondsSinceEpoch(entity.timestamp),
    status: _statusFromStorage(entity.status),
    isOutgoing: entity.isOutgoing,
    replyToId: entity.replyToId,
    isStarred: entity.isStarred,
    expiresAt: entity.expiresAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(entity.expiresAt!),
    editedAt: entity.editedAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(entity.editedAt!),
    reactions: entity.reactions,
    caption: entity.caption,
    isViewOnce: entity.isViewOnce,
    isViewed: entity.isViewed,
    isPinned: entity.isPinned,
    pinnedAt: entity.pinnedAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(entity.pinnedAt!),
  );
}

List<String> _csv(String? value) => value == null || value.trim().isEmpty
    ? const []
    : value.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

MessageContentType _contentTypeFromStorage(
  storage.StorageMessageContentType type,
) {
  return switch (type) {
    storage.StorageMessageContentType.text => MessageContentType.text,
    storage.StorageMessageContentType.image => MessageContentType.image,
    storage.StorageMessageContentType.file => MessageContentType.file,
    storage.StorageMessageContentType.voiceNote => MessageContentType.voiceNote,
    storage.StorageMessageContentType.system => MessageContentType.system,
    storage.StorageMessageContentType.deleted => MessageContentType.deleted,
    storage.StorageMessageContentType.poll => MessageContentType.poll,
  };
}

MessageStatus _statusFromStorage(storage.StorageMessageStatus status) {
  return switch (status) {
    storage.StorageMessageStatus.sending => MessageStatus.sending,
    storage.StorageMessageStatus.sent => MessageStatus.sent,
    storage.StorageMessageStatus.delivered => MessageStatus.delivered,
    storage.StorageMessageStatus.read => MessageStatus.read,
    storage.StorageMessageStatus.failed => MessageStatus.failed,
  };
}
