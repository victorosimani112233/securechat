import 'dart:convert';

sealed class SignalMessage {
  const SignalMessage({
    required this.senderId,
    required this.recipientId,
    required this.timestamp,
  });

  final String senderId;
  final String recipientId;
  final DateTime timestamp;

  String get type;

  Map<String, Object?> toJson();

  static const maxEncodedBytes = 256 * 1024;

  static SignalMessage decode(String raw) {
    if (utf8.encode(raw).length > maxEncodedBytes) {
      throw const FormatException('Signal frame exceeds the 256 KiB limit');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Signal frame must be a JSON object');
    }
    final data = decoded.cast<String, Object?>();
    final type = data['type'] as String?;
    return switch (type) {
      'sdp_offer' => SdpOfferSignal.fromJson(data),
      'sdp_answer' => SdpAnswerSignal.fromJson(data),
      'ice_candidate' => IceCandidateSignal.fromJson(data),
      'encrypted_message' => EncryptedSignalMessage.fromJson(data),
      'prekey_bundle' => PreKeyBundleSignal.fromJson(data),
      'audio_data' => AudioDataSignal.fromJson(data),
      'video_data' => VideoDataSignal.fromJson(data),
      'group_message_fanout' => GroupMessageFanoutSignal.fromJson(data),
      'file_transfer' => FileTransferSignal.fromJson(data),
      'group_notification' => GroupNotificationSignal.fromJson(data),
      'admin_encrypted_log' => AdminEncryptedLogSignal.fromJson(data),
      'delivery_receipt' => DeliveryReceiptSignal.fromJson(data),
      'message_delete' => MessageDeleteSignal.fromJson(data),
      'message_edit' => MessageEditSignal.fromJson(data),
      'message_reaction' => MessageReactionSignal.fromJson(data),
      'message_pin' => MessagePinSignal.fromJson(data),
      'typing_indicator' => TypingIndicatorSignal.fromJson(data),
      'presence_update' => PresenceUpdateSignal.fromJson(data),
      'presence_subscribe' => PresenceSubscribeSignal.fromJson(data),
      'presence_unsubscribe' => PresenceUnsubscribeSignal.fromJson(data),
      'disappearing_timer' => DisappearingTimerSignal.fromJson(data),
      'call_control' => CallControlSignal.fromJson(data),
      'call_control_ack' => CallControlAckSignal.fromJson(data),
      'session_reset_request' => SessionResetRequestSignal.fromJson(data),
      'sfu_room_created' => SfuRoomCreatedSignal.fromJson(data),
      'server_shutdown' => ServerShutdownSignal.fromJson(data),
      'group_call_invite' => GroupCallInviteSignal.fromJson(data),
      'group_call_member_joined' => GroupCallMemberJoinedSignal.fromJson(data),
      'group_call_member_left' => GroupCallMemberLeftSignal.fromJson(data),
      'group_call_coordinator_changed' =>
        GroupCallCoordinatorChangedSignal.fromJson(data),
      'group_call_join_request' => GroupCallJoinRequestSignal.fromJson(data),
      'group_call_status_query' => GroupCallStatusQuerySignal.fromJson(data),
      'group_call_status_response' => GroupCallStatusResponseSignal.fromJson(
        data,
      ),
      _ => UnknownSignalMessage.fromJson(data),
    };
  }

  String encode() => jsonEncode(toJson());
}

DateTime _dt(Object? value) =>
    DateTime.fromMillisecondsSinceEpoch((value as num?)?.toInt() ?? 0);

Map<String, Object?> _base(SignalMessage msg) => {
  'type': msg.type,
  'senderId': msg.senderId,
  'recipientId': msg.recipientId,
  'timestamp': msg.timestamp.millisecondsSinceEpoch,
};

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value.whereType<String>().toList(growable: false);
}

