import 'dart:convert';

enum StorageMessageContentType {
  text,
  image,
  file,
  voiceNote,
  system,
  deleted,
  poll,
}

enum StorageMessageStatus { sending, sent, delivered, read, failed }

const _notProvided = Object();

enum TrustLevel { untrusted, trustedUnverified, trustedVerified }

class ConversationEntity {
  const ConversationEntity({
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
    this.groupMembers,
    this.contactNote,
    this.customNotificationUri,
    this.isArchived = false,
    this.disappearingDuration = 0,
    this.groupAdmins,
    this.isFavorite = false,
    this.isLocked = false,
    this.isExportEnabled = false,
    this.manuallyUnread = false,
    this.isReadOnly = false,
  });

  final String id;
  final String peerId;
  final String peerName;
  final String peerPhone;
  final String? lastMessage;
  final int? lastMessageTimestamp;
  final int unreadCount;
  final bool isMuted;
  final bool isPinned;
  final bool isGroup;
  final String? groupMembers;
  final String? contactNote;
  final String? customNotificationUri;
  final bool isArchived;
  final int disappearingDuration;
  final String? groupAdmins;
  final bool isFavorite;
  final bool isLocked;
  final bool isExportEnabled;
  final bool manuallyUnread;
  final bool isReadOnly;

  ConversationEntity copyWith({
    String? peerName,
    String? peerPhone,
    Object? lastMessage = _notProvided,
    Object? lastMessageTimestamp = _notProvided,
    int? unreadCount,
    bool? isMuted,
    bool? isPinned,
    String? groupMembers,
    String? contactNote,
    String? customNotificationUri,
    bool? isArchived,
    int? disappearingDuration,
    String? groupAdmins,
    bool? isFavorite,
    bool? isLocked,
    bool? isExportEnabled,
    bool? manuallyUnread,
    bool? isReadOnly,
  }) => ConversationEntity(
    id: id,
    peerId: peerId,
    peerName: peerName ?? this.peerName,
    peerPhone: peerPhone ?? this.peerPhone,
    lastMessage: identical(lastMessage, _notProvided)
        ? this.lastMessage
        : lastMessage as String?,
    lastMessageTimestamp: identical(lastMessageTimestamp, _notProvided)
        ? this.lastMessageTimestamp
        : lastMessageTimestamp as int?,
    unreadCount: unreadCount ?? this.unreadCount,
    isMuted: isMuted ?? this.isMuted,
    isPinned: isPinned ?? this.isPinned,
    isGroup: isGroup,
    groupMembers: groupMembers ?? this.groupMembers,
    contactNote: contactNote ?? this.contactNote,
    customNotificationUri: customNotificationUri ?? this.customNotificationUri,
    isArchived: isArchived ?? this.isArchived,
    disappearingDuration: disappearingDuration ?? this.disappearingDuration,
    groupAdmins: groupAdmins ?? this.groupAdmins,
    isFavorite: isFavorite ?? this.isFavorite,
    isLocked: isLocked ?? this.isLocked,
    isExportEnabled: isExportEnabled ?? this.isExportEnabled,
    manuallyUnread: manuallyUnread ?? this.manuallyUnread,
    isReadOnly: isReadOnly ?? this.isReadOnly,
  );

