enum MessageContentType { text, image, file, voiceNote, system, deleted, poll }

enum MessageStatus { sending, sent, delivered, read, failed }

enum ConnectionStateKind { disconnected, connecting, connected, error }

class Conversation {
  const Conversation({
    required this.id,
    required this.peerId,
    required this.peerName,
    required this.peerPhone,
    this.lastMessage,
    this.lastMessageTimestamp,
    this.unreadCount = 0,
    this.isMuted = false,
    this.isPinned = false,
    this.isGroup = false,
    this.groupMembers = const [],
    this.groupAdmins = const [],
    this.isArchived = false,
    this.disappearingDuration = Duration.zero,
    this.isFavorite = false,
    this.isLocked = false,
    this.manuallyUnread = false,
    this.isReadOnly = false,
    this.isExportEnabled = false,
  });

  final String id;
  final String peerId;
  final String peerName;
  final String peerPhone;
  final String? lastMessage;
  final DateTime? lastMessageTimestamp;
  final int unreadCount;
  final bool isMuted;
  final bool isPinned;
  final bool isGroup;
  final List<String> groupMembers;
  final List<String> groupAdmins;
  final bool isArchived;
  final Duration disappearingDuration;
  final bool isFavorite;
  final bool isLocked;
  final bool manuallyUnread;
  final bool isReadOnly;
  final bool isExportEnabled;

  bool get hasUnread => unreadCount > 0 || manuallyUnread;

  Conversation copyWith({
    String? lastMessage,
    DateTime? lastMessageTimestamp,
    int? unreadCount,
    bool? isMuted,
    bool? isPinned,
    bool? isArchived,
    Duration? disappearingDuration,
    bool? isFavorite,
    bool? isLocked,
    bool? manuallyUnread,
    bool? isReadOnly,
    bool? isExportEnabled,
  }) {
    return Conversation(
      id: id,
      peerId: peerId,
      peerName: peerName,
      peerPhone: peerPhone,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTimestamp: lastMessageTimestamp ?? this.lastMessageTimestamp,
      unreadCount: unreadCount ?? this.unreadCount,
      isMuted: isMuted ?? this.isMuted,
      isPinned: isPinned ?? this.isPinned,
      isGroup: isGroup,
      groupMembers: groupMembers,
      groupAdmins: groupAdmins,
      isArchived: isArchived ?? this.isArchived,
      disappearingDuration: disappearingDuration ?? this.disappearingDuration,
      isFavorite: isFavorite ?? this.isFavorite,
      isLocked: isLocked ?? this.isLocked,
      manuallyUnread: manuallyUnread ?? this.manuallyUnread,
      isReadOnly: isReadOnly ?? this.isReadOnly,
      isExportEnabled: isExportEnabled ?? this.isExportEnabled,
    );
  }

  factory Conversation.fromJson(Map<String, Object?> json) => Conversation(
    id: json['id'] as String? ?? '',
    peerId: json['peerId'] as String? ?? '',
    peerName: json['peerName'] as String? ?? '',
    peerPhone: json['peerPhone'] as String? ?? '',
    lastMessage: json['lastMessage'] as String?,
    lastMessageTimestamp: _dateTimeOrNull(json['lastMessageTimestamp']),
    unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
    isMuted: json['isMuted'] as bool? ?? false,
    isPinned: json['isPinned'] as bool? ?? false,
    isGroup: json['isGroup'] as bool? ?? false,
    groupMembers: _stringList(json['groupMembers']),
    groupAdmins: _stringList(json['groupAdmins']),
    isArchived: json['isArchived'] as bool? ?? false,
    disappearingDuration: Duration(
      milliseconds: (json['disappearingDurationMs'] as num?)?.toInt() ?? 0,
    ),
    isFavorite: json['isFavorite'] as bool? ?? false,
    isLocked: json['isLocked'] as bool? ?? false,
    manuallyUnread: json['manuallyUnread'] as bool? ?? false,
    isReadOnly: json['isReadOnly'] as bool? ?? false,
    isExportEnabled: json['isExportEnabled'] as bool? ?? false,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'peerId': peerId,
    'peerName': peerName,
    'peerPhone': peerPhone,
    'lastMessage': lastMessage,
    'lastMessageTimestamp': lastMessageTimestamp?.millisecondsSinceEpoch,
    'unreadCount': unreadCount,
    'isMuted': isMuted,
    'isPinned': isPinned,
    'isGroup': isGroup,
    'groupMembers': groupMembers,
    'groupAdmins': groupAdmins,
    'isArchived': isArchived,
    'disappearingDurationMs': disappearingDuration.inMilliseconds,
    'isFavorite': isFavorite,
    'isLocked': isLocked,
    'manuallyUnread': manuallyUnread,
    'isReadOnly': isReadOnly,
    'isExportEnabled': isExportEnabled,
  };
}

