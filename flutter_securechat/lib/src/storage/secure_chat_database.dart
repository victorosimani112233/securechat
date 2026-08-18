import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../services/crypto_service.dart';
import 'storage_entities.dart';

class SecureChatDatabase {
  SecureChatDatabase._({
    required File file,
    required LocalAeadCryptoService crypto,
    required _StorageSnapshot snapshot,
  }) : _file = file,
       _crypto = crypto,
       _snapshot = snapshot {
    conversations = ConversationDao._(this);
    messages = MessageDao._(this);
    contacts = ContactDao._(this);
    callLogs = CallLogDao._(this);
    scheduledMessages = ScheduledMessageDao._(this);
    exportLogs = ExportLogDao._(this);
    pendingTimerUpdates = PendingTimerUpdateDao._(this);
    identities = IdentityDao._(this);
    preKeys = PreKeyDao._(this);
    signedPreKeys = SignedPreKeyDao._(this);
    sessions = SessionDao._(this);
    senderKeys = SenderKeyDao._(this);
    cryptoState = CryptoStateDao._(this);
    pendingSignals = PendingSignalDao._(this);
  }

  final File _file;
  final LocalAeadCryptoService _crypto;
  _StorageSnapshot _snapshot;
  final _changed = StreamController<void>.broadcast();
  Future<void> _writeTail = Future<void>.value();
  Future<void>? _closeTask;
  bool _closed = false;

  late final ConversationDao conversations;
  late final MessageDao messages;
  late final ContactDao contacts;
  late final CallLogDao callLogs;
  late final ScheduledMessageDao scheduledMessages;
  late final ExportLogDao exportLogs;
  late final PendingTimerUpdateDao pendingTimerUpdates;
  late final IdentityDao identities;
  late final PreKeyDao preKeys;
  late final SignedPreKeyDao signedPreKeys;
  late final SessionDao sessions;
  late final SenderKeyDao senderKeys;
  late final CryptoStateDao cryptoState;
  late final PendingSignalDao pendingSignals;

  static Future<SecureChatDatabase> open({
    required File file,
    required LocalAeadCryptoService crypto,
  }) async {
    if (await file.exists()) {
      final envelope = await file.readAsString();
      if (envelope.trim().isNotEmpty) {
        final json =
            jsonDecode(await crypto.decryptStorageJson(envelope))
                as Map<String, Object?>;
        return SecureChatDatabase._(
          file: file,
          crypto: crypto,
          snapshot: _StorageSnapshot.fromJson(json),
        );
      }
    }
    final db = SecureChatDatabase._(
      file: file,
      crypto: crypto,
      snapshot: _StorageSnapshot.empty(),
    );
    await db._persist();
    return db;
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
    await _writeTail;
    await _changed.close();
  }

  /// Returns a portable, unencrypted snapshot for the password-protected
  /// backup layer. Callers must never persist this string without encrypting
  /// it first.
  Future<String> exportPortableJson() async {
    await _writeTail;
    return jsonEncode(_snapshot.toJson());
  }

  /// Atomically replaces all persisted application state after a backup has
  /// been authenticated, decompressed and fully parsed.
  Future<void> replaceFromPortableJson(String rawJson) async {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map) {
      throw const FormatException('Backup database snapshot is not an object');
    }
    final map = decoded.cast<String, Object?>();
    final schema = (map['schema'] as num?)?.toInt() ?? 0;
    if (schema < 1 || schema > 1) {
      throw FormatException('Unsupported database schema: $schema');
    }
    // Parse before entering the serialized write queue. A malformed backup
    // therefore cannot partially mutate the active database.
    final replacement = _StorageSnapshot.fromJson(map);
    await _write((_) => _snapshot = replacement);
  }

  static const legacyRoomImportMarker = 'legacy_room_v22_imported';

  Future<bool> isLegacyRoomImportComplete() async =>
      _snapshot.cryptoState[legacyRoomImportMarker] == 'true';

  /// Installs a fully parsed Room conversion only into a pristine Flutter
  /// database. The marker is committed in the same encrypted file write as
  /// all imported rows, so a process crash cannot expose a partial import.
  Future<void> importLegacyRoomPortableJson(String rawJson) async {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map) {
      throw const FormatException('Legacy Room snapshot is not an object');
    }
    final replacement = _StorageSnapshot.fromJson(
      decoded.cast<String, Object?>(),
    );
    replacement.cryptoState[legacyRoomImportMarker] = 'true';
    await _write((current) {
      if (current.cryptoState[legacyRoomImportMarker] == 'true') return;
      if (!current.isPristineForLegacyImport) {
        throw StateError(
          'Legacy Room import refused because Flutter storage contains user data',
        );
      }
      _snapshot = replacement;
    });
  }

  /// Clears every logical table in one serialized, atomically persisted
  /// snapshot replacement. The database file remains valid and encrypted.
  Future<void> clearAll() =>
      _write((_) => _snapshot = _StorageSnapshot.empty());

  /// Drops only peer cryptographic state. Conversation/message/user data is
  /// preserved. Used once when replacing the pre-libsignal Flutter preview's
  /// incompatible JSON key records with real Signal protobuf records.
  Future<void> clearCryptoProtocolState() => _write((snapshot) {
    snapshot.identities.clear();
    snapshot.preKeys.clear();
    snapshot.signedPreKeys.clear();
    snapshot.sessions.clear();
    snapshot.senderKeys.clear();
    snapshot.cryptoState.removeWhere(
      (key, _) =>
          key == 'local_registration_id' ||
          key == 'local_identity_key_pair_v1' ||
          key.startsWith('pending_sender_key_rotation:'),
    );
  });

  Future<void> _write(FutureOr<void> Function(_StorageSnapshot s) mutate) {
    if (_closed) throw StateError('Secure chat database is closed');
    final operation = _writeTail.then<void>((_) async {
      final before = _StorageSnapshot.fromJson(_snapshot.toJson());
      try {
        await mutate(_snapshot);
        await _persist();
        _changed.add(null);
      } catch (_) {
        _snapshot = before;
        rethrow;
      }
    });
    _writeTail = operation.then<void>((_) {}, onError: (_, _) {});
    return operation;
  }

  Stream<T> _watch<T>(T Function(_StorageSnapshot s) project) async* {
    yield project(_snapshot);
    yield* _changed.stream.map((_) => project(_snapshot));
  }

  Future<void> _persist() async {
    await _file.parent.create(recursive: true);
    final envelope = await _crypto.encryptStorageJson(
      jsonEncode(_snapshot.toJson()),
    );
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(envelope, flush: true);
    // File.rename replaces an existing regular file on Android/iOS/Linux.
    // Deleting the destination first would create a crash window in which the
    // authenticated database disappears entirely.
    await tmp.rename(_file.path);
  }
}

