import 'dart:async';
import 'dart:math';

import '../core/signal_message.dart';
import '../services/crypto_service.dart';
import '../services/session_store.dart';
import '../services/async_operation_tracker.dart';
import '../services/signaling_service.dart';
import '../notifications/missed_call_tracker.dart';
import '../storage/secure_chat_database.dart';
import '../storage/storage_entities.dart';
import 'call_models.dart';
import 'group_media_engine.dart';
import 'ice_server_fetcher.dart';
import 'janus_client.dart';
import 'media_engine.dart';
import 'native_call_integration.dart';

typedef PeerNameResolver = Future<String> Function(String peerId);
typedef JanusClientFactory = JanusClient Function();
typedef GroupLocalIdResolver = Future<String?> Function(String routingToken);
typedef GroupCallPrivacyPreparation =
    Future<String> Function({
      required String groupId,
      required String groupName,
      required List<String> peerIds,
    });

Future<String?> _rejectUnknownGroup(String _) async => null;
Future<String> _identityPeerName(String id) async => id;

class CallManager {
  CallManager({
    required SessionStore session,
    required SignalingService signaling,
    required MediaEngine media,
    GroupMediaEngine? groupMedia,
    required IceServerProvider iceServers,
    required CallLogDao callLogs,
    NativeCallIntegration? nativeCalls,
    JanusClientFactory? janusClientFactory,
    PeerNameResolver? peerNameResolver,
    GroupLocalIdResolver? groupLocalIdResolver,
    GroupCallPrivacyPreparation? preparePrivateGroupCall,
    MissedCallLifecycle? missedCalls,
    this.ringTimeout = const Duration(seconds: 60),
    this.reconnectTimeout = const Duration(seconds: 15),
    this.terminalVisibility = const Duration(milliseconds: 900),
    AsyncOperationFailureHandler? onAsyncFailure,
  }) : _session = session,
       _signaling = signaling,
       _media = media,
       _groupMedia = groupMedia,
       _iceServers = iceServers,
       _callLogs = callLogs,
       _nativeCalls = nativeCalls,
       _janusClientFactory = janusClientFactory ?? JanusClient.new,
       _missedCalls = missedCalls,
       _peerNameResolver = peerNameResolver ?? _identityPeerName,
       _groupLocalIdResolver = groupLocalIdResolver ?? _rejectUnknownGroup,
       _preparePrivateGroupCall = preparePrivateGroupCall,
       _operations = AsyncOperationTracker(onFailure: onAsyncFailure) {
    _signalSubscription = signaling.incoming.listen(_handleSignal);
    _mediaSubscription = media.connectionStates.listen(_handleMediaState);
    _nativeSubscription = nativeCalls?.actions.listen(_handleNativeAction);
    _groupMediaSubscription = groupMedia?.peerStates.listen(
      _handleGroupPeerState,
    );
  }

  final SessionStore _session;
  final SignalingService _signaling;
  final MediaEngine _media;
  final GroupMediaEngine? _groupMedia;
  final IceServerProvider _iceServers;
  final CallLogDao _callLogs;
  final NativeCallIntegration? _nativeCalls;
  final JanusClientFactory _janusClientFactory;
  final PeerNameResolver _peerNameResolver;
  final GroupLocalIdResolver _groupLocalIdResolver;
  final GroupCallPrivacyPreparation? _preparePrivateGroupCall;
  final MissedCallLifecycle? _missedCalls;
  final Duration ringTimeout;
  final Duration reconnectTimeout;
  final Duration terminalVisibility;
  final _sessions = StreamController<CallSession?>.broadcast();
  final _secondarySessions = StreamController<CallSession?>.broadcast();
  final _openRequests = StreamController<void>.broadcast();
  bool _hasPendingOpenRequest = false;
  final Map<String, Completer<void>> _controlAcks = {};
  final AsyncOperationTracker _operations;
  final List<IceCandidateSignal> _pendingIce = [];
  final Random _random = Random.secure();
  late final StreamSubscription<SignalMessage> _signalSubscription;
  late final StreamSubscription<MediaConnectionState> _mediaSubscription;
  StreamSubscription<NativeCallAction>? _nativeSubscription;
  StreamSubscription<GroupPeerState>? _groupMediaSubscription;
  StreamSubscription<JanusEvent>? _janusSubscription;
  CallSession? _current;
  CallSession? _secondary;
  String? _pendingOffer;
  String? _secondaryOffer;
  Timer? _ringTimer;
  Timer? _reconnectTimer;
  Timer? _terminalTimer;
  bool _terminating = false;
  bool _isGroupCoordinator = false;
  String? _currentGroupRoutingToken;
  final Map<String, String> _pendingGroupOffers = {};
  final Map<String, List<IceCandidateSignal>> _pendingGroupIce = {};
  final Map<int, String> _sfuFeedPeers = {};
  JanusClient? _janus;
  bool _disposed = false;
  Future<void>? _disposeTask;

  Stream<CallSession?> get sessions async* {
    yield _current;
    yield* _sessions.stream;
  }

