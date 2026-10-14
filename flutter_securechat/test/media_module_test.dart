import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'package:flutter_securechat/src/calls/call_history_service.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/media/call_manager.dart';
import 'package:flutter_securechat/src/media/call_media_key.dart';
import 'package:flutter_securechat/src/media/call_models.dart';
import 'package:flutter_securechat/src/media/file_transfer_manager.dart';
import 'package:flutter_securechat/src/media/group_media_engine.dart';
import 'package:flutter_securechat/src/media/ice_server_fetcher.dart';
import 'package:flutter_securechat/src/media/media_engine.dart';
import 'package:flutter_securechat/src/media/native_call_integration.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'outgoing call performs SDP/ICE flow and records completed call',
    () async {
      final fixture = await _Fixture.open();
      addTearDown(fixture.dispose);
      final signaling = InMemorySignalingService();
      await signaling.connect(
        userId: 'me',
        url: 'wss://test.invalid',
        accessToken: 'token',
      );
      final media = _FakeMediaEngine();
      final manager = CallManager(
        session: SessionStore(userId: 'me', accessToken: 'token'),
        signaling: signaling,
        media: media,
        iceServers: const StaticIceServerProvider([
          IceServerConfig(urls: ['stun:test.invalid']),
        ]),
        callLogs: fixture.database.callLogs,
        terminalVisibility: const Duration(minutes: 1),
      );
      addTearDown(manager.dispose);

      expect(
        await manager.initiateCall(
          peerId: 'peer',
          peerName: 'Peer Name',
          callType: CallType.video,
        ),
        isTrue,
      );
      expect(manager.currentSession?.state, CallState.ringing);
      expect(
        signaling.sentMessages.whereType<SdpOfferSignal>().single.sdp,
        'offer',
      );

      signaling.addIncoming(
        SdpAnswerSignal(
          senderId: 'peer',
          recipientId: 'me',
          timestamp: DateTime.now(),
          sdp: 'answer',
        ),
      );
      await _flush();
      expect(media.appliedAnswer, 'answer');
      media.emit(MediaConnectionState.connected);
      await _flush();
      expect(manager.currentSession?.state, CallState.active);

      signaling.addIncoming(
        CallControlSignal(
          senderId: 'peer',
          recipientId: 'me',
          timestamp: DateTime.now(),
          action: 'HANGUP',
        ),
      );
      final logs = await fixture.database.callLogs.getAll().firstWhere(
        (values) => values.isNotEmpty,
      );
      expect(logs.single.peerName, 'Peer Name');
      expect(logs.single.callType, 'VIDEO');
      expect(logs.single.status, 'ANSWERED');
      final history = await CallHistoryService(
        fixture.database.callLogs,
      ).watchAll().first;
      expect(history.single.callType, CallType.video);
      expect(history.single.direction, CallDirection.outgoing);
      expect(history.single.status, CallHistoryStatus.completed);
      expect(history.single.id, logs.single.id);
      expect(
        history.single.timestamp.millisecondsSinceEpoch,
        logs.single.timestamp,
      );
      final peerHistory = await CallHistoryService(
        fixture.database.callLogs,
      ).watchPeer('peer').first;
      expect(peerHistory.map((entry) => entry.id), [logs.single.id]);
      expect(
        await CallHistoryService(
          fixture.database.callLogs,
        ).watchPeer('somebody-else').first,
        isEmpty,
      );
    },
  );

  test('incoming call buffers ICE and creates SDP answer on accept', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.dispose);
    final signaling = InMemorySignalingService();
    await signaling.connect(
      userId: 'me',
      url: 'wss://test.invalid',
      accessToken: 'token',
    );
    final media = _FakeMediaEngine();
    final manager = CallManager(
      session: SessionStore(userId: 'me', accessToken: 'token'),
      signaling: signaling,
      media: media,
      iceServers: const StaticIceServerProvider([]),
      callLogs: fixture.database.callLogs,
      terminalVisibility: const Duration(minutes: 1),
    );
    addTearDown(manager.dispose);

    signaling.addIncoming(
      SdpOfferSignal(
        senderId: 'caller',
        recipientId: 'me',
        timestamp: DateTime.now(),
        sdp: 'remote-offer',
        callType: 'VOICE',
      ),
    );
    signaling.addIncoming(
      IceCandidateSignal(
        senderId: 'caller',
        recipientId: 'me',
        timestamp: DateTime.now(),
        candidate: 'candidate',
        sdpMid: 'audio',
        sdpMLineIndex: 0,
      ),
    );
    await _flush();
    expect(manager.currentSession?.direction, CallDirection.incoming);
    expect(manager.currentSession?.state, CallState.ringing);
    expect(await manager.acceptCall(), isTrue);
    expect(media.acceptedOffer, 'remote-offer');
    expect(media.candidates.single.$1, 'candidate');
    expect(
      signaling.sentMessages.whereType<SdpAnswerSignal>().single.sdp,
      'answer',
    );
  });

  test('call from a blocked user never rings and gets no reply', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.dispose);
    final signaling = InMemorySignalingService();
    await signaling.connect(
      userId: 'me',
      url: 'wss://test.invalid',
      accessToken: 'token',
    );
    final nativeCalls = _FakeNativeCalls();
    final manager = CallManager(
      session: SessionStore(userId: 'me', accessToken: 'token'),
      signaling: signaling,
      media: _FakeMediaEngine(),
      iceServers: const StaticIceServerProvider([]),
      callLogs: fixture.database.callLogs,
      nativeCalls: nativeCalls,
      isBlocked: (userId) => userId == 'blocked',
    );
    addTearDown(manager.dispose);
    signaling.sentMessages.clear();

    signaling.addIncoming(
      SdpOfferSignal(
        senderId: 'blocked',
        recipientId: 'me',
        timestamp: DateTime.now(),
        sdp: 'remote-offer',
        callType: 'VOICE',
      ),
    );
    await _flush();

    expect(manager.currentSession, isNull);
    expect(nativeCalls.reported, isEmpty);
    expect(nativeCalls.dismissed, 1);
    expect(signaling.sentMessages.whereType<CallControlSignal>(), isEmpty);
    expect(
      await CallHistoryService(
        fixture.database.callLogs,
      ).watchPeer('blocked').first,
      isEmpty,
    );
  });

  test('native open action requests the active Flutter call route', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.dispose);
    final signaling = InMemorySignalingService();
    await signaling.connect(
      userId: 'me',
      url: 'wss://test.invalid',
      accessToken: 'token',
    );
    final nativeCalls = _FakeNativeCalls();
    final manager = CallManager(
      session: SessionStore(userId: 'me', accessToken: 'token'),
      signaling: signaling,
      media: _FakeMediaEngine(),
      iceServers: const StaticIceServerProvider([]),
      callLogs: fixture.database.callLogs,
      nativeCalls: nativeCalls,
      terminalVisibility: const Duration(minutes: 1),
    );
    addTearDown(manager.dispose);

    signaling.addIncoming(
      SdpOfferSignal(
        senderId: 'caller',
        recipientId: 'me',
        timestamp: DateTime.now(),
        sdp: 'remote-offer',
        callType: 'VOICE',
      ),
    );
    await _flush();
    final callId = manager.currentSession!.callId;
    final openRequest = manager.openRequests.first;

    nativeCalls.emit(NativeCallActionType.open, callId);

    await expectLater(openRequest, completes);
  });

  test('speaker routing prefers Telecom and falls back to WebRTC', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.dispose);
    final signaling = InMemorySignalingService();
    await signaling.connect(
      userId: 'me',
      url: 'wss://test.invalid',
      accessToken: 'token',
    );
    final media = _FakeMediaEngine();
    final nativeCalls = _FakeNativeCalls()..handlesSpeaker = true;
    final manager = CallManager(
      session: SessionStore(userId: 'me', accessToken: 'token'),
      signaling: signaling,
      media: media,
      iceServers: const StaticIceServerProvider([]),
      callLogs: fixture.database.callLogs,
      nativeCalls: nativeCalls,
      terminalVisibility: const Duration(minutes: 1),
    );
    addTearDown(manager.dispose);

    expect(
      await manager.initiateCall(
        peerId: 'peer',
        peerName: 'Peer',
        callType: CallType.voice,
      ),
      isTrue,
    );
    final callId = manager.currentSession!.callId;

    await manager.toggleSpeaker();

    expect(nativeCalls.speakerRequests, [(callId, true)]);
    expect(media.speakerValues, isEmpty);
    expect(manager.currentSession?.isSpeakerOn, isTrue);

    nativeCalls.emit(NativeCallActionType.speakerOff, callId);
    await _flush();
    expect(manager.currentSession?.isSpeakerOn, isFalse);

    nativeCalls.handlesSpeaker = false;
    await manager.toggleSpeaker();
    expect(media.speakerValues, [true]);
    expect(manager.currentSession?.isSpeakerOn, isTrue);
  });

  group('QA 2026-10-12 Bulgu 5 speaker route', () {
    Future<(CallManager, _FakeMediaEngine, _FakeNativeCalls)> connectedCall(
      CallType type, {
      bool handlesSpeaker = true,
    }) async {
      final fixture = await _Fixture.open();
      addTearDown(fixture.dispose);
      final signaling = InMemorySignalingService();
      await signaling.connect(
        userId: 'me',
        url: 'wss://test.invalid',
        accessToken: 'token',
      );
      final media = _FakeMediaEngine();
      final nativeCalls = _FakeNativeCalls()..handlesSpeaker = handlesSpeaker;
      final manager = CallManager(
        session: SessionStore(userId: 'me', accessToken: 'token'),
        signaling: signaling,
        media: media,
        iceServers: const StaticIceServerProvider([]),
        callLogs: fixture.database.callLogs,
        nativeCalls: nativeCalls,
        terminalVisibility: const Duration(minutes: 1),
      );
      addTearDown(manager.dispose);
      expect(
        await manager.initiateCall(
          peerId: 'peer',
          peerName: 'Peer',
          callType: type,
        ),
        isTrue,
      );
      // Rota istenmeden UI "hoparlor acik" demez.
      expect(manager.currentSession!.isSpeakerOn, isFalse);
      expect(nativeCalls.speakerRequests, isEmpty);
      signaling.addIncoming(
        SdpAnswerSignal(
          senderId: 'peer',
          recipientId: 'me',
          timestamp: DateTime.now(),
          sdp: 'answer',
        ),
      );
      await _flush();
      media.emit(MediaConnectionState.connected);
      await _flush();
      return (manager, media, nativeCalls);
    }

    test('video call asks Telecom for the speaker once it connects', () async {
      final (manager, media, nativeCalls) = await connectedCall(CallType.video);
      final callId = manager.currentSession!.callId;
      expect(nativeCalls.speakerRequests, [(callId, true)]);
      expect(media.speakerValues, isEmpty);
      expect(manager.currentSession!.isSpeakerOn, isTrue);

      // Yeniden baglanma ikinci bir istek uretmez.
      media.emit(MediaConnectionState.disconnected);
      media.emit(MediaConnectionState.connected);
      await _flush();
      expect(nativeCalls.speakerRequests, hasLength(1));

      // Tek dokunus ahizeye alir (onceden ilk dokunus "kapat" idi).
      await manager.toggleSpeaker();
      expect(nativeCalls.speakerRequests.last, (callId, false));
      expect(manager.currentSession!.isSpeakerOn, isFalse);
    });

    test('video call without Telecom routes through WebRTC', () async {
      final (manager, media, _) = await connectedCall(
        CallType.video,
        handlesSpeaker: false,
      );
      expect(media.speakerValues, [true]);
      expect(manager.currentSession!.isSpeakerOn, isTrue);
    });

    test('voice call stays on the earpiece', () async {
      final (manager, media, nativeCalls) = await connectedCall(CallType.voice);
      expect(nativeCalls.speakerRequests, isEmpty);
      expect(media.speakerValues, isEmpty);
      expect(manager.currentSession!.isSpeakerOn, isFalse);
    });

    test('a failed route request leaves the button state alone', () async {
      final (manager, _, nativeCalls) = await connectedCall(CallType.voice);
      nativeCalls.failSpeaker = true;
      await expectLater(manager.toggleSpeaker(), throwsStateError);
      expect(manager.currentSession!.isSpeakerOn, isFalse);
    });

    test('a route event for another call does not touch this one', () async {
      final (manager, _, nativeCalls) = await connectedCall(CallType.voice);
      nativeCalls.emit(NativeCallActionType.speakerOn, 'another-call');
      await _flush();
      expect(manager.currentSession!.isSpeakerOn, isFalse);
    });
  });

  test(
    'group coordinator fans invites and opens mesh peer after accept',
    () async {
      final fixture = await _Fixture.open();
      addTearDown(fixture.dispose);
      final signaling = InMemorySignalingService();
      await signaling.connect(
        userId: 'me',
        url: 'wss://test.invalid',
        accessToken: 'token',
      );
      final groupMedia = _FakeGroupMediaEngine();
      final callRoutingToken = newOpaqueRoutingNonce();
      final manager = CallManager(
        session: SessionStore(userId: 'me', accessToken: 'token'),
        signaling: signaling,
        media: _FakeMediaEngine(),
        groupMedia: groupMedia,
        iceServers: const StaticIceServerProvider([]),
        callLogs: fixture.database.callLogs,
        preparePrivateGroupCall:
            ({
              required String groupId,
              required String groupName,
              required List<String> peerIds,
            }) async => callRoutingToken,
        terminalVisibility: const Duration(minutes: 1),
      );
      addTearDown(manager.dispose);

      expect(
        await manager.initiateGroupCall(
          groupId: 'group-1',
          groupName: 'Ekip',
          peerIds: const ['me', 'peer-a', 'peer-b'],
          callType: CallType.video,
        ),
        isTrue,
      );
      expect(manager.currentSession?.isGroupCall, isTrue);
      expect(manager.currentSession?.state, CallState.ringing);
      final groupInvites = signaling.sentMessages
          .whereType<GroupCallInviteSignal>()
          .toList();
      expect(groupInvites, hasLength(2));
      expect(
        groupInvites,
        everyElement(
          predicate<GroupCallInviteSignal>(
            (s) => s.groupId == callRoutingToken,
          ),
        ),
      );
      expect(
        groupInvites,
        everyElement(
          predicate<GroupCallInviteSignal>((s) => s.participants.isEmpty),
        ),
      );
      expect(
        jsonEncode(groupInvites.map((s) => s.toJson()).toList()),
        isNot(contains('group-1')),
      );

      signaling.addIncoming(
        CallControlSignal(
          senderId: 'peer-a',
          recipientId: 'me',
          timestamp: DateTime.now(),
          action: 'ACCEPT',
          groupId: callRoutingToken,
        ),
      );
      await _flush();
      expect(groupMedia.offers, ['peer-a']);
      expect(
        signaling.sentMessages.whereType<SdpOfferSignal>().single.recipientId,
        'peer-a',
      );

      signaling.addIncoming(
        SdpAnswerSignal(
          senderId: 'peer-a',
          recipientId: 'me',
          timestamp: DateTime.now(),
          sdp: 'peer-answer',
        ),
      );
      groupMedia.emit('peer-a', MediaConnectionState.connected);
      await _flush();
      expect(groupMedia.answers['peer-a'], 'peer-answer');
      expect(manager.currentSession?.connectedPeerIds, contains('peer-a'));
    },
  );

  test('group call accepts exactly eight total participants', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.dispose);
    final signaling = InMemorySignalingService();
    await signaling.connect(
      userId: 'me',
      url: 'wss://test.invalid',
      accessToken: 'token',
    );
    final manager = CallManager(
      session: SessionStore(userId: 'me', accessToken: 'token'),
      signaling: signaling,
      media: _FakeMediaEngine(),
      groupMedia: _FakeGroupMediaEngine(),
      iceServers: const StaticIceServerProvider([]),
      callLogs: fixture.database.callLogs,
      preparePrivateGroupCall:
          ({
            required String groupId,
            required String groupName,
            required List<String> peerIds,
          }) async => newOpaqueRoutingNonce(),
      terminalVisibility: const Duration(minutes: 1),
    );
    addTearDown(manager.dispose);

    expect(maxGroupCallParticipants, 8);
    expect(
      await manager.initiateGroupCall(
        groupId: 'group-at-limit',
        groupName: 'Ekip',
        peerIds: [
          'me',
          ...List.generate(maxGroupCallParticipants - 1, (i) => 'peer-$i'),
        ],
        callType: CallType.video,
      ),
      isTrue,
    );
    expect(
      signaling.sentMessages.whereType<GroupCallInviteSignal>(),
      hasLength(maxGroupCallParticipants - 1),
    );
  });

  test('group call rejects a ninth participant before signaling', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.dispose);
    final signaling = InMemorySignalingService();
    await signaling.connect(
      userId: 'me',
      url: 'wss://test.invalid',
      accessToken: 'token',
    );
    final groupMedia = _FakeGroupMediaEngine();
    final manager = CallManager(
      session: SessionStore(userId: 'me', accessToken: 'token'),
      signaling: signaling,
      media: _FakeMediaEngine(),
      groupMedia: groupMedia,
      iceServers: const StaticIceServerProvider([]),
      callLogs: fixture.database.callLogs,
      preparePrivateGroupCall:
          ({
            required String groupId,
            required String groupName,
            required List<String> peerIds,
          }) async => newOpaqueRoutingNonce(),
      terminalVisibility: const Duration(minutes: 1),
    );
    addTearDown(manager.dispose);

    expect(
      await manager.initiateGroupCall(
        groupId: 'group-over-limit',
        groupName: 'Ekip',
        peerIds: [
          'me',
          ...List.generate(maxGroupCallParticipants, (i) => 'peer-$i'),
        ],
        callType: CallType.video,
      ),
      isFalse,
    );
    expect(manager.currentSession, isNull);
    expect(signaling.sentMessages.whereType<GroupCallInviteSignal>(), isEmpty);
  });

  test('incoming group call buffers mesh offer until accepted', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.dispose);
    final signaling = InMemorySignalingService();
    await signaling.connect(
      userId: 'me',
      url: 'wss://test.invalid',
      accessToken: 'token',
    );
    final groupMedia = _FakeGroupMediaEngine();
    final routingToken = newOpaqueRoutingNonce();
    final manager = CallManager(
      session: SessionStore(userId: 'me', accessToken: 'token'),
      signaling: signaling,
      media: _FakeMediaEngine(),
      groupMedia: groupMedia,
      iceServers: const StaticIceServerProvider([]),
      callLogs: fixture.database.callLogs,
      groupLocalIdResolver: (token) async =>
          token == routingToken ? 'group-1' : null,
      terminalVisibility: const Duration(minutes: 1),
    );
    addTearDown(manager.dispose);
    signaling.addIncoming(
      GroupCallInviteSignal(
        senderId: 'coordinator',
        recipientId: 'me',
        timestamp: DateTime.now(),
        groupId: routingToken,
        callType: 'VOICE',
        callId: 'call-1',
        participants: const ['coordinator', 'me'],
      ),
    );
    await _flush();
    expect(manager.currentSession?.groupId, 'group-1');
    signaling.addIncoming(
      SdpOfferSignal(
        senderId: 'coordinator',
        recipientId: 'me',
        timestamp: DateTime.now(),
        sdp: 'mesh-offer',
        callType: 'VOICE',
      ),
    );
    await _flush();
    expect(groupMedia.acceptedOffers, isEmpty);
    expect(await manager.acceptCall(), isTrue);
    expect(groupMedia.acceptedOffers['coordinator'], 'mesh-offer');
    expect(
      signaling.sentMessages.whereType<SdpAnswerSignal>().single.sdp,
      'mesh-answer',
    );
  });

  test('inactive group status closes the local session and media', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.dispose);
    final signaling = InMemorySignalingService();
    await signaling.connect(
      userId: 'me',
      url: 'wss://test.invalid',
      accessToken: 'token',
    );
    final groupMedia = _FakeGroupMediaEngine();
    final routingToken = newOpaqueRoutingNonce();
    final manager = CallManager(
      session: SessionStore(userId: 'me', accessToken: 'token'),
      signaling: signaling,
      media: _FakeMediaEngine(),
      groupMedia: groupMedia,
      iceServers: const StaticIceServerProvider([]),
      callLogs: fixture.database.callLogs,
      groupLocalIdResolver: (token) async =>
          token == routingToken ? 'group-1' : null,
      terminalVisibility: const Duration(minutes: 1),
    );
    addTearDown(manager.dispose);

    signaling.addIncoming(
      GroupCallInviteSignal(
        senderId: 'coordinator',
        recipientId: 'me',
        timestamp: DateTime.now(),
        groupId: routingToken,
        callType: 'VOICE',
        callId: 'call-remote-end',
        participants: const ['coordinator', 'me'],
      ),
    );
    await _flush();
    expect(manager.currentSession?.isGroupCall, isTrue);

    final endedSession = manager.sessions
        .firstWhere((session) => session?.state == CallState.ended)
        .timeout(const Duration(seconds: 5));
    signaling.addIncoming(
      GroupCallStatusResponseSignal(
        recipientId: 'me',
        timestamp: DateTime.now(),
        groupId: routingToken,
        isActive: false,
      ),
    );
    expect((await endedSession)?.state, CallState.ended);
    expect(groupMedia.closed, isTrue);
  });

  test('file transfer encrypts chunks and reassembles out of order', () async {
    final root = await Directory.systemTemp.createTemp('securechat_media_');
    addTearDown(() => root.delete(recursive: true));
    final signaling = InMemorySignalingService();
    await signaling.connect(
      userId: 'me',
      url: 'wss://test.invalid',
      accessToken: 'token',
    );
    final crypto = LocalAeadCryptoService(
      SecretKey(List<int>.generate(32, (index) => index + 1)),
    );
    final manager = FileTransferManager(
      signaling: signaling,
      crypto: crypto,
      filesDirectory: root,
      chunkSize: 32,
    );
    addTearDown(manager.dispose);
    final payload = Uint8List.fromList(
      List<int>.generate(77, (index) => (index * 13) % 256),
    );

    final result = await manager.sendStream(
      localUserId: 'me',
      recipientId: 'peer',
      stream: Stream.value(payload),
      fileSize: payload.length,
      fileName: '../../gizli belge.bin',
      mimeType: 'application/pdf',
      caption: 'gizli baslik',
      isViewOnce: true,
      originalMessageId: 'private-message-reference',
      absoluteExpiresAt: DateTime.fromMillisecondsSinceEpoch(2000000000000),
    );
    expect(result, isA<FileTransferSuccess>());
    final chunks = signaling.sentMessages
        .whereType<FileTransferSignal>()
        .toList();
    expect(chunks, hasLength(3));
    expect(chunks.first.data, isNot(contains('AA0a')));
    expect(chunks.first.encryption, FileTransferManager.directWireVersion);
    expect(chunks.first.fileName, 'attachment.bin');
    expect(chunks.first.mimeType, 'application/octet-stream');
    expect(chunks.first.groupId, isNull);
    expect(chunks.first.groupName, isNull);
    expect(chunks.first.isViewOnce, isFalse);
    expect(chunks.first.originalMessageId, isNull);
    expect(chunks.first.absoluteExpiresAt, isNull);
    expect(chunks.first.fileSize, 96);
    expect(chunks.first.fileSize, isNot(payload.length));
    final serialized = jsonEncode(
      chunks.map((chunk) => chunk.toJson()).toList(),
    );
    expect(serialized, isNot(contains('gizli')));
    expect(serialized, isNot(contains('application/pdf')));
    expect(serialized, isNot(contains('private-message-reference')));

    ReceivedFile? received;
    var inspectedPartialMetadata = false;
    for (final chunk in chunks.reversed) {
      final incoming = FileTransferSignal.fromJson({
        ...chunk.toJson(),
        'senderId': 'peer',
        'recipientId': 'me',
      });
      received = await manager.receiveChunk(incoming) ?? received;
      if (!inspectedPartialMetadata && received == null) {
        final metadata = File(
          '${root.path}/incoming_parts/${chunk.transferId}/metadata.secure',
        );
        final persisted = await metadata.readAsString();
        expect(persisted, startsWith('STORE:v1:LOCAL_AES_GCM:'));
        expect(persisted, isNot(contains('peer')));
        expect(persisted, isNot(contains('attachment.bin')));
        inspectedPartialMetadata = true;
      }
    }
    expect(inspectedPartialMetadata, isTrue);
    expect(received, isNotNull);
    expect(await received!.file.readAsBytes(), payload);
    expect(received.fileName, 'gizli_belge.bin');
    expect(received.mimeType, 'application/pdf');
    expect(received.caption, 'gizli baslik');
    expect(received.isViewOnce, isTrue);
    expect(received.originalMessageId, 'private-message-reference');
    expect(
      received.absoluteExpiresAt,
      DateTime.fromMillisecondsSinceEpoch(2000000000000),
    );
  });

  test('group file wire exposes only an opaque routing token', () async {
    final root = await Directory.systemTemp.createTemp(
      'securechat_group_file_privacy_',
    );
    addTearDown(() => root.delete(recursive: true));
    final signaling = InMemorySignalingService();
    await signaling.connect(
      userId: 'alice',
      url: 'wss://test.invalid',
      accessToken: 'token',
    );
    const groupId = '4ac44c82-57c4-4f34-9634-42a45bf5d481';
    final manager = FileTransferManager(
      signaling: signaling,
      crypto: LocalAeadCryptoService(
        SecretKey(List<int>.generate(32, (index) => index + 4)),
      ),
      filesDirectory: root,
      groupRoutingResolver: (token) async =>
          token == await groupRoutingToken(groupId) ? groupId : null,
    );
    addTearDown(manager.dispose);

    final result = await manager.sendStream(
      localUserId: 'alice',
      recipientId: groupId,
      stream: Stream.value([1, 2, 3, 4]),
      fileSize: 4,
      fileName: 'yonetim-plani.pdf',
      mimeType: 'application/pdf',
      isGroup: true,
      groupMembers: const ['alice', 'bob'],
      caption: 'yalnizca grup icin',
    );
    expect(result, isA<FileTransferSuccess>());
    final signal = signaling.sentMessages
        .whereType<FileTransferSignal>()
        .single;
    final wire = jsonEncode(signal.toJson());
    expect(signal.recipientId, 'bob');
    expect(signal.encryption, FileTransferManager.groupWireVersion);
    expect(signal.groupId, isNull);
    expect(signal.groupName, isNull);
    expect(signal.fileSize, FileTransferManager.maximumGroupChunkSize);
    expect(signal.fileSize, isNot(4));
    expect(wire, isNot(contains(groupId)));
    expect(wire, isNot(contains('yonetim-plani')));
    expect(wire, isNot(contains('application/pdf')));
    expect(wire, isNot(contains('yalnizca grup icin')));

    final received = await manager.receiveChunk(
      FileTransferSignal.fromJson({
        ...signal.toJson(),
        'senderId': 'alice',
        'recipientId': 'bob',
      }),
    );
    expect(received, isNotNull);
    expect(received!.groupId, groupId);
    expect(received.fileName, 'yonetim-plani.pdf');
    expect(received.mimeType, 'application/pdf');
    expect(received.caption, 'yalnizca grup icin');
    expect(await received.file.readAsBytes(), [1, 2, 3, 4]);
  });

  test('file transfer rejects tampered encrypted chunks', () async {
    final root = await Directory.systemTemp.createTemp('securechat_tamper_');
    addTearDown(() => root.delete(recursive: true));
    final signaling = InMemorySignalingService();
    await signaling.connect(
      userId: 'me',
      url: 'wss://test.invalid',
      accessToken: 'token',
    );
    final failures = <String>[];
    final manager = FileTransferManager(
      signaling: signaling,
      crypto: LocalAeadCryptoService(
        SecretKey(List<int>.generate(32, (index) => index + 1)),
      ),
      filesDirectory: root,
      onAsyncFailure: (operation, error, stackTrace) {
        failures.add(operation);
        // Even a broken diagnostic backend must not break cleanup.
        throw StateError('reporter unavailable');
      },
    );
    addTearDown(manager.dispose);
    final signal = FileTransferSignal(
      senderId: 'peer',
      recipientId: 'me',
      timestamp: DateTime.now(),
      fileName: 'x.txt',
      mimeType: 'text/plain',
      fileSize: 3,
      data: 'not-valid-ciphertext',
      transferId: 'tampered',
      encryption: 'flutter-e2ee-v1',
    );
    expect(await manager.receiveChunk(signal), isNull);
    expect(failures, ['file-transfer.receive']);
    expect(
      await Directory('${root.path}/incoming_parts/tampered').exists(),
      isFalse,
    );
    expect(await Directory('${root.path}/received_files').exists(), isFalse);
  });

  group('call media encryption', () {
    /// Frame sifrelemesi mesh'in DTLS-SRTP katmaninin ustune cagri anahtariyla
    /// ikinci bir katman ekler; yetenegi bildirmeyen katilimci sifreli
    /// baslayan aramaya alinmaz.
    Future<_MediaKeyFixture> openCall({
      bool withDistributor = true,
      List<String> peerIds = const ['peer-a', 'peer-b'],
      Set<String> undeliverable = const {},
      bool failEncryption = false,
    }) async {
      final fixture = await _Fixture.open();
      final signaling = InMemorySignalingService();
      await signaling.connect(
        userId: 'me',
        url: 'wss://test.invalid',
        accessToken: 'token',
      );
      final groupMedia = _FakeGroupMediaEngine()
        ..failMediaEncryption = failEncryption;
      final distributedTo = <String>[];
      final payloads = <String>[];
      final manager = CallManager(
        session: SessionStore(userId: 'me', accessToken: 'token'),
        signaling: signaling,
        media: _FakeMediaEngine(),
        groupMedia: groupMedia,
        iceServers: const StaticIceServerProvider([]),
        callLogs: fixture.database.callLogs,
        preparePrivateGroupCall:
            ({
              required String groupId,
              required String groupName,
              required List<String> peerIds,
            }) async => newOpaqueRoutingNonce(),
        distributeCallMediaKey: withDistributor
            ? ({required String recipientId, required String payload}) async {
                distributedTo.add(recipientId);
                payloads.add(payload);
                return !undeliverable.contains(recipientId);
              }
            : null,
        terminalVisibility: const Duration(minutes: 1),
      );
      final started = await manager.initiateGroupCall(
        groupId: 'group-1',
        groupName: 'Ekip',
        peerIds: ['me', ...peerIds],
        callType: CallType.video,
      );
      return _MediaKeyFixture(
        fixture: fixture,
        manager: manager,
        signaling: signaling,
        engine: groupMedia,
        distributedTo: distributedTo,
        payloads: payloads,
        started: started,
      );
    }

    Future<_MediaKeyFixture> openIncomingCall({
      String coordinatorId = 'coordinator',
      CallMediaKey? mediaKey,
      bool keyBeforeInvite = false,
    }) async {
      final fixture = await _Fixture.open();
      final signaling = InMemorySignalingService();
      await signaling.connect(
        userId: 'me',
        url: 'wss://test.invalid',
        accessToken: 'token',
      );
      final routingToken = newOpaqueRoutingNonce();
      final groupMedia = _FakeGroupMediaEngine();
      final distributedTo = <String>[];
      final payloads = <String>[];
      final manager = CallManager(
        session: SessionStore(userId: 'me', accessToken: 'token'),
        signaling: signaling,
        media: _FakeMediaEngine(),
        groupMedia: groupMedia,
        iceServers: const StaticIceServerProvider([]),
        callLogs: fixture.database.callLogs,
        groupLocalIdResolver: (token) async =>
            token == routingToken ? 'group-1' : null,
        distributeCallMediaKey:
            ({required String recipientId, required String payload}) async {
              distributedTo.add(recipientId);
              payloads.add(payload);
              return true;
            },
        terminalVisibility: const Duration(minutes: 1),
      );
      final key = mediaKey ?? CallMediaKey.generate(callId: 'call-incoming');
      if (keyBeforeInvite) {
        await manager.applyIncomingMediaKey(
          senderId: coordinatorId,
          payload: key.encode(),
        );
      }
      signaling.addIncoming(
        GroupCallInviteSignal(
          senderId: coordinatorId,
          recipientId: 'me',
          timestamp: DateTime.now(),
          groupId: routingToken,
          callType: 'VIDEO',
          callId: key.callId,
          participants: const [],
          mediaE2ee: true,
        ),
      );
      await _flush();
      if (!keyBeforeInvite) {
        await manager.applyIncomingMediaKey(
          senderId: coordinatorId,
          payload: key.encode(),
        );
      }
      return _MediaKeyFixture(
        fixture: fixture,
        manager: manager,
        signaling: signaling,
        engine: groupMedia,
        distributedTo: distributedTo,
        payloads: payloads,
        started: true,
      );
    }

    test(
      'a group call distributes one key and advertises the capability',
      () async {
        final call = await openCall();
        addTearDown(call.dispose);

        expect(call.started, isTrue);
        expect(call.manager.mediaEncryptionActive, isTrue);
        // Anahtar her katilimciya ayri ayri gider.
        expect(call.distributedTo, ['peer-a', 'peer-b']);
        // Ayni anahtar; kusak sifirdan baslar.
        expect(call.payloads.toSet(), hasLength(1));
        expect(CallMediaKey.tryParse(call.payloads.first)?.epoch, 0);
        // Sifreleme baglantilar kurulmadan once acilir.
        expect(call.engine.appliedMediaKeys, hasLength(1));

        final invites = call.signaling.sentMessages
            .whereType<GroupCallInviteSignal>()
            .toList();
        expect(invites, hasLength(2));
        expect(invites.every((invite) => invite.mediaE2ee), isTrue);
      },
    );

    test(
      'an unsupported platform starts the call without frame encryption',
      () async {
        final call = await openCall(peerIds: ['peer-a'], failEncryption: true);
        addTearDown(call.dispose);

        expect(call.started, isTrue);
        expect(call.manager.mediaEncryptionActive, isFalse);
        // Yetenek bildirilmez; sunucu bu aramaya sifreleme sart kosmaz.
        final invite = call.signaling.sentMessages
            .whereType<GroupCallInviteSignal>()
            .single;
        expect(invite.mediaE2ee, isFalse);
      },
    );

    test(
      'a participant that never receives the key disables encryption',
      () async {
        final call = await openCall(undeliverable: {'peer-b'});
        addTearDown(call.dispose);

        // Anahtari alamayan katilimci frame'leri cozemezdi.
        expect(call.manager.mediaEncryptionActive, isFalse);
        expect(call.engine.appliedMediaKeys, isEmpty);
        expect(
          call.signaling.sentMessages.whereType<GroupCallInviteSignal>().every(
            (invite) => invite.mediaE2ee,
          ),
          isFalse,
        );
      },
    );

    test('without a distributor no key is generated', () async {
      final call = await openCall(peerIds: ['peer-a'], withDistributor: false);
      addTearDown(call.dispose);

      expect(call.manager.mediaEncryptionActive, isFalse);
      expect(call.engine.appliedMediaKeys, isEmpty);
    });

    test('an incoming key minted for another call is refused', () async {
      final call = await openIncomingCall();
      addTearDown(call.dispose);

      final foreign = CallMediaKey.generate(callId: 'someone-elses-call');

      expect(
        await call.manager.applyIncomingMediaKey(
          senderId: 'coordinator',
          payload: foreign.encode(),
        ),
        isFalse,
      );
    });

    test('a superseded epoch cannot be replayed', () async {
      final initial = CallMediaKey.generate(callId: 'call-incoming');
      final call = await openIncomingCall(mediaKey: initial);
      addTearDown(call.dispose);
      final callId = call.manager.currentSession!.callId;

      final newer = CallMediaKey.generate(callId: callId, epoch: 5);
      expect(
        await call.manager.applyIncomingMediaKey(
          senderId: 'coordinator',
          payload: newer.encode(),
        ),
        isTrue,
      );

      final older = CallMediaKey.generate(callId: callId, epoch: 4);
      expect(
        await call.manager.applyIncomingMediaKey(
          senderId: 'coordinator',
          payload: older.encode(),
        ),
        isFalse,
      );
    });

    test(
      'a media key received before its invite is applied after binding',
      () async {
        final call = await openIncomingCall(keyBeforeInvite: true);
        addTearDown(call.dispose);

        expect(call.manager.mediaEncryptionActive, isTrue);
        expect(call.engine.appliedMediaKeys, hasLength(1));
      },
    );

    test('a non-coordinator cannot replace the active media key', () async {
      final initial = CallMediaKey.generate(callId: 'call-incoming');
      final call = await openIncomingCall(mediaKey: initial);
      addTearDown(call.dispose);
      final injected = CallMediaKey.generate(
        callId: initial.callId,
        epoch: initial.epoch + 1,
      );

      expect(
        await call.manager.applyIncomingMediaKey(
          senderId: 'ordinary-member',
          payload: injected.encode(),
        ),
        isFalse,
      );
      expect(call.engine.appliedMediaKeys, [initial]);
    });

    test('the same epoch is idempotent but cannot carry another key', () async {
      final initial = CallMediaKey.generate(callId: 'call-incoming');
      final call = await openIncomingCall(mediaKey: initial);
      addTearDown(call.dispose);

      expect(
        await call.manager.applyIncomingMediaKey(
          senderId: 'coordinator',
          payload: initial.encode(),
        ),
        isTrue,
      );
      final substituted = CallMediaKey.generate(
        callId: initial.callId,
        epoch: initial.epoch,
      );
      expect(
        await call.manager.applyIncomingMediaKey(
          senderId: 'coordinator',
          payload: substituted.encode(),
        ),
        isFalse,
      );
      expect(call.manager.currentSession?.state, CallState.failed);
      expect(call.manager.mediaEncryptionActive, isFalse);
    });

    test('only the coordinator rotates after a membership update', () async {
      final initial = CallMediaKey.generate(callId: 'call-incoming');
      final call = await openIncomingCall(mediaKey: initial);
      addTearDown(call.dispose);

      call.signaling.addIncoming(
        GroupCallMemberJoinedSignal(
          senderId: 'coordinator',
          recipientId: 'me',
          timestamp: DateTime.now(),
          groupCallId: initial.callId,
          joinedMemberId: 'new-member',
        ),
      );
      await _flush();

      expect(call.distributedTo, isEmpty);
      expect(call.engine.appliedMediaKeys, [initial]);
    });

    test('a partial rotation failure terminates the encrypted call', () async {
      final undeliverable = <String>{};
      final call = await openCall(
        peerIds: ['peer-a', 'peer-b'],
        undeliverable: undeliverable,
      );
      addTearDown(call.dispose);
      expect(call.manager.mediaEncryptionActive, isTrue);
      undeliverable.add('peer-b');

      call.signaling.addIncoming(
        GroupCallJoinRequestSignal(
          senderId: 'peer-b',
          recipientId: 'me',
          timestamp: DateTime.now(),
          callId: call.manager.currentSession!.callId,
          groupId: call.signaling.sentMessages
              .whereType<GroupCallInviteSignal>()
              .first
              .groupId,
          callType: 'VIDEO',
          mediaE2ee: true,
        ),
      );
      final acknowledged = <String>{};
      for (var attempt = 0; attempt < 20; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        for (final control
            in call.signaling.sentMessages.whereType<CallControlSignal>()) {
          final messageId = control.messageId;
          if (messageId == null || !acknowledged.add(messageId)) continue;
          call.signaling.addIncoming(
            CallControlAckSignal(
              senderId: control.recipientId,
              recipientId: 'me',
              timestamp: DateTime.now(),
              messageId: messageId,
              action: control.action,
            ),
          );
        }
        if (call.manager.currentSession?.state == CallState.failed) break;
      }

      expect(call.manager.currentSession?.state, CallState.failed);
      expect(call.manager.mediaEncryptionActive, isFalse);
    });

    test('the media key is dropped when the call ends', () async {
      final call = await openCall(peerIds: ['peer-a']);
      addTearDown(call.dispose);
      expect(call.manager.mediaEncryptionActive, isTrue);

      await call.manager.endCall();

      expect(call.manager.mediaEncryptionActive, isFalse);
    });
  });
}