class ConversationDao {
  ConversationDao._(this._db);
  final SecureChatDatabase _db;

  Stream<List<ConversationEntity>> getAll() => _db._watch(_sorted);
  Future<List<ConversationEntity>> getAllImmediate() async =>
      _sorted(_db._snapshot);
  Future<List<ConversationEntity>> getAllGroups() async => _db
      ._snapshot
      .conversations
      .values
      .where((c) => c.isGroup)
      .toList(growable: false);
  Future<ConversationEntity?> getById(String id) async =>
      _db._snapshot.conversations[id];
  Stream<ConversationEntity?> observeById(String id) =>
      _db._watch((s) => s.conversations[id]);
  Future<ConversationEntity?> getByPeerId(String peerId) async => _db
      ._snapshot
      .conversations
      .values
      .where((c) => c.peerId == peerId)
      .firstOrNull;
  Future<List<ConversationEntity>> getByPeerIds(List<String> peerIds) async =>
      _db._snapshot.conversations.values
          .where((c) => peerIds.contains(c.peerId))
          .toList(growable: false);
  Future<void> insert(ConversationEntity conversation) =>
      _db._write((s) => s.conversations[conversation.id] = conversation);
  Future<void> update(ConversationEntity conversation) => insert(conversation);
  Future<void> markAsRead(String conversationId) => _patch(
    conversationId,
    (c) => c.copyWith(unreadCount: 0, manuallyUnread: false),
  );
  Future<void> delete(String conversationId) => _db._write((s) {
    s.conversations.remove(conversationId);
    s.messages.removeWhere((_, m) => m.conversationId == conversationId);
  });
  Future<void> updateGroupMembers(String groupId, String groupMembers) =>
      _patch(groupId, (c) => c.copyWith(groupMembers: groupMembers));
  Future<void> updateLastMessage(
    String peerId,
    String message,
    int timestamp,
  ) => _db._write((s) {
    for (final entry in s.conversations.entries) {
      if (entry.value.peerId == peerId) {
        s.conversations[entry.key] = entry.value.copyWith(
          lastMessage: message,
          lastMessageTimestamp: timestamp,
        );
      }
    }
  });
  Future<void> incrementUnreadCount(String peerId) => _db._write((s) {
    for (final entry in s.conversations.entries) {
      if (entry.value.peerId == peerId) {
        s.conversations[entry.key] = entry.value.copyWith(
          unreadCount: entry.value.unreadCount + 1,
        );
      }
    }
  });
  Future<void> updateContactNote(String id, String? note) =>
      _patch(id, (c) => c.copyWith(contactNote: note));
  Future<void> updateCustomNotification(String id, String? uri) =>
      _patch(id, (c) => c.copyWith(customNotificationUri: uri));
  Future<void> updatePeerName(String id, String name) =>
      _patch(id, (c) => c.copyWith(peerName: name));
  Future<void> updateArchived(String id, bool isArchived) =>
      _patch(id, (c) => c.copyWith(isArchived: isArchived));
  Future<void> updatePinned(String id, bool isPinned) =>
      _patch(id, (c) => c.copyWith(isPinned: isPinned));
  Stream<List<ConversationEntity>> getArchived() =>
      _db._watch((s) => _sorted(s).where((c) => c.isArchived).toList());
  Future<void> updateDisappearingDuration(String id, int duration) =>
      _patch(id, (c) => c.copyWith(disappearingDuration: duration));
  Future<void> updateGroupAdmins(String id, String admins) =>
      _patch(id, (c) => c.copyWith(groupAdmins: admins));
  Future<void> updateFavorite(String id, bool isFavorite) =>
      _patch(id, (c) => c.copyWith(isFavorite: isFavorite));
  Future<void> updateMuted(String id, bool isMuted) =>
      _patch(id, (c) => c.copyWith(isMuted: isMuted));
  Future<void> updateLocked(String id, bool isLocked) =>
      _patch(id, (c) => c.copyWith(isLocked: isLocked));
  Future<void> updateExportEnabled(String id, bool isEnabled) =>
      _patch(id, (c) => c.copyWith(isExportEnabled: isEnabled));
  Future<String?> getLastMessageContent(String conversationId) async =>
      (await _latest(conversationId))?.content;
  Future<int?> getLastMessageTimestamp(String conversationId) async =>
      (await _latest(conversationId))?.timestamp;
  Future<MessageEntity?> getLastMessageInfo(String conversationId) =>
      _latest(conversationId);
  Future<void> updateLastMessageById(
    String conversationId,
    String message,
    int timestamp,
  ) => _patch(
    conversationId,
    (c) => c.copyWith(lastMessage: message, lastMessageTimestamp: timestamp),
  );
  Future<void> clearLastMessage(String conversationId) => _db._write((s) {
    final current = s.conversations[conversationId];
    if (current == null) return;
    s.conversations[conversationId] = ConversationEntity(
      id: current.id,
      peerId: current.peerId,
      peerName: current.peerName,
      peerPhone: current.peerPhone,
      unreadCount: current.unreadCount,
      isMuted: current.isMuted,
      isPinned: current.isPinned,
      isGroup: current.isGroup,
      groupMembers: current.groupMembers,
      contactNote: current.contactNote,
      customNotificationUri: current.customNotificationUri,
      isArchived: current.isArchived,
      disappearingDuration: current.disappearingDuration,
      groupAdmins: current.groupAdmins,
      isFavorite: current.isFavorite,
      isLocked: current.isLocked,
      isExportEnabled: current.isExportEnabled,
      manuallyUnread: current.manuallyUnread,
      isReadOnly: current.isReadOnly,
    );
  });
  Future<void> updateManuallyUnread(String id, bool manuallyUnread) =>
      _patch(id, (c) => c.copyWith(manuallyUnread: manuallyUnread));
  Future<void> updateReadOnly(String id, bool isReadOnly) =>
      _patch(id, (c) => c.copyWith(isReadOnly: isReadOnly));

