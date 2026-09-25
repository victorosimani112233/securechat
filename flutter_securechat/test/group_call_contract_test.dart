import 'dart:async';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/media/call_manager.dart';
import 'package:flutter_securechat/src/media/call_media_key.dart';
import 'package:flutter_securechat/src/media/call_models.dart';
import 'package:flutter_securechat/src/media/group_media_engine.dart';
import 'package:flutter_securechat/src/media/ice_server_fetcher.dart';
import 'package:flutter_securechat/src/media/janus_client.dart';
import 'package:flutter_securechat/src/media/media_engine.dart';
import 'package:flutter_securechat/src/media/native_call_integration.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_test/flutter_test.dart';

const alice = '00000000-0000-4000-8000-000000000001';
const bob = '00000000-0000-4000-8000-000000000002';
const carol = '00000000-0000-4000-8000-000000000003';

void main() {
  test(
    'an established group call survives without further media state events',
    () async {
      final f = await _Network.open(ringTimeout: const Duration(seconds: 1));
      addTearDown(f.dispose);
      await f.start(peers: [bob]);
      await _until(() => f.nodes[bob]!.manager.currentSession != null);
      await f.nodes[bob]!.manager.acceptCall();
      await _until(() => f.nodes[alice]!.media.remoteSdp.contains(bob));
      f.nodes[alice]!.media.states.add(
        const GroupPeerState(bob, MediaConnectionState.connected),
      );
      f.nodes[bob]!.media.states.add(
        const GroupPeerState(alice, MediaConnectionState.connected),
      );
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(f.nodes[alice]!.manager.currentSession!.state, CallState.active);
      expect(f.nodes[bob]!.manager.currentSession!.state, CallState.active);
      expect(f.failures, isEmpty);
    },
  );

  test('incoming rekey waits for departing peer cleanup', () async {
    final f = await _Network.open();
    addTearDown(f.dispose);
    await f.start();
    await _until(
      () =>
          f.nodes[bob]!.manager.currentSession != null &&
          f.nodes[carol]!.manager.currentSession != null,
    );
    await f.nodes[bob]!.manager.acceptCall();
    await f.nodes[carol]!.manager.acceptCall();
    await _until(
      () => f.nodes.values.every((n) => n.media.remoteSdp.length == 2),
    );
    final receiver = f.nodes[bob]!;
    receiver.media.states.add(
      const GroupPeerState(alice, MediaConnectionState.connected),
    );
    await _until(
      () => receiver.manager.currentSession!.state == CallState.active,
    );
    final gate = Completer<void>();
    receiver.media.removalGate = gate;
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    f.deliver(
      GroupCallMemberLeftSignal(
        senderId: 'server',
        recipientId: bob,
        timestamp: DateTime.now(),
        groupCallId: receiver.manager.currentSession!.callId,
        groupId: f.token,
        leftMemberId: carol,
      ),
    );
    await _until(() => receiver.media.removalInProgress);
    final next = receiver.media.key!.rotate();
    final applied = receiver.manager.applyIncomingMediaKey(
      senderId: alice,
      payload: next.encode(),
    );
    await _settle();
    gate.complete();
    expect(await applied, isTrue);
    expect(receiver.manager.currentSession!.state, CallState.active);
    expect(receiver.manager.currentSession!.peerIds, [alice]);
    expect(receiver.media.key, next);
    expect(f.failures, isEmpty);
  });

  test(
    'app answer activates native call once even when system echoes answer',
    () async {
      final f = await _Network.open(nativeAnswer: true);
      addTearDown(f.dispose);
      await f.start(peers: [bob]);
      await _until(() => f.nodes[bob]!.manager.currentSession != null);
      final results = await Future.wait([
        f.nodes[bob]!.manager.acceptCall(),
        f.nodes[bob]!.manager.acceptCall(),
      ]);
      expect(results, [true, true]);
      expect(f.nativeAnswers, 1);
      await _until(
        () => f.frames.whereType<GroupCallJoinRequestSignal>().isNotEmpty,
      );
      expect(f.frames.whereType<GroupCallJoinRequestSignal>(), hasLength(1));
      expect(f.failures, isEmpty);
    },
  );

  for (final type in CallType.values) {
    for (final departing in [alice, carol]) {
      test(
        '${type.name}: leaving ${departing == alice ? 'coordinator' : 'member'} preserves the remaining call',
        () async {
          final f = await _Network.open();
          addTearDown(f.dispose);
          await f.start(type: type);
          await _until(
            () =>
                f.nodes[bob]!.manager.currentSession != null &&
                f.nodes[carol]!.manager.currentSession != null,
          );
          await f.nodes[bob]!.manager.acceptCall();
          await f.nodes[carol]!.manager.acceptCall();
          await _until(
            () => f.nodes.values.every((n) => n.media.remoteSdp.length == 2),
          );
          for (final entry in f.nodes.entries) {
            for (final peer in f.nodes.keys.where((id) => id != entry.key)) {
              entry.value.media.states.add(
                GroupPeerState(peer, MediaConnectionState.connected),
              );
            }
          }
          await _until(
            () => f.nodes.values.every(
              (n) => n.manager.currentSession!.state == CallState.active,
            ),
          );
          final callId = f.nodes[alice]!.manager.currentSession!.callId;
          final prior = f.nodes[alice]!.media.key!;
          final remaining = f.nodes.keys
              .where((id) => id != departing)
              .toList();
          await f.nodes[departing]!.manager.endCall();
          for (final recipient in remaining) {
            f.deliver(
              GroupCallMemberLeftSignal(
                senderId: 'server',
                recipientId: recipient,
                timestamp: DateTime.now(),
                groupCallId: callId,
                groupId: f.token,
                leftMemberId: departing,
              ),
            );
          }
          if (departing == alice) {
            // Let the new key overtake the server handoff on the other socket.
            f.deliver(
              GroupCallCoordinatorChangedSignal(
                senderId: 'server',
                recipientId: bob,
                timestamp: DateTime.now(),
                groupCallId: callId,
                groupId: f.token,
                previousCoordinatorId: alice,
                newCoordinatorId: bob,
              ),
            );
            await _until(() => f.nodes[bob]!.media.key!.epoch > prior.epoch);
            f.deliver(
              GroupCallCoordinatorChangedSignal(
                senderId: 'server',
                recipientId: carol,
                timestamp: DateTime.now(),
                groupCallId: callId,
                groupId: f.token,
                previousCoordinatorId: alice,
                newCoordinatorId: bob,
              ),
            );
          }
          await _until(
            () => remaining.every(
              (id) =>
                  f.nodes[id]!.media.key!.epoch > prior.epoch &&
                  f.nodes[id]!.manager.currentSession!.peerIds.length == 1,
            ),
          );
          await _settle();
          for (final id in remaining) {
            final node = f.nodes[id]!;
            expect(node.manager.currentSession!.state, CallState.active);
            expect(
              node.manager.currentSession!.connectedPeerIds,
              remaining.where((peer) => peer != id).toList(),
            );
            expect(
              node.media.meshPeers,
              remaining.where((peer) => peer != id).toSet(),
            );
            expect(node.media.key, f.nodes[remaining.first]!.media.key);
            expect(node.manager.mediaEncryptionActive, isTrue);
          }
          expect(f.failures, isEmpty);
          expect(
            f.frames.whereType<CallControlSignal>().where(
              (s) => s.action == 'HANGUP' && remaining.contains(s.senderId),
            ),
            isEmpty,
          );
        },
      );
    }
    test(
      '${type.name}: declined member rejoins active call with a fresh media key',
      () async {
        final f = await _Network.open();
        addTearDown(f.dispose);
        await f.start(type: type);
        await _until(
          () =>
              f.nodes[bob]!.manager.currentSession != null &&
              f.nodes[carol]!.manager.currentSession != null,
        );
        await f.nodes[bob]!.manager.acceptCall();
        await _until(() => f.nodes[alice]!.media.remoteSdp.contains(bob));
        f.nodes[alice]!.media.states.add(
          const GroupPeerState(bob, MediaConnectionState.connected),
        );
        await f.nodes[carol]!.manager.rejectCall();
        await _until(
          () =>
              !f.nodes[alice]!.manager.currentSession!.peerIds.contains(carol),
        );
        final prior = f.nodes[alice]!.media.key;
        final active = await f.nodes[carol]!.manager.activeGroupCall(
          'local-group',
        );
        expect(active, isNotNull);
        expect(active!.callType, type);
        expect(
          await f.nodes[carol]!.manager.joinActiveGroupCall(active),
          isTrue,
        );
        await _until(() => f.nodes[carol]!.media.remoteSdp.length == 2);
        expect(f.nodes[carol]!.media.key, f.nodes[alice]!.media.key);
        expect(f.nodes[carol]!.media.key, isNot(prior));
        expect(f.failures, isEmpty);
        await f.nodes[alice]!.manager.endCall();
        expect(
          await f.nodes[carol]!.manager.activeGroupCall('local-group'),
          isNull,
        );
        expect(
          await f.nodes[carol]!.manager.joinActiveGroupCall(active),
          isFalse,
        );
      },
    );
  }
  for (final type in CallType.values) {
    test('${type.name}: concurrent joins form every mesh edge once', () async {
      final f = await _Network.open();
      addTearDown(f.dispose);
      await f.start(type: type);
      expect(f.nodes[alice]!.manager.currentSession!.state, CallState.ringing);
      expect(f.nodes[alice]!.manager.currentSession!.startTime, isNull);
      await _until(
        () =>
            f.nodes[bob]!.manager.currentSession != null &&
            f.nodes[carol]!.manager.currentSession != null,
      );
      await Future.wait([
        f.nodes[bob]!.manager.acceptCall(),
        f.nodes[carol]!.manager.acceptCall(),
      ]);
      await _until(
        () => f.nodes.values.every((n) => n.media.remoteSdp.length == 2),
      );
      expect(f.frames.whereType<SdpOfferSignal>(), hasLength(3));
      expect(f.frames.whereType<SdpAnswerSignal>(), hasLength(3));
      expect(f.frames.whereType<GroupCallJoinRequestSignal>(), hasLength(2));
      expect(
        f.frames.whereType<GroupCallInviteSignal>().every(
          (s) =>
              s.participants.isEmpty &&
              s.groupId == f.token &&
              s.callType == type.name.toUpperCase(),
        ),
        isTrue,
      );
      for (final node in f.nodes.values) {
        expect(node.media.video, type == CallType.video);
        expect(node.media.candidates, hasLength(2));
        expect(node.manager.secondarySession, isNull);
        expect(node.media.key, f.nodes[alice]!.media.key);
        node.media.states.add(
          GroupPeerState(
            node.media.remoteSdp.first,
            MediaConnectionState.connected,
          ),
        );
      }
      await _until(
        () => f.nodes.values.every(
          (n) => n.manager.currentSession!.state == CallState.active,
        ),
      );
      final joins = f.frames.whereType<GroupCallJoinRequestSignal>().toList();
      for (final join in joins) {
        f.deliver(join);
      }
      await _settle();
      expect(f.frames.whereType<SdpOfferSignal>(), hasLength(3));
      expect(f.failures, isEmpty);
    });
  }

  test('connects before encrypted group preparation', () async {
    final f = await _Network.open();
    addTearDown(f.dispose);
    await f.start();
    expect(f.preparedWhileConnected, isTrue);
  });

  test(
    'only a correlated server group error terminates the current call',
    () async {
      final f = await _Network.open();
      addTearDown(f.dispose);
      await f.start(peers: [bob]);
      final callId = f.nodes[alice]!.manager.currentSession!.callId;
      GroupCallErrorSignal error(String sender, String group, String call) =>
          GroupCallErrorSignal(
            senderId: sender,
            recipientId: alice,
            timestamp: DateTime.now(),
            groupId: group,
            callId: call,
            code: 'CAPACITY_REACHED',
          );
      for (final signal in [
        error(bob, f.token, callId),
        error('', f.token, callId),
        error('server', 'another-group', callId),
        error('server', f.token, 'another-call'),
      ]) {
        f.deliver(signal);
      }
      await _settle();
      expect(f.nodes[alice]!.manager.currentSession!.state, CallState.ringing);
      final valid = error('server', f.token, callId);
      expect(
        (SignalMessage.decode(valid.encode()) as GroupCallErrorSignal).code,
        'CAPACITY_REACHED',
      );
      f.deliver(valid);
      await _until(() => f.nodes[alice]!.manager.currentSession!.isTerminal);
      expect(f.nodes[alice]!.manager.currentSession!.state, CallState.failed);
      expect(f.nodes[alice]!.media.initialized, isFalse);
    },
  );

  test('failed SDP send terminates and releases media', () async {
    final f = await _Network.open();
    addTearDown(f.dispose);
    await f.start(peers: [bob]);
    await _until(() => f.nodes[bob]!.manager.currentSession != null);
    f.rejectOffers = true;
    await f.nodes[bob]!.manager.acceptCall();
    await _until(() => f.nodes[alice]!.manager.currentSession!.isTerminal);
    expect(f.nodes[alice]!.manager.currentSession!.state, CallState.failed);
    expect(f.nodes[alice]!.media.initialized, isFalse);
    expect(f.nodes[alice]!.media.key, isNull);
  });

  test(
    'rapid next call survives the previous terminal visibility timer',
    () async {
      final f = await _Network.open(
        terminalVisibility: const Duration(milliseconds: 80),
      );
      addTearDown(f.dispose);
      await f.start(peers: [bob]);
      final first = f.nodes[alice]!.manager.currentSession!.callId;
      await f.nodes[alice]!.manager.endCall();
      await _until(
        () => f.nodes[bob]!.manager.currentSession?.isTerminal == true,
      );
      await f.start(peers: [bob]);
      await _until(() => f.nodes[bob]!.manager.currentSession?.callId != first);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(f.nodes[alice]!.manager.currentSession?.state, CallState.ringing);
      expect(f.nodes[bob]!.manager.currentSession?.state, CallState.ringing);
      expect(f.nodes[bob]!.manager.mediaEncryptionActive, isTrue);
    },
  );

  test(
    'key arriving after acceptance waits and does not publish plaintext',
    () async {
      final f = await _Network.open();
      addTearDown(f.dispose);
      f.holdKeys = true;
      await f.start(peers: [bob]);
      await _until(() => f.nodes[bob]!.manager.currentSession != null);
      final incoming = f.nodes[bob]!;
      final accepting = incoming.manager.acceptCall();
      await _settle();
      expect(incoming.manager.currentSession!.state, CallState.connecting);
      expect(f.frames.whereType<GroupCallJoinRequestSignal>(), isEmpty);
      f.holdKeys = false;
      await f.releaseKeys();
      expect(await accepting, isTrue);
      await _until(() => incoming.media.remoteSdp.isNotEmpty);
      expect(incoming.media.key, isNotNull);
      expect(f.failures, isEmpty);
    },
  );

  test('missing required key fails closed with server HANGUP', () async {
    final f = await _Network.open(keyTimeout: const Duration(milliseconds: 40));
    addTearDown(f.dispose);
    f.holdKeys = true;
    await f.start(peers: [bob]);
    await _until(() => f.nodes[bob]!.manager.currentSession != null);
    expect(await f.nodes[bob]!.manager.acceptCall(), isFalse);
    expect(f.nodes[bob]!.media.offers, isEmpty);
    expect(f.frames.whereType<GroupCallJoinRequestSignal>(), isEmpty);
    expect(
      f.frames.whereType<CallControlSignal>().any(
        (s) =>
            s.senderId == bob &&
            s.recipientId == 'server' &&
            s.action == 'HANGUP',
      ),
      isTrue,
    );
  });

  test('permission denial sends no invite and releases group media', () async {
    final f = await _Network.open();
    addTearDown(f.dispose);
    f.nodes[alice]!.media.denyCapture = true;
    expect(await f.start(expectSuccess: false), isFalse);
    expect(f.frames.whereType<GroupCallInviteSignal>(), isEmpty);
    expect(f.nodes[alice]!.media.closed, isTrue);
    expect(f.nodes[alice]!.manager.currentSession!.state, CallState.failed);
  });

  test(
    'eight total accepted; ninth rejected before preparation or capture',
    () async {
      final f = await _Network.open();
      addTearDown(f.dispose);
      expect(
        await f.start(
          peers: List.generate(8, (i) => 'peer-$i'),
          expectSuccess: false,
        ),
        isFalse,
      );
      expect(f.preparedWhileConnected, isFalse);
      expect(f.nodes[alice]!.media.initialized, isFalse);
      expect(await f.start(peers: List.generate(7, (i) => 'peer-$i')), isTrue);
      expect(f.frames.whereType<GroupCallInviteSignal>(), hasLength(7));
    },
  );

  test('forged membership and wrong-call joins cannot open media', () async {
    final f = await _Network.open();
    addTearDown(f.dispose);
    await f.start();
    final callId = f.nodes[alice]!.manager.currentSession!.callId;
    f.deliver(
      GroupCallJoinRequestSignal(
        senderId: bob,
        recipientId: alice,
        timestamp: DateTime.now(),
        groupId: f.token,
        callId: 'wrong',
        callType: 'VOICE',
        mediaE2ee: true,
      ),
    );
    f.deliver(
      GroupCallMemberJoinedSignal(
        senderId: bob,
        recipientId: alice,
        timestamp: DateTime.now(),
        groupCallId: callId,
        joinedMemberId: 'stranger',
      ),
    );
    await _settle();
    expect(f.frames.whereType<SdpOfferSignal>(), isEmpty);
    expect(f.nodes[alice]!.manager.currentSession!.peerIds, [bob, carol]);
  });

  test('unencrypted mesh ignores SFU announcements', () async {
    final f = await _Network.open(encrypted: false);
    addTearDown(f.dispose);
    await f.start(peers: [bob]);
    f.room(alice);
    await _settle();
    expect(f.janusCreated, 0);
    expect(f.nodes[alice]!.manager.currentSession!.isSfuMode, isFalse);
  });

  test(
    'SFU waits for acceptance and key reinstallation after initialize',
    () async {
      final f = await _Network.open();
      addTearDown(f.dispose);
      await f.start(peers: [bob]);
      await _until(() => f.nodes[bob]!.manager.currentSession != null);
      f.room(bob);
      await _settle();
      expect(f.janusCreated, 0);
      expect(f.nodes[bob]!.media.initialized, isFalse);
      expect(await f.nodes[bob]!.manager.acceptCall(), isTrue);
      await _until(() => f.nodes[bob]!.manager.currentSession!.isSfuMode);
      expect(f.janusCreated, 1);
      expect(f.nodes[bob]!.media.key, isNotNull);
      f.room(bob);
      await _settle();
      expect(f.janusCreated, 1);
    },
  );

  test('rejection removes server membership, not a server REJECT', () async {
    final f = await _Network.open();
    addTearDown(f.dispose);
    await f.start(peers: [bob]);
    await _until(() => f.nodes[bob]!.manager.currentSession != null);
    await f.nodes[bob]!.manager.rejectCall();
    expect(
      f.frames.whereType<CallControlSignal>().any(
        (s) =>
            s.senderId == bob &&
            s.recipientId == 'server' &&
            s.action == 'HANGUP',
      ),
      isTrue,
    );
  });

  test(
    'SFU handoff ignores late mesh SDP ICE and does not recreate peers',
    () async {
      final f = await _Network.open();
      addTearDown(f.dispose);
      await f.start(peers: [bob, carol]);
      await _until(() => f.nodes[bob]!.manager.currentSession != null);
      expect(await f.nodes[bob]!.manager.acceptCall(), isTrue);
      final node = f.nodes[alice]!;
      await _until(() => node.media.remoteSdp.contains(bob));
      final gate = Completer<void>();
      node.media.publisherGate = gate;
      f.room(alice);
      await _until(() => node.media.publisherStarted);
      expect(node.media.meshPeers, isEmpty);
      final operations = node.media.meshOperations;
      void lateFrames() {
        f.deliver(
          SdpAnswerSignal(
            senderId: bob,
            recipientId: alice,
            timestamp: DateTime.now(),
            sdp: 'late-answer',
          ),
        );
        f.deliver(
          SdpOfferSignal(
            senderId: bob,
            recipientId: alice,
            timestamp: DateTime.now(),
            sdp: 'late-offer',
            callType: 'VIDEO',
          ),
        );
        f.deliver(
          IceCandidateSignal(
            senderId: bob,
            recipientId: alice,
            timestamp: DateTime.now(),
            candidate: 'late-ice',
            sdpMid: '0',
            sdpMLineIndex: 0,
          ),
        );
      }

      lateFrames();
      expect(await f.nodes[carol]!.manager.acceptCall(), isTrue);
      await _settle();
      expect(node.media.meshOperations, operations);
      gate.complete();
      await _until(() => node.manager.currentSession!.isSfuMode);
      await _settle();
      lateFrames();
      await _settle();
      expect(node.media.meshOperations, operations);
      expect(node.media.meshPeers, isEmpty);
      expect(node.manager.currentSession!.state, isNot(CallState.failed));
      expect(f.failures, isEmpty);
    },
  );
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 30));
Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 200; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Group contract did not converge');
}