  Stream<CallSession?> get secondarySessions async* {
    yield _secondary;
    yield* _secondarySessions.stream;
  }

  Stream<void> get openRequests async* {
    if (_hasPendingOpenRequest) {
      _hasPendingOpenRequest = false;
      yield null;
    }
    yield* _openRequests.stream;
  }

  CallSession? get currentSession => _current;
  CallSession? get secondarySession => _secondary;
  MediaEngine get media => _media;
  GroupMediaEngine? get groupMedia => _groupMedia;

  Future<bool> initiateCall({
    required String peerId,
    required String peerName,
    required CallType callType,
  }) async {
    final userId = _requireUserId();
    if (_hasLiveCall) return false;
    _terminating = false;
    final session = CallSession(
      callId: _newId(),
      peerId: peerId,
      peerName: peerName,
      callType: callType,
      direction: CallDirection.outgoing,
      state: CallState.initiating,
      isSpeakerOn: callType == CallType.video,
    );
    _setSession(session);
    try {
      await _nativeCalls?.reportOutgoing(session);
      if (!await _signaling.ensureConnected(
        timeout: const Duration(seconds: 8),
      )) {
        throw StateError('Signaling connection is unavailable');
      }
      final servers = await _iceServers.fetch();
      final offer = await _media.createOffer(
        video: callType == CallType.video,
        iceServers: servers,
        onIceCandidate: (candidate, mid, line) => _sendIce(
          userId: userId,
          peerId: peerId,
          candidate: candidate,
          sdpMid: mid,
          sdpMLineIndex: line,
        ),
      );
      final sent = await _signaling.send(
        SdpOfferSignal(
          senderId: userId,
          recipientId: peerId,
          timestamp: DateTime.now(),
          sdp: offer,
          callType: callType.name.toUpperCase(),
        ),
      );
      if (!sent) throw StateError('SDP offer could not be delivered');
      _setSession(session.copyWith(state: CallState.ringing));
      _startRingTimeout();
      return true;
    } catch (_) {
      await _finish(CallState.failed, notifyPeer: false);
      return false;
    }
  }

  Future<bool> initiateGroupCall({
    required String groupId,
    required String groupName,
    required List<String> peerIds,
    required CallType callType,
  }) async {
    final groupMedia = _groupMedia;
    final userId = _requireUserId();
    if (_hasLiveCall || groupMedia == null) return false;
    final recipients = peerIds.where((id) => id != userId).toSet().toList();
    if (recipients.isEmpty) return false;
    _terminating = false;
    _isGroupCoordinator = true;
    final session = CallSession(
      callId: _newId(),
      peerId: groupId,
      peerName: groupName,
      callType: callType,
      direction: CallDirection.outgoing,
      state: CallState.initiating,
      startTime: DateTime.now(),
      isSpeakerOn: true,
      isGroupCall: true,
      groupId: groupId,
      peerIds: recipients,
    );
    _setSession(session);
    try {
      final routingToken = _preparePrivateGroupCall == null
          ? await groupRoutingToken(groupId)
          : await _preparePrivateGroupCall(
              groupId: groupId,
              groupName: groupName,
              peerIds: [...recipients, userId],
            );
      _currentGroupRoutingToken = routingToken;
      if (!await _signaling.ensureConnected(
        timeout: const Duration(seconds: 8),
      )) {
        throw StateError('Signaling connection is unavailable');
      }
      await groupMedia.initialize(
        video: callType == CallType.video,
        iceServers: await _iceServers.fetch(),
      );
      var allSent = true;
      for (final peerId in recipients) {
        final sent = await _signaling.send(
          GroupCallInviteSignal(
            senderId: userId,
            recipientId: peerId,
            timestamp: DateTime.now(),
            groupId: routingToken,
            callType: callType.name.toUpperCase(),
            callId: session.callId,
            // The target already appears in recipientId and the coordinator in
            // senderId. Repeating the full social graph here only leaks data.
            participants: const [],
          ),
        );
        allSent = allSent && sent;
      }
      if (!allSent) throw StateError('One or more group invites failed');
      _setSession(session.copyWith(state: CallState.active));
      return true;
    } catch (_) {
      await _finish(CallState.failed, notifyPeer: true);
      return false;
    }
  }

  Future<bool> acceptCall() async {
    final session = _current;
    if (session == null ||
        session.direction != CallDirection.incoming ||
        session.state != CallState.ringing) {
      return false;
    }
    if (session.isGroupCall) return _acceptGroupCall(session);
    final offer = _pendingOffer;
    if (offer == null) return false;
    final userId = _requireUserId();
    _ringTimer?.cancel();
    _missedCalls?.cancel(session.callId);
    _setSession(session.copyWith(state: CallState.connecting));
    try {
      await _sendControl(session.peerId, 'ACCEPT', reliable: false);
      final answer = await _media.acceptOffer(
        offerSdp: offer,
        video: session.callType == CallType.video,
        iceServers: await _iceServers.fetch(),
        onIceCandidate: (candidate, mid, line) => _sendIce(
          userId: userId,
          peerId: session.peerId,
          candidate: candidate,
          sdpMid: mid,
          sdpMLineIndex: line,
        ),
      );
      final sent = await _signaling.send(
        SdpAnswerSignal(
          senderId: userId,
          recipientId: session.peerId,
          timestamp: DateTime.now(),
          sdp: answer,
        ),
      );
      if (!sent) throw StateError('SDP answer could not be delivered');
      _pendingOffer = null;
      await _replayPendingIce();
      return true;
    } catch (_) {
      await _finish(CallState.failed, notifyPeer: true);
      return false;
    }
  }