  Future<MessageEntity?> _latest(String conversationId) async => _db
      ._snapshot
      .messages
      .values
      .where((m) => m.conversationId == conversationId)
      .sortedBy((m) => -m.timestamp)
      .firstOrNull;

  Future<void> _patch(
    String id,
    ConversationEntity Function(ConversationEntity c) patch,
  ) => _db._write((s) {
    final current = s.conversations[id];
    if (current != null) s.conversations[id] = patch(current);
  });

  static List<ConversationEntity> _sorted(_StorageSnapshot s) =>
      s.conversations.values.toList()..sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        return (b.lastMessageTimestamp ?? 0).compareTo(
          a.lastMessageTimestamp ?? 0,
        );
      });
}

class MessageDao {
  MessageDao._(this._db);
  final SecureChatDatabase _db;

  Stream<List<MessageEntity>> getMessages(String conversationId) => _db._watch(
    (s) => s.messages.values
        .where((m) => m.conversationId == conversationId)
        .sortedBy((m) => m.timestamp),
  );
  Future<List<MessageEntity>> getMessagesImmediate(
    String conversationId,
  ) async => _db._snapshot.messages.values
      .where((message) => message.conversationId == conversationId)
      .sortedBy((message) => message.timestamp);
  Stream<List<MessageEntity>> getRecentMessages(String id, int limit) =>
      _db._watch(
        (s) => s.messages.values
            .where((m) => m.conversationId == id)
            .sortedBy((m) => -m.timestamp)
            .take(limit)
            .toList(),
      );
  Future<void> insert(MessageEntity message) =>
      _db._write((s) => s.messages[message.id] = message);
  Future<void> update(MessageEntity message) => insert(message);
  Future<void> updateStatus(String id, StorageMessageStatus status) =>
      _patch(id, (m) => m.copyWith(status: status));
  Future<MessageEntity?> getById(String id) async => _db._snapshot.messages[id];
  Future<void> delete(String id) => _db._write((s) => s.messages.remove(id));
  Future<void> deleteByConversation(String conversationId) => _db._write(
    (s) => s.messages.removeWhere((_, m) => m.conversationId == conversationId),
  );
  Stream<int> getUnreadCount(String conversationId) => _db._watch(
    (s) => s.messages.values
        .where(
          (m) =>
              m.conversationId == conversationId &&
              !m.isOutgoing &&
              m.status != StorageMessageStatus.read,
        )
        .length,
  );
  Future<void> deleteOlderThan(int cutoff) =>
      _db._write((s) => s.messages.removeWhere((_, m) => m.timestamp < cutoff));
  Future<void> updateContent(
    String id,
    String content,
    StorageMessageContentType type,
  ) => _patch(id, (m) => m.copyWith(content: content, contentType: type));
  Future<List<MessageEntity>> getAllMessages() async =>
      _db._snapshot.messages.values.sortedBy((m) => m.timestamp);
  Future<List<MessageEntity>> getMessagesPaginated(
    String conversationId,
    int limit,
    int offset,
  ) async => _db._snapshot.messages.values
      .where((m) => m.conversationId == conversationId)
      .sortedBy((m) => -m.timestamp)
      .skip(offset)
      .take(limit)
      .toList();
  Future<List<MessageEntity>> getOlderMessages(
    String conversationId,
    int beforeTimestamp,
    int limit,
  ) async => _db._snapshot.messages.values
      .where((m) => m.conversationId == conversationId)
      .where((m) => m.timestamp < beforeTimestamp)
      .sortedBy((m) => -m.timestamp)
      .take(limit)
      .toList();
  Future<int> getMessageCount(String conversationId) async => _db
      ._snapshot
      .messages
      .values
      .where((m) => m.conversationId == conversationId)
      .length;
  Future<List<MessageEntity>> getMessagesBatch(int limit, int offset) async =>
      _db._snapshot.messages.values
          .sortedBy((m) => m.timestamp)
          .skip(offset)
          .take(limit)
          .toList();
  Future<void> updateContentEdited(
    String id,
    String content,
    int editedAt,
    String? editHistory,
  ) => _patch(
    id,
    (m) => m.copyWith(
      content: content,
      editedAt: editedAt,
      editHistory: editHistory,
    ),
  );
  Future<void> markViewOnceAsViewed(String id) =>
      _patch(id, (m) => m.copyWith(isViewed: true));
  Future<void> consumeViewOnceText(String id) => _patch(
    id,
    (m) => m.contentType == StorageMessageContentType.text
        ? m.copyWith(isViewed: true, content: '')
        : m,
  );
  Future<void> updateStarred(String id, bool isStarred) =>
      _patch(id, (m) => m.copyWith(isStarred: isStarred));
  Stream<List<MessageEntity>> getStarredMessages(String conversationId) =>
      _db._watch(
        (s) => s.messages.values
            .where((m) => m.conversationId == conversationId && m.isStarred)
            .sortedBy((m) => -m.timestamp),
      );
  Stream<List<MessageEntity>> getAllStarredMessages() => _db._watch(
    (s) => s.messages.values
        .where((m) => m.isStarred)
        .sortedBy((m) => -m.timestamp),
  );
  Stream<List<MessageEntity>> searchMessages(String conversationId, String q) =>
      _db._watch(
        (s) => s.messages.values
            .where((m) => m.conversationId == conversationId)
            .where((m) => m.content.contains(q.replaceAll('%', '')))
            .sortedBy((m) => -m.timestamp),
      );
  Future<List<MessageEntity>> searchAllMessages(
    String q, {
    int limit = 100,
  }) async {
    final clean = q.replaceAll('%', '').trim().toLowerCase();
    if (clean.length < 2 || limit <= 0) return const [];
    return _db._snapshot.messages.values
        .where((m) => m.content.toLowerCase().contains(clean))
        .where(
          (m) =>
              m.contentType == StorageMessageContentType.text ||
              m.contentType == StorageMessageContentType.voiceNote,
        )
        .sortedBy((m) => -m.timestamp)
        .take(limit)
        .toList();
  }