class LocalMessage {
  const LocalMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.peerId,
    required this.content,
    required this.contentType,
    required this.timestamp,
    required this.status,
    required this.isOutgoing,
    this.replyToId,
    this.isStarred = false,
    this.expiresAt,
    this.editedAt,
    this.reactions,
    this.caption,
    this.isViewOnce = false,
    this.isViewed = false,
    this.isPinned = false,
    this.pinnedAt,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String peerId;
  final String content;
  final MessageContentType contentType;
  final DateTime timestamp;
  final MessageStatus status;
  final bool isOutgoing;
  final String? replyToId;
  final bool isStarred;
  final DateTime? expiresAt;
  final DateTime? editedAt;
  final String? reactions;
  final String? caption;
  final bool isViewOnce;
  final bool isViewed;
  final bool isPinned;
  final DateTime? pinnedAt;

  bool get isEdited => editedAt != null;
  bool get isDeleted => contentType == MessageContentType.deleted;
  bool get isFileMessage =>
      contentType == MessageContentType.image ||
      contentType == MessageContentType.file ||
      contentType == MessageContentType.voiceNote;

  List<String> get _fileParts => isFileMessage ? content.split('|') : const [];
  String? get fileName => _fileParts.isNotEmpty ? _fileParts[0] : null;
  String? get fileMimeType => _fileParts.length > 1 ? _fileParts[1] : null;
  int? get fileSize =>
      _fileParts.length > 2 ? int.tryParse(_fileParts[2]) : null;
  String? get filePath => _fileParts.length > 3 ? _fileParts[3] : null;
  Duration? get voiceNoteDuration => contentType == MessageContentType.voiceNote
      ? Duration(
          milliseconds: int.tryParse(_fileParts.elementAtOrNull(4) ?? '') ?? 0,
        )
      : null;
  List<double> get voiceNoteWaveform =>
      contentType != MessageContentType.voiceNote
      ? const []
      : (_fileParts.elementAtOrNull(5) ?? '')
            .split(',')
            .map(double.tryParse)
            .whereType<double>()
            .map((value) => value.clamp(0.0, 1.0).toDouble())
            .take(64)
            .toList(growable: false);

  String get previewText {
    final cap = caption?.trim();
    if (isDeleted) return 'Bu mesaj silindi';
    if (isViewOnce && contentType == MessageContentType.image)
      return 'Tek gösterimlik fotoğraf';
    if (isViewOnce && contentType == MessageContentType.text)
      return 'Tek gösterimlik mesaj';
    if (contentType == MessageContentType.image)
      return cap?.isNotEmpty == true ? 'Fotoğraf · $cap' : 'Fotoğraf';
    if (contentType == MessageContentType.file)
      return cap?.isNotEmpty == true ? 'Dosya · $cap' : (fileName ?? 'Dosya');
    if (contentType == MessageContentType.voiceNote) return 'Sesli mesaj';
    if (contentType == MessageContentType.poll) return 'Anket';
    return content;
  }

  static String buildFileContent({
    required String fileName,
    required String mimeType,
    required int fileSize,
    String filePath = '',
  }) {
    return '$fileName|$mimeType|$fileSize|$filePath';
  }

