import 'dart:convert';
import 'dart:io';

import '../chat/conversation_preview.dart';
import '../core/models.dart';
import 'secure_chat_database.dart';
import 'storage_entities.dart';

enum MediaCategory { photo, video, document }

enum NetworkKind { wifi, cellular, other }

abstract interface class NetworkKindProvider {
  NetworkKind get currentNetworkKind;
}

class AutoDownloadPolicy {
  const AutoDownloadPolicy({
    this.photosOnWifi = true,
    this.photosOnCellular = true,
    this.videosOnWifi = true,
    this.videosOnCellular = false,
    this.documentsOnWifi = true,
    this.documentsOnCellular = false,
    this.maxAutoDownloadBytes = 25 * 1024 * 1024,
  });
  final bool photosOnWifi;
  final bool photosOnCellular;
  final bool videosOnWifi;
  final bool videosOnCellular;
  final bool documentsOnWifi;
  final bool documentsOnCellular;
  final int maxAutoDownloadBytes;

  AutoDownloadPolicy copyWith({
    bool? photosOnWifi,
    bool? photosOnCellular,
    bool? videosOnWifi,
    bool? videosOnCellular,
    bool? documentsOnWifi,
    bool? documentsOnCellular,
    int? maxAutoDownloadBytes,
  }) => AutoDownloadPolicy(
    photosOnWifi: photosOnWifi ?? this.photosOnWifi,
    photosOnCellular: photosOnCellular ?? this.photosOnCellular,
    videosOnWifi: videosOnWifi ?? this.videosOnWifi,
    videosOnCellular: videosOnCellular ?? this.videosOnCellular,
    documentsOnWifi: documentsOnWifi ?? this.documentsOnWifi,
    documentsOnCellular: documentsOnCellular ?? this.documentsOnCellular,
    maxAutoDownloadBytes: maxAutoDownloadBytes ?? this.maxAutoDownloadBytes,
  );
  factory AutoDownloadPolicy.fromJson(Map<String, Object?> json) =>
      AutoDownloadPolicy(
        photosOnWifi: json['photosOnWifi'] as bool? ?? true,
        photosOnCellular: json['photosOnCellular'] as bool? ?? true,
        videosOnWifi: json['videosOnWifi'] as bool? ?? true,
        videosOnCellular: json['videosOnCellular'] as bool? ?? false,
        documentsOnWifi: json['documentsOnWifi'] as bool? ?? true,
        documentsOnCellular: json['documentsOnCellular'] as bool? ?? false,
        maxAutoDownloadBytes:
            (json['maxAutoDownloadBytes'] as num?)?.toInt() ?? 25 * 1024 * 1024,
      );
  Map<String, Object?> toJson() => {
    'photosOnWifi': photosOnWifi,
    'photosOnCellular': photosOnCellular,
    'videosOnWifi': videosOnWifi,
    'videosOnCellular': videosOnCellular,
    'documentsOnWifi': documentsOnWifi,
    'documentsOnCellular': documentsOnCellular,
    'maxAutoDownloadBytes': maxAutoDownloadBytes,
  };
}

class ChatStorageBreakdown {
  const ChatStorageBreakdown({
    required this.conversationId,
    required this.displayName,
    required this.isGroup,
    required this.messageCount,
    required this.fileCount,
    required this.fileBytes,
    required this.totalBytes,
  });
  final String conversationId;
  final String displayName;
  final bool isGroup;
  final int messageCount;
  final int fileCount;
  final int fileBytes;
  final int totalBytes;
}

enum StorageFileCategory { photo, video, audio, document }

class ChatStorageFile {
  const ChatStorageFile({
    required this.message,
    required this.diskBytes,
    required this.available,
    this.localPath,
  });
  final LocalMessage message;
  final int diskBytes;
  final bool available;
  final String? localPath;
  String? get path => localPath ?? message.filePath;

  bool get canOpen =>
      available &&
      message.isFileMessage &&
      !message.isViewOnce &&
      !message.isMediaPreviewDeferred &&
      (message.expiresAt == null || message.expiresAt!.isAfter(DateTime.now()));
  StorageFileCategory get category {
    final mime = message.fileMimeType ?? '';
    if (mime.startsWith('image/')) return StorageFileCategory.photo;
    if (mime.startsWith('video/')) return StorageFileCategory.video;
    if (mime.startsWith('audio/') ||
        message.contentType == MessageContentType.voiceNote) {
      return StorageFileCategory.audio;
    }
    return StorageFileCategory.document;
  }
}

class StorageCleanupResult {
  const StorageCleanupResult({
    required this.deletedCount,
    required this.freedBytes,
    required this.failedIds,
  });
  final int deletedCount;
  final int freedBytes;
  final List<String> failedIds;
}

class StorageManagementService {
  const StorageManagementService(this._database, {this.mediaDirectory});
  static const _policyKey = 'auto_download_policy_v1';
  static const textOverheadPerMessage = 256;
  final SecureChatDatabase _database;
  final Directory? mediaDirectory;

