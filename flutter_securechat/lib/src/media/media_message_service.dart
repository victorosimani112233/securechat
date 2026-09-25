import 'dart:async';
import 'dart:io';
import 'dart:math';

import '../core/models.dart';
import '../groups/private_group_control.dart';
import '../chat/conversation_preview.dart';
import '../contacts/phone_number_sharing_service.dart';
import '../contacts/contact_service.dart';
import '../incoming/incoming_message_handler.dart';
import '../l10n/service_strings.dart';
import '../services/session_store.dart';
import '../services/async_operation_tracker.dart';
import '../storage/secure_chat_database.dart';
import '../storage/storage_entities.dart';
import '../storage/storage_management_service.dart';
import 'file_transfer_manager.dart';
import 'media_attachment.dart';
import 'voice_note_service.dart';

class MediaSendOutcome {
  const MediaSendOutcome({required this.attachment, required this.result});
  final MediaAttachment attachment;
  final FileTransferResult result;
}

class MediaMessageService {
  MediaMessageService({
    required SecureChatDatabase database,
    required FileTransferManager transfers,
    required SessionStore session,
    required Directory localMediaDirectory,
    StorageManagementService? storageManagement,
    NetworkKindProvider? networkKindProvider,
    AsyncOperationFailureHandler? onAsyncFailure,
    PhoneNumberSharingService? phoneSharing,
    PrivateGroupControlSender? groupControls,
    ContactIdentityResolver? identityResolver,
    ServiceStrings? strings,
  }) : _database = database,
       _transfers = transfers,
       _session = session,
       _localMediaDirectory = localMediaDirectory,
       _storageManagement = storageManagement,
       _networkKindProvider = networkKindProvider,
       _phoneSharing = phoneSharing,
       _groupControls = groupControls,
       _identityResolver =
           identityResolver ?? ContactIdentityResolver(database: database),
       _strings =
           strings ??
           ServiceStrings(languageCode: () async => session.languagePreference),
       _operations = AsyncOperationTracker(onFailure: onAsyncFailure);

  final SecureChatDatabase _database;
  final FileTransferManager _transfers;
  final SessionStore _session;
  final Directory _localMediaDirectory;
  final StorageManagementService? _storageManagement;
  final NetworkKindProvider? _networkKindProvider;
  final PhoneNumberSharingService? _phoneSharing;
  final PrivateGroupControlSender? _groupControls;
  final ContactIdentityResolver _identityResolver;
  final ServiceStrings _strings;
  final _acceptedMessages = StreamController<IncomingMessageEvent>.broadcast(
    sync: true,
  );
  Stream<IncomingMessageEvent> get acceptedMessages => _acceptedMessages.stream;
  final AsyncOperationTracker _operations;
  final Random _random = Random.secure();
  StreamSubscription<ReceivedFile>? _receivedSubscription;
  Future<void> _incomingTail = Future<void>.value();
  Future<void>? _closeTask;
  bool _closed = false;
  final _activeViewOnce = <String>{};
  final _purgingViewOnce = <String>{};

  void start() {
    if (_closed) throw StateError('Media message service is closed');
    if (_receivedSubscription == null) {
      _operations.run(
        'media.view-once.recover-cleanup',
        cleanupViewedOnceMedia(),
      );
    }
    _receivedSubscription ??= _transfers.receivedFiles.listen((received) {
      // Replays can use different transfer IDs; serialize the message-ID
      // deduplication and unread update, not just chunk assembly.
      final pending = _incomingTail.then((_) => _persistIncoming(received));
      _incomingTail = pending.then<void>((_) {}, onError: (_, _) {});
      _operations.run('media-message.persist-incoming', pending);
    });
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
    await _receivedSubscription?.cancel();
    _receivedSubscription = null;
    _activeViewOnce.clear();
    _operations.run(
      'media.view-once.shutdown-cleanup',
      cleanupViewedOnceMedia(),
    );
    await _operations.close();
    await _acceptedMessages.close();
  }

  /// Deterministic boundary for background/file callbacks already delivered
  /// to this service. Production shutdown uses [close]; tests and foreground
  /// reconciliation can await persistence without stopping the service.
  Future<void> waitForIdle() => _operations.waitForIdle();

