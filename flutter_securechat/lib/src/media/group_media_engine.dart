import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'call_media_key.dart';
import 'call_models.dart';
import 'media_engine.dart';

class GroupPeerState {
  const GroupPeerState(this.peerId, this.state);
  final String peerId;
  final MediaConnectionState state;
}

abstract interface class GroupMediaEngine {
  Stream<GroupPeerState> get peerStates;
  RTCVideoRenderer get localRenderer;
  Map<String, RTCVideoRenderer> get remoteRenderers;

  Future<void> initialize({
    required bool video,
    required List<IceServerConfig> iceServers,
  });
  Future<String> createOffer({
    required String peerId,
    required LocalIceCandidateHandler onIceCandidate,
  });
  Future<String> acceptOffer({
    required String peerId,
    required String offerSdp,
    required LocalIceCandidateHandler onIceCandidate,
  });
  Future<void> applyAnswer({required String peerId, required String answerSdp});
  Future<void> addIceCandidate({
    required String peerId,
    required String candidate,
    required String? sdpMid,
    required int sdpMLineIndex,
  });
  Future<String> createSfuPublisherOffer({
    required LocalIceCandidateHandler onIceCandidate,
  });
  Future<void> applySfuPublisherAnswer(String answerSdp);
  Future<String> acceptSfuSubscriberOffer({
    required int feedId,
    required String offerSdp,
    required LocalIceCandidateHandler onIceCandidate,
  });
  Future<void> addSfuSubscriberIce({
    required int feedId,
    required String candidate,
    required String? sdpMid,
    required int sdpMLineIndex,
  });

  /// Medya frame sifrelemesini acar.
  ///
  /// SFU yolunda WebRTC oturumu Janus'ta sonlanir; bu katman olmadan medya
  /// sunucunun guven sinirinin icinde kalir. Baglantilar kurulmadan **once**
  /// cagrilmalidir, aksi halde ilk frame'ler sifresiz gider.
  ///
  /// Platform destegi yoksa hata firlatir; cagiran mesh'te kalmalidir.
  Future<void> enableMediaEncryption(CallMediaKey mediaKey);

  /// Uyelik degisiminde yeni kusaga gecer.
  Future<void> rotateMediaKey(CallMediaKey mediaKey);

  /// Frame sifrelemesi su an etkin mi.
  bool get mediaEncryptionEnabled;

  Future<void> removePeer(String peerId);
  Future<void> removeSfuFeed(int feedId);
  Future<void> setMuted(bool muted);
  Future<void> setSpeakerOn(bool enabled);
  Future<void> setCameraEnabled(bool enabled);
  Future<void> switchCamera();
  Future<void> close();
  Future<void> dispose();
}

class WebRtcGroupMediaEngine implements GroupMediaEngine {
  final _peerStates = StreamController<GroupPeerState>.broadcast();
  final _localRenderer = RTCVideoRenderer();
  final Map<String, RTCPeerConnection> _connections = {};
  final Map<String, RTCVideoRenderer> _renderers = {};
  final Map<String, MediaStream> _remoteStreams = {};
  MediaStream? _localStream;
  List<IceServerConfig> _iceServers = const [];
  bool _video = false;
  bool _localRendererInitialized = false;
  Future<void>? _disposeTask;

  static const _sfuPublisherKey = 'sfu:publisher';
  static String _sfuSubscriberKey(int feedId) => 'sfu:$feedId';

  /// Frame sifreleme durumu.
  ///
  /// Anahtar halkasi tum katilimcilar icin ortaktir: cagri basina tek medya
  /// anahtari vardir ve kusak, anahtar indeksi olarak tasinir.
  KeyProvider? _keyProvider;
  CallMediaKey? _mediaKey;
  final Map<String, List<FrameCryptor>> _cryptors = {};

  @override
  bool get mediaEncryptionEnabled => _mediaKey != null;

  @override
  Future<void> enableMediaEncryption(CallMediaKey mediaKey) async {
    if (_mediaKey != null && _mediaKey!.callId != mediaKey.callId) {
      throw StateError('Close the previous call before installing a new key');
    }
    final provider = _keyProvider ??= await frameCryptorFactory
        .createDefaultKeyProvider(
          KeyProviderOptions(
            // Cagri basina tek ortak anahtar; kusak anahtar indeksidir.
            sharedKey: true,
            ratchetSalt: _ratchetSalt(mediaKey.callId),
            ratchetWindowSize: 0,
            keyRingSize: CallMediaKey.keyRingSize,
            // Anahtar hazir degilken frame acik gonderilmez, dusurulur.
            discardFrameWhenCryptorNotReady: true,
          ),
        );
    await provider.setSharedKey(key: mediaKey.key, index: mediaKey.keyIndex);
    _mediaKey = mediaKey;
  }

