import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/media/call_manager.dart';
import 'package:flutter_securechat/src/media/call_models.dart';
import 'package:flutter_securechat/src/media/ice_server_fetcher.dart';
import 'package:flutter_securechat/src/media/media_engine.dart';
import 'package:flutter_securechat/src/media/native_call_integration.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/ios-outgoing-call');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late MethodChannelNativeCallIntegration native;
  late InMemorySignalingService signaling;
  late _Media media;
  late _CallLogs logs;
  late CallManager manager;
  late List<Object> failures;
  late List<String> failureStages;

  setUp(() async {
    native = MethodChannelNativeCallIntegration(channel: channel);
    signaling = InMemorySignalingService();
    await signaling.connect(
      userId: 'me',
      url: 'ws://test.invalid',
      accessToken: 'test',
    );
    media = _Media();
    logs = _CallLogs();
    failures = [];
    failureStages = [];
    manager = CallManager(
      session: SessionStore(userId: 'me', accessToken: 'test'),
      signaling: signaling,
      media: media,
      iceServers: const StaticIceServerProvider([]),
      callLogs: logs,
      nativeCalls: native,
      terminalVisibility: Duration.zero,
      onAsyncFailure: (operation, error, _) {
        failures.add(error);
        failureStages.add(operation);
      },
    );
  });

  tearDown(() async {
    await manager.dispose();
    await native.dispose();
    await signaling.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'native outgoing registration gates media and the signaling offer',
    () async {
      final accepted = Completer<void>();
      final requested = Completer<MethodCall>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'reportOutgoingCall') {
          requested.complete(call);
          await accepted.future;
        }
        return null;
      });
      final started = manager.initiateCall(
        peerId: 'private-account',
        peerName: 'Private Name',
        callType: CallType.video,
      );
      final request = await requested.future;
      expect(manager.currentSession?.state, CallState.initiating);
      expect(media.offers, 0);
      expect(signaling.sentMessages.whereType<SdpOfferSignal>(), isEmpty);
      expect(request.arguments, containsPair('hasVideo', true));
      expect(request.arguments, containsPair('peerId', 'private'));
      expect(request.arguments.toString(), isNot(contains('Private Name')));

      accepted.complete();
      expect(await started, isTrue);
      expect(media.offers, 1);
      expect(manager.currentSession?.state, CallState.ringing);
      expect(signaling.sentMessages.whereType<SdpOfferSignal>(), hasLength(1));
    },
  );

  test(
    'rejected CallKit start fails before offer and clean native end permits retry',
    () async {
      var rejectStart = true;
      final methods = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        methods.add(call.method);
        if (call.method == 'reportOutgoingCall' && rejectStart) {
          throw PlatformException(
            code: 'CALLKIT_OUTGOING_FAILED',
            details: {
              'domain': 'com.apple.CallKit.error.requesttransaction',
              'code': 1,
            },
          );
        }
        // The Swift regression tests verify rejected UUIDs are forgotten so
        // endNativeCall succeeds here without a second invalid transaction.
        return null;
      });
      Future<bool> dial() => manager.initiateCall(
        peerId: 'peer',
        peerName: 'Peer',
        callType: CallType.voice,
      );

      expect(await dial(), isFalse);
      expect(media.offers, 0);
      expect(signaling.sentMessages.whereType<SdpOfferSignal>(), isEmpty);
      expect(methods, ['reportOutgoingCall', 'endNativeCall']);
      expect(logs.entries.single.status, 'FAILED');
      expect(failures.single, isA<PlatformException>());
      expect(failureStages, ['call-manager.initiate-call.native-registration']);
      expect(
        (failures.single as PlatformException).details,
        containsPair('code', 1),
      );
      await manager.sessions.firstWhere((session) => session == null);

      rejectStart = false;
      expect(await dial(), isTrue);
      expect(media.offers, 1);
      expect(manager.currentSession?.state, CallState.ringing);
    },
  );
}

class _CallLogs implements CallLogDao {
  final entries = <CallLogEntity>[];

  @override
  Future<void> insert(CallLogEntity entry) async => entries.add(entry);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Media implements MediaEngine {
  final _states = StreamController<MediaConnectionState>.broadcast();
  int offers = 0;

  @override
  Stream<MediaConnectionState> get connectionStates => _states.stream;

  @override
  Future<String> createOffer({
    required bool video,
    required List<IceServerConfig> iceServers,
    required LocalIceCandidateHandler onIceCandidate,
  }) async {
    offers++;
    return 'v=0\r\n';
  }

  @override
  Future<void> close() async {}

  @override
  Future<void> dispose() => _states.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