  Future<bool> _acceptGroupCall(CallSession session) async {
    final groupMedia = _groupMedia;
    if (groupMedia == null) return false;
    _ringTimer?.cancel();
    _missedCalls?.cancel(session.callId);
    try {
      await groupMedia.initialize(
        video: session.callType == CallType.video,
        iceServers: await _iceServers.fetch(),
      );
      await _sendControl(
        session.peerId,
        'ACCEPT',
        reliable: false,
        groupId: _currentGroupRoutingToken,
      );
      _setSession(
        session.copyWith(state: CallState.active, startTime: DateTime.now()),
      );
      final offers = Map<String, String>.from(_pendingGroupOffers);
      _pendingGroupOffers.clear();
      for (final entry in offers.entries) {
        await _acceptGroupPeerOffer(entry.key, entry.value);
      }
      return true;
    } catch (_) {
      await _finish(CallState.failed, notifyPeer: true);
      return false;
    }
  }

  Future<void> rejectCall() => _finish(CallState.rejected, action: 'REJECT');

  Future<void> endCall() => _finish(CallState.ended, action: 'HANGUP');

  Future<void> acceptSecondaryCall() async {
    final secondary = _secondary;
    final offer = _secondaryOffer;
    if (secondary == null || offer == null) return;
    await endCall();
    _secondary = null;
    _secondaryOffer = null;
    _secondarySessions.add(null);
    _pendingOffer = offer;
    _setSession(secondary);
    await acceptCall();
  }

  Future<void> rejectSecondaryCall() async {
    final secondary = _secondary;
    if (secondary == null) return;
    await _sendControl(secondary.peerId, 'REJECT', reliable: true);
    await _saveLog(secondary, CallState.rejected);
    _secondary = null;
    _secondaryOffer = null;
    _secondarySessions.add(null);
  }

  Future<void> toggleMute() async {
    final session = _current;
    if (session == null || session.isTerminal) return;
    final muted = !session.isMuted;
    if (session.isGroupCall) {
      await _groupMedia?.setMuted(muted);
    } else {
      await _media.setMuted(muted);
    }
    _setSession(session.copyWith(isMuted: muted));
  }

  Future<void> toggleSpeaker() async {
    final session = _current;
    if (session == null || session.isTerminal) return;
    final enabled = !session.isSpeakerOn;
    if (session.isGroupCall) {
      await _groupMedia?.setSpeakerOn(enabled);
    } else {
      await _media.setSpeakerOn(enabled);
    }
    _setSession(session.copyWith(isSpeakerOn: enabled));
  }

  Future<void> toggleCamera() async {
    final session = _current;
    if (session == null || session.callType != CallType.video) return;
    final enabled = !session.isCameraEnabled;
    if (session.isGroupCall) {
      await _groupMedia?.setCameraEnabled(enabled);
    } else {
      await _media.setCameraEnabled(enabled);
    }
    _setSession(session.copyWith(isCameraEnabled: enabled));
    await _sendControl(
      session.peerId,
      enabled ? 'CAMERA_ON' : 'CAMERA_OFF',
      reliable: false,
      groupId: session.isGroupCall ? _currentGroupRoutingToken : null,
    );
  }

  Future<void> switchCamera() async {
    final session = _current;
    if (session == null || session.callType != CallType.video) return;
    if (session.isGroupCall) {
      await _groupMedia?.switchCamera();
    } else {
      await _media.switchCamera();
    }
    _setSession(
      session.copyWith(isUsingFrontCamera: !session.isUsingFrontCamera),
    );
  }

  Duration? get currentDuration {
    final start = _current?.startTime;
    return start == null ? null : DateTime.now().difference(start);
  }

  bool get _hasLiveCall => _current != null && !_current!.isTerminal;

  void _handleSignal(SignalMessage signal) {
    if (_disposed) return;
    final userId = _session.userId;
    if (userId == null ||
        (signal.recipientId != userId && signal.recipientId != 'broadcast')) {
      return;
    }
    switch (signal) {
      case SdpOfferSignal():
        _track(_handleOffer(signal));
      case SdpAnswerSignal():
        _track(_handleAnswer(signal));
      case IceCandidateSignal():
        _track(_handleIce(signal));
      case CallControlSignal():
        _track(_handleControl(signal));
      case CallControlAckSignal():
        _controlAcks.remove(signal.messageId)?.complete();
      case GroupCallInviteSignal():
        _track(_handleGroupInvite(signal));
      case GroupCallMemberJoinedSignal():
        _track(_handleGroupMemberJoined(signal));
      case GroupCallMemberLeftSignal():
        _track(_handleGroupMemberLeft(signal));
      case GroupCallCoordinatorChangedSignal():
        _track(_handleCoordinatorChanged(signal));
      case SfuRoomCreatedSignal():
        _track(_bindSfuRoom(signal));
      case GroupCallStatusResponseSignal():
        _track(_handleGroupStatus(signal));
      default:
        break;
    }
  }

