import 'dart:async';

import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/media/call_manager.dart';
import 'package:flutter_securechat/src/media/call_models.dart';
import 'package:flutter_securechat/src/media/group_media_engine.dart';
import 'package:flutter_securechat/src/media/ice_server_fetcher.dart';
import 'package:flutter_securechat/src/media/media_engine.dart';
import 'package:flutter_securechat/src/media/native_call_integration.dart';
import 'package:flutter_securechat/src/notifications/missed_call_tracker.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'busy direct retransmissions produce one log and notification, no secondary',
    () async {
      final f = await _Fixture.open();
      final active = await f.startDirect();
      final offer = _offer('outsider', 'attempt-1');
      await f.deliver([offer, offer, offer]);

      f.expectPreserved(active);
      expect(f.busyControls, isNotEmpty);
      expect(
        f.busyControls.every(
          (s) => s.recipientId == 'outsider' && s.groupId == null,
        ),
        isTrue,
      );
      expect(f.logs.rows, hasLength(1));
      expect(f.missed.triggered, hasLength(1));
      _expectBusy(
        f.logs.rows.single,
        f.missed.triggered.single,
        peer: 'outsider',
      );
      expect(f.failures, isEmpty);
    },
  );

  test('different SDP or sender is a new busy direct attempt', () async {
    final f = await _Fixture.open();
    final active = await f.startDirect();
    await f.deliver([
      _offer('outsider', 'attempt-1'),
      _offer('outsider', 'attempt-2'),
      _offer('another-peer', 'attempt-1'),
    ]);
    f.expectPreserved(active);
    expect(f.logs.rows, hasLength(3));
    expect(f.logs.rows.map((log) => log.id).toSet(), hasLength(3));
    expect(f.missed.triggered.map((call) => call.peerId), [
      'outsider',
      'outsider',
      'another-peer',
    ]);
  });

  test('busy direct dedupe is bounded and evicts the oldest attempt', () async {
    final f = await _Fixture.open();
    final active = await f.startDirect();
    await f.deliver([
      for (var i = 0; i < 129; i++) _offer('outsider', 'attempt-$i'),
    ]);
    expect(f.logs.rows, hasLength(129));
    expect(f.logs.writeCount, 129);
    await f.deliver([_offer('outsider', 'attempt-128')]);
    expect(f.logs.rows, hasLength(129));
    expect(f.logs.writeCount, 129);
    await f.deliver([_offer('outsider', 'attempt-0')]);
    expect(f.logs.rows, hasLength(129));
    expect(f.logs.writeCount, 130);
    expect(f.missed.triggered, hasLength(130));
    f.expectPreserved(active);
  });

  test(
    'offers from the ongoing direct peer are ignored, not treated as busy',
    () async {
      final f = await _Fixture.open();
      final active = await f.startDirect();
      await f.deliver([
        _offer('current-peer', 'original-offer'),
        _offer('current-peer', 'original-offer'),
        _offer('current-peer', 'updated-offer'),
      ]);
      f.expectPreserved(active);
      expect(f.signaling.sentMessages, isEmpty);
      expect(f.logs.rows, isEmpty);
      expect(f.missed.triggered, isEmpty);
    },
  );

  for (final activeGroup in [false, true]) {
    test(
      'third-party stale controls do not alter active group=$activeGroup call',
      () async {
        final f = await _Fixture.open();
        final active = activeGroup
            ? await f.startGroup()
            : await f.startDirect();
        await f.deliver([
          for (final action in [
            'BUSY',
            'REJECT',
            'HANGUP',
            'ACCEPT',
            'CAMERA_OFF',
          ])
            CallControlSignal(
              senderId: 'outsider',
              recipientId: 'me',
              timestamp: DateTime.now(),
              action: action,
              groupId: activeGroup ? _activeToken : null,
            ),
        ]);
        f.expectPreserved(active);
        expect(f.logs.rows, isEmpty);
        expect(f.missed.triggered, isEmpty);
      },
    );
  }

  test('group-scoped controls from current direct peer are ignored', () async {
    final f = await _Fixture.open();
    final active = await f.startDirect();
    await f.deliver([
      for (final action in ['BUSY', 'REJECT', 'HANGUP', 'ACCEPT', 'CAMERA_OFF'])
        CallControlSignal(
          senderId: 'current-peer',
          recipientId: 'me',
          timestamp: DateTime.now(),
          action: action,
          groupId: _otherToken,
        ),
    ]);
    f.expectPreserved(active);
    expect(f.logs.rows, isEmpty);
    expect(f.missed.triggered, isEmpty);
  });

  test('busy group invites notify once per token and call ID', () async {
    final f = await _Fixture.open();
    final active = await f.startDirect();
    final invite = _invite('busy-group-1', token: _otherToken);
    await f.deliver([invite, invite]);
    f.expectPreserved(active);
    expect(f.busyControls, isNotEmpty);
    expect(
      f.busyControls.every(
        (s) => s.recipientId == 'coordinator' && s.groupId == _otherToken,
      ),
      isTrue,
    );
    expect(f.logs.rows, hasLength(1));
    expect(f.missed.triggered, hasLength(1));
    _expectBusy(
      f.logs.rows.single,
      f.missed.triggered.single,
      peer: 'coordinator',
      groupId: 'other-group',
    );
    expect(f.logs.rows.single.id, 'busy-group-1');
    expect(f.missed.triggered.single.peerName, 'name:other-group');

    await f.deliver([_invite('busy-group-2', token: _otherToken)]);
    expect(f.logs.rows, hasLength(2));
    expect(f.missed.triggered, hasLength(2));
    f.expectPreserved(active);
  });

  test(
    'stale invite for active routing token cannot BUSY or HANGUP the room',
    () async {
      final f = await _Fixture.open();
      final active = await f.startGroup();
      await f.deliver([
        _invite(active.callId),
        _invite('old-call-id'),
        _invite('another-stale-call', sender: 'outsider'),
      ]);
      f.expectPreserved(active);
      expect(f.signaling.sentMessages, isEmpty);
      expect(f.logs.rows, isEmpty);
      expect(f.missed.triggered, isEmpty);
    },
  );

  test(
    'active group rejects outsider direct SDP but still accepts its participant',
    () async {
      final f = await _Fixture.open();
      final active = await f.startGroup();
      await f.deliver([_offer('outsider', 'direct-offer')]);
      f.expectPreserved(active);
      expect(f.busyControls.single.recipientId, 'outsider');
      expect(f.logs.rows, hasLength(1));
      expect(f.missed.triggered, hasLength(1));
      _expectBusy(
        f.logs.rows.single,
        f.missed.triggered.single,
        peer: 'outsider',
      );
      expect(f.groupMedia.acceptedOffers, isEmpty);

      // This participant is already in peerIds; the validator deliberately
      // returns false for it to exercise the peerIds OR membership rule.
      await f.deliver([_offer('member', 'mesh-offer')]);
      expect(f.groupMedia.acceptedOffers, {'member': 'mesh-offer'});
      expect(
        f.signaling.sentMessages
            .whereType<SdpAnswerSignal>()
            .single
            .recipientId,
        'member',
      );
      expect(f.manager.currentSession, same(active));
      expect(f.logs.rows, hasLength(1));
      expect(f.missed.triggered, hasLength(1));
    },
  );

  test(
    'validated group SDP arriving before membership is buffered, not BUSY',
    () async {
      final f = await _Fixture.open();
      final active = await f.startGroup();
      await f.deliver([_offer('late-member', 'early-mesh-offer')]);
      f.expectPreserved(active);
      expect(f.busyControls, isEmpty);
      expect(f.missed.triggered, isEmpty);
      expect(f.groupMedia.acceptedOffers, isEmpty);

      await f.deliver([
        GroupCallMemberJoinedSignal(
          senderId: 'coordinator',
          recipientId: 'me',
          timestamp: DateTime.now(),
          groupCallId: active.callId,
          joinedMemberId: 'late-member',
        ),
      ]);
      expect(f.groupMedia.acceptedOffers, {'late-member': 'early-mesh-offer'});
      expect(f.manager.currentSession!.callId, active.callId);
      expect(f.manager.currentSession!.state, CallState.active);
      expect(f.busyControls, isEmpty);
      expect(f.logs.rows, isEmpty);
    },
  );

  for (final activeGroup in [false, true]) {
    for (final incomingGroup in [false, true]) {
      test(
        'throwing busy notification preserves active group=$activeGroup for incoming group=$incomingGroup',
        () async {
          final f = await _Fixture.open();
          final active = activeGroup
              ? await f.startGroup()
              : await f.startDirect();
          final error = StateError('notification unavailable');
          f.missed.failure = error;
          final incoming = incomingGroup
              ? _invite('failed-notification', token: _otherToken)
              : _offer('outsider', 'failed-notification');
          await f.deliver([incoming]);
          f.expectPreserved(active);
          await f.deliver([incoming]);

          f.expectPreserved(active);
          expect(f.logs.rows, hasLength(1));
          expect(f.logs.rows.single.status, 'BUSY');
          expect(f.logs.writeCount, 2);
          expect(f.missed.triggered, hasLength(2));
          expect(
            f.missed.triggered.map((call) => call.state),
            everyElement(CallState.busy),
          );
          expect(f.failures, hasLength(2));
          for (final failure in f.failures) {
            expect(failure.$1, startsWith('call-manager.'));
            expect(failure.$2, same(error));
          }
          expect(f.busyControls, isNotEmpty);
        },
      );
    }

    test(
      'busy notification retry reuses one history ID with active group=$activeGroup',
      () async {
        final f = await _Fixture.open();
        final active = activeGroup
            ? await f.startGroup()
            : await f.startDirect();
        final error = StateError('temporary notification failure');
        final offer = _offer('outsider', 'retry-offer');
        f.missed.failure = error;
        await f.deliver([offer]);
        f.expectPreserved(active);
        expect(f.logs.rows, hasLength(1));
        expect(f.missed.triggered, hasLength(1));
        expect(f.failures, hasLength(1));
        expect(f.failures.single.$2, same(error));
        final busyId = f.logs.rows.single.id;
        expect(busyId, startsWith('busy-'));

        f.missed.failure = null;
        await f.deliver([offer]);
        f.expectPreserved(active);
        expect(f.logs.rows, hasLength(1));
        expect(f.logs.rows.single.id, busyId);
        expect(f.logs.writeCount, 2);
        expect(f.missed.triggered.map((call) => call.callId), [busyId, busyId]);
        _expectBusy(
          f.logs.rows.single,
          f.missed.triggered.last,
          peer: 'outsider',
        );
        expect(f.failures, hasLength(1));

        await f.deliver([offer]);
        f.expectPreserved(active);
        expect(f.logs.rows, hasLength(1));
        expect(f.logs.writeCount, 2);
        expect(f.missed.triggered, hasLength(2));
        expect(f.failures, hasLength(1));
      },
    );
  }
}

