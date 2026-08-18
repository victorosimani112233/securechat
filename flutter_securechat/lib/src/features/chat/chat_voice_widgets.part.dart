part of 'chat_screen.dart';

class _VoiceRecorderSheet extends StatefulWidget {
  const _VoiceRecorderSheet({required this.recorder});

  final VoiceNoteRecorder recorder;

  @override
  State<_VoiceRecorderSheet> createState() => _VoiceRecorderSheetState();
}

class _VoiceRecorderSheetState extends State<_VoiceRecorderSheet> {
  StreamSubscription<VoiceRecordingSnapshot>? _subscription;
  VoiceRecordingSnapshot _snapshot = const VoiceRecordingSnapshot(
    elapsed: Duration.zero,
    waveform: [],
    isPaused: false,
  );
  String? _error;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _subscription = widget.recorder.snapshots.listen((snapshot) {
      if (mounted) setState(() => _snapshot = snapshot);
    });
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      await widget.recorder.start();
      if (mounted) setState(() => _busy = false);
    } catch (error) {
      if (mounted)
        setState(() {
          _busy = false;
          _error = '$error';
        });
    }
  }

  Future<void> _cancel() async {
    if (_busy) return;
    setState(() => _busy = true);
    await widget.recorder.cancel();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _finish() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final draft = await widget.recorder.stop();
      if (!mounted) return;
      if (draft == null) {
        setState(() {
          _busy = false;
          _error = context.l10n.invalid_voice_recording;
        });
        return;
      }
      Navigator.pop(context, draft);
    } catch (error) {
      if (mounted)
        setState(() {
          _busy = false;
          _error = '$error';
        });
    }
  }

  Future<void> _togglePause() async {
    if (_busy) return;
    if (_snapshot.isPaused) {
      await widget.recorder.resume();
    } else {
      await widget.recorder.pause();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    if (widget.recorder.isRecording) unawaited(_cancelAfterDismiss());
    super.dispose();
  }

  Future<void> _cancelAfterDismiss() async {
    try {
      await widget.recorder.cancel();
    } catch (_) {
      // The recorder owns backend cleanup; a dismissed route has no UI target
      // for a secondary cancellation error.
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error == null
                  ? context.l10n.voice_message
                  : context.l10n.recording_start_failed,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Text(_error!, textAlign: TextAlign.center)
            else ...[
              _Waveform(
                samples: _snapshot.waveform,
                progress: 1,
                activeColor: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                _durationLabel(_snapshot.elapsed),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                _snapshot.isPaused
                    ? context.l10n.recording_paused
                    : context.l10n.recording_active,
              ),
            ],
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: _busy ? null : _cancel,
                  icon: const Icon(Icons.delete_outline),
                  label: Text(context.l10n.cancel),
                ),
                if (_error == null)
                  IconButton.filledTonal(
                    onPressed: _busy ? null : _togglePause,
                    icon: Icon(_snapshot.isPaused ? Icons.mic : Icons.pause),
                  ),
                FilledButton.icon(
                  onPressed: _busy || _error != null ? null : _finish,
                  icon: const Icon(Icons.send),
                  label: Text(context.l10n.send),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceNoteContent extends StatefulWidget {
  const _VoiceNoteContent({required this.message, required this.outgoing});

  final LocalMessage message;
  final bool outgoing;

  @override
  State<_VoiceNoteContent> createState() => _VoiceNoteContentState();
}

class _VoiceNoteContentState extends State<_VoiceNoteContent> {
  final AudioPlayer _player = AudioPlayer();
  bool _loaded = false;
  String? _error;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final path = widget.message.filePath;
    if (path == null || !await File(path).exists()) {
      if (mounted) setState(() => _error = context.l10n.audio_not_found);
      return;
    }
    try {
      if (!_loaded) {
        await _player.setFilePath(path);
        _loaded = true;
      }
      if (_player.processingState == ProcessingState.completed) {
        await _player.seek(Duration.zero);
      }
      if (_player.playing) {
        await _player.pause();
      } else {
        await _player.play();
      }
    } catch (_) {
      if (mounted) setState(() => _error = context.l10n.audio_play_failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final foreground = widget.outgoing
        ? Theme.of(context).colorScheme.onPrimary
        : Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      width: 250,
      child: StreamBuilder<PlayerState>(
        stream: _player.playerStateStream,
        builder: (context, stateSnapshot) => StreamBuilder<Duration>(
          stream: _player.positionStream,
          builder: (context, positionSnapshot) {
            final state = stateSnapshot.data;
            final playing = state?.playing == true;
            final position = positionSnapshot.data ?? Duration.zero;
            final duration =
                _player.duration ??
                widget.message.voiceNoteDuration ??
                Duration.zero;
            final progress = duration.inMilliseconds <= 0
                ? 0.0
                : (position.inMilliseconds / duration.inMilliseconds).clamp(
                    0.0,
                    1.0,
                  );
            return Row(
              children: [
                IconButton.filledTonal(
                  tooltip: playing ? 'Duraklat' : 'Oynat',
                  onPressed: _toggle,
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Waveform(
                        samples: widget.message.voiceNoteWaveform,
                        progress: progress,
                        activeColor: foreground,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _error ??
                            _durationLabel(
                              playing || position > Duration.zero
                                  ? position
                                  : duration,
                            ),
                        style: TextStyle(fontSize: 11, color: foreground),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Waveform extends StatelessWidget {
  const _Waveform({
    required this.samples,
    required this.progress,
    required this.activeColor,
  });

  final List<double> samples;
  final double progress;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    final values = samples.isEmpty
        ? List<double>.filled(24, 0.12)
        : samples.take(32).toList(growable: false);
    final activeCount = (values.length * progress.clamp(0.0, 1.0)).round();
    return SizedBox(
      height: 32,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var index = 0; index < values.length; index++)
            Expanded(
              child: Align(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  height: 5 + values[index].clamp(0.0, 1.0) * 27,
                  decoration: BoxDecoration(
                    color: index < activeCount
                        ? activeColor
                        : activeColor.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _durationLabel(Duration value) {
  final total = value.inSeconds;
  return '${(total ~/ 60).toString().padLeft(2, '0')}:${(total % 60).toString().padLeft(2, '0')}';
}