  Future<List<MediaSendOutcome>> send({
    required String conversationId,
    required String recipientId,
    required List<MediaAttachment> attachments,
    required bool isGroup,
    required List<String> groupMembers,
    String? caption,
    bool isViewOnce = false,
    VoiceNoteMetadata? voiceNote,
  }) async {
    final localUserId = _session.userId;
    if (localUserId == null || localUserId.isEmpty) {
      throw StateError('Medya göndermek için oturum açılmalıdır.');
    }
    if (attachments.isEmpty) return const [];
    if (voiceNote != null && attachments.length != 1) {
      throw ArgumentError('Sesli mesaj tek bir ses kaydı içermelidir.');
    }
    final conversation = await _database.conversations.getById(conversationId);
    if (conversation != null && conversation.isGroup != isGroup) {
      throw StateError('Conversation type changed; reopen the conversation');
    }
    if (!isGroup) await _phoneSharing?.shareWith(recipientId);
    final outcomes = <MediaSendOutcome>[];
    for (var index = 0; index < attachments.length; index++) {
      var recipients = <String>[recipientId];
      var transferMembers = const <String>[];
      if (isGroup) {
        final group = await _database.conversations.getById(conversationId);
        final members = (group?.groupMembers ?? '')
            .split(',')
            .map((id) => id.trim())
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList();
        if (group?.isGroup != true ||
            !members.contains(localUserId) ||
            recipientId != conversationId) {
          throw StateError('Group membership is required to send media');
        }
        // A picker can stay open while a member leaves. Never use its stale
        // recipient list to distribute new media keys to departed members.
        recipients = List<String>.unmodifiable(
          members.where((id) => id != localUserId),
        );
        // Transfer membership validation includes self; receipt targets do not.
        transferMembers = List<String>.unmodifiable(members);
        await _groupControls?.send(
          senderId: localUserId,
          groupId: conversationId,
          groupName: group!.peerName,
          memberIds: members,
          recipients: members,
          action: 'CREATE',
        );
      }
      final attachment = attachments[index];
      final messageId = _newId('media');
      final retained = await _retain(attachment, messageId);
      final itemCaption = index == 0 ? _cleanCaption(caption) : null;
      final wireCaption = voiceNote?.encode() ?? itemCaption;
      await _persistOutgoing(
        messageId: messageId,
        conversationId: conversationId,
        localUserId: localUserId,
        attachment: attachment,
        retained: retained,
        caption: itemCaption,
        isViewOnce: isViewOnce,
        voiceNote: voiceNote,
        status: StorageMessageStatus.sending,
        receiptRecipients: recipients,
      );
      late final FileTransferResult result;
      try {
        result = await _transfers.sendFile(
          localUserId: localUserId,
          recipientId: recipientId,
          file: retained,
          fileName: attachment.fileName,
          mimeType: attachment.mimeType,
          isGroup: isGroup,
          groupMembers: transferMembers,
          caption: wireCaption,
          isViewOnce: isViewOnce,
          originalMessageId: messageId,
        );
      } catch (_) {
        await _database.messages.updateStatusIfSending(
          messageId,
          StorageMessageStatus.failed,
        );
        rethrow;
      }
      // Persist before transfer so a fast delivery receipt cannot be lost.
      await _database.messages.updateStatusIfSending(
        messageId,
        result is FileTransferSuccess
            ? StorageMessageStatus.sent
            : StorageMessageStatus.failed,
      );
      outcomes.add(MediaSendOutcome(attachment: attachment, result: result));
    }
    return outcomes;
  }

  Future<MediaSendOutcome> sendVoiceNote({
    required String conversationId,
    required String recipientId,
    required VoiceNoteDraft draft,
    required bool isGroup,
    required List<String> groupMembers,
  }) async {
    try {
      final results = await send(
        conversationId: conversationId,
        recipientId: recipientId,
        attachments: [draft.attachment],
        isGroup: isGroup,
        groupMembers: groupMembers,
        voiceNote: draft.metadata,
      );
      return results.single;
    } finally {
      final draftFile = File(draft.attachment.path);
      if (await draftFile.exists()) await draftFile.delete();
    }
  }

  /// Called only after an explicit open in an authorized chat. This does not
  /// claim view-once media; the caller must still use [markViewOnceViewed].
  Future<LocalMessage?> activateMediaPreview(LocalMessage message) async {
    if (_closed) return null;
    final entity = await _database.messages.activateMediaPreview(
      message.id,
      conversationId: message.conversationId,
    );
    if (entity == null) return null;
    return LocalMessage.fromJson({
      ...entity.toJson(),
      'peerId': message.peerId,
    });
  }

  Future<bool> markViewOnceViewed(LocalMessage message) async {
    if (!message.isViewOnce ||
        message.isOutgoing ||
        message.isViewed ||
        !_activeViewOnce.add(message.id))
      return false;
    try {
      final claimed = await _database.messages.markViewOnceAsViewed(message.id);
      if (!claimed) _activeViewOnce.remove(message.id);
      return claimed;
    } catch (_) {
      _activeViewOnce.remove(message.id);
      rethrow;
    }
  }