  factory ConversationEntity.fromJson(Map<String, Object?> json) =>
      ConversationEntity(
        id: json['id'] as String? ?? '',
        peerId: json['peerId'] as String? ?? '',
        peerName: json['peerName'] as String? ?? '',
        peerPhone: json['peerPhone'] as String? ?? '',
        lastMessage: json['lastMessage'] as String?,
        lastMessageTimestamp: (json['lastMessageTimestamp'] as num?)?.toInt(),
        unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
        isMuted: json['isMuted'] as bool? ?? false,
        isPinned: json['isPinned'] as bool? ?? false,
        isGroup: json['isGroup'] as bool? ?? false,
        groupMembers: json['groupMembers'] as String?,
        contactNote: json['contactNote'] as String?,
        customNotificationUri: json['customNotificationUri'] as String?,
        isArchived: json['isArchived'] as bool? ?? false,
        disappearingDuration:
            (json['disappearingDuration'] as num?)?.toInt() ?? 0,
        groupAdmins: json['groupAdmins'] as String?,
        isFavorite: json['isFavorite'] as bool? ?? false,
        isLocked: json['isLocked'] as bool? ?? false,
        isExportEnabled: json['isExportEnabled'] as bool? ?? false,
        manuallyUnread: json['manuallyUnread'] as bool? ?? false,
        isReadOnly: json['isReadOnly'] as bool? ?? false,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'peerId': peerId,
    'peerName': peerName,
    'peerPhone': peerPhone,
    'lastMessage': lastMessage,
    'lastMessageTimestamp': lastMessageTimestamp,
    'unreadCount': unreadCount,
    'isMuted': isMuted,
    'isPinned': isPinned,
    'isGroup': isGroup,
    'groupMembers': groupMembers,
    'contactNote': contactNote,
    'customNotificationUri': customNotificationUri,
    'isArchived': isArchived,
    'disappearingDuration': disappearingDuration,
    'groupAdmins': groupAdmins,
    'isFavorite': isFavorite,
    'isLocked': isLocked,
    'isExportEnabled': isExportEnabled,
    'manuallyUnread': manuallyUnread,
    'isReadOnly': isReadOnly,
  };
}