class _Network {
  _Network(this.root, this.db);
  final Directory root;
  final SecureChatDatabase db;
  final token = newOpaqueRoutingNonce();
  final nodes = <String, _Node>{};
  final frames = <SignalMessage>[];
  final failures = <String>[];
  final heldKeys = <(String, String, String)>[];
  bool holdKeys = false;
  bool rejectOffers = false;
  bool preparedWhileConnected = false;
  int janusCreated = 0;
  int nativeAnswers = 0;

  static Future<_Network> open({
    bool encrypted = true,
    bool nativeAnswer = false,
    Duration keyTimeout = const Duration(seconds: 1),
    Duration ringTimeout = const Duration(seconds: 60),
    Duration terminalVisibility = const Duration(minutes: 1),
  }) async {
    final root = await Directory.systemTemp.createTemp('group_contract_');
    final db = await SecureChatDatabase.open(
      file: File('${root.path}/db'),
      crypto: LocalAeadCryptoService(SecretKey(List.filled(32, 7))),
    );
    final f = _Network(root, db);
    for (final id in [alice, bob, carol]) {
      final wire = _Wire(f);
      final media = _GroupMedia();
      final manager = CallManager(
        session: SessionStore(userId: id, accessToken: 'token'),
        signaling: wire,
        media: _UnusedMedia(),
        groupMedia: media,
        iceServers: const StaticIceServerProvider([]),
        callLogs: db.callLogs,
        terminalVisibility: terminalVisibility,
        mediaKeyTimeout: keyTimeout,
        ringTimeout: ringTimeout,
        groupLocalIdResolver: (token) async =>
            token == f.token ? 'local-group' : null,
        groupCallTokens: (_) async => [f.token],
        groupMemberValidator: (_, peer) async =>
            [alice, bob, carol].contains(peer),
        nativeCalls: nativeAnswer ? _AnswerNative(f, id) : null,
        preparePrivateGroupCall:
            ({required groupId, required groupName, required peerIds}) async {
              f.preparedWhileConnected = wire.ready;
              if (!wire.ready)
                throw StateError('Privacy preparation has no socket');
              return f.token;
            },
        distributeCallMediaKey: encrypted
            ? ({required recipientId, required payload}) async {
                if (f.holdKeys) {
                  f.heldKeys.add((id, recipientId, payload));
                  return true;
                }
                await f.nodes[recipientId]?.manager.applyIncomingMediaKey(
                  senderId: id,
                  payload: payload,
                );
                return true;
              }
            : null,
        janusClientFactory: () {
          f.janusCreated++;
          return _Janus();
        },
        onAsyncFailure: (operation, error, _) =>
            f.failures.add('$operation: $error'),
      );
      f.nodes[id] = _Node(manager, media, wire);
    }
    return f;
  }

