import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

import '../chat/message_reactions.dart';
import '../chat/message_search.dart';
import '../chat/conversation_preview.dart';
import '../services/crypto_service.dart';
import 'encrypted_record_store.dart';
import 'storage_entities.dart';

class SecureChatDatabase {
  SecureChatDatabase._({
    required _StorageSnapshot snapshot,
    required EncryptedRecordStore store,
  }) : _store = store,
       _cachedSnapshot = snapshot {
    _changed = StreamController<void>.broadcast(
      onListen: _startWatching,
      onCancel: _stopWatching,
    );
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

  final EncryptedRecordStore _store;

  /// Hata enjeksiyon testleri icin depoya erisim.
  @visibleForTesting
  EncryptedRecordStore get store => _store;
  _StorageSnapshot _cachedSnapshot;
  int? _snapshotVersion;
  bool _inWrite = false;
  Timer? _refreshTimer;
  late final StreamController<void> _changed;
  Future<void> _writeTail = Future<void>.value();
  Future<void>? _closeTask;
  bool _closed = false;

  _StorageSnapshot get _snapshot {
    if (!_inWrite && !_closed) _refreshSnapshot();
    return _cachedSnapshot;
  }

  set _snapshot(_StorageSnapshot value) => _cachedSnapshot = value;

  /// Checks for external commits after earlier queued writes, then atomically
  /// reloads and notifies watchers only if changed. Call before reconnect or
  /// foreground maintenance. Errors propagate; no partial snapshot is exposed.
  Future<void> refreshFromDisk() => _enqueue(_refreshSnapshot);

  void _refreshSnapshot() {
    if (_snapshotVersion == _store.dataVersion) return;
    final loaded = _store.readTransaction(() {
      final version = _store.dataVersion;
      return (snapshot: _load(_store), version: version);
    });
    _cachedSnapshot = loaded.snapshot;
    _snapshotVersion = loaded.version;
    _changed.add(null);
  }

  void _startWatching() {
    if (_closed) return;
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      // No full reload or notification when data_version is unchanged.
      // This synchronous read cannot interleave a synchronous write transaction.
      // Keep idle polling out of the write queue and its shutdown barrier.
      try {
        _refreshSnapshot();
      } catch (error, stack) {
        if (!_closed) _changed.addError(error, stack);
      }
    });
  }

  void _stopWatching() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  /// Anlik goruntunun tamami degistiginde (hesap silme, eski Room ice
  /// aktarimi) depodaki eski satirlar da gitmelidir. Izleme yalnizca
  /// dokunulan kayitlari bildigi icin bu durum ayrica isaretlenir.
  bool _fullReset = false;

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

  /// Artimli deponun dosya yolu. Eski JSON dosyasi YERINDE BIRAKILIR:
  /// gecis dogrulanana kadar geri donus yolu acik kalmali.
  static File storeFileFor(File legacyFile) =>
      File('${legacyFile.path}.sqlcipher');

  static Future<SecureChatDatabase> open({
    required File file,
    required LocalAeadCryptoService crypto,
  }) async {
    final store = await EncryptedRecordStore.open(
      file: storeFileFor(file),
      key: await crypto.deriveDatabaseKey(),
    );
    // Depo acildiktan sonraki her hata yolunda native tanitici KAPATILMALI.
    // Bozuk bir depoda okuma hata verdiginde tanitici acik kaliyordu.
    final db = SecureChatDatabase._(
      snapshot: _StorageSnapshot.empty(),
      store: store,
    );
    try {
      final legacy = store.count() == 0
          ? await _readLegacy(file, crypto)
          : null;
      if (legacy != null) {
        await db._write((_) {
          // A second runtime may have populated the store during decryption.
          if (store.count() != 0) return;
          db._snapshot = legacy;
          for (final collection in legacy.tracked) {
            collection.markAll();
          }
        });
      }
      await db._repairConversationPreviews();
      return db;
    } catch (_) {
      await db.close();
      rethrow;
    }
  }

  Future<void> _repairConversationPreviews() => _write((snapshot) {
    final latest = <String, MessageEntity>{};
    for (final message in snapshot.messages.values) {
      final previous = latest[message.conversationId];
      if (previous == null || message.timestamp > previous.timestamp)
        latest[message.conversationId] = message;
    }
    final repairs = <String, ConversationEntity>{};
    for (final entry in latest.entries) {
      final conversation = snapshot.conversations[entry.key];
      final message = entry.value;
      if (conversation == null ||
          conversation.lastMessageTimestamp != message.timestamp)
        continue;
      final preview = message.isViewOnce
          ? viewOncePreviewLabel
          : conversation.lastMessage;
      final status = message.isOutgoing
          ? message.status.name
          : conversation.lastMessageStatus;
      if (preview != conversation.lastMessage ||
          status != conversation.lastMessageStatus) {
        repairs[entry.key] = conversation.copyWith(
          lastMessage: preview,
          lastMessageStatus: status,
        );
      }
    }
    snapshot.conversations.addAll(repairs);
  });

  /// Eski tek dosyali JSON deposunu okur; yoksa veya bossa `null` doner.
  static Future<_StorageSnapshot?> _readLegacy(
    File file,
    LocalAeadCryptoService crypto,
  ) async {
    if (!await file.exists()) return null;
    final envelope = await file.readAsString();
    if (envelope.trim().isEmpty) return null;
    final json =
        jsonDecode(await crypto.decryptStorageJson(envelope))
            as Map<String, Object?>;
    return _StorageSnapshot.fromJson(json);
  }

  static _StorageSnapshot _load(EncryptedRecordStore store) {
    Map<String, T> byString<T>(
      String name,
      T Function(Map<String, Object?> json) decode,
    ) => {
      for (final entry in store.loadCollection(name).entries)
        entry.key: decode(entry.value),
    };
    Map<int, T> byInt<T>(
      String name,
      T Function(Map<String, Object?> json) decode,
    ) => {
      for (final entry in store.loadCollection(name).entries)
        int.parse(entry.key): decode(entry.value),
    };
    return _StorageSnapshot(
      conversations: byString('conversations', ConversationEntity.fromJson),
      messages: byString('messages', MessageEntity.fromJson),
      contacts: byString('contacts', ContactEntity.fromJson),
      callLogs: byString('callLogs', CallLogEntity.fromJson),
      scheduledMessages: byString(
        'scheduledMessages',
        ScheduledMessageEntity.fromJson,
      ),
      scheduledMessageHistory: byString(
        'scheduledMessageHistory',
        ScheduledMessageHistoryEntity.fromJson,
      ),
      exportLogs: byString('exportLogs', ExportLogEntity.fromJson),
      pendingTimerUpdates: byString(
        'pendingTimerUpdates',
        PendingTimerUpdateEntity.fromJson,
      ),
      identities: byString('identities', IdentityEntity.fromJson),
      preKeys: byInt('preKeys', PreKeyEntity.fromJson),
      signedPreKeys: byInt('signedPreKeys', SignedPreKeyEntity.fromJson),
      sessions: byString('sessions', SessionEntity.fromJson),
      senderKeys: byString('senderKeys', SenderKeyEntity.fromJson),
      cryptoState: {
        for (final entry in store.loadCollection('cryptoState').entries)
          entry.key: entry.value['value'] as String,
      },
      pendingSignals: byString('pendingSignals', PendingSignalEntity.fromJson),
    );
  }

  Future<void> close() {
    final active = _closeTask;
    if (active != null) return active;
    _closed = true;
    _stopWatching();
    final operation = _close();
    _closeTask = operation;
    return operation;
  }

  Future<void> _close() async {
    await _writeTail;
    await _changed.close();
    _store.close();
  }

  /// Returns a portable, unencrypted snapshot for the password-protected
  /// backup layer. Callers must never persist this string without encrypting
  /// it first.
  Future<String> exportPortableJson() async {
    await refreshFromDisk();
    return jsonEncode(_snapshot.toJson());
  }

  /// Atomically replaces all persisted application state after a backup has
  /// been authenticated, decompressed and fully parsed.
  Future<void> replaceFromPortableJson(
    String rawJson, {
    bool preserveLocalSecurityState = false,
    void Function()? validateBeforeCommit,
  }) async {
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
    await _write((current) {
      validateBeforeCommit?.call();
      if (preserveLocalSecurityState) {
        // Copy inside the write queue so pending protocol writes are retained.
        replacement.identities
          ..clear()
          ..addAll(current.identities);
        replacement.preKeys
          ..clear()
          ..addAll(current.preKeys);
        replacement.signedPreKeys
          ..clear()
          ..addAll(current.signedPreKeys);
        replacement.sessions
          ..clear()
          ..addAll(current.sessions);
        replacement.senderKeys
          ..clear()
          ..addAll(current.senderKeys);
        replacement.pendingSignals
          ..clear()
          ..addAll(current.pendingSignals);
        replacement.cryptoState
          ..clear()
          ..addAll(current.cryptoState);
      }
      _snapshot = replacement;
      _fullReset = true;
      for (final collection in replacement.tracked) {
        collection.markAll();
      }
    });
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
      _fullReset = true;
      for (final collection in replacement.tracked) {
        collection.markAll();
      }
    });
  }

  /// Clears every logical table in one serialized, atomically persisted
  /// snapshot replacement. The database file remains valid and encrypted.
  Future<void> clearAll() => _write((_) {
    _snapshot = _StorageSnapshot.empty();
    _fullReset = true;
  });

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
          key == 'account_recovery_pending_v1' ||
          key.startsWith('pending_sender_key_rotation:'),
    );
  });

  /// Installs previously staged local keys only after account recovery is
  /// confirmed. Peer identity pins survive; sessions tied to old local keys do
  /// not. The pending record survives until credential persistence succeeds.
  Future<void> installRecoveryIdentity({
    required String expectedPendingRecord,
    required List<int> identityKeyPair,
    required int registrationId,
    required List<PreKeyEntity> preKeys,
    required List<SignedPreKeyEntity> signedPreKeys,
  }) => _write((snapshot) {
    if (snapshot.cryptoState['account_recovery_pending_v1'] !=
        expectedPendingRecord) {
      throw StateError('Recovery operation changed');
    }
    final encodedIdentity = base64Encode(identityKeyPair);
    if (snapshot.cryptoState['local_identity_key_pair_v1'] == encodedIdentity) {
      return;
    }
    snapshot.preKeys
      ..clear()
      ..addEntries(preKeys.map((key) => MapEntry(key.id, key)));
    snapshot.signedPreKeys
      ..clear()
      ..addEntries(signedPreKeys.map((key) => MapEntry(key.id, key)));
    snapshot.sessions.clear();
    snapshot.senderKeys.clear();
    snapshot.cryptoState.removeWhere(
      (key, _) => key.startsWith('pending_sender_key_rotation:'),
    );
    snapshot.cryptoState['local_identity_key_pair_v1'] = encodedIdentity;
    snapshot.cryptoState['local_registration_id'] = registrationId.toString();
  });

  Future<void> _enqueue(void Function() action) {
    if (_closed) throw StateError('Secure chat database is closed');
    final operation = _writeTail.then<void>((_) => action());
    _writeTail = operation.then<void>((_) {}, onError: (_, _) {});
    return operation;
  }

  Future<void> _write(void Function(_StorageSnapshot s) mutate) => _enqueue(() {
    _StorageSnapshot? previous;
    final previousFullReset = _fullReset;
    try {
      _store.writeTransaction(() {
        // Take the cross-runtime writer lock BEFORE reading mutation state.
        _refreshSnapshot();
        previous = _cachedSnapshot;
        _inWrite = true;
        mutate(_cachedSnapshot);
        _persist();
      });
      // Do not discard rollback journals until the OUTER commit succeeds.
      _fullReset = false;
      for (final collection in _cachedSnapshot.tracked) {
        collection.commit();
      }
      _changed.add(null);
    } catch (_) {
      // A failed whole-snapshot replacement must restore the old reference,
      // not roll back the newly loaded maps into an empty in-memory state.
      if (previous != null) _cachedSnapshot = previous!;
      _fullReset = previousFullReset;
      // Geri alma yalnizca DOKUNULAN kayitlari eski degerine dondurur.
      // Onceden burada anlik goruntunun tam derin kopyasi cikariliyordu;
      // yazma yolundaki iki O(n) maliyetten biri buydu.
      for (final collection in _cachedSnapshot.tracked) {
        collection.rollback();
      }
      rethrow;
    } finally {
      _inWrite = false;
    }
  });

  Future<bool> approvePeerIdentity({
    required String peerId,
    required List<int>? expectedIdentity,
    required List<int> approvedIdentity,
    required List<int> expectedLocalIdentityRecord,
  }) async {
    var approved = false;
    await _write((snapshot) {
      final previous = snapshot.identities[peerId]?.identityKey;
      final expected = expectedIdentity == null
          ? null
          : base64Encode(expectedIdentity);
      if ((previous == null ? null : base64Encode(previous)) != expected ||
          snapshot.cryptoState['local_identity_key_pair_v1'] !=
              base64Encode(expectedLocalIdentityRecord)) {
        return;
      }
      if (expected != base64Encode(approvedIdentity)) {
        snapshot.sessions.removeWhere((id, _) => id.startsWith('$peerId:'));
      }
      snapshot.identities[peerId] = IdentityEntity(
        addressName: peerId,
        identityKey: List.of(approvedIdentity),
        trustLevel: TrustLevel.trustedVerified,
      );
      approved = true;
    });
    return approved;
  }

  Stream<T> _watch<T>(T Function(_StorageSnapshot s) project) =>
      Stream<T>.multi((controller) {
        // Subscribe before projecting so an update cannot fall in a yield gap.
        final subscription = _changed.stream
            .map((_) => project(_snapshot))
            .listen(
              controller.addSync,
              onError: controller.addErrorSync,
              onDone: controller.closeSync,
            );
        controller.onCancel = subscription.cancel;
        controller.onPause = subscription.pause;
        controller.onResume = subscription.resume;
        try {
          controller.addSync(project(_snapshot));
        } catch (error, stack) {
          controller.addErrorSync(error, stack);
        }
      });

  /// Yalnizca degisen kayitlari yazar.
  ///
  /// Onceki surum her cagrida tum veriyi JSON'a cevirip sifreleyip diske
  /// yaziyordu. Olculen maliyet: 50 mesajda 7 ms, 2 000 mesajda 120 ms —
  /// gecmisle dogru orantili. Artik maliyet yalnizca degisen kayit sayisina
  /// baglidir. Atomiklik SQLite isleminden gelir.
  void _persist() {
    final upserts = <String, Map<String, Map<String, Object?>>>{};
    final deletions = <String, Set<String>>{};
    for (final collection in _snapshot.tracked) {
      collection.collect(upserts, deletions);
    }
    _store.applyChanges(
      upserts: upserts,
      deletions: deletions,
      clearFirst: _fullReset,
    );
  }
}

