import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:record/record.dart';

import '../services/async_operation_tracker.dart';
import 'media_attachment.dart';

const voiceNoteMaximumDuration = Duration(minutes: 10);
const _voiceMetadataPrefix = 'SCVN1:';

class VoiceNoteMetadata {
  const VoiceNoteMetadata({required this.duration, required this.waveform});

  final Duration duration;
  final List<double> waveform;

  String encode() {
    final payload = jsonEncode({
      'durationMs': duration.inMilliseconds.clamp(
        0,
        voiceNoteMaximumDuration.inMilliseconds,
      ),
      'waveform': waveform
          .take(64)
          .map((value) => (value.clamp(0.0, 1.0) * 1000).round())
          .toList(growable: false),
    });
    return '$_voiceMetadataPrefix${base64UrlEncode(utf8.encode(payload))}';
  }

  static VoiceNoteMetadata? tryDecode(String? value) {
    if (value == null || !value.startsWith(_voiceMetadataPrefix)) return null;
    try {
      final json = jsonDecode(
        utf8.decode(
          base64Url.decode(value.substring(_voiceMetadataPrefix.length)),
        ),
      );
      if (json is! Map) return null;
      final durationMs = (json['durationMs'] as num?)?.toInt();
      final samples = json['waveform'];
      if (durationMs == null ||
          durationMs < 0 ||
          durationMs > voiceNoteMaximumDuration.inMilliseconds ||
          samples is! List ||
          samples.length > 64) {
        return null;
      }
      final waveform = <double>[];
      for (final sample in samples) {
        if (sample is! num || sample < 0 || sample > 1000) return null;
        waveform.add(sample.toDouble() / 1000);
      }
      return VoiceNoteMetadata(
        duration: Duration(milliseconds: durationMs),
        waveform: List.unmodifiable(waveform),
      );
    } catch (_) {
      return null;
    }
  }
}

class VoiceNoteDraft {
  const VoiceNoteDraft({required this.attachment, required this.metadata});

  final MediaAttachment attachment;
  final VoiceNoteMetadata metadata;
}

class VoiceRecordingSnapshot {
  const VoiceRecordingSnapshot({
    required this.elapsed,
    required this.waveform,
    required this.isPaused,
  });

  final Duration elapsed;
  final List<double> waveform;
  final bool isPaused;
}

abstract interface class VoiceRecorderBackend {
  Future<bool> hasPermission();
  Future<void> start(String path);
  Future<void> pause();
  Future<void> resume();
  Future<String?> stop();
  Future<void> cancel();
  Stream<double> amplitudes();
  Future<void> dispose();
}

class PluginVoiceRecorderBackend implements VoiceRecorderBackend {
  PluginVoiceRecorderBackend({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<void> start(String path) => _recorder.start(
    const RecordConfig(
      encoder: AudioEncoder.aacLc,
      bitRate: 64000,
      sampleRate: 32000,
      numChannels: 1,
      autoGain: true,
      echoCancel: true,
      noiseSuppress: true,
    ),
    path: path,
  );

  @override
  Future<void> pause() => _recorder.pause();

  @override
  Future<void> resume() => _recorder.resume();

  @override
  Future<String?> stop() => _recorder.stop();

  @override
  Future<void> cancel() => _recorder.cancel();

  @override
  Stream<double> amplitudes() => _recorder
      .onAmplitudeChanged(const Duration(milliseconds: 100))
      .map((value) => value.max);

  @override
  Future<void> dispose() => _recorder.dispose();
}

class VoiceNoteRecorder {
  VoiceNoteRecorder({
    required VoiceRecorderBackend backend,
    required Directory recordingDirectory,
    AsyncOperationFailureHandler? onAsyncFailure,
  }) : _backend = backend,
       _recordingDirectory = recordingDirectory,
       _operations = AsyncOperationTracker(onFailure: onAsyncFailure);

  final VoiceRecorderBackend _backend;
  final Directory _recordingDirectory;
  final AsyncOperationTracker _operations;
  final StreamController<VoiceRecordingSnapshot> _snapshots =
      StreamController.broadcast();
  final Stopwatch _stopwatch = Stopwatch();
  final List<double> _waveform = [];
  final Random _random = Random.secure();
  StreamSubscription<double>? _amplitudeSubscription;
  Timer? _ticker;
  String? _path;
  bool _paused = false;
  bool _disposed = false;
  bool _disposeRequested = false;
  Future<void> _transition = Future<void>.value();
  Future<void>? _disposeTask;

  Stream<VoiceRecordingSnapshot> get snapshots => _snapshots.stream;
  bool get isRecording => _path != null;
  bool get isPaused => _paused;

  Future<void> start() => _serialize(_start);

  Future<void> _start() async {
    if (_disposed || _disposeRequested) {
      throw StateError('Ses kaydedici kapatıldı.');
    }
    if (isRecording) throw StateError('Bir ses kaydı zaten devam ediyor.');
    if (!await _backend.hasPermission()) {
      throw StateError('Mikrofon izni verilmedi.');
    }
    await _recordingDirectory.create(recursive: true);
    final suffix = _random.nextInt(0x7fffffff).toRadixString(16);
    final path =
        '${_recordingDirectory.path}/voice_${DateTime.now().microsecondsSinceEpoch}_$suffix.m4a';
    _path = path;
    _paused = false;
    _waveform.clear();
    _stopwatch
      ..reset()
      ..start();
    try {
      await _backend.start(path);
      _amplitudeSubscription = _backend.amplitudes().listen(_addAmplitude);
      _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
        _emit();
        if (_stopwatch.elapsed >= voiceNoteMaximumDuration && !_paused) {
          _operations.run('voice-recorder.auto-pause', pause());
        }
      });
      _emit();
    } catch (_) {
      _reset();
      final file = File(path);
      if (await file.exists()) await file.delete();
      rethrow;
    }
  }