Map<String, String> _stringMap(Object? value) {
  if (value is! Map) return const {};
  return value.map(
    (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
  );
}

class SdpOfferSignal extends SignalMessage {
  const SdpOfferSignal({
    required super.senderId,
    required super.recipientId,
    required super.timestamp,
    required this.sdp,
    required this.callType,
  });

  final String sdp;
  final String callType;

  @override
  String get type => 'sdp_offer';

  factory SdpOfferSignal.fromJson(Map<String, Object?> json) => SdpOfferSignal(
    senderId: json['senderId'] as String? ?? '',
    recipientId: json['recipientId'] as String? ?? '',
    timestamp: _dt(json['timestamp']),
    sdp: json['sdp'] as String? ?? '',
    callType: json['callType'] as String? ?? 'VOICE',
  );

  @override
  Map<String, Object?> toJson() => {
    ..._base(this),
    'sdp': sdp,
    'callType': callType,
  };
}

class SdpAnswerSignal extends SignalMessage {
  const SdpAnswerSignal({
    required super.senderId,
    required super.recipientId,
    required super.timestamp,
    required this.sdp,
  });

  final String sdp;

  @override
  String get type => 'sdp_answer';

  factory SdpAnswerSignal.fromJson(Map<String, Object?> json) =>
      SdpAnswerSignal(
        senderId: json['senderId'] as String? ?? '',
        recipientId: json['recipientId'] as String? ?? '',
        timestamp: _dt(json['timestamp']),
        sdp: json['sdp'] as String? ?? '',
      );

  @override
  Map<String, Object?> toJson() => {..._base(this), 'sdp': sdp};
}

class IceCandidateSignal extends SignalMessage {
  const IceCandidateSignal({
    required super.senderId,
    required super.recipientId,
    required super.timestamp,
    required this.candidate,
    this.sdpMid,
    required this.sdpMLineIndex,
  });

  final String candidate;
  final String? sdpMid;
  final int sdpMLineIndex;

  @override
  String get type => 'ice_candidate';

  factory IceCandidateSignal.fromJson(Map<String, Object?> json) =>
      IceCandidateSignal(
        senderId: json['senderId'] as String? ?? '',
        recipientId: json['recipientId'] as String? ?? '',
        timestamp: _dt(json['timestamp']),
        candidate: json['candidate'] as String? ?? '',
        sdpMid: json['sdpMid'] as String?,
        sdpMLineIndex: (json['sdpMLineIndex'] as num?)?.toInt() ?? 0,
      );

  @override
  Map<String, Object?> toJson() => {
    ..._base(this),
    'candidate': candidate,
    'sdpMid': sdpMid,
    'sdpMLineIndex': sdpMLineIndex,
  };
}

class EncryptedSignalMessage extends SignalMessage {
  const EncryptedSignalMessage({
    required super.senderId,
    required super.recipientId,
    required super.timestamp,
    required this.envelope,
  });

  final String envelope;

  @override
  String get type => 'encrypted_message';

  factory EncryptedSignalMessage.fromJson(Map<String, Object?> json) {
    return EncryptedSignalMessage(
      senderId: json['senderId'] as String? ?? '',
      recipientId: json['recipientId'] as String? ?? '',
      timestamp: _dt(json['timestamp']),
      envelope: json['envelope'] as String? ?? '',
    );
  }

  @override
  Map<String, Object?> toJson() => {..._base(this), 'envelope': envelope};
}

class PreKeyBundleSignal extends SignalMessage {
  const PreKeyBundleSignal({
    required super.senderId,
    required super.recipientId,
    required super.timestamp,
    required this.bundle,
  });

  final String bundle;

  @override
  String get type => 'prekey_bundle';

  factory PreKeyBundleSignal.fromJson(Map<String, Object?> json) =>
      PreKeyBundleSignal(
        senderId: json['senderId'] as String? ?? '',
        recipientId: json['recipientId'] as String? ?? '',
        timestamp: _dt(json['timestamp']),
        bundle: json['bundle'] as String? ?? '',
      );

  @override
  Map<String, Object?> toJson() => {..._base(this), 'bundle': bundle};
}

class AudioDataSignal extends SignalMessage {
  const AudioDataSignal({
    required super.senderId,
    required super.recipientId,
    required super.timestamp,
    required this.data,
  });

  final String data;

  @override
  String get type => 'audio_data';

  factory AudioDataSignal.fromJson(Map<String, Object?> json) =>
      AudioDataSignal(
        senderId: json['senderId'] as String? ?? '',
        recipientId: json['recipientId'] as String? ?? '',
        timestamp: _dt(json['timestamp']),
        data: json['data'] as String? ?? '',
      );

  @override
  Map<String, Object?> toJson() => {..._base(this), 'data': data};
}

class VideoDataSignal extends AudioDataSignal {
  const VideoDataSignal({
    required super.senderId,
    required super.recipientId,
    required super.timestamp,
    required super.data,
    required this.width,
    required this.height,
  });

  final int width;
  final int height;

  @override
  String get type => 'video_data';

  factory VideoDataSignal.fromJson(Map<String, Object?> json) =>
      VideoDataSignal(
        senderId: json['senderId'] as String? ?? '',
        recipientId: json['recipientId'] as String? ?? '',
        timestamp: _dt(json['timestamp']),
        data: json['data'] as String? ?? '',
        width: (json['width'] as num?)?.toInt() ?? 0,
        height: (json['height'] as num?)?.toInt() ?? 0,
      );

  @override
  Map<String, Object?> toJson() => {
    ..._base(this),
    'data': data,
    'width': width,
    'height': height,
  };
}

class GroupMessageFanoutSignal extends SignalMessage {
  const GroupMessageFanoutSignal({
    required super.senderId,
    required super.timestamp,
    required this.groupId,
    required this.recipientPayloads,
  }) : super(recipientId: 'server');

  final String groupId;
  final Map<String, String> recipientPayloads;

  @override
  String get type => 'group_message_fanout';

  factory GroupMessageFanoutSignal.fromJson(Map<String, Object?> json) =>
      GroupMessageFanoutSignal(
        senderId: json['senderId'] as String? ?? '',
        timestamp: _dt(json['timestamp']),
        groupId: json['groupId'] as String? ?? '',
        recipientPayloads: _stringMap(json['recipientPayloads']),
      );

  @override
  Map<String, Object?> toJson() => {
    ..._base(this),
    'groupId': groupId,
    'recipientPayloads': recipientPayloads,
  };
}

class FileTransferSignal extends SignalMessage {
  const FileTransferSignal({
    required super.senderId,
    required super.recipientId,
    required super.timestamp,
    required this.fileName,
    required this.mimeType,
    required this.fileSize,
    required this.data,
    this.groupId,
    this.groupName,
    this.transferId,
    this.chunkIndex = 0,
    this.totalChunks = 1,
    this.caption,
    this.isViewOnce = false,
    this.originalMessageId,
    this.absoluteExpiresAt,
    this.encryption,
  });

  final String fileName;
  final String mimeType;
  final int fileSize;
  final String data;
  final String? groupId;
  final String? groupName;
  final String? transferId;
  final int chunkIndex;
  final int totalChunks;
  final String? caption;
  final bool isViewOnce;
  final String? originalMessageId;
  final DateTime? absoluteExpiresAt;
  final String? encryption;

  @override
  String get type => 'file_transfer';

  factory FileTransferSignal.fromJson(Map<String, Object?> json) =>
      FileTransferSignal(
        senderId: json['senderId'] as String? ?? '',
        recipientId: json['recipientId'] as String? ?? '',
        timestamp: _dt(json['timestamp']),
        fileName: json['fileName'] as String? ?? '',
        mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
        fileSize: (json['fileSize'] as num?)?.toInt() ?? 0,
        data: json['data'] as String? ?? '',
        groupId: json['groupId'] as String?,
        groupName: json['groupName'] as String?,
        transferId: json['transferId'] as String?,
        chunkIndex: (json['chunkIndex'] as num?)?.toInt() ?? 0,
        totalChunks: (json['totalChunks'] as num?)?.toInt() ?? 1,
        caption: json['caption'] as String?,
        isViewOnce: json['isViewOnce'] as bool? ?? false,
        originalMessageId: json['originalMessageId'] as String?,
        absoluteExpiresAt: json['absoluteExpiresAt'] == null
            ? null
            : _dt(json['absoluteExpiresAt']),
        encryption: json['encryption'] as String?,
      );

  @override
  Map<String, Object?> toJson() => {
    ..._base(this),
    'fileName': fileName,
    'mimeType': mimeType,
    'fileSize': fileSize,
    'data': data,
    if (groupId != null) 'groupId': groupId,
    if (groupName != null) 'groupName': groupName,
    if (transferId != null) 'transferId': transferId,
    'chunkIndex': chunkIndex,
    'totalChunks': totalChunks,
    if (caption != null) 'caption': caption,
    'isViewOnce': isViewOnce,
    if (originalMessageId != null) 'originalMessageId': originalMessageId,
    if (absoluteExpiresAt != null)
      'absoluteExpiresAt': absoluteExpiresAt!.millisecondsSinceEpoch,
    if (encryption != null) 'encryption': encryption,
  };
}

class GroupNotificationSignal extends SignalMessage {
  const GroupNotificationSignal({
    required super.senderId,
    required super.recipientId,
    required super.timestamp,
    required this.groupId,
    required this.groupName,
    required this.action,
    required this.groupMembers,
    this.targetMemberId,
  });

  final String groupId;
  final String groupName;
  final String action;
  final List<String> groupMembers;
  final String? targetMemberId;

  @override
  String get type => 'group_notification';

  factory GroupNotificationSignal.fromJson(Map<String, Object?> json) =>
      GroupNotificationSignal(
        senderId: json['senderId'] as String? ?? '',
        recipientId: json['recipientId'] as String? ?? '',
        timestamp: _dt(json['timestamp']),
        groupId: json['groupId'] as String? ?? '',
        groupName: json['groupName'] as String? ?? '',
        action: json['action'] as String? ?? '',
        groupMembers: _stringList(json['groupMembers']),
        targetMemberId: json['targetMemberId'] as String?,
      );

  @override
  Map<String, Object?> toJson() => {
    ..._base(this),
    'groupId': groupId,
    'groupName': groupName,
    'action': action,
    'groupMembers': groupMembers,
    if (targetMemberId != null) 'targetMemberId': targetMemberId,
  };
}

class AdminEncryptedLogSignal extends SignalMessage {
  const AdminEncryptedLogSignal({
    required super.senderId,
    super.recipientId = 'server',
    required super.timestamp,
    required this.groupId,
    required this.eventType,
    required this.adminPayloads,
  });

  final String groupId;
  final String eventType;
  final Map<String, String> adminPayloads;

  @override
  String get type => 'admin_encrypted_log';

  factory AdminEncryptedLogSignal.fromJson(Map<String, Object?> json) =>
      AdminEncryptedLogSignal(
        senderId: json['senderId'] as String? ?? '',
        recipientId: json['recipientId'] as String? ?? 'server',
        timestamp: _dt(json['timestamp']),
        groupId: json['groupId'] as String? ?? '',
        eventType: json['eventType'] as String? ?? '',
        adminPayloads: _stringMap(json['adminPayloads']),
      );

  @override
  Map<String, Object?> toJson() => {
    ..._base(this),
    'groupId': groupId,
    'eventType': eventType,
    'adminPayloads': adminPayloads,
  };
}

class DeliveryReceiptSignal extends SignalMessage {
  const DeliveryReceiptSignal({
    required super.senderId,
    required super.recipientId,
    required super.timestamp,
    required this.messageId,
    required this.status,
  });

  final String messageId;
  final String status;

  @override
  String get type => 'delivery_receipt';

  factory DeliveryReceiptSignal.fromJson(Map<String, Object?> json) {
    return DeliveryReceiptSignal(
      senderId: json['senderId'] as String? ?? '',
      recipientId: json['recipientId'] as String? ?? '',
      timestamp: _dt(json['timestamp']),
      messageId: json['messageId'] as String? ?? '',
      status: json['status'] as String? ?? '',
    );
  }

  @override
  Map<String, Object?> toJson() => {
    ..._base(this),
    'messageId': messageId,
    'status': status,
  };
}

class MessageDeleteSignal extends SignalMessage {
  const MessageDeleteSignal({
    required super.senderId,
    required super.recipientId,
    required super.timestamp,
    required this.messageId,
  });

  final String messageId;

  @override
  String get type => 'message_delete';

  factory MessageDeleteSignal.fromJson(Map<String, Object?> json) =>
      MessageDeleteSignal(
        senderId: json['senderId'] as String? ?? '',
        recipientId: json['recipientId'] as String? ?? '',
        timestamp: _dt(json['timestamp']),
        messageId: json['messageId'] as String? ?? '',
      );

  @override
  Map<String, Object?> toJson() => {..._base(this), 'messageId': messageId};
}

class MessageEditSignal extends MessageDeleteSignal {
  const MessageEditSignal({
    required super.senderId,
    required super.recipientId,
    required super.timestamp,
    required super.messageId,
    required this.newContent,
  });

  final String newContent;

  @override
  String get type => 'message_edit';

  factory MessageEditSignal.fromJson(Map<String, Object?> json) =>
      MessageEditSignal(
        senderId: json['senderId'] as String? ?? '',
        recipientId: json['recipientId'] as String? ?? '',
        timestamp: _dt(json['timestamp']),
        messageId: json['messageId'] as String? ?? '',
        newContent: json['newContent'] as String? ?? '',
      );

  @override
  Map<String, Object?> toJson() => {
    ..._base(this),
    'messageId': messageId,
    'newContent': newContent,
  };
}

class MessageReactionSignal extends MessageDeleteSignal {
  const MessageReactionSignal({
    required super.senderId,
    required super.recipientId,
    required super.timestamp,
    required super.messageId,
    required this.emoji,
    this.remove = false,
  });

  final String emoji;
  final bool remove;

  @override
  String get type => 'message_reaction';

  factory MessageReactionSignal.fromJson(Map<String, Object?> json) =>
      MessageReactionSignal(
        senderId: json['senderId'] as String? ?? '',
        recipientId: json['recipientId'] as String? ?? '',
        timestamp: _dt(json['timestamp']),
        messageId: json['messageId'] as String? ?? '',
        emoji: json['emoji'] as String? ?? '',
        remove: json['remove'] as bool? ?? false,
      );

  @override
  Map<String, Object?> toJson() => {
    ..._base(this),
    'messageId': messageId,
    'emoji': emoji,
    'remove': remove,
  };
}

class MessagePinSignal extends MessageDeleteSignal {
  const MessagePinSignal({
    required super.senderId,
    required super.recipientId,
    required super.timestamp,
    required super.messageId,
    required this.isPinned,
    this.pinnedAt,
    this.groupId,
  });

  final bool isPinned;
  final DateTime? pinnedAt;
  final String? groupId;

  @override
  String get type => 'message_pin';

  factory MessagePinSignal.fromJson(Map<String, Object?> json) =>
      MessagePinSignal(
        senderId: json['senderId'] as String? ?? '',
        recipientId: json['recipientId'] as String? ?? '',
        timestamp: _dt(json['timestamp']),
        messageId: json['messageId'] as String? ?? '',
        isPinned: json['isPinned'] as bool? ?? false,
        pinnedAt: json['pinnedAt'] == null ? null : _dt(json['pinnedAt']),
        groupId: json['groupId'] as String?,
      );

  @override
  Map<String, Object?> toJson() => {
    ..._base(this),
    'messageId': messageId,
    'isPinned': isPinned,
    if (pinnedAt != null) 'pinnedAt': pinnedAt!.millisecondsSinceEpoch,
    if (groupId != null) 'groupId': groupId,
  };
}

class TypingIndicatorSignal extends SignalMessage {
  const TypingIndicatorSignal({
    required super.senderId,
    required super.recipientId,
    required super.timestamp,
    required this.isTyping,
  });

  final bool isTyping;

  @override
  String get type => 'typing_indicator';

  factory TypingIndicatorSignal.fromJson(Map<String, Object?> json) {
    return TypingIndicatorSignal(
      senderId: json['senderId'] as String? ?? '',
      recipientId: json['recipientId'] as String? ?? '',
      timestamp: _dt(json['timestamp']),
      isTyping: json['isTyping'] as bool? ?? false,
    );
  }

  @override
  Map<String, Object?> toJson() => {..._base(this), 'isTyping': isTyping};
}

class PresenceUpdateSignal extends SignalMessage {
  const PresenceUpdateSignal({
    required super.senderId,
    required super.recipientId,
    required super.timestamp,
    required this.isOnline,
    required this.lastSeen,
    this.hideLastSeen = false,
  });

  final bool isOnline;
  final DateTime lastSeen;
  final bool hideLastSeen;

  @override
  String get type => 'presence_update';

  factory PresenceUpdateSignal.fromJson(Map<String, Object?> json) =>
      PresenceUpdateSignal(
        senderId: json['senderId'] as String? ?? '',
        recipientId: json['recipientId'] as String? ?? '',
        timestamp: _dt(json['timestamp']),
        isOnline: json['isOnline'] as bool? ?? false,
        lastSeen: _dt(json['lastSeen']),
        hideLastSeen: json['hideLastSeen'] as bool? ?? false,
      );

  @override
  Map<String, Object?> toJson() => {
    ..._base(this),
    'isOnline': isOnline,
    'lastSeen': lastSeen.millisecondsSinceEpoch,
    'hideLastSeen': hideLastSeen,
  };
}

class PresenceSubscribeSignal extends SignalMessage {
  const PresenceSubscribeSignal({
    required super.senderId,
    required super.recipientId,
    required super.timestamp,
  });

  @override
  String get type => 'presence_subscribe';

  factory PresenceSubscribeSignal.fromJson(Map<String, Object?> json) =>
      PresenceSubscribeSignal(
        senderId: json['senderId'] as String? ?? '',
        recipientId: json['recipientId'] as String? ?? '',
        timestamp: _dt(json['timestamp']),
      );

  @override
  Map<String, Object?> toJson() => _base(this);
}

class PresenceUnsubscribeSignal extends PresenceSubscribeSignal {
  const PresenceUnsubscribeSignal({
    required super.senderId,
    required super.recipientId,
    required super.timestamp,
  });

  @override
  String get type => 'presence_unsubscribe';

  factory PresenceUnsubscribeSignal.fromJson(Map<String, Object?> json) =>
      PresenceUnsubscribeSignal(
        senderId: json['senderId'] as String? ?? '',
        recipientId: json['recipientId'] as String? ?? '',
        timestamp: _dt(json['timestamp']),
      );
}

class DisappearingTimerSignal extends SignalMessage {
  const DisappearingTimerSignal({
    required super.senderId,
    required super.recipientId,
    required super.timestamp,
    required this.durationMs,
    this.conversationId = '',
  });

  final int durationMs;
  final String conversationId;

  @override
  String get type => 'disappearing_timer';

  factory DisappearingTimerSignal.fromJson(Map<String, Object?> json) =>
      DisappearingTimerSignal(
        senderId: json['senderId'] as String? ?? '',
        recipientId: json['recipientId'] as String? ?? '',
        timestamp: _dt(json['timestamp']),
        durationMs: (json['duration'] as num?)?.toInt() ?? 0,
        conversationId: json['conversationId'] as String? ?? '',
      );

  @override
  Map<String, Object?> toJson() => {
    ..._base(this),
    'duration': durationMs,
    'conversationId': conversationId,
  };
}

class CallControlSignal extends SignalMessage {
  const CallControlSignal({
    required super.senderId,
    required super.recipientId,
    required super.timestamp,
    required this.action,
    this.messageId,
    this.groupId,
  });

  final String action;
  final String? messageId;
  final String? groupId;

  @override
  String get type => 'call_control';

  factory CallControlSignal.fromJson(Map<String, Object?> json) {
    return CallControlSignal(
      senderId: json['senderId'] as String? ?? '',
      recipientId: json['recipientId'] as String? ?? '',
      timestamp: _dt(json['timestamp']),
      action: json['action'] as String? ?? '',
      messageId: json['messageId'] as String?,
      groupId: json['groupId'] as String?,
    );
  }

  @override
  Map<String, Object?> toJson() => {
    ..._base(this),
    'action': action,
    if (messageId != null) 'messageId': messageId,
    if (groupId != null) 'groupId': groupId,
  };
}

class CallControlAckSignal extends SignalMessage {
  const CallControlAckSignal({
    super.senderId = 'server',
    required super.recipientId,
    required super.timestamp,
    required this.messageId,
    required this.action,
  });

  final String messageId;
  final String action;

  @override
  String get type => 'call_control_ack';

  factory CallControlAckSignal.fromJson(Map<String, Object?> json) =>
      CallControlAckSignal(
        senderId: json['senderId'] as String? ?? 'server',
        recipientId: json['recipientId'] as String? ?? '',
        timestamp: _dt(json['timestamp']),
        messageId: json['messageId'] as String? ?? '',
        action: json['action'] as String? ?? '',
      );

  @override
  Map<String, Object?> toJson() => {
    ..._base(this),
    'messageId': messageId,
    'action': action,
  };
}

class SessionResetRequestSignal extends SignalMessage {
  const SessionResetRequestSignal({
    required super.senderId,
    required super.recipientId,
    required super.timestamp,
    required this.reason,
  });

  final String reason;

  @override
  String get type => 'session_reset_request';

  factory SessionResetRequestSignal.fromJson(Map<String, Object?> json) =>
      SessionResetRequestSignal(
        senderId: json['senderId'] as String? ?? '',
        recipientId: json['recipientId'] as String? ?? '',
        timestamp: _dt(json['timestamp']),
        reason: json['reason'] as String? ?? '',
      );

  @override
  Map<String, Object?> toJson() => {..._base(this), 'reason': reason};
}

class SfuRoomCreatedSignal extends SignalMessage {
  const SfuRoomCreatedSignal({
    super.senderId = 'server',
    super.recipientId = 'broadcast',
    required super.timestamp,
    required this.groupId,
    required this.roomId,
    required this.janusWsUrl,
  });

  final String groupId;
  final int roomId;
  final String janusWsUrl;

  @override
  String get type => 'sfu_room_created';

  factory SfuRoomCreatedSignal.fromJson(Map<String, Object?> json) =>
      SfuRoomCreatedSignal(
        senderId: json['senderId'] as String? ?? 'server',
        recipientId: json['recipientId'] as String? ?? 'broadcast',
        timestamp: _dt(json['timestamp']),
        groupId: json['groupId'] as String? ?? '',
        roomId: (json['roomId'] as num?)?.toInt() ?? 0,
        janusWsUrl: json['janusWsUrl'] as String? ?? '',
      );

  @override
  Map<String, Object?> toJson() => {
    ..._base(this),
    'groupId': groupId,
    'roomId': roomId,
    'janusWsUrl': janusWsUrl,
  };
}

class ServerShutdownSignal extends SignalMessage {
  const ServerShutdownSignal({
    super.senderId = 'server',
    super.recipientId = 'broadcast',
    required super.timestamp,
    this.message = '',
  });

  final String message;

  @override
  String get type => 'server_shutdown';

  factory ServerShutdownSignal.fromJson(Map<String, Object?> json) =>
      ServerShutdownSignal(
        senderId: json['senderId'] as String? ?? 'server',
        recipientId: json['recipientId'] as String? ?? 'broadcast',
        timestamp: _dt(json['timestamp']),
        message: json['message'] as String? ?? '',
      );

  @override
  Map<String, Object?> toJson() => {..._base(this), 'message': message};
}

class GroupCallInviteSignal extends SignalMessage {
  const GroupCallInviteSignal({
    required super.senderId,
    required super.recipientId,
    required super.timestamp,
    required this.groupId,
    required this.callType,
    required this.callId,
    required this.participants,
  });

  final String groupId;
  final String callType;
  final String callId;
  final List<String> participants;

  @override
  String get type => 'group_call_invite';

  factory GroupCallInviteSignal.fromJson(Map<String, Object?> json) =>
      GroupCallInviteSignal(
        senderId: json['senderId'] as String? ?? '',
        recipientId: json['recipientId'] as String? ?? '',
        timestamp: _dt(json['timestamp']),
        groupId: json['groupId'] as String? ?? '',
        callType: json['callType'] as String? ?? 'VOICE',
        callId: json['callId'] as String? ?? '',
        participants: _stringList(json['participants']),
      );

  @override
  Map<String, Object?> toJson() => {
    ..._base(this),
    'groupId': groupId,
    'callType': callType,
    'callId': callId,
    'participants': participants,
  };
}

class GroupCallMemberJoinedSignal extends SignalMessage {
  const GroupCallMemberJoinedSignal({
    required super.senderId,
    required super.recipientId,
    required super.timestamp,
    required this.groupCallId,
    required this.joinedMemberId,
  });

  final String groupCallId;
  final String joinedMemberId;

  @override
  String get type => 'group_call_member_joined';

  factory GroupCallMemberJoinedSignal.fromJson(Map<String, Object?> json) =>
      GroupCallMemberJoinedSignal(
        senderId: json['senderId'] as String? ?? '',
        recipientId: json['recipientId'] as String? ?? '',
        timestamp: _dt(json['timestamp']),
        groupCallId: json['groupCallId'] as String? ?? '',
        joinedMemberId: json['joinedMemberId'] as String? ?? '',
      );

  @override
  Map<String, Object?> toJson() => {
    ..._base(this),
    'groupCallId': groupCallId,
    'joinedMemberId': joinedMemberId,
  };
}

class GroupCallMemberLeftSignal extends SignalMessage {
  const GroupCallMemberLeftSignal({
    required super.senderId,
    required super.recipientId,
    required super.timestamp,
    required this.groupCallId,
    required this.groupId,
    required this.leftMemberId,
  });

  final String groupCallId;
  final String groupId;
  final String leftMemberId;

  @override
  String get type => 'group_call_member_left';

  factory GroupCallMemberLeftSignal.fromJson(Map<String, Object?> json) =>
      GroupCallMemberLeftSignal(
        senderId: json['senderId'] as String? ?? 'server',
        recipientId: json['recipientId'] as String? ?? '',
        timestamp: _dt(json['timestamp']),
        groupCallId: json['groupCallId'] as String? ?? '',
        groupId: json['groupId'] as String? ?? '',
        leftMemberId: json['leftMemberId'] as String? ?? '',
      );

  @override
  Map<String, Object?> toJson() => {
    ..._base(this),
    'groupCallId': groupCallId,
    'groupId': groupId,
    'leftMemberId': leftMemberId,
  };
}

class GroupCallCoordinatorChangedSignal extends SignalMessage {
  const GroupCallCoordinatorChangedSignal({
    required super.senderId,
    required super.recipientId,
    required super.timestamp,
    required this.groupCallId,
    required this.groupId,
    required this.newCoordinatorId,
    required this.previousCoordinatorId,
  });

  final String groupCallId;
  final String groupId;
  final String newCoordinatorId;
  final String previousCoordinatorId;

  @override
  String get type => 'group_call_coordinator_changed';

  factory GroupCallCoordinatorChangedSignal.fromJson(
    Map<String, Object?> json,
  ) => GroupCallCoordinatorChangedSignal(
    senderId: json['senderId'] as String? ?? 'server',
    recipientId: json['recipientId'] as String? ?? '',
    timestamp: _dt(json['timestamp']),
    groupCallId: json['groupCallId'] as String? ?? '',
    groupId: json['groupId'] as String? ?? '',
    newCoordinatorId: json['newCoordinatorId'] as String? ?? '',
    previousCoordinatorId: json['previousCoordinatorId'] as String? ?? '',
  );

  @override
  Map<String, Object?> toJson() => {
    ..._base(this),
    'groupCallId': groupCallId,
    'groupId': groupId,
    'newCoordinatorId': newCoordinatorId,
    'previousCoordinatorId': previousCoordinatorId,
  };
}

class GroupCallJoinRequestSignal extends SignalMessage {
  const GroupCallJoinRequestSignal({
    required super.senderId,
    required super.recipientId,
    required super.timestamp,
    required this.groupId,
    required this.callId,
    required this.callType,
  });

  final String groupId;
  final String callId;
  final String callType;

  @override
  String get type => 'group_call_join_request';

  factory GroupCallJoinRequestSignal.fromJson(Map<String, Object?> json) =>
      GroupCallJoinRequestSignal(
        senderId: json['senderId'] as String? ?? '',
        recipientId: json['recipientId'] as String? ?? '',
        timestamp: _dt(json['timestamp']),
        groupId: json['groupId'] as String? ?? '',
        callId: json['callId'] as String? ?? '',
        callType: json['callType'] as String? ?? 'VOICE',
      );

  @override
  Map<String, Object?> toJson() => {
    ..._base(this),
    'groupId': groupId,
    'callId': callId,
    'callType': callType,
  };
}

class GroupCallStatusQuerySignal extends SignalMessage {
  const GroupCallStatusQuerySignal({
    required super.senderId,
    super.recipientId = 'server',
    required super.timestamp,
    required this.groupId,
  });

  final String groupId;

  @override
  String get type => 'group_call_status_query';

  factory GroupCallStatusQuerySignal.fromJson(Map<String, Object?> json) =>
      GroupCallStatusQuerySignal(
        senderId: json['senderId'] as String? ?? '',
        recipientId: json['recipientId'] as String? ?? 'server',
        timestamp: _dt(json['timestamp']),
        groupId: json['groupId'] as String? ?? '',
      );

  @override
  Map<String, Object?> toJson() => {..._base(this), 'groupId': groupId};
}

class GroupCallStatusResponseSignal extends SignalMessage {
  const GroupCallStatusResponseSignal({
    super.senderId = 'server',
    required super.recipientId,
    required super.timestamp,
    required this.groupId,
    required this.isActive,
    this.callId,
    this.coordinatorId,
    this.callType,
    this.participants = const [],
    this.mode,
    this.sfuRoomId,
    this.janusWsUrl,
  });

  final String groupId;
  final bool isActive;
  final String? callId;
  final String? coordinatorId;
  final String? callType;
  final List<String> participants;
  final String? mode;
  final int? sfuRoomId;
  final String? janusWsUrl;

  @override
  String get type => 'group_call_status_response';

  factory GroupCallStatusResponseSignal.fromJson(Map<String, Object?> json) =>
      GroupCallStatusResponseSignal(
        senderId: json['senderId'] as String? ?? 'server',
        recipientId: json['recipientId'] as String? ?? '',
        timestamp: _dt(json['timestamp']),
        groupId: json['groupId'] as String? ?? '',
        isActive: json['isActive'] as bool? ?? false,
        callId: json['callId'] as String?,
        coordinatorId: json['coordinatorId'] as String?,
        callType: json['callType'] as String?,
        participants: _stringList(json['participants']),
        mode: json['mode'] as String?,
        sfuRoomId: (json['sfuRoomId'] as num?)?.toInt(),
        janusWsUrl: json['janusWsUrl'] as String?,
      );

  @override
  Map<String, Object?> toJson() => {
    ..._base(this),
    'groupId': groupId,
    'isActive': isActive,
    if (callId != null) 'callId': callId,
    if (coordinatorId != null) 'coordinatorId': coordinatorId,
    if (callType != null) 'callType': callType,
    'participants': participants,
    if (mode != null) 'mode': mode,
    if (sfuRoomId != null) 'sfuRoomId': sfuRoomId,
    if (janusWsUrl != null) 'janusWsUrl': janusWsUrl,
  };
}

class UnknownSignalMessage extends SignalMessage {
  const UnknownSignalMessage({
    required super.senderId,
    required super.recipientId,
    required super.timestamp,
    required this.rawType,
    required this.raw,
  });

  final String rawType;
  final Map<String, Object?> raw;

  @override
  String get type => rawType;

  factory UnknownSignalMessage.fromJson(Map<String, Object?> json) {
    return UnknownSignalMessage(
      senderId: json['senderId'] as String? ?? '',
      recipientId: json['recipientId'] as String? ?? '',
      timestamp: _dt(json['timestamp']),
      rawType: json['type'] as String? ?? 'unknown',
      raw: json,
    );
  }

  @override
  Map<String, Object?> toJson() => raw;
}
