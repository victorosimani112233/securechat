import 'dart:convert';
import 'dart:io';

import 'secure_chat_database.dart';

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

class StorageManagementService {
  const StorageManagementService(this._database);
  static const _policyKey = 'auto_download_policy_v1';
  static const textOverheadPerMessage = 256;
  final SecureChatDatabase _database;

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
    var freed = 0;
    for (final content
        in await _database.messages.getFileContentsByConversation(
          conversationId,
        )) {
      final path = _parts(content).path;
      if (path == null || path.isEmpty) continue;
      final file = File(path);
      try {
        if (await file.exists()) {
          freed += await file.length();
          await file.delete();
        }
      } on FileSystemException {
        // Database cleanup still proceeds for stale/unreadable media paths.
      }
    }
    await _database.messages.deleteMediaByConversation(conversationId);
    return freed;
  }

  Future<int> _size(String content) async {
    final parts = _parts(content);
    if (parts.path != null && parts.path!.isNotEmpty) {
      try {
        final file = File(parts.path!);
        if (await file.exists()) return file.length();
      } on FileSystemException {}
    }
    return parts.declaredSize;
  }

  static ({int declaredSize, String? path}) _parts(String content) {
    final pieces = content.split('|');
    return (
      declaredSize: pieces.length > 2 ? int.tryParse(pieces[2]) ?? 0 : 0,
      path: pieces.length > 3 ? pieces[3] : null,
    );
  }
}