  Future<void> _handleOffer(SdpOfferSignal signal) async {
    final current = _current;
    if (current?.isGroupCall == true &&
        current!.peerIds.contains(signal.senderId)) {
      if (current.state == CallState.ringing) {
        _pendingGroupOffers[signal.senderId] = signal.sdp;
      } else if (current.state == CallState.active) {
        await _acceptGroupPeerOffer(signal.senderId, signal.sdp);
      }
      return;
    }
    final type = signal.callType.toUpperCase() == 'VIDEO'
        ? CallType.video
        : CallType.voice;
    final incoming = CallSession(
      callId: _newId(),
      peerId: signal.senderId,
      peerName: await _peerNameResolver(signal.senderId),
      callType: type,
      direction: CallDirection.incoming,
      state: CallState.ringing,
      isSpeakerOn: type == CallType.video,
    );
    if (_hasLiveCall) {
      if (_secondary == null) {
        _secondary = incoming;
        _secondaryOffer = signal.sdp;
        _secondarySessions.add(incoming);
      } else {
        await _sendControl(signal.senderId, 'BUSY', reliable: false);
        await _saveLog(incoming, CallState.busy);
      }
      return;
    }
    _terminating = false;
    _pendingOffer = signal.sdp;
    _pendingIce.clear();
    _setSession(incoming);
    await _nativeCalls?.reportIncoming(incoming);
    _missedCalls?.start(incoming);
    await _sendControl(signal.senderId, 'RINGING', reliable: false);
    _startRingTimeout();
  }

  Future<void> _handleAnswer(SdpAnswerSignal signal) async {
    final session = _current;
    if (session?.isGroupCall == true) {
      try {
        await _groupMedia?.applyAnswer(
          peerId: signal.senderId,
          answerSdp: signal.sdp,
        );
        await _replayGroupIce(signal.senderId);
      } catch (_) {
        // A late answer from a peer already removed is safely ignored.
      }
      return;
    }
    if (session == null ||
        session.peerId != signal.senderId ||
        session.direction != CallDirection.outgoing) {
      return;
    }
    try {
      _ringTimer?.cancel();
      _setSession(session.copyWith(state: CallState.connecting));
      await _media.applyAnswer(signal.sdp);
      await _replayPendingIce();
    } catch (_) {
      await _finish(CallState.failed, notifyPeer: true);
    }
  }

  Future<void> _handleIce(IceCandidateSignal signal) async {
    final session = _current;
    if (session == null) return;
    if (session.isGroupCall) {
      try {
        await _groupMedia?.addIceCandidate(
          peerId: signal.senderId,
          candidate: signal.candidate,
          sdpMid: signal.sdpMid,
          sdpMLineIndex: signal.sdpMLineIndex,
        );
      } catch (_) {
        _pendingGroupIce.putIfAbsent(signal.senderId, () => []).add(signal);
      }
      return;
    }
    if (session.peerId != signal.senderId) return;
    if (session.state == CallState.ringing &&
        session.direction == CallDirection.incoming) {
      _pendingIce.add(signal);
      return;
    }
    try {
      await _media.addIceCandidate(
        candidate: signal.candidate,
        sdpMid: signal.sdpMid,
        sdpMLineIndex: signal.sdpMLineIndex,
      );
    } catch (_) {
      _pendingIce.add(signal);
    }
  }

  Future<void> _replayPendingIce() async {
    final buffered = List<IceCandidateSignal>.from(_pendingIce);
    _pendingIce.clear();
    for (final signal in buffered) {
      try {
        await _media.addIceCandidate(
          candidate: signal.candidate,
          sdpMid: signal.sdpMid,
          sdpMLineIndex: signal.sdpMLineIndex,
        );
      } catch (_) {
        _pendingIce.add(signal);
      }
    }
  }

  Future<void> _handleControl(CallControlSignal signal) async {
    final session = _current;
    if (session == null) return;
    if (session.isGroupCall) {
      if (signal.groupId == null ||
          signal.groupId != _currentGroupRoutingToken) {
        return;
      }
      switch (signal.action.toUpperCase()) {
        case 'ACCEPT':
          if (_isGroupCoordinator &&
              session.peerIds.contains(signal.senderId)) {
            await _connectNewGroupMember(signal.senderId);
          }
        case 'REJECT' || 'BUSY':
          await _removeGroupPeer(signal.senderId);
        case 'HANGUP':
          if (signal.senderId == 'server' ||
              signal.senderId == session.peerId) {
            await _finish(CallState.ended, notifyPeer: false);
          } else {
            await _removeGroupPeer(signal.senderId);
          }
        case 'CAMERA_OFF' || 'CAMERA_ON' || 'RINGING':
          break;
      }
      return;
    }
    if (session.peerId != signal.senderId) return;
    switch (signal.action.toUpperCase()) {
      case 'ACCEPT':
        _ringTimer?.cancel();
        if (session.state == CallState.ringing) {
          _setSession(session.copyWith(state: CallState.connecting));
        }
      case 'REJECT':
        await _finish(CallState.rejected, notifyPeer: false);
      case 'BUSY':
        await _finish(CallState.busy, notifyPeer: false);
      case 'HANGUP':
        await _finish(CallState.ended, notifyPeer: false);
      case 'CAMERA_OFF':
        _setSession(session.copyWith(isRemoteCameraEnabled: false));
      case 'CAMERA_ON':
        _setSession(session.copyWith(isRemoteCameraEnabled: true));
      case 'RINGING':
        break;
    }
  }