Future<void> _flush() => Future<void>.delayed(const Duration(milliseconds: 20));

class _FakeMediaEngine implements MediaEngine {
  final _states = StreamController<MediaConnectionState>.broadcast();
  final _local = RTCVideoRenderer();
  final _remote = RTCVideoRenderer();
  String? acceptedOffer;
  String? appliedAnswer;
  final candidates = <(String, String?, int)>[];
  final speakerValues = <bool>[];

  void emit(MediaConnectionState state) => _states.add(state);

  @override
  Stream<MediaConnectionState> get connectionStates => _states.stream;
  @override
  RTCVideoRenderer get localRenderer => _local;
  @override
  RTCVideoRenderer get remoteRenderer => _remote;

  @override
  Future<String> createOffer({
    required bool video,
    required List<IceServerConfig> iceServers,
    required LocalIceCandidateHandler onIceCandidate,
  }) async => 'offer';

  @override
  Future<String> acceptOffer({
    required String offerSdp,
    required bool video,
    required List<IceServerConfig> iceServers,
    required LocalIceCandidateHandler onIceCandidate,
  }) async {
    acceptedOffer = offerSdp;
    return 'answer';
  }

  @override
  Future<void> applyAnswer(String answerSdp) async {
    appliedAnswer = answerSdp;
  }