const _activeToken = 'active-routing-token';
const _otherToken = 'other-routing-token';

SdpOfferSignal _offer(String sender, String sdp) => SdpOfferSignal(
  senderId: sender,
  recipientId: 'me',
  timestamp: DateTime.now(),
  sdp: sdp,
  callType: 'VOICE',
);

GroupCallInviteSignal _invite(
  String callId, {
  String token = _activeToken,
  String sender = 'coordinator',
}) => GroupCallInviteSignal(
  senderId: sender,
  recipientId: 'me',
  timestamp: DateTime.now(),
  groupId: token,
  callId: callId,
  callType: 'VOICE',
  participants: const ['coordinator', 'member', 'me'],
);

void _expectBusy(
  CallLogEntity log,
  CallSession notification, {
  required String peer,
  String? groupId,
}) {
  expect(log.status, 'BUSY');
  expect(log.direction, 'INCOMING');
  expect(log.peerId, peer);
  expect(log.groupId, groupId);
  expect(notification.callId, log.id);
  expect(notification.peerId, peer);
  expect(notification.state, CallState.busy);
  expect(notification.direction, CallDirection.incoming);
  expect(notification.isGroupCall, groupId != null);
  expect(notification.groupId, groupId);
}

class _Fixture {
  final signaling = _AutoAckSignaling();
  final media = _FakeMedia();
  final groupMedia = _FakeGroupMedia();
  final native = _FakeNative();
  final missed = _FakeMissed();
  final logs = _MemoryCallLogs();
  final failures = <(String, Object)>[];
  final secondary = <CallSession?>[];
  late final CallManager manager;
  late final StreamSubscription<CallSession?> _secondarySubscription;