  Future<void> _handleGroupInvite(GroupCallInviteSignal signal) async {
    final localGroupId = await _groupLocalIdResolver(signal.groupId);
    if (localGroupId == null || localGroupId.isEmpty) {
      await _sendControl(
        'server',
        'HANGUP',
        reliable: false,
        groupId: signal.groupId,
      );
      return;
    }
    if (_hasLiveCall) {
      await _sendControl(
        signal.senderId,
        'BUSY',
        reliable: false,
        groupId: signal.groupId,
      );
      await _sendControl(
        'server',
        'HANGUP',
        reliable: false,
        groupId: signal.groupId,
      );
      return;
    }
    final userId = _requireUserId();
    _terminating = false;
    _isGroupCoordinator = false;
    _currentGroupRoutingToken = signal.groupId;
    _pendingGroupOffers.clear();
    _pendingGroupIce.clear();
    final session = CallSession(
      callId: signal.callId,
      peerId: signal.senderId,
      peerName: await _peerNameResolver(localGroupId),
      callType: signal.callType.toUpperCase() == 'VIDEO'
          ? CallType.video
          : CallType.voice,
      direction: CallDirection.incoming,
      state: CallState.ringing,
      isSpeakerOn: true,
      isGroupCall: true,
      groupId: localGroupId,
      peerIds: {
        signal.senderId,
        ...signal.participants.where((id) => id != userId),
      }.where((id) => id.isNotEmpty && id != userId).toList(),
    );
    _setSession(session);
    await _nativeCalls?.reportIncoming(session);
    _missedCalls?.start(session);
    _startRingTimeout();
  }

  Future<void> _connectNewGroupMember(String memberId) async {
    final session = _current;
    final userId = _requireUserId();
    if (session == null || !session.isGroupCall || _groupMedia == null) return;
    for (final peerId in session.connectedPeerIds) {
      if (peerId == memberId || peerId.startsWith('sfu:')) continue;
      await _signaling.send(
        GroupCallMemberJoinedSignal(
          senderId: userId,
          recipientId: peerId,
          timestamp: DateTime.now(),
          groupCallId: session.callId,
          joinedMemberId: memberId,
        ),
      );
    }
    await _offerToGroupPeer(memberId);
  }

  Future<void> _handleGroupMemberJoined(
    GroupCallMemberJoinedSignal signal,
  ) async {
    final session = _current;
    if (session == null ||
        !session.isGroupCall ||
        session.callId != signal.groupCallId ||
        signal.joinedMemberId == _session.userId) {
      return;
    }
    if (!session.peerIds.contains(signal.joinedMemberId)) {
      _setSession(
        session.copyWith(peerIds: [...session.peerIds, signal.joinedMemberId]),
      );
    }
    await _offerToGroupPeer(signal.joinedMemberId);
  }

  Future<void> _offerToGroupPeer(String peerId) async {
    final groupMedia = _groupMedia;
    final session = _current;
    final userId = _requireUserId();
    if (groupMedia == null || session == null || !session.isGroupCall) return;
    final offer = await groupMedia.createOffer(
      peerId: peerId,
      onIceCandidate: (candidate, mid, line) => _sendIce(
        userId: userId,
        peerId: peerId,
        candidate: candidate,
        sdpMid: mid,
        sdpMLineIndex: line,
      ),
    );
    await _signaling.send(
      SdpOfferSignal(
        senderId: userId,
        recipientId: peerId,
        timestamp: DateTime.now(),
        sdp: offer,
        callType: session.callType.name.toUpperCase(),
      ),
    );
    await _replayGroupIce(peerId);
  }

  Future<void> _acceptGroupPeerOffer(String peerId, String offerSdp) async {
    final groupMedia = _groupMedia;
    final session = _current;
    final userId = _requireUserId();
    if (groupMedia == null || session == null || !session.isGroupCall) return;
    final answer = await groupMedia.acceptOffer(
      peerId: peerId,
      offerSdp: offerSdp,
      onIceCandidate: (candidate, mid, line) => _sendIce(
        userId: userId,
        peerId: peerId,
        candidate: candidate,
        sdpMid: mid,
        sdpMLineIndex: line,
      ),
    );
    await _signaling.send(
      SdpAnswerSignal(
        senderId: userId,
        recipientId: peerId,
        timestamp: DateTime.now(),
        sdp: answer,
      ),
    );
    await _replayGroupIce(peerId);
  }