  Future<void> pause() =>
      _disposeRequested ? Future<void>.value() : _serialize(_pause);

  Future<void> _pause() async {
    if (!isRecording || _paused) return;
    _paused = true;
    _stopwatch.stop();
    try {
      await _backend.pause();
      _emit();
    } catch (_) {
      _paused = false;
      _stopwatch.start();
      rethrow;
    }
  }

  Future<void> resume() =>
      _disposeRequested ? Future<void>.value() : _serialize(_resume);

  Future<void> _resume() async {
    if (!isRecording || !_paused) return;
    if (_stopwatch.elapsed >= voiceNoteMaximumDuration) return;
    await _backend.resume();
    _paused = false;
    _stopwatch.start();
    _emit();
  }

  Future<VoiceNoteDraft?> stop() {
    if (_disposeRequested) return Future<VoiceNoteDraft?>.value();
    return _serialize(_stop);
  }

  Future<VoiceNoteDraft?> _stop() async {
    final requestedPath = _path;
    if (requestedPath == null) return null;
    _stopwatch.stop();
    final duration = _stopwatch.elapsed > voiceNoteMaximumDuration
        ? voiceNoteMaximumDuration
        : _stopwatch.elapsed;
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    final outputPath = await _backend.stop() ?? requestedPath;
    final waveform = List<double>.unmodifiable(
      _waveform.isEmpty ? const [0.08] : _waveform,
    );
    _reset();
    final file = File(outputPath);
    if (!await file.exists() || await file.length() == 0) {
      if (await file.exists()) await file.delete();
      return null;
    }
    return VoiceNoteDraft(
      attachment: await MediaAttachment.fromPath(
        outputPath,
        mimeType: 'audio/mp4',
      ),
      metadata: VoiceNoteMetadata(duration: duration, waveform: waveform),
    );
  }

  Future<void> cancel() =>
      _disposeRequested ? Future<void>.value() : _serialize(_cancel);

  Future<void> _cancel() async {
    final path = _path;
    if (path == null) return;
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    try {
      await _backend.cancel();
    } finally {
      _reset();
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> dispose() {
    final active = _disposeTask;
    if (active != null) return active;
    _disposeRequested = true;
    final operation = _serialize(_dispose);
    _disposeTask = operation;
    return operation;
  }

  Future<void> _dispose() async {
    if (isRecording) await _cancel();
    await _operations.close();
    _disposed = true;
    await _backend.dispose();
    await _snapshots.close();
  }

  Future<T> _serialize<T>(Future<T> Function() action) {
    final operation = _transition.then((_) => action());
    _transition = operation.then<void>((_) {}, onError: (_, _) {});
    return operation;
  }

  void _addAmplitude(double decibels) {
    final normalized = ((decibels + 60) / 60).clamp(0.04, 1.0).toDouble();
    _waveform.add(normalized);
    if (_waveform.length > 64) {
      final reduced = <double>[];
      for (var index = 0; index < _waveform.length; index += 2) {
        final next = index + 1;
        reduced.add(
          next < _waveform.length
              ? max(_waveform[index], _waveform[next])
              : _waveform[index],
        );
      }
      _waveform
        ..clear()
        ..addAll(reduced);
    }
    _emit();
  }

  void _emit() {
    if (_snapshots.isClosed || !isRecording) return;
    _snapshots.add(
      VoiceRecordingSnapshot(
        elapsed: _stopwatch.elapsed,
        waveform: List.unmodifiable(_waveform),
        isPaused: _paused,
      ),
    );
  }

  void _reset() {
    _ticker?.cancel();
    _ticker = null;
    _stopwatch
      ..stop()
      ..reset();
    _path = null;
    _paused = false;
  }
}