  @override
  Future<void> rotateMediaKey(CallMediaKey mediaKey) async {
    final provider = _keyProvider;
    if (provider == null) {
      // Henuz acilmadiysa rotasyon acilis demektir.
      await enableMediaEncryption(mediaKey);
      return;
    }
    await provider.setSharedKey(key: mediaKey.key, index: mediaKey.keyIndex);
    for (final cryptors in _cryptors.values) {
      for (final cryptor in cryptors) {
        await cryptor.setKeyIndex(mediaKey.keyIndex);
      }
    }
    _mediaKey = mediaKey;
  }

  /// Salt cagriya baglidir; sabit bir deger tum aramalarda ayni turetmeyi
  /// verirdi.
  static Uint8List _ratchetSalt(String callId) =>
      Uint8List.fromList('securechat-call-$callId'.codeUnits);

  Future<void> _attachSenderCryptors(String key, RTCPeerConnection pc) async {
    final mediaKey = _mediaKey;
    final provider = _keyProvider;
    if (mediaKey == null || provider == null) return;
    for (final sender in await pc.getSenders()) {
      final cryptor = await frameCryptorFactory.createFrameCryptorForRtpSender(
        participantId: _participantId,
        sender: sender,
        algorithm: Algorithm.kAesGcm,
        keyProvider: provider,
      );
      await cryptor.setKeyIndex(mediaKey.keyIndex);
      await cryptor.setEnabled(true);
      _cryptors.putIfAbsent(key, () => []).add(cryptor);
    }
  }

  Future<void> _attachReceiverCryptor(
    String key,
    RTCRtpReceiver? receiver,
  ) async {
    final mediaKey = _mediaKey;
    final provider = _keyProvider;
    if (mediaKey == null || provider == null || receiver == null) return;
    final cryptor = await frameCryptorFactory.createFrameCryptorForRtpReceiver(
      participantId: key,
      receiver: receiver,
      algorithm: Algorithm.kAesGcm,
      keyProvider: provider,
    );
    await cryptor.setKeyIndex(mediaKey.keyIndex);
    await cryptor.setEnabled(true);
    _cryptors.putIfAbsent(key, () => []).add(cryptor);
  }

  Future<void> _attachReceiverCryptors(String key, RTCPeerConnection pc) async {
    for (final receiver in await pc.getReceivers()) {
      await _attachReceiverCryptor(key, receiver);
    }
  }

  /// Kendi gonderdigimiz frame'lerin katilimci etiketi.
  static const String _participantId = 'self';

  @override
  Stream<GroupPeerState> get peerStates => _peerStates.stream;

  @override
  RTCVideoRenderer get localRenderer => _localRenderer;

  @override
  Map<String, RTCVideoRenderer> get remoteRenderers =>
      Map.unmodifiable(_renderers);

