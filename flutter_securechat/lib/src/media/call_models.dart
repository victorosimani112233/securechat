enum CallType { voice, video }

enum CallDirection { incoming, outgoing }

enum CallState {
  idle,
  initiating,
  ringing,
  connecting,
  active,
  reconnecting,
  ended,
  rejected,
  busy,
  failed,
}

class CallSession {
  const CallSession({
    required this.callId,
    required this.peerId,
    required this.peerName,
    required this.callType,
    required this.direction,
    required this.state,
    this.startTime,
    this.duration,
    this.isMuted = false,
    this.isSpeakerOn = false,
    this.isCameraEnabled = true,
    this.isUsingFrontCamera = true,
    this.isRemoteCameraEnabled = true,
    this.isGroupCall = false,
    this.groupId,
    this.peerIds = const [],
    this.connectedPeerIds = const [],
    this.isSfuMode = false,
    this.sfuRoomId = 0,
  });

  final String callId;
  final String peerId;
  final String peerName;
  final CallType callType;
  final CallDirection direction;
  final CallState state;
  final DateTime? startTime;
  final Duration? duration;
  final bool isMuted;
  final bool isSpeakerOn;
  final bool isCameraEnabled;
  final bool isUsingFrontCamera;
  final bool isRemoteCameraEnabled;
  final bool isGroupCall;
  final String? groupId;
  final List<String> peerIds;
  final List<String> connectedPeerIds;
  final bool isSfuMode;
  final int sfuRoomId;

  bool get isTerminal => const {
    CallState.ended,
    CallState.rejected,
    CallState.busy,
    CallState.failed,
  }.contains(state);

  CallSession copyWith({
    String? peerId,
    String? peerName,
    CallState? state,
    DateTime? startTime,
    bool clearStartTime = false,
    Duration? duration,
    bool? isMuted,
    bool? isSpeakerOn,
    bool? isCameraEnabled,
    bool? isUsingFrontCamera,
    bool? isRemoteCameraEnabled,
    List<String>? connectedPeerIds,
    List<String>? peerIds,
    bool? isSfuMode,
    int? sfuRoomId,
  }) => CallSession(
    callId: callId,
    peerId: peerId ?? this.peerId,
    peerName: peerName ?? this.peerName,
    callType: callType,
    direction: direction,
    state: state ?? this.state,
    startTime: clearStartTime ? null : startTime ?? this.startTime,
    duration: duration ?? this.duration,
    isMuted: isMuted ?? this.isMuted,
    isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
    isCameraEnabled: isCameraEnabled ?? this.isCameraEnabled,
    isUsingFrontCamera: isUsingFrontCamera ?? this.isUsingFrontCamera,
    isRemoteCameraEnabled: isRemoteCameraEnabled ?? this.isRemoteCameraEnabled,
    isGroupCall: isGroupCall,
    groupId: groupId,
    peerIds: peerIds ?? this.peerIds,
    connectedPeerIds: connectedPeerIds ?? this.connectedPeerIds,
    isSfuMode: isSfuMode ?? this.isSfuMode,
    sfuRoomId: sfuRoomId ?? this.sfuRoomId,
  );
}

class IceServerConfig {
  const IceServerConfig({required this.urls, this.username, this.credential});

  final List<String> urls;
  final String? username;
  final String? credential;

  Map<String, Object> toWebRtcJson() => {
    'urls': urls,
    if (username != null) 'username': username!,
    if (credential != null) 'credential': credential!,
  };
}