  Stream<List<MessageEntity>> getMediaMessages(String conversationId) =>
      _db._watch(
        (s) => s.messages.values
            .where((m) => m.conversationId == conversationId)
            .where((m) => _isMedia(m))
            .sortedBy((m) => -m.timestamp),
      );
  Stream<List<MessageEntity>> getDocumentMessages(String conversationId) =>
      _db._watch(
        (s) => s.messages.values
            .where((m) => m.conversationId == conversationId)
            .where(
              (m) =>
                  m.contentType == StorageMessageContentType.file &&
                  !_isMedia(m),
            )
            .sortedBy((m) => -m.timestamp),
      );
  Future<int> deleteExpiredMessages(int now) async {
    final ids = _db._snapshot.messages.values
        .where((m) => m.expiresAt != null && m.expiresAt! < now)
        .map((m) => m.id)
        .toList();
    await _db._write((s) {
      for (final id in ids) {
        s.messages.remove(id);
      }
    });
    return ids.length;
  }

  Future<List<String>> getExpiredConversationIds(int now) async => _db
      ._snapshot
      .messages
      .values
      .where((m) => m.expiresAt != null && m.expiresAt! < now)
      .map((m) => m.conversationId)
      .toSet()
      .toList();
  Future<List<String>> getExpiredMediaContents(int now) async => _db
      ._snapshot
      .messages
      .values
      .where((m) => m.expiresAt != null && m.expiresAt! < now)
      .where(_isFileLike)
      .map((m) => m.content)
      .toList();
  Future<MessageEntity?> getLatestMessage(String conversationId) async => _db
      ._snapshot
      .messages
      .values
      .where((m) => m.conversationId == conversationId)
      .sortedBy((m) => -m.timestamp)
      .firstOrNull;
  Future<int> applyRetroactiveExpiry(
    String conversationId,
    int duration,
    int windowStart,
    int now,
  ) async {
    var count = 0;
    await _db._write((s) {
      for (final entry in s.messages.entries.toList()) {
        final m = entry.value;
        if (m.conversationId == conversationId &&
            !m.isOutgoing &&
            m.expiresAt == null &&
            m.timestamp >= windowStart &&
            m.timestamp <= now) {
          s.messages[entry.key] = m.copyWith(expiresAt: m.timestamp + duration);
          count++;
        }
      }
    });
    return count;
  }