  Future<bool> start({
    CallType type = CallType.voice,
    List<String> peers = const [bob, carol],
    bool expectSuccess = true,
  }) async {
    final result = await nodes[alice]!.manager.initiateGroupCall(
      groupId: 'local-group',
      groupName: 'Group',
      peerIds: [alice, ...peers],
      callType: type,
    );
    expect(result, expectSuccess);
    return result;
  }

  void deliver(SignalMessage message) {
    final decoded = SignalMessage.decode(message.encode());
    nodes[decoded.recipientId]?.wire.addIncoming(decoded);
  }

  void room(String recipient) => deliver(
    SfuRoomCreatedSignal(
      recipientId: recipient,
      timestamp: DateTime.now(),
      groupId: token,
      roomId: 42,
      janusWsUrl: 'wss://janus.invalid',
    ),
  );

  Future<void> releaseKeys() async {
    for (final key in heldKeys) {
      await nodes[key.$2]?.manager.applyIncomingMediaKey(
        senderId: key.$1,
        payload: key.$3,
      );
    }
    heldKeys.clear();
  }

  Future<void> dispose() async {
    for (final n in nodes.values) {
      await n.manager.dispose();
    }
    await db.close();
    await root.delete(recursive: true);
  }
}

class _Node {
  _Node(this.manager, this.media, this.wire);
  final CallManager manager;
  final _GroupMedia media;
  final _Wire wire;
}