  void finishViewOnce(String id) {
    _activeViewOnce.remove(id);
    if (_closed) return;
    _operations.run('media.view-once.cleanup', _purgeViewedOnce(id));
  }

  Future<void> cleanupViewedOnceMedia() async {
    Object? failure;
    StackTrace? failureStack;
    for (final message in await _database.messages.getAllMessages()) {
      if (message.isViewOnce &&
          message.isViewed &&
          !message.isOutgoing &&
          !_activeViewOnce.contains(message.id) &&
          (message.content.isNotEmpty || message.caption != null)) {
        try {
          await _purgeViewedOnce(message.id);
        } catch (error, stack) {
          failure ??= error;
          failureStack ??= stack;
        }
      }
    }
    if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
  }

  Future<void> _purgeViewedOnce(String id) async {
    if (!_purgingViewOnce.add(id)) return;
    try {
      final entity = await _database.messages.getById(id);
      if (entity == null ||
          !entity.isViewOnce ||
          !entity.isViewed ||
          entity.isOutgoing)
        return;
      final message = LocalMessage.fromJson(entity.toJson());
      final path = message.isFileMessage ? message.filePath : null;
      if (path != null && path.isNotEmpty) {
        final storage =
            _storageManagement ??
            StorageManagementService(
              _database,
              mediaDirectory: _localMediaDirectory,
            );
        final resolved = await storage.resolveMediaPath(path, strict: true);
        if (resolved != null) await File(resolved).delete();
      }
      // Keep the viewed tombstone to prevent replay, but not the content or
      // caption. Retain the path on deletion failure so startup can retry.
      await _database.messages.eraseViewedOnceContent(id);
    } finally {
      _purgingViewOnce.remove(id);
    }
  }

  Future<File> _retain(MediaAttachment attachment, String messageId) async {
    final sentDirectory = Directory('${_localMediaDirectory.path}/sent');
    await sentDirectory.create(recursive: true);
    final safeName = sanitizeMediaFileName(attachment.fileName);
    final target = File('${sentDirectory.path}/${messageId}_$safeName');
    final source = File(attachment.path);
    if (source.absolute.path == target.absolute.path) return source;
    return source.copy(target.path);
  }