  @override
  Future<void> addIceCandidate({
    required String candidate,
    required String? sdpMid,
    required int sdpMLineIndex,
  }) async => candidates.add((candidate, sdpMid, sdpMLineIndex));

  @override
  Future<void> close() async {}
  @override
  Future<void> dispose() async => _states.close();
  @override
  Future<void> setCameraEnabled(bool enabled) async {}
  @override
  Future<void> setMuted(bool muted) async {}
  @override
  Future<void> setSpeakerOn(bool enabled) async => speakerValues.add(enabled);
  @override
  Future<void> switchCamera() async {}
}

class _MediaKeyFixture {
  _MediaKeyFixture({
    required this.fixture,
    required this.manager,
    required this.signaling,
    required this.engine,
    required this.distributedTo,
    required this.payloads,
    required this.started,
  });

  final _Fixture fixture;
  final CallManager manager;
  final InMemorySignalingService signaling;
  final _FakeGroupMediaEngine engine;
  final List<String> distributedTo;
  final List<String> payloads;
  final bool started;

  Future<void> dispose() async {
    await manager.dispose();
    await fixture.dispose();
  }
}

class _FakeGroupMediaEngine implements GroupMediaEngine {
  final _states = StreamController<GroupPeerState>.broadcast();
  final _local = RTCVideoRenderer();
  final offers = <String>[];
  final acceptedOffers = <String, String>{};
  final answers = <String, String>{};
  final candidates = <String, List<String>>{};
  final appliedMediaKeys = <CallMediaKey>[];
  bool closed = false;
  bool failMediaEncryption = false;