// A local relay of actual wire frames, not a Kotlin server emulator. It uses
// the server's routed join/ACCEPT and ACK contracts; no remote server is used.
class _Wire extends InMemorySignalingService {
  _Wire(this.network);
  final _Network network;
  bool ready = false;
  @override
  Future<bool> ensureConnected({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    ready = true;
    return true;
  }

  @override
  Future<bool> send(SignalMessage message) async {
    final decoded = SignalMessage.decode(message.encode());
    network.frames.add(decoded);
    if (decoded is GroupCallStatusQuerySignal) {
      final current = network.nodes[alice]!.manager.currentSession;
      final active = current != null && !current.isTerminal;
      network.deliver(
        GroupCallStatusResponseSignal(
          recipientId: decoded.senderId,
          timestamp: DateTime.now(),
          groupId: decoded.groupId,
          isActive: active,
          callId: active ? current.callId : null,
          coordinatorId: active ? alice : null,
          callType: active ? current.callType.name.toUpperCase() : null,
          mediaE2ee:
              active && network.nodes[alice]!.manager.mediaEncryptionActive,
          participants: active
              ? [
                  alice,
                  ...current.peerIds.where(
                    (id) =>
                        network.nodes[id]!.manager.currentSession?.state !=
                        CallState.ringing,
                  ),
                ]
              : const [],
        ),
      );
      return true;
    }
    if (network.rejectOffers && decoded is SdpOfferSignal) return false;
    network.deliver(decoded);
    if (decoded is CallControlSignal && decoded.messageId != null) {
      network.deliver(
        CallControlAckSignal(
          senderId: 'server',
          recipientId: decoded.senderId,
          timestamp: DateTime.now(),
          messageId: decoded.messageId!,
          action: decoded.action,
        ),
      );
    }
    return true;
  }
}

class _AnswerNative implements NativeCallIntegration {
  _AnswerNative(this.network, this.userId);
  final _Network network;
  final String userId;
  final controller = StreamController<NativeCallAction>.broadcast();
  @override
  Stream<NativeCallAction> get actions => controller.stream;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> reportIncoming(CallSession session) async {}
  @override
  Future<void> reportOutgoing(CallSession session) async {}
  @override
  Future<void> answer(String callId) async {
    network.nativeAnswers++;
    controller.add(
      NativeCallAction(type: NativeCallActionType.answer, callId: callId),
    );
    await Future<void>.delayed(Duration.zero);
  }