  Future<ConversationEntity?> getConversation(String id) =>
      _database.conversations.getById(id);

  Stream<List<LocalMessage>> watchChatMessages(String conversationId) =>
      _database.messages
          .getMessages(conversationId)
          .map(
            (messages) => messages
                .map((message) => LocalMessage.fromJson(message.toJson()))
                .toList(growable: false),
          );

  Future<List<ChatStorageFile>> filesForChat(String conversationId) async {
    final result = <ChatStorageFile>[];
    for (final entity in await _database.messages.getMessagesImmediate(
      conversationId,
    )) {
      final message = LocalMessage.fromJson(entity.toJson());
      if (!message.isFileMessage) continue;
      var bytes = 0;
      File? file;
      final path = message.filePath;
      if (path != null && path.isNotEmpty) {
        try {
          file = await _resolveMediaFile(path);
          if (file != null) bytes = await file.length();
        } on FileSystemException {
          file = null;
        }
      }
      result.add(
        ChatStorageFile(
          message: message,
          diskBytes: bytes,
          available: file != null,
          localPath: file?.path,
        ),
      );
    }
    result.sort((a, b) => b.diskBytes.compareTo(a.diskBytes));
    return result;
  }

  /// Re-read privacy flags and the retained path immediately before opening.
  /// Chat authorization remains the caller's responsibility.
  Future<ChatStorageFile?> fileForOpening(
    String conversationId,
    String id,
  ) async {
    final entity = await _database.messages.getById(id);
    if (entity == null || entity.conversationId != conversationId) return null;
    final message = LocalMessage.fromJson(entity.toJson());
    final candidate = ChatStorageFile(
      message: message,
      diskBytes: 0,
      available: true,
    );
    if (!candidate.canOpen) return null;
    final path = message.filePath;
    if (path == null || path.isEmpty) return null;
    try {
      final file = await _resolveMediaFile(path);
      if (file == null || !candidate.canOpen) return null;
      final bytes = await file.length();
      final latest = await _database.messages.getById(id);
      if (latest == null || latest.conversationId != conversationId)
        return null;
      final current = LocalMessage.fromJson(latest.toJson());
      if (current.filePath != message.filePath) return null;
      final result = ChatStorageFile(
        message: current,
        diskBytes: bytes,
        available: true,
        localPath: file.path,
      );
      return result.canOpen ? result : null;
    } on FileSystemException {
      return null;
    }
  }