  @override
  bool get mediaEncryptionEnabled => appliedMediaKeys.isNotEmpty;

  @override
  Future<void> enableMediaEncryption(CallMediaKey mediaKey) async {
    if (failMediaEncryption) {
      throw StateError('frame encryption unsupported');
    }
    appliedMediaKeys.add(mediaKey);
  }

  @override
  Future<void> rotateMediaKey(CallMediaKey mediaKey) async {
    if (failMediaEncryption) {
      throw StateError('frame encryption unsupported');
    }
    appliedMediaKeys.add(mediaKey);
  }

  void emit(String peerId, MediaConnectionState state) =>
      _states.add(GroupPeerState(peerId, state));

  @override
  Stream<GroupPeerState> get peerStates => _states.stream;
  @override
  RTCVideoRenderer get localRenderer => _local;
  @override
  Map<String, RTCVideoRenderer> get remoteRenderers => const {};

  @override
  Future<void> initialize({
    required bool video,
    required List<IceServerConfig> iceServers,
  }) async {}

  @override
  Future<String> createOffer({
    required String peerId,
    required LocalIceCandidateHandler onIceCandidate,
  }) async {
    offers.add(peerId);
    return 'mesh-offer-for-$peerId';
  }

  @override
  Future<String> acceptOffer({
    required String peerId,
    required String offerSdp,
    required LocalIceCandidateHandler onIceCandidate,
  }) async {
    acceptedOffers[peerId] = offerSdp;
    return 'mesh-answer';
  }