  @override
  Future<void> setActive(String callId) async {}
  @override
  Future<bool> setSpeaker(String callId, bool enabled) async => false;
  @override
  Future<void> end(String callId) async {}
}

class _UnusedMedia implements MediaEngine {
  @override
  Stream<MediaConnectionState> get connectionStates => const Stream.empty();
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _GroupMedia implements GroupMediaEngine {
  final states = StreamController<GroupPeerState>.broadcast();
  final offers = <String>[];
  final remoteSdp = <String>{};
  final candidates = <String>{};
  final meshPeers = <String>{};
  int meshOperations = 0;
  Completer<void>? publisherGate;
  Completer<void>? removalGate;
  bool removalInProgress = false;
  bool publisherStarted = false;
  CallMediaKey? key;
  bool initialized = false;
  bool closed = false;
  bool denyCapture = false;
  bool video = false;
  @override
  Stream<GroupPeerState> get peerStates => states.stream;
  @override
  bool get mediaEncryptionEnabled => key != null;
  @override
  Future<void> enableMediaEncryption(CallMediaKey mediaKey) async {
    key = mediaKey;
  }

  @override
  Future<void> rotateMediaKey(CallMediaKey mediaKey) async {
    if (removalInProgress) throw StateError('Cryptor is being disposed');
    key = mediaKey;
  }

  @override
  Future<void> initialize({
    required bool video,
    required List<IceServerConfig> iceServers,
  }) async {
    await close();
    if (denyCapture) throw StateError('Microphone permission denied');
    initialized = true;
    this.video = video;
  }

  @override
  Future<String> createOffer({
    required String peerId,
    required LocalIceCandidateHandler onIceCandidate,
  }) async {
    expect(initialized, isTrue);
    offers.add(peerId);
    meshPeers.add(peerId);
    meshOperations++;
    onIceCandidate('candidate:1 1 udp 1 203.0.113.1 1234 typ srflx', '0', 0);
    return 'offer';
  }

  @override
  Future<String> acceptOffer({
    required String peerId,
    required String offerSdp,
    required LocalIceCandidateHandler onIceCandidate,
  }) async {
    expect(initialized, isTrue);
    remoteSdp.add(peerId);
    meshPeers.add(peerId);
    meshOperations++;
    onIceCandidate('candidate:2 1 udp 1 203.0.113.2 1234 typ srflx', '0', 0);
    return 'answer';
  }

  @override
  Future<void> applyAnswer({
    required String peerId,
    required String answerSdp,
  }) async {
    expect(offers, contains(peerId));
    meshOperations++;
    if (!meshPeers.contains(peerId)) throw StateError('Mesh peer removed');
    remoteSdp.add(peerId);
  }

  @override
  Future<void> addIceCandidate({
    required String peerId,
    required String candidate,
    required String? sdpMid,
    required int sdpMLineIndex,
  }) async {
    if (!remoteSdp.contains(peerId)) throw StateError('Remote SDP not set');
    meshOperations++;
    candidates.add(peerId);
  }

  @override
  Future<String> createSfuPublisherOffer({
    required LocalIceCandidateHandler onIceCandidate,
  }) async {
    expect(initialized, isTrue);
    expect(key, isNotNull);
    publisherStarted = true;
    await publisherGate?.future;
    return 'publisher-offer';
  }

  @override
  Future<void> applySfuPublisherAnswer(String answerSdp) async {}
  @override
  Future<void> removePeer(String peerId) async {
    removalInProgress = true;
    try {
      await removalGate?.future;
      remoteSdp.remove(peerId);
      meshPeers.remove(peerId);
    } finally {
      removalInProgress = false;
    }
  }

  @override
  Future<void> close() async {
    closed = true;
    initialized = false;
    key = null;
  }

  @override
  Future<void> dispose() async {
    await states.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Janus extends JanusClient {
  @override
  Future<bool> connect({
    required String url,
    required String accessToken,
  }) async => true;
  @override
  Future<int> createSession() async => 1;
  @override
  Future<int> attachVideoRoom() async => 2;
  @override
  Future<List<(int, String?)>> joinAsPublisher({
    required int roomId,
    required String displayName,
  }) async => [];
  @override
  Future<String> publishSdp(String offerSdp) async => 'publisher-answer';
}
