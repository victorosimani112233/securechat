import 'dart:async';

import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../services/async_operation_tracker.dart';
import 'call_models.dart';

abstract interface class CallTonePlayer {
  Future<void> startRingback();
  Future<void> stopRingback();
  Future<void> playConnectedCue();
  Future<void> playEndedCue();
  Future<void> dispose();
}

class JustAudioCallTonePlayer implements CallTonePlayer {
  JustAudioCallTonePlayer({AudioPlayer? player})
    : _player = player ?? AudioPlayer();

  final AudioPlayer _player;
  bool _disposed = false;

  @override
  Future<void> startRingback() async {
    if (_disposed) return;
    await _player.stop();
    await _player.setLoopMode(LoopMode.one);
    await _player.setAsset('assets/sounds/elcim_ringback.wav');
    unawaited(_player.play().catchError((_) {}));
  }

  @override
  Future<void> stopRingback() async {
    if (_disposed) return;
    await _player.stop();
  }

  @override
  Future<void> playConnectedCue() =>
      _playOnce('assets/sounds/elcim_call_connected.wav');

  @override
  Future<void> playEndedCue() =>
      _playOnce('assets/sounds/elcim_call_ended.wav');

  Future<void> _playOnce(String asset) async {
    if (_disposed) return;
    await _player.stop();
    await _player.setLoopMode(LoopMode.off);
    await _player.setAsset(asset);
    unawaited(_player.play().catchError((_) {}));
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _player.dispose();
  }
}

/// Uses the operating system's call-signalling audio path and falls back to
/// just_audio on platforms where the native bridge is unavailable.
class PlatformCallTonePlayer implements CallTonePlayer {
  PlatformCallTonePlayer({MethodChannel? channel, CallTonePlayer? fallback})
    : _channel = channel ?? const MethodChannel('com.securechat/native'),
      _fallback = fallback ?? JustAudioCallTonePlayer();

  final MethodChannel _channel;
  final CallTonePlayer _fallback;
  bool _nativeAvailable = true;

  Future<bool> _invoke(String method, [Map<String, Object?>? arguments]) async {
    if (!_nativeAvailable) return false;
    try {
      final handled = await _channel.invokeMethod<bool>(method, arguments);
      if (handled == true) return true;
    } on MissingPluginException {
      _nativeAvailable = false;
    } on PlatformException {
      // A device-specific native audio failure falls back to packaged audio.
    }
    return false;
  }

  @override
  Future<void> startRingback() async {
    if (!await _invoke('startNativeCallRingback')) {
      await _fallback.startRingback();
    }
  }

  @override
  Future<void> stopRingback() async {
    await _invoke('stopNativeCallTones');
    await _fallback.stopRingback();
  }

  @override
  Future<void> playConnectedCue() async {
    if (!await _invoke('playNativeCallCue', {'cue': 'connected'})) {
      await _fallback.playConnectedCue();
    }
  }

  @override
  Future<void> playEndedCue() async {
    if (!await _invoke('playNativeCallCue', {'cue': 'ended'})) {
      await _fallback.playEndedCue();
    }
  }

  @override
  Future<void> dispose() async {
    await _invoke('stopNativeCallTones');
    await _fallback.dispose();
  }
}

class CallToneCoordinator {
  CallToneCoordinator({
    required Stream<CallSession?> sessions,
    required CallTonePlayer player,
    AsyncOperationFailureHandler? onAsyncFailure,
  }) : _sessions = sessions,
       _player = player,
       _operations = AsyncOperationTracker(onFailure: onAsyncFailure);

  final Stream<CallSession?> _sessions;
  final CallTonePlayer _player;
  final AsyncOperationTracker _operations;
  StreamSubscription<CallSession?>? _subscription;
  Future<void> _transition = Future<void>.value();
  CallSession? _previous;
  bool _ringbackPlaying = false;
  bool _closed = false;

  void start() {
    if (_closed) throw StateError('Call tone coordinator is closed');
    _subscription ??= _sessions.listen(
      _onSession,
      onError: (Object error, StackTrace stackTrace) {
        if (_operations.isClosed) return;
        _operations.run(
          'call-tone.session-stream',
          Future<void>.error(error, stackTrace),
        );
      },
    );
  }

  void _onSession(CallSession? session) {
    final previous = _previous;
    _previous = session;
    final sameCall =
        previous != null &&
        session != null &&
        previous.callId == session.callId;
    final shouldRing =
        session != null &&
        !session.isGroupCall &&
        session.direction == CallDirection.outgoing &&
        (session.state == CallState.initiating ||
            session.state == CallState.ringing);
    final answered =
        sameCall &&
        !session.isGroupCall &&
        !previous.isTerminal &&
        ((session.state == CallState.connecting &&
                previous.state != CallState.connecting &&
                previous.state != CallState.active) ||
            (session.state == CallState.active &&
                previous.state != CallState.connecting &&
                previous.state != CallState.active));
    final ended = sameCall && !previous.isTerminal && session.isTerminal;
    final wasRinging = _ringbackPlaying;
    _ringbackPlaying = shouldRing;
    if (shouldRing == wasRinging && !answered && !ended) return;

    final operation = _transition.then((_) async {
      if (_closed) return;
      if (ended) {
        await _player.stopRingback();
        await _player.playEndedCue();
      } else if (answered) {
        await _player.stopRingback();
        await _player.playConnectedCue();
      } else if (shouldRing) {
        await _player.startRingback();
      } else if (wasRinging) {
        await _player.stopRingback();
      }
    });
    _transition = operation.catchError((_) {});
    _operations.run('call-tone.update', operation);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _ringbackPlaying = false;
    await _subscription?.cancel();
    _subscription = null;
    await _transition;
    await _operations.close();
    try {
      await _player.stopRingback();
    } finally {
      await _player.dispose();
    }
  }
}