  Future<File?> _resolveMediaFile(String storedPath) async {
    final root = mediaDirectory;
    if (root == null) return null;
    var path = storedPath;
    final uri = Uri.tryParse(path);
    if (uri?.hasScheme == true) {
      if (uri!.scheme != 'file' ||
          uri.host.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment) {
        throw const FileSystemException('Not a local media path');
      }
      path = uri.toFilePath();
    }
    if (!File(path).isAbsolute ||
        path.split('/').any((part) => part == '..' || part == '.')) {
      throw const FileSystemException('Invalid media path');
    }
    final safeRoot = await root.resolveSymbolicLinks();
    var candidate = File(path);
    if (!await candidate.exists()) {
      // iOS may relocate the app container after restore/update. Only rebase
      // the known private media subtree, never arbitrary basenames or paths.
      const uuid =
          r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}';
      final oldContainer = RegExp(
        '^(?:/(?:private/)?var/mobile|/Users/[^/]+/Library/Developer/CoreSimulator/Devices/$uuid/data)'
        '/Containers/Data/Application/$uuid/Library/Application Support/media/(.+)\$',
      ).firstMatch(path);
      if (oldContainer == null) {
        if (!path.startsWith('$safeRoot${Platform.pathSeparator}') &&
            !path.startsWith(
              '${root.absolute.path}${Platform.pathSeparator}',
            )) {
          throw const FileSystemException('Media path outside managed storage');
        }
        return null;
      }
      candidate = File('$safeRoot/${oldContainer.group(1)!}');
      if (!await candidate.exists()) return null;
    }
    final resolved = File(await candidate.resolveSymbolicLinks());
    if (!resolved.path.startsWith('$safeRoot${Platform.pathSeparator}')) {
      throw const FileSystemException('Media path outside managed storage');
    }
    return resolved;
  }

  Future<String?> resolveMediaPath(
    String storedPath, {
    bool strict = false,
  }) async {
    try {
      if (strict && mediaDirectory == null) {
        throw const FileSystemException('Media directory unavailable');
      }
      return (await _resolveMediaFile(storedPath))?.path;
    } on FileSystemException {
      if (strict) rethrow;
      return null;
    }
  }

  Future<AutoDownloadPolicy> loadPolicy() async {
    final raw = await _database.cryptoState.get(_policyKey);
    if (raw == null) return const AutoDownloadPolicy();
    try {
      return AutoDownloadPolicy.fromJson(
        (jsonDecode(raw) as Map).cast<String, Object?>(),
      );
    } catch (_) {
      return const AutoDownloadPolicy();
    }
  }

  Future<void> savePolicy(AutoDownloadPolicy policy) =>
      _database.cryptoState.put(_policyKey, jsonEncode(policy.toJson()));

  bool shouldDownload({
    required AutoDownloadPolicy policy,
    required MediaCategory category,
    required int fileSize,
    required NetworkKind network,
  }) {
    final cellular = network == NetworkKind.cellular;
    if (cellular && fileSize > policy.maxAutoDownloadBytes) return false;
    return switch (category) {
      MediaCategory.photo =>
        cellular ? policy.photosOnCellular : policy.photosOnWifi,
      MediaCategory.video =>
        cellular ? policy.videosOnCellular : policy.videosOnWifi,
      MediaCategory.document =>
        cellular ? policy.documentsOnCellular : policy.documentsOnWifi,
    };
  }

  MediaCategory categoryFor(String mime) => mime.startsWith('image/')
      ? MediaCategory.photo
      : mime.startsWith('video/')
      ? MediaCategory.video
      : MediaCategory.document;

  Future<List<ChatStorageBreakdown>> analyzeAll() async {
    final result = <ChatStorageBreakdown>[];
    for (final conversation
        in await _database.conversations.getAllImmediate()) {
      final contents = await _database.messages.getFileContentsByConversation(
        conversation.id,
      );
      var bytes = 0;
      for (final content in contents) {
        bytes += await _size(content);
      }
      final count = await _database.messages.getMessageCount(conversation.id);
      result.add(
        ChatStorageBreakdown(
          conversationId: conversation.id,
          displayName: conversation.peerName.isEmpty
              ? conversation.peerId
              : conversation.peerName,
          isGroup: conversation.isGroup,
          messageCount: count,
          fileCount: contents.length,
          fileBytes: bytes,
          totalBytes: bytes + count * textOverheadPerMessage,
        ),
      );
    }
    result.sort((a, b) => b.totalBytes.compareTo(a.totalBytes));
    return result;
  }

  Future<int> cleanFiles(String conversationId) async {
    final files = await filesForChat(conversationId);
    final result = await cleanSelectedFiles(
      conversationId,
      files.map((file) => file.message.id),
    );
    if (result.failedIds.isNotEmpty)
      throw const FileSystemException('Some local media could not be removed');
    return result.freedBytes;
  }

  Future<StorageCleanupResult> cleanSelectedFiles(
    String conversationId,
    Iterable<String> messageIds,
  ) async {
    final selected = messageIds.toSet();
    var freed = 0;
    var deleted = 0;
    final failed = <String>[];
    for (final id in selected) {
      final entity = await _database.messages.getById(id);
      if (entity == null || entity.conversationId != conversationId) continue;
      final message = LocalMessage.fromJson(entity.toJson());
      if (!message.isFileMessage) continue;
      try {
        final path = message.filePath;
        final file = path == null || path.isEmpty
            ? null
            : await _resolveMediaFile(path);
        if (path != null && path.isNotEmpty && mediaDirectory == null) {
          throw const FileSystemException('Media directory unavailable');
        }
        if (file != null) {
          var shared = false;
          for (final other in await _database.messages.getAllMessages()) {
            if (other.id == id) continue;
            final otherMessage = LocalMessage.fromJson(other.toJson());
            final otherPath = otherMessage.filePath;
            if (otherPath == null || otherPath.isEmpty) continue;
            File? otherFile;
            try {
              otherFile = await _resolveMediaFile(otherPath);
            } on FileSystemException {
              continue;
            }
            if (otherFile?.path == file.path) {
              shared = true;
              break;
            }
          }
          // The last local reference owns deletion, including shared/forwarded files.
          if (!shared) {
            final size = await file.length();
            await file.delete();
            freed += size;
          }
        }
        await _database.messages.delete(id);
        deleted++;
      } on FileSystemException {
        failed.add(id);
      }
    }
    if (deleted > 0) {
      final latest = await _database.messages.getMessagesPaginated(
        conversationId,
        1,
        0,
      );
      if (latest.isEmpty) {
        await _database.conversations.clearLastMessage(conversationId);
      } else {
        final message = latest.single;
        await _database.conversations.updateLastMessageById(
          conversationId,
          conversationPreview(
            content: message.content,
            isViewOnce: message.isViewOnce,
            contentType: message.contentType,
          ),
          message.timestamp,
          type: message.contentType,
          outgoing: message.isOutgoing,
          status: message.status,
        );
      }
    }
    return StorageCleanupResult(
      deletedCount: deleted,
      freedBytes: freed,
      failedIds: failed,
    );
  }

  Future<int> _size(String content) async {
    final parts = _parts(content);
    if (parts.path != null && parts.path!.isNotEmpty) {
      try {
        final file = await _resolveMediaFile(parts.path!);
        if (file != null) return file.length();
      } on FileSystemException {}
    }
    return 0;
  }

  static ({int declaredSize, String? path}) _parts(String content) {
    final pieces = content.split('|');
    return (
      declaredSize: pieces.length > 2 ? int.tryParse(pieces[2]) ?? 0 : 0,
      path: pieces.length > 3 ? pieces[3] : null,
    );
  }
}
