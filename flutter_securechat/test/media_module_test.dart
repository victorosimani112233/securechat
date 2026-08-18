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
import 'package:flutter_securechat/src/media/call_models.dart';
import 'package:flutter_securechat/src/media/file_transfer_manager.dart';
import 'package:flutter_securechat/src/media/group_media_engine.dart';
import 'package:flutter_securechat/src/media/ice_server_fetcher.dart';
import 'package:flutter_securechat/src/media/janus_client.dart';
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
      expect(manager.currentSession?.state, CallState.active);
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
    expect(chunks.first.encryption, 'flutter-file-v2-direct');
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
    expect(signal.encryption, 'flutter-file-v3-group');
    expect(signal.groupId, isNull);
    expect(signal.groupName, isNull);
    expect(signal.fileSize, manager.chunkSize);
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
    final manager = FileTransferManager(
      signaling: signaling,
      crypto: LocalAeadCryptoService(
        SecretKey(List<int>.generate(32, (index) => index + 1)),
      ),
      filesDirectory: root,
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
    expect(await Directory('${root.path}/received_files').exists(), isFalse);
  });

  test(
    'Janus client authenticates and completes VideoRoom publisher flow',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      String? authorization;
      final requests = <Map<String, Object?>>[];
      var nextHandle = 10;
      server.listen((request) async {
        authorization = request.headers.value(HttpHeaders.authorizationHeader);
        final socket = await WebSocketTransformer.upgrade(
          request,
          protocolSelector: (protocols) =>
              protocols.contains('janus-protocol') ? 'janus-protocol' : null,
        );
        socket.listen((raw) {
          final message = (jsonDecode(raw as String) as Map)
              .cast<String, Object?>();
          requests.add(message);
          final transaction = message['transaction'];
          final kind = message['janus'];
          if (kind == 'create') {
            socket.add(
              jsonEncode({
                'janus': 'success',
                'transaction': transaction,
                'data': {'id': 1},
              }),
            );
          } else if (kind == 'attach') {
            socket.add(
              jsonEncode({
                'janus': 'success',
                'transaction': transaction,
                'data': {'id': nextHandle++},
              }),
            );
          } else if (kind == 'message') {
            final body = (message['body'] as Map).cast<String, Object?>();
            switch (body['request']) {
              case 'join' when body['ptype'] == 'publisher':
                socket.add(
                  jsonEncode({
                    'janus': 'event',
                    'transaction': transaction,
                    'plugindata': {
                      'data': {
                        'publishers': [
                          {'id': 9, 'display': 'peer'},
                        ],
                      },
                    },
                  }),
                );
              case 'configure':
                socket.add(
                  jsonEncode({
                    'janus': 'event',
                    'transaction': transaction,
                    'plugindata': {
                      'data': {'configured': 'ok'},
                    },
                    'jsep': {'type': 'answer', 'sdp': 'remote-answer'},
                  }),
                );
              case 'join':
                socket.add(
                  jsonEncode({
                    'janus': 'event',
                    'transaction': transaction,
                    'plugindata': {
                      'data': {'started': 'ok'},
                    },
                    'jsep': {'type': 'offer', 'sdp': 'subscriber-offer'},
                  }),
                );
              case 'start' || 'leave':
                socket.add(
                  jsonEncode({
                    'janus': 'event',
                    'transaction': transaction,
                    'plugindata': {
                      'data': {'started': 'ok'},
                    },
                  }),
                );
            }
          }
        });
      });
      final client = JanusClient(requestTimeout: const Duration(seconds: 2));
      addTearDown(client.dispose);
      expect(
        await client.connect(
          url: 'ws://${server.address.host}:${server.port}',
          accessToken: 'jwt-token',
        ),
        isTrue,
      );
      expect(await client.createSession(), 1);
      expect(await client.attachVideoRoom(), 10);
      expect(await client.joinAsPublisher(roomId: 77, displayName: 'me'), [
        (9, 'peer'),
      ]);
      final answer = await client.publishSdp(
        'v=0\r\na=candidate:1 1 UDP 1 192.168.1.2 5000 typ host\r\na=sendrecv',
      );
      expect(answer, 'remote-answer');
      final sentOffer = requests
          .where((m) => (m['body'] as Map?)?['request'] == 'configure')
          .single;
      expect((sentOffer['jsep'] as Map)['sdp'], isNot(contains('192.168.1.2')));
      expect(await client.subscribeToFeed(9), 'subscriber-offer');
      await client.answerSubscription(feedId: 9, answerSdp: 'local-answer');
      expect(
        client.trickleIce(
          handleId: 10,
          candidate: 'candidate:1 1 UDP 1 10.0.0.2 5000 typ host',
          sdpMid: '0',
          sdpMLineIndex: 0,
        ),
        isFalse,
      );
      expect(authorization, 'Bearer jwt-token');
      final firstDispose = client.dispose();
      final secondDispose = client.dispose();
      expect(identical(firstDispose, secondDispose), isTrue);
      await Future.wait([firstDispose, secondDispose]);
      await expectLater(
        client.connect(url: 'ws://test.invalid', accessToken: 'token'),
        throwsStateError,
      );
    },
  );
}

Future<void> _flush() => Future<void>.delayed(const Duration(milliseconds: 20));

class _FakeMediaEngine implements MediaEngine {
  final _states = StreamController<MediaConnectionState>.broadcast();
  final _local = RTCVideoRenderer();
  final _remote = RTCVideoRenderer();
  String? acceptedOffer;
  String? appliedAnswer;
  final candidates = <(String, String?, int)>[];

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
  Future<void> setSpeakerOn(bool enabled) async {}
  @override
  Future<void> switchCamera() async {}
}

class _FakeGroupMediaEngine implements GroupMediaEngine {
  final _states = StreamController<GroupPeerState>.broadcast();
  final _local = RTCVideoRenderer();
  final offers = <String>[];
  final acceptedOffers = <String, String>{};
  final answers = <String, String>{};
  final candidates = <String, List<String>>{};
  bool closed = false;

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
  Future<String> createSfuPublisherOffer({
    required LocalIceCandidateHandler onIceCandidate,
  }) async => 'sfu-publisher-offer';
  @override
  Future<void> applySfuPublisherAnswer(String answerSdp) async {}
  @override
  Future<String> acceptSfuSubscriberOffer({
    required int feedId,
    required String offerSdp,
    required LocalIceCandidateHandler onIceCandidate,
  }) async => 'sfu-subscriber-answer';
  @override
  Future<void> addSfuSubscriberIce({
    required int feedId,
    required String candidate,
    required String? sdpMid,
    required int sdpMLineIndex,
  }) async {}
  @override
  Future<void> removePeer(String peerId) async {}
  @override
  Future<void> removeSfuFeed(int feedId) async {}
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

  void emit(NativeCallActionType type, String callId) {
    _actions.add(NativeCallAction(type: type, callId: callId));
  }

  @override
  Stream<NativeCallAction> get actions => _actions.stream;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> reportIncoming(CallSession session) async {}
  @override
  Future<void> reportOutgoing(CallSession session) async {}
  @override
  Future<void> setActive(String callId) async {}
  @override
  Future<void> end(String callId) async {}
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