  static Future<_Fixture> open() async {
    final f = _Fixture();
    await f.signaling.connect(
      userId: 'me',
      url: 'wss://test.invalid',
      accessToken: 'token',
    );
    f.manager = CallManager(
      session: SessionStore(userId: 'me', accessToken: 'token'),
      signaling: f.signaling,
      media: f.media,
      groupMedia: f.groupMedia,
      iceServers: const StaticIceServerProvider([]),
      callLogs: f.logs,
      nativeCalls: f.native,
      missedCalls: f.missed,
      peerNameResolver: (peer) async => 'name:$peer',
      groupLocalIdResolver: (token) async => switch (token) {
        _activeToken => 'active-group',
        _otherToken => 'other-group',
        _ => null,
      },
      groupMemberValidator: (_, peer) async =>
          const {'coordinator', 'late-member'}.contains(peer),
      onAsyncFailure: (operation, error, _) =>
          f.failures.add((operation, error)),
      ringTimeout: const Duration(hours: 1),
    );
    f._secondarySubscription = f.manager.secondarySessions.listen(
      f.secondary.add,
    );
    addTearDown(() async {
      await f._secondarySubscription.cancel();
      await f.manager.dispose();
      await f.signaling.dispose();
    });
    return f;
  }

  Future<void> deliver(List<SignalMessage> signals) async {
    for (final signal in signals) {
      signaling.addIncoming(signal);
    }
    // All fakes complete in microtasks; no disk, network or plugin work occurs.
    await Future<void>.delayed(Duration.zero);
  }