  Future<void> _replayGroupIce(String peerId) async {
    final buffered = _pendingGroupIce.remove(peerId) ?? const [];
    for (final signal in buffered) {
      try {
        await _groupMedia?.addIceCandidate(
          peerId: peerId,
          candidate: signal.candidate,
          sdpMid: signal.sdpMid,
          sdpMLineIndex: signal.sdpMLineIndex,
        );
      } catch (_) {
        _pendingGroupIce.putIfAbsent(peerId, () => []).add(signal);
      }
    }
  }

  Future<void> _handleGroupMemberLeft(GroupCallMemberLeftSignal signal) async {
    final session = _current;
    if (session == null ||
        !session.isGroupCall ||
        session.callId != signal.groupCallId ||
        signal.groupId != _currentGroupRoutingToken) {
      return;
    }
    await _removeGroupPeer(signal.leftMemberId);
  }

  Future<void> _removeGroupPeer(String peerId) async {
    final session = _current;
    if (session == null || !session.isGroupCall) return;
    await _groupMedia?.removePeer(peerId);
    _pendingGroupOffers.remove(peerId);
    _pendingGroupIce.remove(peerId);
    final peers = session.peerIds.where((id) => id != peerId).toList();
    final connected = session.connectedPeerIds
        .where((id) => id != peerId)
        .toList();
    _setSession(session.copyWith(peerIds: peers, connectedPeerIds: connected));
    if (peers.isEmpty) await _finish(CallState.ended, notifyPeer: false);
  }

  Future<void> _handleCoordinatorChanged(
    GroupCallCoordinatorChangedSignal signal,
  ) async {
    final session = _current;
    if (session == null ||
        !session.isGroupCall ||
        session.callId != signal.groupCallId ||
        signal.groupId != _currentGroupRoutingToken) {
      return;
    }
    _isGroupCoordinator = signal.newCoordinatorId == _session.userId;
    _setSession(
      session.copyWith(
        peerId: signal.newCoordinatorId,
        peerName: await _peerNameResolver(session.groupId!),
      ),
    );
  }

  void _handleGroupPeerState(GroupPeerState update) {
    final session = _current;
    if (session == null || !session.isGroupCall || session.isTerminal) return;
    final connected = session.connectedPeerIds.toSet();
    switch (update.state) {
      case MediaConnectionState.connected:
        connected.add(update.peerId);
      case MediaConnectionState.failed || MediaConnectionState.closed:
        connected.remove(update.peerId);
      case MediaConnectionState.newConnection ||
          MediaConnectionState.connecting ||
          MediaConnectionState.disconnected:
        break;
    }
    _setSession(session.copyWith(connectedPeerIds: connected.toList()));
  }

  Future<void> _handleGroupStatus(GroupCallStatusResponseSignal signal) async {
    final session = _current;
    if (session == null ||
        !session.isGroupCall ||
        signal.groupId != _currentGroupRoutingToken) {
      return;
    }
    if (!signal.isActive) {
      await _finish(CallState.ended, notifyPeer: false);
      return;
    }
    if (signal.mode?.toUpperCase() == 'SFU' &&
        signal.sfuRoomId != null &&
        signal.janusWsUrl != null) {
      await _bindSfu(roomId: signal.sfuRoomId!, janusWsUrl: signal.janusWsUrl!);
    }
  }

  Future<void> _bindSfuRoom(SfuRoomCreatedSignal signal) async {
    final session = _current;
    if (session == null ||
        !session.isGroupCall ||
        signal.groupId != _currentGroupRoutingToken) {
      return;
    }
    await _bindSfu(roomId: signal.roomId, janusWsUrl: signal.janusWsUrl);
  }

  Future<void> _bindSfu({
    required int roomId,
    required String janusWsUrl,
  }) async {
    final session = _current;
    final groupMedia = _groupMedia;
    final userId = _requireUserId();
    final token = _session.accessToken;
    if (session == null ||
        groupMedia == null ||
        token == null ||
        session.isSfuMode) {
      return;
    }
    final janus = _janusClientFactory();
    try {
      if (!await janus.connect(url: janusWsUrl, accessToken: token)) {
        throw StateError('Janus connection failed');
      }
      await janus.createSession();
      await janus.attachVideoRoom();
      final publishers = await janus.joinAsPublisher(
        roomId: roomId,
        displayName: userId,
      );
      for (final peer in session.peerIds) {
        await groupMedia.removePeer(peer);
      }
      final offer = await groupMedia.createSfuPublisherOffer(
        onIceCandidate: (candidate, mid, line) => janus.trickleIce(
          handleId: janus.publisherHandleId,
          candidate: candidate,
          sdpMid: mid,
          sdpMLineIndex: line,
        ),
      );
      await groupMedia.applySfuPublisherAnswer(await janus.publishSdp(offer));
      await _janus?.dispose();
      await _janusSubscription?.cancel();
      _janus = janus;
      _janusSubscription = janus.events.listen(_handleJanusEvent);
      for (final publisher in publishers) {
        await _subscribeToSfuFeed(publisher.$1, publisher.$2);
      }
      _setSession(
        session.copyWith(
          isSfuMode: true,
          sfuRoomId: roomId,
          connectedPeerIds: const [],
        ),
      );
    } catch (_) {
      await janus.dispose();
      await _finish(CallState.failed, notifyPeer: true);
    }
  }