  @override
  Future<void> initialize({
    required bool video,
    required List<IceServerConfig> iceServers,
  }) async {
    await close();
    _video = video;
    _iceServers = List.unmodifiable(iceServers);
    if (!_localRendererInitialized) {
      await _localRenderer.initialize();
      _localRendererInitialized = true;
    }
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': video
          ? {
              'facingMode': 'user',
              'width': {'ideal': 960},
              'height': {'ideal': 540},
              'frameRate': {'ideal': 24, 'max': 30},
            }
          : false,
    });
    _localRenderer.srcObject = _localStream;
    await Helper.setSpeakerphoneOn(true);
  }

  @override
  Future<String> createOffer({
    required String peerId,
    required LocalIceCandidateHandler onIceCandidate,
  }) async {
    final pc = await _createConnection(
      key: peerId,
      onIceCandidate: onIceCandidate,
      publishLocalTracks: true,
    );
    final offer = await pc.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': _video,
    });
    await pc.setLocalDescription(offer);
    return _requireSdp(offer, 'group offer');
  }

  @override
  Future<String> acceptOffer({
    required String peerId,
    required String offerSdp,
    required LocalIceCandidateHandler onIceCandidate,
  }) async {
    final pc = await _createConnection(
      key: peerId,
      onIceCandidate: onIceCandidate,
      publishLocalTracks: true,
    );
    await pc.setRemoteDescription(RTCSessionDescription(offerSdp, 'offer'));
    await _attachReceiverCryptors(peerId, pc);
    final answer = await pc.createAnswer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': _video,
    });
    await pc.setLocalDescription(answer);
    return _requireSdp(answer, 'group answer');
  }

  @override
  Future<void> applyAnswer({
    required String peerId,
    required String answerSdp,
  }) async {
    final pc = _connections[peerId];
    if (pc == null)
      throw StateError('Group peer connection is missing: $peerId');
    await pc.setRemoteDescription(RTCSessionDescription(answerSdp, 'answer'));
    await _attachReceiverCryptors(peerId, pc);
  }

  @override
  Future<void> addIceCandidate({
    required String peerId,
    required String candidate,
    required String? sdpMid,
    required int sdpMLineIndex,
  }) async {
    final pc = _connections[peerId];
    if (pc == null)
      throw StateError('Group peer connection is missing: $peerId');
    await pc.addCandidate(RTCIceCandidate(candidate, sdpMid, sdpMLineIndex));
  }

  @override
  Future<String> createSfuPublisherOffer({
    required LocalIceCandidateHandler onIceCandidate,
  }) async {
    final pc = await _createConnection(
      key: _sfuPublisherKey,
      onIceCandidate: onIceCandidate,
      publishLocalTracks: true,
      renderRemote: false,
    );
    final offer = await pc.createOffer({
      'offerToReceiveAudio': false,
      'offerToReceiveVideo': false,
    });
    await pc.setLocalDescription(offer);
    return _requireSdp(offer, 'SFU publisher offer');
  }

  @override
  Future<void> applySfuPublisherAnswer(String answerSdp) async {
    final pc = _connections[_sfuPublisherKey];
    if (pc == null) throw StateError('SFU publisher connection is missing');
    await pc.setRemoteDescription(RTCSessionDescription(answerSdp, 'answer'));
  }

  @override
  Future<String> acceptSfuSubscriberOffer({
    required int feedId,
    required String offerSdp,
    required LocalIceCandidateHandler onIceCandidate,
  }) async {
    final key = _sfuSubscriberKey(feedId);
    final pc = await _createConnection(
      key: key,
      onIceCandidate: onIceCandidate,
      publishLocalTracks: false,
    );
    await pc.setRemoteDescription(RTCSessionDescription(offerSdp, 'offer'));
    await _attachReceiverCryptors(key, pc);
    final answer = await pc.createAnswer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': _video,
    });
    await pc.setLocalDescription(answer);
    return _requireSdp(answer, 'SFU subscriber answer');
  }

  @override
  Future<void> addSfuSubscriberIce({
    required int feedId,
    required String candidate,
    required String? sdpMid,
    required int sdpMLineIndex,
  }) => addIceCandidate(
    peerId: _sfuSubscriberKey(feedId),
    candidate: candidate,
    sdpMid: sdpMid,
    sdpMLineIndex: sdpMLineIndex,
  );

  Future<RTCPeerConnection> _createConnection({
    required String key,
    required LocalIceCandidateHandler onIceCandidate,
    required bool publishLocalTracks,
    bool renderRemote = true,
  }) async {
    await _disposeConnection(key);
    final pc = await createPeerConnection({
      'iceServers': _iceServers.map((server) => server.toWebRtcJson()).toList(),
      'sdpSemantics': 'unified-plan',
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
    });
    _connections[key] = pc;
    if (publishLocalTracks) {
      final stream = _localStream;
      if (stream == null)
        throw StateError('Group local media is not initialized');
      for (final track in stream.getTracks()) {
        await pc.addTrack(track, stream);
      }
    }
    pc.onIceCandidate = (candidate) {
      final value = candidate.candidate;
      if (value == null || value.isEmpty) return;
      onIceCandidate(value, candidate.sdpMid, candidate.sdpMLineIndex ?? 0);
    };
    // Sifreleme acikken cryptor'lar frame akmadan once baglanmalidir.
    await _attachSenderCryptors(key, pc);
    if (renderRemote) {
      pc.onTrack = (event) {
        unawaited(_attachRemoteStream(key, event));
      };
    }
    pc.onConnectionState = (state) {
      _peerStates.add(GroupPeerState(key, WebRtcMediaEngine.mapState(state)));
    };
    return pc;
  }

  Future<void> _attachRemoteStream(String key, RTCTrackEvent event) async {
    if (event.streams.isEmpty) return;
    var renderer = _renderers[key];
    if (renderer == null) {
      renderer = RTCVideoRenderer();
      await renderer.initialize();
      _renderers[key] = renderer;
    }
    _remoteStreams[key] = event.streams.first;
    renderer.srcObject = event.streams.first;
  }

  @override
  Future<void> removePeer(String peerId) => _disposeConnection(peerId);

  @override
  Future<void> removeSfuFeed(int feedId) =>
      _disposeConnection(_sfuSubscriberKey(feedId));

  Future<void> _disposeConnection(String key) async {
    for (final cryptor in _cryptors.remove(key) ?? const <FrameCryptor>[]) {
      await cryptor.dispose();
    }
    final pc = _connections.remove(key);
    if (pc != null) {
      await pc.close();
      await pc.dispose();
    }
    await _remoteStreams.remove(key)?.dispose();
    final renderer = _renderers.remove(key);
    if (renderer != null) await renderer.dispose();
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
    if (tracks.isNotEmpty) await Helper.switchCamera(tracks.first);
  }

  @override
  Future<void> close() async {
    final keys = _connections.keys.toList(growable: false);
    for (final key in keys) {
      await _disposeConnection(key);
    }
    for (final track in _localStream?.getTracks() ?? const []) {
      await track.stop();
    }
    await _localStream?.dispose();
    _localStream = null;
    if (_localRendererInitialized) _localRenderer.srcObject = null;
    _mediaKey = null;
    final provider = _keyProvider;
    _keyProvider = null;
    await provider?.dispose();
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
    if (_localRendererInitialized) await _localRenderer.dispose();
    await _peerStates.close();
  }

  static String _requireSdp(RTCSessionDescription value, String label) {
    final sdp = value.sdp;
    if (sdp == null || sdp.isEmpty) throw StateError('$label is empty');
    return sdp;
  }
}