  Future<CallSession> startDirect() async {
    await deliver([_offer('current-peer', 'original-offer')]);
    expect(await manager.acceptCall(), isTrue);
    media.states.add(MediaConnectionState.connected);
    await deliver([]);
    return _baseline();
  }

  Future<CallSession> startGroup() async {
    await deliver([_invite('active-call')]);
    expect(await manager.acceptCall(), isTrue);
    groupMedia.states.add(
      const GroupPeerState('coordinator', MediaConnectionState.connected),
    );
    await deliver([]);
    return _baseline();
  }

  CallSession _baseline() {
    final active = manager.currentSession!;
    expect(active.state, CallState.active);
    expect(failures, isEmpty);
    signaling.sentMessages.clear();
    native.events.clear();
    media.events.clear();
    groupMedia.events.clear();
    missed.started.clear();
    missed.cancelled.clear();
    secondary.clear();
    return active;
  }

  Iterable<CallControlSignal> get busyControls => signaling.sentMessages
      .whereType<CallControlSignal>()
      .where((signal) => signal.action == 'BUSY');

  void expectPreserved(CallSession active) {
    expect(manager.currentSession, same(active));
    expect(manager.currentSession!.state, CallState.active);
    expect(manager.secondarySession, isNull);
    expect(secondary.whereType<CallSession>(), isEmpty);
    expect(native.events, isEmpty);
    expect(media.events, isEmpty);
    expect(groupMedia.events, isEmpty);
    expect(missed.started, isEmpty);
    expect(missed.cancelled, isEmpty);
  }
}