  void _handleJanusEvent(JanusEvent event) {
    if (_disposed) return;
    switch (event) {
      case JanusPublisherJoined():
        _track(_subscribeToSfuFeed(event.feedId, event.displayName));
      case JanusPublisherLeft():
        _sfuFeedPeers.remove(event.feedId);
        final operation = _groupMedia?.removeSfuFeed(event.feedId);
        if (operation != null) _track(operation);
      case JanusRemoteOffer():
        _track(_answerSfuOffer(event.feedId, event.sdp));
      case JanusRemoteAnswer():
        final operation = _groupMedia?.applySfuPublisherAnswer(event.sdp);
        if (operation != null) _track(operation);
    }
  }

  Future<void> _subscribeToSfuFeed(int feedId, String? displayName) async {
    final janus = _janus;
    if (janus == null || _groupMedia == null) return;
    _sfuFeedPeers[feedId] = displayName ?? 'feed_$feedId';
    await _answerSfuOffer(feedId, await janus.subscribeToFeed(feedId));
  }

  Future<void> _answerSfuOffer(int feedId, String offerSdp) async {
    final janus = _janus;
    final groupMedia = _groupMedia;
    if (janus == null || groupMedia == null) return;
    final answer = await groupMedia.acceptSfuSubscriberOffer(
      feedId: feedId,
      offerSdp: offerSdp,
      onIceCandidate: (candidate, mid, line) {
        final handle = janus.subscriberHandleId(feedId);
        if (handle != null) {
          janus.trickleIce(
            handleId: handle,
            candidate: candidate,
            sdpMid: mid,
            sdpMLineIndex: line,
          );
        }
      },
    );
    await janus.answerSubscription(feedId: feedId, answerSdp: answer);
  }

  void _handleMediaState(MediaConnectionState state) {
    if (_disposed) return;
    final session = _current;
    if (session == null || session.isTerminal) return;
    switch (state) {
      case MediaConnectionState.connected:
        _ringTimer?.cancel();
        _reconnectTimer?.cancel();
        _setSession(
          session.copyWith(
            state: CallState.active,
            startTime: session.startTime ?? DateTime.now(),
          ),
        );
        final operation = _nativeCalls?.setActive(session.callId);
        if (operation != null) _track(operation);
      case MediaConnectionState.disconnected:
        if (session.state == CallState.active) {
          _setSession(session.copyWith(state: CallState.reconnecting));
          _reconnectTimer?.cancel();
          _reconnectTimer = Timer(
            reconnectTimeout,
            () => _track(_finish(CallState.failed, notifyPeer: true)),
          );
        }
      case MediaConnectionState.failed:
        _track(_finish(CallState.failed, notifyPeer: true));
      case MediaConnectionState.closed:
        if (!_terminating) {
          _track(_finish(CallState.ended, notifyPeer: false));
        }
      case MediaConnectionState.newConnection:
      case MediaConnectionState.connecting:
        break;
    }
  }

  Future<void> _finish(
    CallState finalState, {
    String? action,
    bool notifyPeer = true,
  }) async {
    final session = _current;
    if (session == null || _terminating) return;
    _terminating = true;
    _ringTimer?.cancel();
    if (session.direction == CallDirection.incoming &&
        session.state == CallState.ringing &&
        finalState != CallState.rejected &&
        finalState != CallState.busy) {
      await _missedCalls?.triggerNow(session);
    } else {
      _missedCalls?.cancel(session.callId);
    }
    _reconnectTimer?.cancel();
    if (notifyPeer && session.isGroupCall) {
      for (final peerId in session.peerIds) {
        await _sendControl(
          peerId,
          action ?? 'HANGUP',
          reliable: true,
          groupId: _currentGroupRoutingToken,
        );
      }
      await _sendControl(
        'server',
        action ?? 'HANGUP',
        reliable: false,
        groupId: _currentGroupRoutingToken,
      );
    } else if (notifyPeer) {
      await _sendControl(session.peerId, action ?? 'HANGUP', reliable: true);
    }
    final duration = session.startTime == null
        ? Duration.zero
        : DateTime.now().difference(session.startTime!);
    if (session.isGroupCall) {
      await _janusSubscription?.cancel();
      _janusSubscription = null;
      await _janus?.leaveRoom();
      await _janus?.dispose();
      _janus = null;
      _sfuFeedPeers.clear();
      await _groupMedia?.close();
    } else {
      await _media.close();
    }
    await _nativeCalls?.end(session.callId);
    await _saveLog(session, finalState, duration: duration);
    _setSession(session.copyWith(state: finalState, duration: duration));
    _pendingOffer = null;
    _pendingIce.clear();
    _terminalTimer?.cancel();
    _terminalTimer = Timer(terminalVisibility, () {
      _current = null;
      _currentGroupRoutingToken = null;
      _sessions.add(null);
      _terminating = false;
    });
  }