  Future<List<MessageEntity>> getStuckSendingMessages(int olderThan) async =>
      _db._snapshot.messages.values
          .where(
            (m) =>
                m.status == StorageMessageStatus.sending &&
                m.isOutgoing &&
                m.timestamp < olderThan,
          )
          .toList();
  Future<int> markStuckMessagesAsFailed(int cutoff) async {
    var count = 0;
    await _db._write((s) {
      for (final entry in s.messages.entries.toList()) {
        final m = entry.value;
        if (m.status == StorageMessageStatus.sending && m.timestamp < cutoff) {
          s.messages[entry.key] = m.copyWith(
            status: StorageMessageStatus.failed,
          );
          count++;
        }
      }
    });
    return count;
  }

  Future<void> updateReactions(String id, String? reactions) =>
      _patch(id, (m) => m.copyWith(reactions: reactions));
  Future<void> updatePinned(String id, bool isPinned, int? pinnedAt) =>
      _patch(id, (m) => m.copyWith(isPinned: isPinned, pinnedAt: pinnedAt));
  Stream<MessageEntity?> observeLatestPinned(String conversationId) =>
      _db._watch(
        (s) => s.messages.values
            .where((m) => m.conversationId == conversationId)
            .where((m) => m.isPinned && m.pinnedAt != null)
            .sortedBy((m) => -m.pinnedAt!)
            .firstOrNull,
      );
  Stream<List<MessageEntity>> getPinnedMessages(String conversationId) =>
      _db._watch(
        (s) => s.messages.values
            .where((m) => m.conversationId == conversationId && m.isPinned)
            .sortedBy((m) => -(m.pinnedAt ?? 0)),
      );
  Future<List<String>> getFileContentsByConversation(
    String conversationId,
  ) async => _db._snapshot.messages.values
      .where((m) => m.conversationId == conversationId)
      .where(_isFileLike)
      .map((m) => m.content)
      .toList();
  Future<void> deleteMediaByConversation(String conversationId) => _db._write(
    (s) => s.messages.removeWhere(
      (_, m) => m.conversationId == conversationId && _isFileLike(m),
    ),
  );

  Future<void> _patch(
    String id,
    MessageEntity Function(MessageEntity m) patch,
  ) => _db._write((s) {
    final current = s.messages[id];
    if (current != null) s.messages[id] = patch(current);
  });

  static bool _isFileLike(MessageEntity m) =>
      m.contentType == StorageMessageContentType.file ||
      m.contentType == StorageMessageContentType.image ||
      m.contentType == StorageMessageContentType.voiceNote;
  static bool _isMedia(MessageEntity m) =>
      m.contentType == StorageMessageContentType.image ||
      (m.contentType == StorageMessageContentType.file &&
          (m.content.contains('|video/') ||
              m.content.contains('|audio/') ||
              m.content.contains('|image/')));
}

class ContactDao {
  ContactDao._(this._db);
  final SecureChatDatabase _db;
  Stream<List<ContactEntity>> getAll() => _db._watch(_sorted);
  Future<List<ContactEntity>> getAllOnce() async => _sorted(_db._snapshot);
  Stream<List<ContactEntity>> getRegistered() =>
      _db._watch((s) => _sorted(s).where((c) => c.isRegistered).toList());
  Future<List<ContactEntity>> getRegisteredPaginated(
    int limit,
    int offset,
  ) async => _sorted(
    _db._snapshot,
  ).where((c) => c.isRegistered).skip(offset).take(limit).toList();
  Future<int> getRegisteredCount() async =>
      _db._snapshot.contacts.values.where((c) => c.isRegistered).length;
  Future<List<ContactEntity>> getByHashes(List<String> hashes) async => _db
      ._snapshot
      .contacts
      .values
      .where((c) => hashes.contains(c.phoneHash))
      .toList();
  Future<ContactEntity?> getById(String id) async => _db._snapshot.contacts[id];
  Future<void> insert(ContactEntity contact) =>
      _db._write((s) => s.contacts[contact.id] = contact);
  Future<void> insertAll(List<ContactEntity> contacts) => _db._write((s) {
    for (final c in contacts) {
      s.contacts[c.id] = c;
    }
  });
  Future<void> update(ContactEntity contact) => insert(contact);
  Future<void> delete(String id) => _db._write((s) => s.contacts.remove(id));
  Stream<List<ContactEntity>> search(String query) => _db._watch(
    (s) => _sorted(s)
        .where(
          (c) => c.displayName.contains(query) || c.phoneNumber.contains(query),
        )
        .toList(),
  );
  static List<ContactEntity> _sorted(_StorageSnapshot s) =>
      s.contacts.values.sortedBy((c) => c.displayName);
}