  @override
  Future<void> applyAnswer({
    required String peerId,
    required String answerSdp,
  }) async => answers[peerId] = answerSdp;

  @override
  Future<void> addIceCandidate({
    required String peerId,
    required String candidate,
    required String? sdpMid,
    required int sdpMLineIndex,
  }) async => candidates.putIfAbsent(peerId, () => []).add(candidate);

  @override
  Future<void> removePeer(String peerId) async {}
  @override
  Future<void> setCameraEnabled(bool enabled) async {}
  @override
  Future<void> setMuted(bool muted) async {}
  @override
  Future<void> setSpeakerOn(bool enabled) async {}
  @override
  Future<void> switchCamera() async {}
  @override
  Future<void> close() async => closed = true;
  @override
  Future<void> dispose() async => _states.close();
}

class _FakeNativeCalls implements NativeCallIntegration {
  final _actions = StreamController<NativeCallAction>.broadcast();
  final speakerRequests = <(String, bool)>[];
  bool handlesSpeaker = false;

  void emit(NativeCallActionType type, String callId) {
    _actions.add(NativeCallAction(type: type, callId: callId));
  }

  @override
  Stream<NativeCallAction> get actions => _actions.stream;
  @override
  Future<void> initialize() async {}
  final reported = <CallSession>[];
  var dismissed = 0;

  @override
  Future<void> reportIncoming(CallSession session) async =>
      reported.add(session);
  @override
  Future<void> reportOutgoing(CallSession session) async {}
  @override
  Future<void> setActive(String callId) async {}
  @override
  Future<void> answer(String callId) async {}
  bool failSpeaker = false;

  @override
  Future<bool> setSpeaker(String callId, bool enabled) async {
    if (failSpeaker) throw StateError('route request failed');
    speakerRequests.add((callId, enabled));
    return handlesSpeaker;
  }

  @override
  Future<void> end(String callId) async {}

  @override
  Future<void> dismissPendingIncoming() async => dismissed++;
}

class _Fixture {
  const _Fixture(this.directory, this.database);
  final Directory directory;
  final SecureChatDatabase database;

  static Future<_Fixture> open() async {
    final directory = await Directory.systemTemp.createTemp(
      'securechat_calls_',
    );
    final database = await SecureChatDatabase.open(
      file: File('${directory.path}/storage.securejson'),
      crypto: LocalAeadCryptoService(
        SecretKey(List<int>.generate(32, (index) => index + 1)),
      ),
    );
    return _Fixture(directory, database);
  }

  Future<void> dispose() => directory.delete(recursive: true);
}