  Future<void> _saveLog(
    CallSession session,
    CallState finalState, {
    Duration duration = Duration.zero,
  }) {
    final status = switch (finalState) {
      CallState.rejected => 'REJECTED',
      CallState.failed => 'FAILED',
      CallState.busy => 'BUSY',
      CallState.ended => duration > Duration.zero ? 'ANSWERED' : 'MISSED',
      _ => duration > Duration.zero ? 'ANSWERED' : 'MISSED',
    };
    return _callLogs.insert(
      CallLogEntity(
        id: session.callId,
        peerId: session.peerId,
        peerName: session.peerName,
        callType: session.callType.name.toUpperCase(),
        direction: session.direction.name.toUpperCase(),
        status: status,
        timestamp: (session.startTime ?? DateTime.now()).millisecondsSinceEpoch,
        duration: duration.inMilliseconds,
      ),
    );
  }

  Future<void> _sendIce({
    required String userId,
    required String peerId,
    required String candidate,
    required String? sdpMid,
    required int sdpMLineIndex,
  }) async {
    await _signaling.send(
      IceCandidateSignal(
        senderId: userId,
        recipientId: peerId,
        timestamp: DateTime.now(),
        candidate: candidate,
        sdpMid: sdpMid,
        sdpMLineIndex: sdpMLineIndex,
      ),
    );
  }

  Future<bool> _sendControl(
    String peerId,
    String action, {
    required bool reliable,
    String? groupId,
  }) async {
    final userId = _session.userId;
    if (userId == null) return false;
    final messageId = reliable ? _newId() : null;
    final signal = CallControlSignal(
      senderId: userId,
      recipientId: peerId,
      timestamp: DateTime.now(),
      action: action,
      messageId: messageId,
      groupId: groupId,
    );
    if (!reliable) return _signaling.send(signal);
    final ack = Completer<void>();
    _controlAcks[messageId!] = ack;
    try {
      for (var attempt = 0; attempt < 3; attempt++) {
        if (await _signaling.send(signal)) {
          try {
            await ack.future.timeout(const Duration(milliseconds: 650));
            return true;
          } on TimeoutException {
            // Retry using the same message id so the server can de-duplicate it.
          }
        }
        await _signaling.ensureConnected(timeout: const Duration(seconds: 2));
      }
      return false;
    } finally {
      _controlAcks.remove(messageId);
    }
  }

  void _startRingTimeout() {
    _ringTimer?.cancel();
    _ringTimer = Timer(
      ringTimeout,
      () => _track(_finish(CallState.failed, notifyPeer: true)),
    );
  }

  void _setSession(CallSession session) {
    _current = session;
    _sessions.add(session);
  }

  void _handleNativeAction(NativeCallAction action) {
    if (_disposed) return;
    final session = _current;
    if (session == null || session.callId != action.callId) return;
    switch (action.type) {
      case NativeCallActionType.answer:
        _requestCallOpen();
        _track(acceptCall());
      case NativeCallActionType.end:
        _track(endCall());
      case NativeCallActionType.mute:
        if (!session.isMuted) _track(toggleMute());
      case NativeCallActionType.unmute:
        if (session.isMuted) _track(toggleMute());
      case NativeCallActionType.open:
        _requestCallOpen();
    }
  }

  String _requireUserId() {
    final value = _session.userId;
    if (value == null || value.isEmpty) {
      throw StateError('A logged-in user is required for calls');
    }
    return value;
  }

  String _newId() {
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final random = List.generate(
      4,
      (_) => _random.nextInt(0x100000000).toRadixString(16).padLeft(8, '0'),
    ).join();
    return '$now-$random';
  }

  Future<void> dispose() {
    final active = _disposeTask;
    if (active != null) return active;
    _disposed = true;
    final operation = _dispose();
    _disposeTask = operation;
    return operation;
  }

  Future<void> _dispose() async {
    _ringTimer?.cancel();
    _reconnectTimer?.cancel();
    _terminalTimer?.cancel();
    await _signalSubscription.cancel();
    await _mediaSubscription.cancel();
    await _nativeSubscription?.cancel();
    await _groupMediaSubscription?.cancel();
    await _janusSubscription?.cancel();
    for (final ack in _controlAcks.values) {
      if (!ack.isCompleted) {
        ack.completeError(StateError('Call manager disposed'));
      }
    }
    _controlAcks.clear();
    _currentGroupRoutingToken = null;
    await _operations.close();
    await _janus?.dispose();
    await _media.dispose();
    await _groupMedia?.dispose();
    await _missedCalls?.close();
    await _sessions.close();
    await _secondarySessions.close();
    await _openRequests.close();
  }

  void _track(Future<dynamic> operation) {
    if (!_operations.isClosed) {
      _operations.run('call-manager.callback', operation);
    }
  }

  void _requestCallOpen() {
    if (_openRequests.hasListener) {
      _openRequests.add(null);
    } else {
      _hasPendingOpenRequest = true;
    }
  }
}