class CallLogDao {
  CallLogDao._(this._db);
  final SecureChatDatabase _db;
  Stream<List<CallLogEntity>> getAll() =>
      _db._watch((s) => s.callLogs.values.sortedBy((c) => -c.timestamp));
  Stream<List<CallLogEntity>> getByPeerId(String peerId) => _db._watch(
    (s) => s.callLogs.values
        .where((c) => c.peerId == peerId)
        .sortedBy((c) => -c.timestamp),
  );
  Future<void> insert(CallLogEntity callLog) =>
      _db._write((s) => s.callLogs[callLog.id] = callLog);
  Future<void> deleteById(String id) =>
      _db._write((s) => s.callLogs.remove(id));
  Future<void> deleteAll() => _db._write((s) => s.callLogs.clear());
}

class ScheduledMessageDao {
  ScheduledMessageDao._(this._db);
  final SecureChatDatabase _db;
  Stream<List<ScheduledMessageEntity>> getAll() => _db._watch(
    (s) => s.scheduledMessages.values.sortedBy((m) => m.nextTriggerTime),
  );
  Future<List<ScheduledMessageEntity>> getAllImmediate() async =>
      _db._snapshot.scheduledMessages.values.sortedBy((m) => m.nextTriggerTime);
  Future<ScheduledMessageEntity?> getById(String id) async =>
      _db._snapshot.scheduledMessages[id];
  Future<List<ScheduledMessageEntity>> getDueMessages(int now) async => _db
      ._snapshot
      .scheduledMessages
      .values
      .where((m) => m.isEnabled && m.nextTriggerTime <= now)
      .sortedBy((m) => m.nextTriggerTime);
  Future<void> insert(ScheduledMessageEntity entity) =>
      _db._write((s) => s.scheduledMessages[entity.id] = entity);
  Future<void> update(ScheduledMessageEntity entity) => insert(entity);
  Future<void> deleteById(String id) =>
      _db._write((s) => s.scheduledMessages.remove(id));
  Future<void> deleteAll() => _db._write((s) => s.scheduledMessages.clear());
}

class ExportLogDao {
  ExportLogDao._(this._db);
  final SecureChatDatabase _db;
  Future<void> insert(ExportLogEntity entry) =>
      _db._write((s) => s.exportLogs.putIfAbsent(entry.id, () => entry));
  Stream<List<ExportLogEntity>> observeForGroup(String groupId) => _db._watch(
    (s) => s.exportLogs.values
        .where((e) => e.groupId == groupId)
        .sortedBy((e) => -e.timestamp),
  );
  Future<int> countForGroup(String groupId) async =>
      _db._snapshot.exportLogs.values.where((e) => e.groupId == groupId).length;
  Future<void> deleteForGroup(String groupId) => _db._write(
    (s) => s.exportLogs.removeWhere((_, e) => e.groupId == groupId),
  );
}

class PendingTimerUpdateDao {
  PendingTimerUpdateDao._(this._db);
  final SecureChatDatabase _db;
  Future<void> insert(PendingTimerUpdateEntity entity) =>
      _db._write((s) => s.pendingTimerUpdates[entity.id] = entity);
  Future<List<PendingTimerUpdateEntity>> getAll() async =>
      _db._snapshot.pendingTimerUpdates.values.sortedBy((e) => e.createdAt);
  Future<void> deleteById(String id) =>
      _db._write((s) => s.pendingTimerUpdates.remove(id));
  Future<void> clear() => _db._write((s) => s.pendingTimerUpdates.clear());
}

class IdentityDao {
  IdentityDao._(this._db);
  final SecureChatDatabase _db;
  Future<IdentityEntity?> get(String name) async =>
      _db._snapshot.identities[name];
  Future<void> insert(IdentityEntity identity) =>
      _db._write((s) => s.identities[identity.addressName] = identity);
  Future<void> delete(String name) =>
      _db._write((s) => s.identities.remove(name));
  Future<bool> exists(String name) async =>
      _db._snapshot.identities.containsKey(name);
}

class PreKeyDao {
  PreKeyDao._(this._db);
  final SecureChatDatabase _db;
  Future<PreKeyEntity?> get(int id) async => _db._snapshot.preKeys[id];
  Future<void> insert(PreKeyEntity preKey) =>
      _db._write((s) => s.preKeys[preKey.id] = preKey);
  Future<void> delete(int id) => _db._write((s) => s.preKeys.remove(id));
  Future<int> count() async => _db._snapshot.preKeys.length;
  Future<int?> maxId() async =>
      _db._snapshot.preKeys.keys.sortedBy((id) => id).lastOrNull;
  Future<bool> exists(int id) async => _db._snapshot.preKeys.containsKey(id);
}