  static String buildVoiceNoteContent({
    required String fileName,
    required String mimeType,
    required int fileSize,
    required String filePath,
    required Duration duration,
    required List<double> waveform,
  }) {
    final samples = waveform
        .take(64)
        .map((value) => value.clamp(0.0, 1.0).toStringAsFixed(3))
        .join(',');
    return '${buildFileContent(fileName: fileName, mimeType: mimeType, fileSize: fileSize, filePath: filePath)}|${duration.inMilliseconds}|$samples';
  }

  LocalMessage copyWith({
    String? content,
    MessageContentType? contentType,
    MessageStatus? status,
    DateTime? editedAt,
    String? reactions,
    bool? isStarred,
    bool? isViewed,
    bool? isPinned,
    DateTime? pinnedAt,
  }) {
    return LocalMessage(
      id: id,
      conversationId: conversationId,
      senderId: senderId,
      peerId: peerId,
      content: content ?? this.content,
      contentType: contentType ?? this.contentType,
      timestamp: timestamp,
      status: status ?? this.status,
      isOutgoing: isOutgoing,
      replyToId: replyToId,
      isStarred: isStarred ?? this.isStarred,
      expiresAt: expiresAt,
      editedAt: editedAt ?? this.editedAt,
      reactions: reactions ?? this.reactions,
      caption: caption,
      isViewOnce: isViewOnce,
      isViewed: isViewed ?? this.isViewed,
      isPinned: isPinned ?? this.isPinned,
      pinnedAt: pinnedAt ?? this.pinnedAt,
    );
  }

  factory LocalMessage.fromJson(Map<String, Object?> json) => LocalMessage(
    id: json['id'] as String? ?? '',
    conversationId: json['conversationId'] as String? ?? '',
    senderId: json['senderId'] as String? ?? '',
    peerId: json['peerId'] as String? ?? '',
    content: json['content'] as String? ?? '',
    contentType: _contentType(json['contentType']),
    timestamp: _dateTime(json['timestamp']),
    status: _messageStatus(json['status']),
    isOutgoing: json['isOutgoing'] as bool? ?? false,
    replyToId: json['replyToId'] as String?,
    isStarred: json['isStarred'] as bool? ?? false,
    expiresAt: _dateTimeOrNull(json['expiresAt']),
    editedAt: _dateTimeOrNull(json['editedAt']),
    reactions: json['reactions'] as String?,
    caption: json['caption'] as String?,
    isViewOnce: json['isViewOnce'] as bool? ?? false,
    isViewed: json['isViewed'] as bool? ?? false,
    isPinned: json['isPinned'] as bool? ?? false,
    pinnedAt: _dateTimeOrNull(json['pinnedAt']),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'conversationId': conversationId,
    'senderId': senderId,
    'peerId': peerId,
    'content': content,
    'contentType': contentType.name,
    'timestamp': timestamp.millisecondsSinceEpoch,
    'status': status.name,
    'isOutgoing': isOutgoing,
    'replyToId': replyToId,
    'isStarred': isStarred,
    'expiresAt': expiresAt?.millisecondsSinceEpoch,
    'editedAt': editedAt?.millisecondsSinceEpoch,
    'reactions': reactions,
    'caption': caption,
    'isViewOnce': isViewOnce,
    'isViewed': isViewed,
    'isPinned': isPinned,
    'pinnedAt': pinnedAt?.millisecondsSinceEpoch,
  };
}

extension<T> on List<T> {
  T? elementAtOrNull(int index) =>
      index >= 0 && index < length ? this[index] : null;
}

DateTime _dateTime(Object? value) =>
    DateTime.fromMillisecondsSinceEpoch((value as num?)?.toInt() ?? 0);

DateTime? _dateTimeOrNull(Object? value) =>
    value == null ? null : _dateTime(value);

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value.whereType<String>().toList(growable: false);
}

MessageContentType _contentType(Object? value) {
  final name = value?.toString();
  return MessageContentType.values.firstWhere(
    (type) => type.name == name,
    orElse: () => MessageContentType.text,
  );
}

MessageStatus _messageStatus(Object? value) {
  final name = value?.toString();
  return MessageStatus.values.firstWhere(
    (status) => status.name == name,
    orElse: () => MessageStatus.sending,
  );
}