  Future<void> _persistOutgoing({
    required String messageId,
    required String conversationId,
    required String localUserId,
    required MediaAttachment attachment,
    required File retained,
    required String? caption,
    required bool isViewOnce,
    required VoiceNoteMetadata? voiceNote,
    required StorageMessageStatus status,
    required List<String> receiptRecipients,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final content = voiceNote == null
        ? LocalMessage.buildFileContent(
            fileName: attachment.fileName,
            mimeType: attachment.mimeType,
            fileSize: attachment.fileSize,
            filePath: retained.absolute.path,
          )
        : LocalMessage.buildVoiceNoteContent(
            fileName: attachment.fileName,
            mimeType: attachment.mimeType,
            fileSize: attachment.fileSize,
            filePath: retained.absolute.path,
            duration: voiceNote.duration,
            waveform: voiceNote.waveform,
          );
    await _database.messages.insert(
      MessageEntity(
        id: messageId,
        conversationId: conversationId,
        senderId: localUserId,
        content: content,
        contentType: _contentType(
          attachment.mimeType,
          isVoiceNote: voiceNote != null,
        ),
        timestamp: now,
        status: status,
        isOutgoing: true,
        receiptRecipients: receiptRecipients,
        caption: caption,
        isViewOnce: isViewOnce,
      ),
    );
    await _database.conversations.updateLastMessageById(
      conversationId,
      _preview(
        attachment.mimeType,
        caption,
        attachment.fileName,
        isVoiceNote: voiceNote != null,
        isViewOnce: isViewOnce,
      ),
      now,
      type: _contentType(attachment.mimeType, isVoiceNote: voiceNote != null),
      outgoing: true,
      status: status,
    );
  }

  Future<void> _persistIncoming(ReceivedFile received) async {
    final conversationId = received.groupId ?? received.senderId;
    final messageId = received.originalMessageId?.trim().isNotEmpty == true
        ? received.originalMessageId!.trim()
        : 'file-${received.transferId}';
    if (await _database.messages.getById(messageId) != null) return;
    var conversation = await _database.conversations.getById(conversationId);
    if (conversation == null) {
      conversation = ConversationEntity(
        id: conversationId,
        peerId: conversationId,
        peerName: conversationId,
        peerPhone: '',
        isGroup: received.groupId != null,
        groupMembers: received.groupId == null ? null : received.senderId,
      );
      await _database.conversations.insert(conversation);
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final voiceNote = received.mimeType.startsWith('audio/')
        ? VoiceNoteMetadata.tryDecode(received.caption)
        : null;
    final isMediaPreviewDeferred = await _shouldDeferIncomingPreview(
      received,
      isVoiceNote: voiceNote != null,
    );
    final filePath = received.file.absolute.path;
    final content = voiceNote == null
        ? LocalMessage.buildFileContent(
            fileName: sanitizeMediaFileName(received.fileName),
            mimeType: received.mimeType,
            fileSize: received.fileSize,
            filePath: filePath,
          )
        : LocalMessage.buildVoiceNoteContent(
            fileName: sanitizeMediaFileName(received.fileName),
            mimeType: received.mimeType,
            fileSize: received.fileSize,
            filePath: filePath,
            duration: voiceNote.duration,
            waveform: voiceNote.waveform,
          );
    await _database.messages.insert(
      MessageEntity(
        id: messageId,
        conversationId: conversationId,
        senderId: received.senderId,
        content: content,
        contentType: _contentType(
          received.mimeType,
          isVoiceNote: voiceNote != null,
        ),
        timestamp: timestamp,
        status: StorageMessageStatus.delivered,
        isOutgoing: false,
        expiresAt: received.absoluteExpiresAt?.millisecondsSinceEpoch,
        caption: voiceNote == null ? _cleanCaption(received.caption) : null,
        isViewOnce: received.isViewOnce,
        isMediaPreviewDeferred: isMediaPreviewDeferred,
      ),
    );
    await _database.conversations.updateLastMessageById(
      conversationId,
      _preview(
        received.mimeType,
        voiceNote == null ? received.caption : null,
        received.fileName,
        isVoiceNote: voiceNote != null,
        isViewOnce: received.isViewOnce,
      ),
      timestamp,
      type: _contentType(received.mimeType, isVoiceNote: voiceNote != null),
      outgoing: false,
    );
    await _database.conversations.incrementUnreadCount(conversationId);
    // Publish only after the file and chat state exist, so notifications and
    // background shutdown observe a fully persisted message.
    final strings = await _strings.load();
    final identity = await _identityResolver.resolve(received.senderId);
    final senderName =
        identity.displayName.isEmpty ||
            identity.displayName == received.senderId
        ? strings.group_unknown_member
        : identity.displayName;
    _acceptedMessages.add(
      IncomingMessageEvent(
        messageId: messageId,
        conversationId: conversationId,
        title: conversation.isGroup
            ? '$senderName (${conversation.peerName})'
            : senderName,
        preview: received.isViewOnce
            ? strings.view_once
            : voiceNote != null
            ? strings.voice_message
            : received.mimeType.startsWith('image/')
            ? strings.photos
            : strings.file,
        timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp),
        isMuted: conversation.isMuted,
        isMention: false,
        customSound: conversation.customNotificationUri,
      ),
    );
  }

  Future<bool> _shouldDeferIncomingPreview(
    ReceivedFile received, {
    required bool isVoiceNote,
  }) async {
    // Pushed chunks have already consumed bandwidth and passed authentication.
    // Preserve the only received copy; policy can defer previews, not receipt.
    // True pre-download opt-out requires a transfer handshake in the protocol.
    if (isVoiceNote) return false;
    final storage = _storageManagement;
    final network = _networkKindProvider;
    if (storage == null || network == null) return false;
    final policy = await storage.loadPolicy();
    return !storage.shouldDownload(
      policy: policy,
      category: storage.categoryFor(received.mimeType),
      fileSize: received.fileSize,
      network: network.currentNetworkKind,
    );
  }

  String _newId(String prefix) {
    final bytes = List<int>.generate(12, (_) => _random.nextInt(256));
    final suffix = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}-$suffix';
  }
}

StorageMessageContentType _contentType(
  String mimeType, {
  bool isVoiceNote = false,
}) => isVoiceNote
    ? StorageMessageContentType.voiceNote
    : mimeType.startsWith('image/')
    ? StorageMessageContentType.image
    : StorageMessageContentType.file;

String? _cleanCaption(String? caption) {
  final clean = caption?.trim();
  if (clean == null || clean.isEmpty) return null;
  return clean.length <= 1000 ? clean : clean.substring(0, 1000);
}

String _preview(
  String mimeType,
  String? caption,
  String fileName, {
  bool isVoiceNote = false,
  bool isViewOnce = false,
}) {
  if (isViewOnce) return viewOncePreviewLabel;
  if (isVoiceNote) return 'Sesli mesaj';
  final clean = _cleanCaption(caption);
  if (mimeType.startsWith('image/')) {
    return clean == null ? 'Fotoğraf' : 'Fotoğraf · $clean';
  }
  return clean == null ? sanitizeMediaFileName(fileName) : 'Dosya · $clean';
}