class MessageEntity {
  const MessageEntity({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.content,
    required this.contentType,
    required this.timestamp,
    required this.status,
    this.replyToId,
    required this.isOutgoing,
    this.isStarred = false,
    this.expiresAt,
    this.editedAt,
    this.editHistory,
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
  final String content;
  final StorageMessageContentType contentType;
  final int timestamp;
  final StorageMessageStatus status;
  final String? replyToId;
  final bool isOutgoing;
  final bool isStarred;
  final int? expiresAt;
  final int? editedAt;
  final String? editHistory;
  final String? reactions;
  final String? caption;
  final bool isViewOnce;
  final bool isViewed;
  final bool isPinned;
  final int? pinnedAt;

  MessageEntity copyWith({
    String? content,
    StorageMessageContentType? contentType,
    StorageMessageStatus? status,
    bool? isStarred,
    int? expiresAt,
    int? editedAt,
    String? editHistory,
    Object? reactions = _notProvided,
    bool? isViewed,
    bool? isPinned,
    Object? pinnedAt = _notProvided,
  }) => MessageEntity(
    id: id,
    conversationId: conversationId,
    senderId: senderId,
    content: content ?? this.content,
    contentType: contentType ?? this.contentType,
    timestamp: timestamp,
    status: status ?? this.status,
    replyToId: replyToId,
    isOutgoing: isOutgoing,
    isStarred: isStarred ?? this.isStarred,
    expiresAt: expiresAt ?? this.expiresAt,
    editedAt: editedAt ?? this.editedAt,
    editHistory: editHistory ?? this.editHistory,
    reactions: identical(reactions, _notProvided)
        ? this.reactions
        : reactions as String?,
    caption: caption,
    isViewOnce: isViewOnce,
    isViewed: isViewed ?? this.isViewed,
    isPinned: isPinned ?? this.isPinned,
    pinnedAt: identical(pinnedAt, _notProvided)
        ? this.pinnedAt
        : pinnedAt as int?,
  );

  factory MessageEntity.fromJson(Map<String, Object?> json) => MessageEntity(
    id: json['id'] as String? ?? '',
    conversationId: json['conversationId'] as String? ?? '',
    senderId: json['senderId'] as String? ?? '',
    content: json['content'] as String? ?? '',
    contentType: _enumByName(
      StorageMessageContentType.values,
      json['contentType'],
      StorageMessageContentType.text,
    ),
    timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
    status: _enumByName(
      StorageMessageStatus.values,
      json['status'],
      StorageMessageStatus.sending,
    ),
    replyToId: json['replyToId'] as String?,
    isOutgoing: json['isOutgoing'] as bool? ?? false,
    isStarred: json['isStarred'] as bool? ?? false,
    expiresAt: (json['expiresAt'] as num?)?.toInt(),
    editedAt: (json['editedAt'] as num?)?.toInt(),
    editHistory: json['editHistory'] as String?,
    reactions: json['reactions'] as String?,
    caption: json['caption'] as String?,
    isViewOnce: json['isViewOnce'] as bool? ?? false,
    isViewed: json['isViewed'] as bool? ?? false,
    isPinned: json['isPinned'] as bool? ?? false,
    pinnedAt: (json['pinnedAt'] as num?)?.toInt(),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'conversationId': conversationId,
    'senderId': senderId,
    'content': content,
    'contentType': contentType.name,
    'timestamp': timestamp,
    'status': status.name,
    'replyToId': replyToId,
    'isOutgoing': isOutgoing,
    'isStarred': isStarred,
    'expiresAt': expiresAt,
    'editedAt': editedAt,
    'editHistory': editHistory,
    'reactions': reactions,
    'caption': caption,
    'isViewOnce': isViewOnce,
    'isViewed': isViewed,
    'isPinned': isPinned,
    'pinnedAt': pinnedAt,
  };
}

class ContactEntity {
  const ContactEntity({
    required this.id,
    required this.phoneNumber,
    required this.phoneHash,
    required this.displayName,
    required this.isRegistered,
    this.avatarUri,
    this.lastSeen,
  });

  final String id;
  final String phoneNumber;
  final String phoneHash;
  final String displayName;
  final bool isRegistered;
  final String? avatarUri;
  final int? lastSeen;

  factory ContactEntity.fromJson(Map<String, Object?> json) => ContactEntity(
    id: json['id'] as String? ?? '',
    phoneNumber: json['phoneNumber'] as String? ?? '',
    phoneHash: json['phoneHash'] as String? ?? '',
    displayName: json['displayName'] as String? ?? '',
    isRegistered: json['isRegistered'] as bool? ?? false,
    avatarUri: json['avatarUri'] as String?,
    lastSeen: (json['lastSeen'] as num?)?.toInt(),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'phoneNumber': phoneNumber,
    'phoneHash': phoneHash,
    'displayName': displayName,
    'isRegistered': isRegistered,
    'avatarUri': avatarUri,
    'lastSeen': lastSeen,
  };
}

class CallLogEntity {
  const CallLogEntity({
    required this.id,
    required this.peerId,
    required this.peerName,
    required this.callType,
    required this.direction,
    required this.status,
    required this.timestamp,
    this.duration = 0,
  });

  final String id;
  final String peerId;
  final String peerName;
  final String callType;
  final String direction;
  final String status;
  final int timestamp;
  final int duration;

  factory CallLogEntity.fromJson(Map<String, Object?> json) => CallLogEntity(
    id: json['id'] as String? ?? '',
    peerId: json['peerId'] as String? ?? '',
    peerName: json['peerName'] as String? ?? '',
    callType: json['callType'] as String? ?? '',
    direction: json['direction'] as String? ?? '',
    status: json['status'] as String? ?? '',
    timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
    duration: (json['duration'] as num?)?.toInt() ?? 0,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'peerId': peerId,
    'peerName': peerName,
    'callType': callType,
    'direction': direction,
    'status': status,
    'timestamp': timestamp,
    'duration': duration,
  };
}

class ScheduledMessageEntity {
  ScheduledMessageEntity({
    required this.id,
    required this.messageContent,
    required this.repeatType,
    this.repeatDays,
    required this.hour,
    required this.minute,
    required this.recipientIds,
    required this.recipientNames,
    this.isEnabled = true,
    required this.nextTriggerTime,
    int? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  final String id;
  final String messageContent;
  final String repeatType;
  final String? repeatDays;
  final int hour;
  final int minute;
  final String recipientIds;
  final String recipientNames;
  final bool isEnabled;
  final int nextTriggerTime;
  final int createdAt;

  ScheduledMessageEntity copyWith({bool? isEnabled, int? nextTriggerTime}) =>
      ScheduledMessageEntity(
        id: id,
        messageContent: messageContent,
        repeatType: repeatType,
        repeatDays: repeatDays,
        hour: hour,
        minute: minute,
        recipientIds: recipientIds,
        recipientNames: recipientNames,
        isEnabled: isEnabled ?? this.isEnabled,
        nextTriggerTime: nextTriggerTime ?? this.nextTriggerTime,
        createdAt: createdAt,
      );

  factory ScheduledMessageEntity.fromJson(Map<String, Object?> json) =>
      ScheduledMessageEntity(
        id: json['id'] as String? ?? '',
        messageContent: json['messageContent'] as String? ?? '',
        repeatType: json['repeatType'] as String? ?? 'ONCE',
        repeatDays: json['repeatDays'] as String?,
        hour: (json['hour'] as num?)?.toInt() ?? 0,
        minute: (json['minute'] as num?)?.toInt() ?? 0,
        recipientIds: json['recipientIds'] as String? ?? '',
        recipientNames: json['recipientNames'] as String? ?? '',
        isEnabled: json['isEnabled'] as bool? ?? true,
        nextTriggerTime: (json['nextTriggerTime'] as num?)?.toInt() ?? 0,
        createdAt: (json['createdAt'] as num?)?.toInt(),
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'messageContent': messageContent,
    'repeatType': repeatType,
    'repeatDays': repeatDays,
    'hour': hour,
    'minute': minute,
    'recipientIds': recipientIds,
    'recipientNames': recipientNames,
    'isEnabled': isEnabled,
    'nextTriggerTime': nextTriggerTime,
    'createdAt': createdAt,
  };
}

class ExportLogEntity {
  const ExportLogEntity({
    required this.id,
    required this.groupId,
    required this.actorUserId,
    required this.actorDisplayName,
    required this.eventType,
    required this.timestamp,
    required this.messageCount,
    this.firstMsgTs,
    this.lastMsgTs,
  });

  final String id;
  final String groupId;
  final String actorUserId;
  final String actorDisplayName;
  final String eventType;
  final int timestamp;
  final int messageCount;
  final int? firstMsgTs;
  final int? lastMsgTs;

  factory ExportLogEntity.fromJson(Map<String, Object?> json) =>
      ExportLogEntity(
        id: json['id'] as String? ?? '',
        groupId: json['groupId'] as String? ?? '',
        actorUserId: json['actorUserId'] as String? ?? '',
        actorDisplayName: json['actorDisplayName'] as String? ?? '',
        eventType: json['eventType'] as String? ?? '',
        timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
        messageCount: (json['messageCount'] as num?)?.toInt() ?? 0,
        firstMsgTs: (json['firstMsgTs'] as num?)?.toInt(),
        lastMsgTs: (json['lastMsgTs'] as num?)?.toInt(),
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'groupId': groupId,
    'actorUserId': actorUserId,
    'actorDisplayName': actorDisplayName,
    'eventType': eventType,
    'timestamp': timestamp,
    'messageCount': messageCount,
    'firstMsgTs': firstMsgTs,
    'lastMsgTs': lastMsgTs,
  };
}

class PendingTimerUpdateEntity {
  PendingTimerUpdateEntity({
    required this.id,
    required this.conversationId,
    required this.targetUserId,
    required this.duration,
    int? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  final String id;
  final String conversationId;
  final String targetUserId;
  final int duration;
  final int createdAt;

  factory PendingTimerUpdateEntity.fromJson(Map<String, Object?> json) =>
      PendingTimerUpdateEntity(
        id: json['id'] as String? ?? '',
        conversationId: json['conversationId'] as String? ?? '',
        targetUserId: json['targetUserId'] as String? ?? '',
        duration: (json['duration'] as num?)?.toInt() ?? 0,
        createdAt: (json['createdAt'] as num?)?.toInt(),
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'conversationId': conversationId,
    'targetUserId': targetUserId,
    'duration': duration,
    'createdAt': createdAt,
  };
}

class IdentityEntity {
  const IdentityEntity({
    required this.addressName,
    required this.identityKey,
    required this.trustLevel,
  });

  final String addressName;
  final List<int> identityKey;
  final TrustLevel trustLevel;

  factory IdentityEntity.fromJson(Map<String, Object?> json) => IdentityEntity(
    addressName: json['addressName'] as String? ?? '',
    identityKey: _bytes(json['identityKey']),
    trustLevel: _enumByName(
      TrustLevel.values,
      json['trustLevel'],
      TrustLevel.untrusted,
    ),
  );

  Map<String, Object?> toJson() => {
    'addressName': addressName,
    'identityKey': base64Encode(identityKey),
    'trustLevel': trustLevel.name,
  };
}

class PreKeyEntity {
  const PreKeyEntity({required this.id, required this.record});

  final int id;
  final List<int> record;

  factory PreKeyEntity.fromJson(Map<String, Object?> json) => PreKeyEntity(
    id: (json['id'] as num?)?.toInt() ?? 0,
    record: _bytes(json['record']),
  );

  Map<String, Object?> toJson() => {'id': id, 'record': base64Encode(record)};
}

class SignedPreKeyEntity extends PreKeyEntity {
  const SignedPreKeyEntity({
    required super.id,
    required super.record,
    required this.createdAt,
  });

  final int createdAt;

  factory SignedPreKeyEntity.fromJson(Map<String, Object?> json) =>
      SignedPreKeyEntity(
        id: (json['id'] as num?)?.toInt() ?? 0,
        record: _bytes(json['record']),
        createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      );

  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'record': base64Encode(record),
    'createdAt': createdAt,
  };
}

class SessionEntity {
  const SessionEntity({required this.id, required this.record});

  final String id;
  final List<int> record;

  factory SessionEntity.fromJson(Map<String, Object?> json) => SessionEntity(
    id: json['id'] as String? ?? '',
    record: _bytes(json['record']),
  );

  Map<String, Object?> toJson() => {'id': id, 'record': base64Encode(record)};
}

class SenderKeyEntity {
  const SenderKeyEntity({
    required this.groupId,
    required this.senderId,
    required this.deviceId,
    required this.record,
    required this.updatedAt,
  });

  final String groupId;
  final String senderId;
  final int deviceId;
  final List<int> record;
  final int updatedAt;

  String get key => '$groupId:$senderId:$deviceId';

  factory SenderKeyEntity.fromJson(Map<String, Object?> json) =>
      SenderKeyEntity(
        groupId: json['groupId'] as String? ?? '',
        senderId: json['senderId'] as String? ?? '',
        deviceId: (json['deviceId'] as num?)?.toInt() ?? 0,
        record: _bytes(json['record']),
        updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
      );

  Map<String, Object?> toJson() => {
    'groupId': groupId,
    'senderId': senderId,
    'deviceId': deviceId,
    'record': base64Encode(record),
    'updatedAt': updatedAt,
  };
}

class PendingSignalEntity {
  const PendingSignalEntity({
    required this.id,
    required this.encodedSignal,
    required this.createdAt,
    this.attempts = 0,
  });

  final String id;
  final String encodedSignal;
  final int createdAt;
  final int attempts;

  PendingSignalEntity copyWith({int? attempts}) => PendingSignalEntity(
    id: id,
    encodedSignal: encodedSignal,
    createdAt: createdAt,
    attempts: attempts ?? this.attempts,
  );

  factory PendingSignalEntity.fromJson(Map<String, Object?> json) =>
      PendingSignalEntity(
        id: json['id'] as String? ?? '',
        encodedSignal: json['encodedSignal'] as String? ?? '',
        createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
        attempts: (json['attempts'] as num?)?.toInt() ?? 0,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'encodedSignal': encodedSignal,
    'createdAt': createdAt,
    'attempts': attempts,
  };
}

T _enumByName<T extends Enum>(List<T> values, Object? raw, T fallback) {
  final normalized = raw?.toString();
  final compact = normalized?.replaceAll('_', '').toLowerCase();
  return values.firstWhere(
    (value) =>
        value.name == normalized ||
        value.name.toUpperCase() == normalized ||
        value.name.toLowerCase() == normalized?.toLowerCase() ||
        value.name.toLowerCase() == compact,
    orElse: () => fallback,
  );
}

List<int> _bytes(Object? raw) {
  if (raw is List) return raw.whereType<int>().toList(growable: false);
  if (raw is String && raw.isNotEmpty) return base64Decode(raw);
  return const [];
}
