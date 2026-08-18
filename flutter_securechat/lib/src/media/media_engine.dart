import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'call_models.dart';

typedef LocalIceCandidateHandler =
    FutureOr<void> Function(
      String candidate,
      String? sdpMid,
      int sdpMLineIndex,
    );

enum MediaConnectionState {
  newConnection,
  connecting,
  connected,
  disconnected,
  failed,
  closed,
}

abstract interface class MediaEngine {
  Stream<MediaConnectionState> get connectionStates;
  RTCVideoRenderer get localRenderer;
  RTCVideoRenderer get remoteRenderer;

  Future<String> createOffer({
    required bool video,
    required List<IceServerConfig> iceServers,
    required LocalIceCandidateHandler onIceCandidate,
  });
  Future<String> acceptOffer({
    required String offerSdp,
    required bool video,
    required List<IceServerConfig> iceServers,
    required LocalIceCandidateHandler onIceCandidate,
  });
  Future<void> applyAnswer(String answerSdp);
  Future<void> addIceCandidate({
    required String candidate,
    required String? sdpMid,
    required int sdpMLineIndex,
  });
  Future<void> setMuted(bool muted);
  Future<void> setSpeakerOn(bool enabled);
  Future<void> setCameraEnabled(bool enabled);
  Future<void> switchCamera();
  Future<void> close();
  Future<void> dispose();
}

class WebRtcMediaEngine implements MediaEngine {
  final _states = StreamController<MediaConnectionState>.broadcast();
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  bool _renderersInitialized = false;
  Future<void>? _disposeTask;

  @override
  Stream<MediaConnectionState> get connectionStates => _states.stream;

  @override
  RTCVideoRenderer get localRenderer => _localRenderer;

  @override
  RTCVideoRenderer get remoteRenderer => _remoteRenderer;

  Future<void> _initializeRenderers() async {
    if (_renderersInitialized) return;
    await Future.wait([
      _localRenderer.initialize(),
      _remoteRenderer.initialize(),
    ]);
    _renderersInitialized = true;
  }