class SignedPreKeyDao {
  SignedPreKeyDao._(this._db);
  final SecureChatDatabase _db;
  Future<SignedPreKeyEntity?> get(int id) async =>
      _db._snapshot.signedPreKeys[id];
  Future<List<SignedPreKeyEntity>> getAll() async =>
      _db._snapshot.signedPreKeys.values.toList();
  Future<void> insert(SignedPreKeyEntity signedPreKey) =>
      _db._write((s) => s.signedPreKeys[signedPreKey.id] = signedPreKey);
  Future<void> delete(int id) => _db._write((s) => s.signedPreKeys.remove(id));
  Future<bool> exists(int id) async =>
      _db._snapshot.signedPreKeys.containsKey(id);
}

class SessionDao {
  SessionDao._(this._db);
  final SecureChatDatabase _db;
  Future<SessionEntity?> get(String id) async => _db._snapshot.sessions[id];
  Future<void> insert(SessionEntity session) =>
      _db._write((s) => s.sessions[session.id] = session);
  Future<void> delete(String id) => _db._write((s) => s.sessions.remove(id));
  Future<bool> exists(String id) async =>
      _db._snapshot.sessions.containsKey(id);
  Future<void> deleteAllForName(String name) => _db._write(
    (s) => s.sessions.removeWhere((id, _) => id.startsWith('$name:')),
  );
  Future<List<String>> getSessionIdsForName(String name) async => _db
      ._snapshot
      .sessions
      .keys
      .where((id) => id.startsWith('$name:'))
      .toList();
}

class SenderKeyDao {
  SenderKeyDao._(this._db);
  final SecureChatDatabase _db;
  Future<SenderKeyEntity?> get(
    String groupId,
    String senderId,
    int deviceId,
  ) async => _db._snapshot.senderKeys['$groupId:$senderId:$deviceId'];
  Future<void> put(SenderKeyEntity entity) =>
      _db._write((s) => s.senderKeys[entity.key] = entity);
  Future<void> delete(String groupId, String senderId, int deviceId) =>
      _db._write((s) => s.senderKeys.remove('$groupId:$senderId:$deviceId'));
  Future<void> deleteAllForGroup(String groupId) => _db._write(
    (s) => s.senderKeys.removeWhere((_, e) => e.groupId == groupId),
  );
  Future<bool> exists(String groupId, String senderId, int deviceId) async =>
      _db._snapshot.senderKeys.containsKey('$groupId:$senderId:$deviceId');
}

/// Small encrypted key/value area for local protocol state that is not a
/// remote identity/session row (registration id and the local identity pair).
class CryptoStateDao {
  CryptoStateDao._(this._db);
  final SecureChatDatabase _db;

  Future<String?> get(String key) async => _db._snapshot.cryptoState[key];

  Future<void> put(String key, String value) =>
      _db._write((snapshot) => snapshot.cryptoState[key] = value);

  Future<void> delete(String key) =>
      _db._write((snapshot) => snapshot.cryptoState.remove(key));

  Future<Map<String, String>> getByPrefix(String prefix) async => {
    for (final entry in _db._snapshot.cryptoState.entries)
      if (entry.key.startsWith(prefix)) entry.key: entry.value,
  };
}

class PendingSignalDao {
  PendingSignalDao._(this._db);
  final SecureChatDatabase _db;

  Future<List<PendingSignalEntity>> getAll() async {
    final result = _db._snapshot.pendingSignals.values.toList();
    result.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return result;
  }

  Future<void> put(PendingSignalEntity signal) =>
      _db._write((snapshot) => snapshot.pendingSignals[signal.id] = signal);

  Future<void> delete(String id) =>
      _db._write((snapshot) => snapshot.pendingSignals.remove(id));

  Future<void> clear() =>
      _db._write((snapshot) => snapshot.pendingSignals.clear());

  Future<int> count() async => _db._snapshot.pendingSignals.length;
}

class _StorageSnapshot {
  _StorageSnapshot({
    required this.conversations,
    required this.messages,
    required this.contacts,
    required this.callLogs,
    required this.scheduledMessages,
    required this.exportLogs,
    required this.pendingTimerUpdates,
    required this.identities,
    required this.preKeys,
    required this.signedPreKeys,
    required this.sessions,
    required this.senderKeys,
    required this.cryptoState,
    required this.pendingSignals,
  });

  final Map<String, ConversationEntity> conversations;
  final Map<String, MessageEntity> messages;
  final Map<String, ContactEntity> contacts;
  final Map<String, CallLogEntity> callLogs;
  final Map<String, ScheduledMessageEntity> scheduledMessages;
  final Map<String, ExportLogEntity> exportLogs;
  final Map<String, PendingTimerUpdateEntity> pendingTimerUpdates;
  final Map<String, IdentityEntity> identities;
  final Map<int, PreKeyEntity> preKeys;
  final Map<int, SignedPreKeyEntity> signedPreKeys;
  final Map<String, SessionEntity> sessions;
  final Map<String, SenderKeyEntity> senderKeys;
  final Map<String, String> cryptoState;
  final Map<String, PendingSignalEntity> pendingSignals;

