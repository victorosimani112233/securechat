import 'dart:async';
import 'dart:io';

import 'package:flutter_securechat/src/media/call_models.dart';
import 'package:flutter_securechat/src/media/call_tone_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ringback, connected and ended tones follow call transitions', () async {
    final sessions = StreamController<CallSession?>.broadcast();
    final player = _FakeCallTonePlayer();
    final coordinator = CallToneCoordinator(
      sessions: sessions.stream,
      player: player,
    )..start();

    sessions.add(_session(CallDirection.outgoing, CallState.initiating));
    await _flush();
    expect(player.ringbackCount, 1);

    sessions.add(_session(CallDirection.outgoing, CallState.ringing));
    await _flush();
    expect(player.ringbackCount, 1);

    sessions.add(_session(CallDirection.outgoing, CallState.connecting));
    await _flush();
    expect(player.stopCount, 1);
    expect(player.connectedCount, 1);

    sessions.add(_session(CallDirection.outgoing, CallState.active));
    await _flush();
    expect(player.connectedCount, 1);

    sessions.add(_session(CallDirection.outgoing, CallState.ended));
    await _flush();
    expect(player.stopCount, 2);
    expect(player.endedCount, 1);

    await coordinator.close();
    await sessions.close();
    expect(player.disposed, isTrue);
  });

  test('all call PCM assets are packaged for Flutter and native apps', () {
    for (final name in const [
      'elcim_ringback.wav',
      'elcim_call_connected.wav',
      'elcim_call_ended.wav',
    ]) {
      for (final path in [
        'assets/sounds/$name',
        'android/app/src/main/res/raw/$name',
        'ios/Runner/Sounds/$name',
      ]) {
        final asset = File(path);
        expect(asset.existsSync(), isTrue, reason: '$path is missing');
        expect(asset.lengthSync(), greaterThan(1000));
      }
    }
    expect(File('pubspec.yaml').readAsStringSync(), contains('assets/sounds/'));
  });
}

CallSession _session(CallDirection direction, CallState state) => CallSession(
  callId: 'call-1',
  peerId: 'alice',
  peerName: 'Alice',
  callType: CallType.voice,
  direction: direction,
  state: state,
);

Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _FakeCallTonePlayer implements CallTonePlayer {
  int ringbackCount = 0;
  int stopCount = 0;
  int connectedCount = 0;
  int endedCount = 0;
  bool disposed = false;

  @override
  Future<void> startRingback() async => ringbackCount++;

  @override
  Future<void> stopRingback() async => stopCount++;

  @override
  Future<void> playConnectedCue() async => connectedCount++;

  @override
  Future<void> playEndedCue() async => endedCount++;

  @override
  Future<void> dispose() async => disposed = true;
}