  Future<RTCPeerConnection> _prepare({
    required bool video,
    required List<IceServerConfig> iceServers,
    required LocalIceCandidateHandler onIceCandidate,
  }) async {
    await close();
    await _initializeRenderers();
    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': video
          ? {
              'facingMode': 'user',
              'width': {'ideal': 1280},
              'height': {'ideal': 720},
              'frameRate': {'ideal': 30, 'max': 30},
            }
          : false,
    });
    _localStream = stream;
    _localRenderer.srcObject = stream;

    final pc = await createPeerConnection({
      'iceServers': iceServers.map((e) => e.toWebRtcJson()).toList(),
      'sdpSemantics': 'unified-plan',
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
    });
    _peerConnection = pc;
    for (final track in stream.getTracks()) {
      await pc.addTrack(track, stream);
    }
    pc.onIceCandidate = (candidate) {
      final value = candidate.candidate;
      if (value == null || value.isEmpty) return;
      onIceCandidate(value, candidate.sdpMid, candidate.sdpMLineIndex ?? 0);
    };
    pc.onTrack = (event) {
      if (event.streams.isEmpty) return;
      _remoteStream = event.streams.first;
      _remoteRenderer.srcObject = _remoteStream;
    };
    pc.onConnectionState = (state) => _states.add(mapState(state));
    return pc;
  }

  @override
  Future<String> createOffer({
    required bool video,
    required List<IceServerConfig> iceServers,
    required LocalIceCandidateHandler onIceCandidate,
  }) async {
    final pc = await _prepare(
      video: video,
      iceServers: iceServers,
      onIceCandidate: onIceCandidate,
    );
    final offer = await pc.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': video,
    });
    await pc.setLocalDescription(offer);
    final sdp = offer.sdp;
    if (sdp == null || sdp.isEmpty)
      throw StateError('WebRTC SDP offer is empty');
    return sdp;
  }

  @override
  Future<String> acceptOffer({
    required String offerSdp,
    required bool video,
    required List<IceServerConfig> iceServers,
    required LocalIceCandidateHandler onIceCandidate,
  }) async {
    final pc = await _prepare(
      video: video,
      iceServers: iceServers,
      onIceCandidate: onIceCandidate,
    );
    await pc.setRemoteDescription(RTCSessionDescription(offerSdp, 'offer'));
    final answer = await pc.createAnswer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': video,
    });
    await pc.setLocalDescription(answer);
    final sdp = answer.sdp;
    if (sdp == null || sdp.isEmpty) {
      throw StateError('WebRTC SDP answer is empty');
    }
    return sdp;
  }

  @override
  Future<void> applyAnswer(String answerSdp) async {
    final pc = _peerConnection;
    if (pc == null) throw StateError('Peer connection is not initialized');
    await pc.setRemoteDescription(RTCSessionDescription(answerSdp, 'answer'));
  }

  @override
  Future<void> addIceCandidate({
    required String candidate,
    required String? sdpMid,
    required int sdpMLineIndex,
  }) async {
    final pc = _peerConnection;
    if (pc == null) throw StateError('Peer connection is not initialized');
    await pc.addCandidate(RTCIceCandidate(candidate, sdpMid, sdpMLineIndex));
  }

  @override
  Future<void> setMuted(bool muted) async {
    for (final track in _localStream?.getAudioTracks() ?? const []) {
      track.enabled = !muted;
      await Helper.setMicrophoneMute(muted, track);
    }
  }

  @override
  Future<void> setSpeakerOn(bool enabled) => Helper.setSpeakerphoneOn(enabled);

  @override
  Future<void> setCameraEnabled(bool enabled) async {
    for (final track in _localStream?.getVideoTracks() ?? const []) {
      track.enabled = enabled;
    }
  }

  @override
  Future<void> switchCamera() async {
    final tracks = _localStream?.getVideoTracks() ?? const [];
    if (tracks.isEmpty) return;
    await Helper.switchCamera(tracks.first);
  }

  @override
  Future<void> close() async {
    final pc = _peerConnection;
    _peerConnection = null;
    if (pc != null) {
      await pc.close();
      await pc.dispose();
    }
    for (final track in _localStream?.getTracks() ?? const []) {
      await track.stop();
    }
    await _localStream?.dispose();
    await _remoteStream?.dispose();
    _localStream = null;
    _remoteStream = null;
    // flutter_webrtc rejects renderer access before initialize(). `_prepare`
    // deliberately calls close() first so a new call can replace an old one;
    // the very first call must therefore leave never-initialized renderers
    // untouched.
    if (_renderersInitialized) {
      _localRenderer.srcObject = null;
      _remoteRenderer.srcObject = null;
    }
  }

  @override
  Future<void> dispose() {
    final active = _disposeTask;
    if (active != null) return active;
    final operation = _dispose();
    _disposeTask = operation;
    return operation;
  }

  Future<void> _dispose() async {
    await close();
    if (_renderersInitialized) {
      await _localRenderer.dispose();
      await _remoteRenderer.dispose();
    }
    await _states.close();
  }

  static MediaConnectionState mapState(RTCPeerConnectionState state) =>
      switch (state) {
        RTCPeerConnectionState.RTCPeerConnectionStateNew =>
          MediaConnectionState.newConnection,
        RTCPeerConnectionState.RTCPeerConnectionStateConnecting =>
          MediaConnectionState.connecting,
        RTCPeerConnectionState.RTCPeerConnectionStateConnected =>
          MediaConnectionState.connected,
        RTCPeerConnectionState.RTCPeerConnectionStateDisconnected =>
          MediaConnectionState.disconnected,
        RTCPeerConnectionState.RTCPeerConnectionStateFailed =>
          MediaConnectionState.failed,
        RTCPeerConnectionState.RTCPeerConnectionStateClosed =>
          MediaConnectionState.closed,
      };
}