  bool get isPristineForLegacyImport =>
      conversations.isEmpty &&
      messages.isEmpty &&
      contacts.isEmpty &&
      callLogs.isEmpty &&
      scheduledMessages.isEmpty &&
      exportLogs.isEmpty &&
      pendingTimerUpdates.isEmpty &&
      identities.isEmpty &&
      preKeys.isEmpty &&
      signedPreKeys.isEmpty &&
      sessions.isEmpty &&
      senderKeys.isEmpty &&
      pendingSignals.isEmpty;

  factory _StorageSnapshot.empty() => _StorageSnapshot(
    conversations: {},
    messages: {},
    contacts: {},
    callLogs: {},
    scheduledMessages: {},
    exportLogs: {},
    pendingTimerUpdates: {},
    identities: {},
    preKeys: {},
    signedPreKeys: {},
    sessions: {},
    senderKeys: {},
    cryptoState: {},
    pendingSignals: {},
  );

  factory _StorageSnapshot.fromJson(Map<String, Object?> json) {
    return _StorageSnapshot(
      conversations: _mapByString(
        json['conversations'],
        ConversationEntity.fromJson,
        (e) => e.id,
      ),
      messages: _mapByString(
        json['messages'],
        MessageEntity.fromJson,
        (e) => e.id,
      ),
      contacts: _mapByString(
        json['contacts'],
        ContactEntity.fromJson,
        (e) => e.id,
      ),
      callLogs: _mapByString(
        json['callLogs'],
        CallLogEntity.fromJson,
        (e) => e.id,
      ),
      scheduledMessages: _mapByString(
        json['scheduledMessages'],
        ScheduledMessageEntity.fromJson,
        (e) => e.id,
      ),
      exportLogs: _mapByString(
        json['exportLogs'],
        ExportLogEntity.fromJson,
        (e) => e.id,
      ),
      pendingTimerUpdates: _mapByString(
        json['pendingTimerUpdates'],
        PendingTimerUpdateEntity.fromJson,
        (e) => e.id,
      ),
      identities: _mapByString(
        json['identities'],
        IdentityEntity.fromJson,
        (e) => e.addressName,
      ),
      preKeys: _mapByInt(json['preKeys'], PreKeyEntity.fromJson, (e) => e.id),
      signedPreKeys: _mapByInt(
        json['signedPreKeys'],
        SignedPreKeyEntity.fromJson,
        (e) => e.id,
      ),
      sessions: _mapByString(
        json['sessions'],
        SessionEntity.fromJson,
        (e) => e.id,
      ),
      senderKeys: _mapByString(
        json['senderKeys'],
        SenderKeyEntity.fromJson,
        (e) => e.key,
      ),
      cryptoState:
          (json['cryptoState'] as Map?)?.map(
            (key, value) => MapEntry(key.toString(), value.toString()),
          ) ??
          const {},
      pendingSignals: _mapByString(
        json['pendingSignals'],
        PendingSignalEntity.fromJson,
        (entity) => entity.id,
      ),
    );
  }

  Map<String, Object?> toJson() => {
    'schema': 1,
    'conversations': conversations.values.map((e) => e.toJson()).toList(),
    'messages': messages.values.map((e) => e.toJson()).toList(),
    'contacts': contacts.values.map((e) => e.toJson()).toList(),
    'callLogs': callLogs.values.map((e) => e.toJson()).toList(),
    'scheduledMessages': scheduledMessages.values
        .map((e) => e.toJson())
        .toList(),
    'exportLogs': exportLogs.values.map((e) => e.toJson()).toList(),
    'pendingTimerUpdates': pendingTimerUpdates.values
        .map((e) => e.toJson())
        .toList(),
    'identities': identities.values.map((e) => e.toJson()).toList(),
    'preKeys': preKeys.values.map((e) => e.toJson()).toList(),
    'signedPreKeys': signedPreKeys.values.map((e) => e.toJson()).toList(),
    'sessions': sessions.values.map((e) => e.toJson()).toList(),
    'senderKeys': senderKeys.values.map((e) => e.toJson()).toList(),
    'cryptoState': cryptoState,
    'pendingSignals': pendingSignals.values.map((e) => e.toJson()).toList(),
  };
}

Map<String, T> _mapByString<T>(
  Object? value,
  T Function(Map<String, Object?> json) decode,
  String Function(T entity) keyOf,
) {
  if (value is! List) return {};
  return {
    for (final item in value.whereType<Map>())
      keyOf(decode(item.cast<String, Object?>())): decode(
        item.cast<String, Object?>(),
      ),
  };
}

Map<int, T> _mapByInt<T>(
  Object? value,
  T Function(Map<String, Object?> json) decode,
  int Function(T entity) keyOf,
) {
  if (value is! List) return {};
  return {
    for (final item in value.whereType<Map>())
      keyOf(decode(item.cast<String, Object?>())): decode(
        item.cast<String, Object?>(),
      ),
  };
}

extension _IterableSort<T> on Iterable<T> {
  List<T> sortedBy(Comparable<dynamic> Function(T item) keyOf) {
    final list = toList();
    list.sort((a, b) => keyOf(a).compareTo(keyOf(b)));
    return list;
  }
}

extension _IterableFirst<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
  T? get lastOrNull => isEmpty ? null : last;
}