class ConversationDao {
  ConversationDao._(this._db);
  final SecureChatDatabase _db;

  Stream<List<ConversationEntity>> getAll() => _db._watch(_sorted);
  Future<List<ConversationEntity>> getAllImmediate() async =>
      _sorted(_db._snapshot);
  Future<Map<String, int>> unreadCounts() async => {
    for (final conversation in _db._snapshot.conversations.values)
      if (conversation.unreadCount > 0)
        conversation.id: conversation.unreadCount,
  };
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
  Future<void> insertWithPendingSignals(
    ConversationEntity conversation,
    List<PendingSignalEntity> signals,
  ) => _db._write((s) {
    if (s.conversations.containsKey(conversation.id)) {
      throw StateError('Conversation already exists');
    }
    s.conversations[conversation.id] = conversation;
    for (final signal in signals) {
      s.pendingSignals[signal.id] = signal;
    }
  });
  Future<void> update(ConversationEntity conversation) => insert(conversation);
  Future<void> markAsRead(String conversationId) => _patch(
    conversationId,
    (c) => c.copyWith(unreadCount: 0, manuallyUnread: false),
  );
  Future<void> delete(String conversationId) => _db._write((s) {
    s.conversations.remove(conversationId);
    s.messages.removeWhere((_, m) => m.conversationId == conversationId);
  });
  Future<void> deleteLocalHistory(
    String conversationId, {
    String? localUserId,
  }) => _db._write((s) {
    final conversation = s.conversations[conversationId];
    final hasLeft =
        localUserId != null &&
        localUserId.isNotEmpty &&
        conversation?.groupMembers != null &&
        !conversation!.groupMembers!.split(',').contains(localUserId);
    if (conversation?.isGroup == true && !hasLeft) {
      s.conversations[conversationId] = _withoutLastMessage(
        conversation!,
      ).copyWith(unreadCount: 0, manuallyUnread: false);
    } else {
      s.conversations.remove(conversationId);
    }
    s.messages.removeWhere(
      (_, message) => message.conversationId == conversationId,
    );
  });
  Future<void> completeLocalGroupLeave(String groupId, String userId) =>
      _db._write((s) {
        final group = s.conversations[groupId];
        if (group == null || !group.isGroup) return;
        String withoutSelf(String? ids) => (ids ?? '')
            .split(',')
            .where((id) => id.isNotEmpty && id != userId)
            .join(',');
        s.conversations[groupId] = group.copyWith(
          groupMembers: withoutSelf(group.groupMembers),
          groupAdmins: withoutSelf(group.groupAdmins),
          isArchived: true,
          unreadCount: 0,
          manuallyUnread: false,
        );
        s.senderKeys.removeWhere((_, key) => key.groupId == groupId);
      });
  Future<void> updateGroupMembers(String groupId, String groupMembers) =>
      _patch(groupId, (c) => c.copyWith(groupMembers: groupMembers));
  Future<void> updateLastMessage(
    String peerId,
    String message,
    int timestamp, {
    StorageMessageContentType? type,
    bool? outgoing,
    StorageMessageStatus? status,
  }) => _db._write((s) {
    for (final entry in s.conversations.entries) {
      if (entry.value.peerId == peerId) {
        s.conversations[entry.key] = entry.value.copyWith(
          lastMessage: message,
          lastMessageTimestamp: timestamp,
          lastMessageType: type?.name,
          lastMessageOutgoing: outgoing,
          lastMessageStatus: status?.name,
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
  Future<void> recordMissedCall(
    String conversationId,
    String message,
    int timestamp,
  ) => _patch(
    conversationId,
    (current) => _withoutLastMessage(current).copyWith(
      lastMessage: message,
      lastMessageTimestamp: timestamp,
      lastMessageType: StorageMessageContentType.system.name,
      lastMessageOutgoing: false,
      unreadCount: current.unreadCount + 1,
    ),
  );
  Future<void> updateContactNote(String id, String? note) =>
      _patch(id, (c) => c.copyWith(contactNote: note));
  Future<void> updateCustomNotification(String id, String? uri) =>
      _patch(id, (c) => c.copyWith(customNotificationUri: uri));
  Future<void> updatePeerName(String id, String name) =>
      _patch(id, (c) => c.copyWith(peerName: name));
  Future<void> updatePeerIdentity(String id, String name, String phone) =>
      _patch(id, (c) => c.copyWith(peerName: name, peerPhone: phone));
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
    int timestamp, {
    StorageMessageContentType? type,
    bool? outgoing,
    StorageMessageStatus? status,
  }) => _patch(
    conversationId,
    (c) => c.copyWith(
      lastMessage: message,
      lastMessageTimestamp: timestamp,
      lastMessageType: type?.name,
      lastMessageOutgoing: outgoing,
      lastMessageStatus: status?.name,
    ),
  );
  Future<void> clearLastMessage(String conversationId) => _db._write((s) {
    final current = s.conversations[conversationId];
    if (current == null) return;
    s.conversations[conversationId] = _withoutLastMessage(current);
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
      _db._write((s) {
        final message = s.messages[id];
        if (message == null) return;
        s.messages[id] = message.copyWith(status: status);
        // Sohbet listesindeki teslim tiki de bu mesaji gosteriyorsa birlikte
        // guncellenir. Tek yerde yapilir; aksi halde her durum degisikligini
        // cagiran tarafin ayrica kopyalamasi gerekirdi ve biri unutulurdu.
        final conversation = s.conversations[message.conversationId];
        if (conversation == null || !message.isOutgoing) return;
        // Son mesaj mi: damga karsilastirmasi yeterli ve O(1). Mesaj
        // tablosunu taramak her durum degisikliginde O(n) maliyet getirirdi.
        if (conversation.lastMessageTimestamp != message.timestamp) return;
        s.conversations[message.conversationId] = conversation.copyWith(
          lastMessageStatus: status.name,
        );
      });
  Future<void> updateStatusIfSending(String id, StorageMessageStatus status) =>
      _db._write((s) {
        final message = s.messages[id];
        if (message == null || message.status != StorageMessageStatus.sending) {
          return;
        }
        s.messages[id] = message.copyWith(status: status);
        final conversation = s.conversations[message.conversationId];
        if (conversation == null ||
            !message.isOutgoing ||
            conversation.lastMessageTimestamp != message.timestamp) {
          return;
        }
        s.conversations[message.conversationId] = conversation.copyWith(
          lastMessageStatus: status.name,
        );
      });
  Future<void> markFailedIfUndelivered(String id) => _db._write((s) {
    final message = s.messages[id];
    if (message == null ||
        (message.status != StorageMessageStatus.sending &&
            message.status != StorageMessageStatus.sent)) {
      return;
    }
    s.messages[id] = message.copyWith(status: StorageMessageStatus.failed);
    final conversation = s.conversations[message.conversationId];
    if (conversation == null ||
        !message.isOutgoing ||
        conversation.lastMessageTimestamp != message.timestamp) {
      return;
    }
    s.conversations[message.conversationId] = conversation.copyWith(
      lastMessageStatus: StorageMessageStatus.failed.name,
    );
  });
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
  Future<MessageEntity?> activateMediaPreview(
    String id, {
    required String conversationId,
  }) async {
    MessageEntity? activated;
    await _db._write((s) {
      final message = s.messages[id];
      if (message == null ||
          message.conversationId != conversationId ||
          (message.contentType != StorageMessageContentType.image &&
              message.contentType != StorageMessageContentType.file &&
              message.contentType != StorageMessageContentType.voiceNote) ||
          (message.expiresAt != null &&
              message.expiresAt! <= DateTime.now().millisecondsSinceEpoch) ||
          (message.isViewOnce && (message.isOutgoing || message.isViewed))) {
        return;
      }
      // Patch the current row, never a stale UI snapshot or a removed row.
      activated = message.copyWith(isMediaPreviewDeferred: false);
      s.messages[id] = activated!;
    });
    return activated;
  }

  Future<bool> markViewOnceAsViewed(String id) async {
    var claimed = false;
    await _db._write((s) {
      final message = s.messages[id];
      if (message == null ||
          !message.isViewOnce ||
          message.isOutgoing ||
          message.isViewed)
        return;
      s.messages[id] = message.copyWith(isViewed: true);
      claimed = true;
    });
    return claimed;
  }

  Future<void> eraseViewedOnceContent(String id) => _patch(
    id,
    (m) => m.isViewOnce && m.isViewed && !m.isOutgoing
        ? m.copyWith(
            content: '',
            caption: null,
            editHistory: '',
            isStarred: false,
          )
        : m,
  );
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
            .where(
              (m) =>
                  m.conversationId == conversationId &&
                  m.isStarred &&
                  _canBrowse(m),
            )
            .sortedBy((m) => -m.timestamp),
      );
  Stream<List<MessageEntity>> getAllStarredMessages() => _db._watch(
    (s) => s.messages.values
        .where((m) => m.isStarred && _canBrowse(m))
        .sortedBy((m) => -m.timestamp),
  );
  Stream<List<MessageEntity>> searchMessages(String conversationId, String q) =>
      _db._watch(
        (s) => s.messages.values
            .where((m) => m.conversationId == conversationId)
            .where((m) => _matchesSearch(m, q))
            .sortedBy((m) => -m.timestamp),
      );
  Future<List<MessageEntity>> searchAllMessages(
    String q, {
    int limit = 100,
  }) async {
    final clean = q.trim().toLowerCase();
    if (clean.length < 2 || limit <= 0) return const [];
    return _db._snapshot.messages.values
        .where((m) => _matchesSearch(m, clean))
        .sortedBy((m) => -m.timestamp)
        .take(limit)
        .toList();
  }

  Stream<List<MessageEntity>> getMediaMessages(String conversationId) =>
      _db._watch(
        (s) => s.messages.values
            .where((m) => m.conversationId == conversationId)
            .where((m) => _canBrowse(m) && _isMedia(m))
            .sortedBy((m) => -m.timestamp),
      );
  Stream<List<MessageEntity>> getDocumentMessages(String conversationId) =>
      _db._watch(
        (s) => s.messages.values
            .where((m) => m.conversationId == conversationId)
            .where(
              (m) =>
                  m.contentType == StorageMessageContentType.file &&
                  _canBrowse(m) &&
                  !_isMedia(m),
            )
            .sortedBy((m) => -m.timestamp),
      );
  Future<int> deleteExpiredMessages(int now) async {
    var deleted = 0;
    await _db._write((s) {
      final expired = s.messages.values
          .where((m) => m.expiresAt != null && m.expiresAt! <= now)
          .toList(growable: false);
      if (expired.isEmpty) return;
      final affectedConversations = expired
          .map((message) => message.conversationId)
          .toSet();
      for (final message in expired) {
        if (s.messages.remove(message.id) != null) deleted++;
      }
      for (final conversationId in affectedConversations) {
        final conversation = s.conversations[conversationId];
        if (conversation == null) continue;
        final remaining = s.messages.values
            .where((message) => message.conversationId == conversationId)
            .sortedBy((message) => -message.timestamp)
            .firstOrNull;
        s.conversations[conversationId] = remaining == null
            ? _withoutLastMessage(conversation)
            : conversation.copyWith(
                lastMessage: conversationPreview(
                  content: remaining.content,
                  isViewOnce: remaining.isViewOnce,
                  contentType: remaining.contentType,
                ),
                lastMessageTimestamp: remaining.timestamp,
                lastMessageType: remaining.contentType.name,
                lastMessageOutgoing: remaining.isOutgoing,
                lastMessageStatus: remaining.status.name,
              );
      }
    });
    return deleted;
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
  Future<void> applyReaction(
    String id, {
    required String userId,
    required String emoji,
    required bool remove,
  }) => _patch(id, (m) {
    if (userId.isEmpty ||
        !isValidMessageReaction(emoji) ||
        m.contentType == StorageMessageContentType.deleted)
      return m;
    return m.copyWith(
      reactions: applyMessageReaction(
        m.reactions,
        userId,
        emoji,
        remove: remove,
      ),
    );
  });
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
  static bool _canBrowse(MessageEntity m) =>
      !m.isViewOnce &&
      m.contentType != StorageMessageContentType.deleted &&
      (m.expiresAt == null ||
          m.expiresAt! > DateTime.now().millisecondsSinceEpoch);
  static bool _matchesSearch(MessageEntity m, String query) {
    final clean = query.trim().toLowerCase();
    return clean.isNotEmpty &&
        _canBrowse(m) &&
        messageSearchText(
          content: m.content,
          contentType: m.contentType.name,
          isViewOnce: m.isViewOnce,
          caption: m.caption,
        ).toLowerCase().contains(clean);
  }

  static bool _isMedia(MessageEntity m) =>
      m.contentType == StorageMessageContentType.image ||
      (m.contentType == StorageMessageContentType.file &&
          (m.content.contains('|video/') ||
              m.content.contains('|audio/') ||
              m.content.contains('|image/')));
}

ConversationEntity _withoutLastMessage(ConversationEntity current) =>
    ConversationEntity(
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
        .where((c) => (c.groupId ?? c.peerId) == peerId)
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
  static const historyLimit = 500;

  Stream<List<ScheduledMessageHistoryEntity>> watchHistory() =>
      _db._watch(_sortedHistory);

  Future<List<ScheduledMessageHistoryEntity>> getHistoryImmediate() async =>
      _sortedHistory(_db._snapshot);

  Future<ConversationEntity?> getRecipient(String id) =>
      _db.conversations.getById(id);

  /// The history and plan transition share one encrypted storage transaction.
  Future<void> completeRun(
    ScheduledMessageHistoryEntity history, {
    ScheduledMessageEntity? nextPlan,
  }) {
    if (nextPlan != null && nextPlan.id != history.planId) {
      throw ArgumentError('History and next plan must refer to the same plan');
    }
    return _db._write((s) {
      s.scheduledMessageHistory[history.id] = history;
      for (final expired in _sortedHistory(s).skip(historyLimit)) {
        s.scheduledMessageHistory.remove(expired.id);
      }
      if (nextPlan == null) {
        s.scheduledMessages.remove(history.planId);
      } else {
        s.scheduledMessages[nextPlan.id] = nextPlan;
      }
    });
  }

  static List<ScheduledMessageHistoryEntity> _sortedHistory(
    _StorageSnapshot s,
  ) => s.scheduledMessageHistory.values.toList()
    ..sort((a, b) {
      final byTime = b.executedAt.compareTo(a.executedAt);
      return byTime == 0 ? b.id.compareTo(a.id) : byTime;
    });

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
  Future<void> deleteDelivered(String messageId, String recipientId) =>
      _db._write(
        (snapshot) => snapshot.pendingSignals.removeWhere(
          (_, signal) =>
              signal.retainUntilReceipt &&
              signal.messageId == messageId &&
              signal.recipientId == recipientId,
        ),
      );
  Future<void> deleteForMessage(String messageId) => _db._write(
    (snapshot) => snapshot.pendingSignals.removeWhere(
      (_, signal) => signal.messageId == messageId,
    ),
  );
  Future<void> incrementAttempts(String id) => _db._write((snapshot) {
    final current = snapshot.pendingSignals[id];
    if (current != null) {
      snapshot.pendingSignals[id] = current.copyWith(
        attempts: current.attempts + 1,
      );
    }
  });

  Future<int> count() async => _db._snapshot.pendingSignals.length;
}

class _StorageSnapshot {
  _StorageSnapshot({
    required Map<String, ConversationEntity> conversations,
    required Map<String, MessageEntity> messages,
    required Map<String, ContactEntity> contacts,
    required Map<String, CallLogEntity> callLogs,
    required Map<String, ScheduledMessageEntity> scheduledMessages,
    required Map<String, ScheduledMessageHistoryEntity> scheduledMessageHistory,
    required Map<String, ExportLogEntity> exportLogs,
    required Map<String, PendingTimerUpdateEntity> pendingTimerUpdates,
    required Map<String, IdentityEntity> identities,
    required Map<int, PreKeyEntity> preKeys,
    required Map<int, SignedPreKeyEntity> signedPreKeys,
    required Map<String, SessionEntity> sessions,
    required Map<String, SenderKeyEntity> senderKeys,
    required Map<String, PendingSignalEntity> pendingSignals,
    required Map<String, String> cryptoState,
  }) : conversations = _TrackedMap(
         'conversations',
         conversations,
         (value) => value.toJson(),
         (key) => key,
       ),
       messages = _TrackedMap(
         'messages',
         messages,
         (value) => value.toJson(),
         (key) => key,
       ),
       contacts = _TrackedMap(
         'contacts',
         contacts,
         (value) => value.toJson(),
         (key) => key,
       ),
       callLogs = _TrackedMap(
         'callLogs',
         callLogs,
         (value) => value.toJson(),
         (key) => key,
       ),
       scheduledMessages = _TrackedMap(
         'scheduledMessages',
         scheduledMessages,
         (value) => value.toJson(),
         (key) => key,
       ),
       scheduledMessageHistory = _TrackedMap(
         'scheduledMessageHistory',
         scheduledMessageHistory,
         (value) => value.toJson(),
         (key) => key,
       ),
       exportLogs = _TrackedMap(
         'exportLogs',
         exportLogs,
         (value) => value.toJson(),
         (key) => key,
       ),
       pendingTimerUpdates = _TrackedMap(
         'pendingTimerUpdates',
         pendingTimerUpdates,
         (value) => value.toJson(),
         (key) => key,
       ),
       identities = _TrackedMap(
         'identities',
         identities,
         (value) => value.toJson(),
         (key) => key,
       ),
       preKeys = _TrackedMap(
         'preKeys',
         preKeys,
         (value) => value.toJson(),
         (key) => key.toString(),
       ),
       signedPreKeys = _TrackedMap(
         'signedPreKeys',
         signedPreKeys,
         (value) => value.toJson(),
         (key) => key.toString(),
       ),
       sessions = _TrackedMap(
         'sessions',
         sessions,
         (value) => value.toJson(),
         (key) => key,
       ),
       senderKeys = _TrackedMap(
         'senderKeys',
         senderKeys,
         (value) => value.toJson(),
         (key) => key,
       ),
       pendingSignals = _TrackedMap(
         'pendingSignals',
         pendingSignals,
         (value) => value.toJson(),
         (key) => key,
       ),
       cryptoState = _TrackedMap(
         'cryptoState',
         cryptoState,
         (value) => {'value': value},
         (key) => key,
       );

  final _TrackedMap<String, ConversationEntity> conversations;
  final _TrackedMap<String, MessageEntity> messages;
  final _TrackedMap<String, ContactEntity> contacts;
  final _TrackedMap<String, CallLogEntity> callLogs;
  final _TrackedMap<String, ScheduledMessageEntity> scheduledMessages;
  final _TrackedMap<String, ScheduledMessageHistoryEntity>
  scheduledMessageHistory;
  final _TrackedMap<String, ExportLogEntity> exportLogs;
  final _TrackedMap<String, PendingTimerUpdateEntity> pendingTimerUpdates;
  final _TrackedMap<String, IdentityEntity> identities;
  final _TrackedMap<int, PreKeyEntity> preKeys;
  final _TrackedMap<int, SignedPreKeyEntity> signedPreKeys;
  final _TrackedMap<String, SessionEntity> sessions;
  final _TrackedMap<String, SenderKeyEntity> senderKeys;
  final _TrackedMap<String, PendingSignalEntity> pendingSignals;
  final _TrackedMap<String, String> cryptoState;

  /// Degisiklik izleyen tum koleksiyonlar.
  List<_Tracked> get tracked => [
    conversations,
    messages,
    contacts,
    callLogs,
    scheduledMessages,
    scheduledMessageHistory,
    exportLogs,
    pendingTimerUpdates,
    identities,
    preKeys,
    signedPreKeys,
    sessions,
    senderKeys,
    pendingSignals,
    cryptoState,
  ];

  bool get isPristineForLegacyImport =>
      conversations.isEmpty &&
      messages.isEmpty &&
      contacts.isEmpty &&
      callLogs.isEmpty &&
      scheduledMessages.isEmpty &&
      scheduledMessageHistory.isEmpty &&
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
    scheduledMessageHistory: {},
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
      scheduledMessageHistory: _mapByString(
        json['scheduledMessageHistory'],
        ScheduledMessageHistoryEntity.fromJson,
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
    'scheduledMessageHistory': scheduledMessageHistory.values
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

/// Yazma sirasinda hangi kayitlarin degistigini bilen koleksiyon.
///
/// Onceki tasarimda bunu bilmeye gerek yoktu: her yazmada dosyanin tamami
/// yeniden yaziliyordu. Artimli depoya gecerken "neyi yazacagiz" sorusunu
/// cevaplamak gerekti. DAO'larin hicbirini degistirmemek icin izleme
/// `Map` arayuzunun arkasina konuldu; cagiran kod farki gormez.
abstract interface class _Tracked {
  String get collection;
  bool get hasChanges;
  void collect(
    Map<String, Map<String, Map<String, Object?>>> upserts,
    Map<String, Set<String>> deletions,
  );
  void rollback();
  void commit();
  void markAll();
}

class _TrackedMap<K, V> extends MapBase<K, V> implements _Tracked {
  _TrackedMap(this.collection, this._inner, this._encode, this._idOf);

  @override
  final String collection;
  final Map<K, V> _inner;
  final Map<String, Object?> Function(V value) _encode;
  final String Function(K key) _idOf;

  /// Degisen anahtarlarin ONCEKI degerleri. `null`, kaydin o sirada
  /// bulunmadigini gosterir. Geri alma icin tam derin kopya cikarmak
  /// gerekmiyor; eski tasarimda her yazmada bu da O(n) maliyet uretiyordu.
  final Map<K, V?> _previous = {};

  void _mark(K key) {
    if (_previous.containsKey(key)) return;
    _previous[key] = _inner[key];
  }

  @override
  V? operator [](Object? key) => _inner[key];

  @override
  void operator []=(K key, V value) {
    _mark(key);
    _inner[key] = value;
  }

  @override
  V? remove(Object? key) {
    if (key is K && _inner.containsKey(key)) _mark(key);
    return _inner.remove(key);
  }

  @override
  void clear() {
    for (final key in _inner.keys) {
      _mark(key);
    }
    _inner.clear();
  }

  @override
  Iterable<K> get keys => _inner.keys;

  @override
  bool get hasChanges => _previous.isNotEmpty;

  @override
  void collect(
    Map<String, Map<String, Map<String, Object?>>> upserts,
    Map<String, Set<String>> deletions,
  ) {
    for (final key in _previous.keys) {
      final current = _inner[key];
      if (current == null) {
        (deletions[collection] ??= <String>{}).add(_idOf(key));
      } else {
        (upserts[collection] ??= {})[_idOf(key)] = _encode(current);
      }
    }
  }

  @override
  void rollback() {
    for (final entry in _previous.entries) {
      final value = entry.value;
      if (value == null) {
        _inner.remove(entry.key);
      } else {
        _inner[entry.key] = value;
      }
    }
    _previous.clear();
  }

  @override
  void commit() => _previous.clear();

  @override
  void markAll() {
    for (final key in _inner.keys) {
      _mark(key);
    }
  }
}