class _MemoryCallLogs extends Fake implements CallLogDao {
  final _byId = <String, CallLogEntity>{};
  Iterable<CallLogEntity> get rows => _byId.values;
  int writeCount = 0;
  @override
  Future<void> insert(CallLogEntity row) async {
    writeCount++;
    _byId[row.id] = row;
  }
}

class _FakeMissed implements MissedCallLifecycle {
  final started = <CallSession>[];
  final cancelled = <String>[];
  final triggered = <CallSession>[];
  Object? failure;
  @override
  void start(CallSession session) => started.add(session);
  @override
  void cancel(String callId) => cancelled.add(callId);
  @override
  Future<void> triggerNow(CallSession session) async {
    triggered.add(session);
    if (failure != null) throw failure!;
  }

  @override
  Future<void> close() async {}
}

class _FakeMedia extends Fake implements MediaEngine {
  final states = StreamController<MediaConnectionState>.broadcast();
  final events = <String>[];
  @override
  Stream<MediaConnectionState> get connectionStates => states.stream;
  @override
  Future<String> acceptOffer({
    required String offerSdp,
    required bool video,
    required List<IceServerConfig> iceServers,
    required LocalIceCandidateHandler onIceCandidate,
  }) async {
    events.add('accept:$offerSdp');
    return 'answer';
  }

  @override
  Future<void> close() async {
    events.add('close');
  }

  @override
  Future<void> dispose() => states.close();
}

class _FakeGroupMedia extends Fake implements GroupMediaEngine {
  final states = StreamController<GroupPeerState>.broadcast();
  final events = <String>[];
  final acceptedOffers = <String, String>{};
  @override
  Stream<GroupPeerState> get peerStates => states.stream;
  @override
  Future<void> initialize({
    required bool video,
    required List<IceServerConfig> iceServers,
  }) async {
    events.add('initialize');
  }

  @override
  Future<String> createOffer({
    required String peerId,
    required LocalIceCandidateHandler onIceCandidate,
  }) async {
    events.add('offer:$peerId');
    return 'mesh-offer';
  }

  @override
  Future<String> acceptOffer({
    required String peerId,
    required String offerSdp,
    required LocalIceCandidateHandler onIceCandidate,
  }) async {
    events.add('accept:$peerId');
    acceptedOffers[peerId] = offerSdp;
    return 'mesh-answer';
  }

  @override
  Future<void> removePeer(String peerId) async {
    events.add('remove:$peerId');
  }

  @override
  Future<void> close() async {
    events.add('close');
  }

  @override
  Future<void> dispose() => states.close();
}

class _FakeNative extends Fake implements NativeCallIntegration {
  final events = <String>[];
  @override
  Stream<NativeCallAction> get actions => const Stream.empty();
  @override
  Future<void> reportIncoming(CallSession session) async {
    events.add('incoming:${session.callId}');
  }

  @override
  Future<void> reportOutgoing(CallSession session) async {
    events.add('outgoing:${session.callId}');
  }

  @override
  Future<void> answer(String callId) async {
    events.add('answer:$callId');
  }

  @override
  Future<void> setActive(String callId) async {
    events.add('active:$callId');
  }

  @override
  Future<void> end(String callId) async {
    events.add('end:$callId');
  }
}

class _AutoAckSignaling extends InMemorySignalingService {
  @override
  Future<bool> send(SignalMessage message) async {
    final sent = await super.send(message);
    if (message is CallControlSignal && message.messageId != null) {
      addIncoming(
        CallControlAckSignal(
          recipientId: 'me',
          timestamp: DateTime.now(),
          messageId: message.messageId!,
          action: message.action,
        ),
      );
    }
    return sent;
  }
}
