import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../media/call_manager.dart';
import '../../media/call_models.dart';
import '../../services/app_container.dart';
import '../../widgets/avatar.dart';
import '../../widgets/haptics.dart';
import '../../widgets/video_stream_view.dart';
import 'call_quality_indicator.dart';

class CallRouteArguments {
  const CallRouteArguments({
    required this.peerId,
    required this.peerName,
    required this.callType,
    this.isGroupCall = false,
    this.peerIds = const [],
  });
  final String peerId;
  final String peerName;
  final CallType callType;
  final bool isGroupCall;
  final List<String> peerIds;
}

class CallScreen extends StatefulWidget {
  const CallScreen({super.key});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  StreamSubscription<CallSession?>? _subscription;
  Timer? _ticker;
  CallSession? _session;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final calls = AppContainerScope.of(context).mediaRuntime?.calls;
    if (calls == null) return;
    _session = calls.currentSession;
    _subscription = calls.sessions.listen((session) {
      if (!mounted) return;
      setState(() => _session = session);
      if (session == null && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _session?.state == CallState.active) setState(() {});
    });
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is CallRouteArguments && calls.currentSession == null) {
      _runCallAction(
        () => args.isGroupCall
            ? calls.initiateGroupCall(
                groupId: args.peerId,
                groupName: args.peerName,
                peerIds: args.peerIds,
                callType: args.callType,
              )
            : calls.initiateCall(
                peerId: args.peerId,
                peerName: args.peerName,
                callType: args.callType,
              ),
      );
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final runtime = AppContainerScope.of(context).mediaRuntime;
    final session = _session;
    if (runtime == null) {
      return Scaffold(
        body: Center(child: Text(context.l10n.call_service_unavailable)),
      );
    }
    if (session == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0D1014),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final calls = runtime.calls;
    final isIncomingRinging =
        session.direction == CallDirection.incoming &&
        session.state == CallState.ringing;
    return Scaffold(
      backgroundColor: const Color(0xFF0D1014),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (session.isGroupCall && session.callType == CallType.video)
              _groupVideoGrid(session, calls)
            else if (session.callType == CallType.video &&
                session.isRemoteCameraEnabled)
              VideoStreamView(renderer: calls.media.remoteRenderer),
            Column(
              children: [
                const Spacer(),
                if ((session.callType == CallType.voice ||
                        !session.isRemoteCameraEnabled) &&
                    !session.isGroupCall)
                  GeneratedAvatar(name: session.peerName, size: 104),
                const SizedBox(height: 24),
                Text(
                  session.peerName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (session.isGroupCall)
                  Text(
                    '${context.l10n.participant_count(session.connectedPeerIds.length + 1)} · '
                    '${session.isSfuMode ? 'SFU' : 'mesh'}',
                    style: const TextStyle(color: Color(0xFFCDD3DB)),
                  ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CallQualityIndicator(quality: session.state.callQuality),
                    const SizedBox(width: 8),
                    Text(
                      _status(context, session, calls.currentDuration),
                      style: const TextStyle(color: Color(0xFFCDD3DB)),
                    ),
                  ],
                ),
                const Spacer(),
                if (isIncomingRinging)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _round(
                          Icons.call_end,
                          const Color(0xFFFF5E87),
                          Colors.white,
                          label: context.l10n.reject,
                          onTap: calls.rejectCall,
                        ),
                        _round(
                          Icons.call,
                          const Color(0xFF36B37E),
                          Colors.white,
                          label: context.l10n.answer,
                          onTap: calls.acceptCall,
                        ),
                      ],
                    ),
                  )
                else
                  _activeControls(session, calls),
              ],
            ),
            if (!session.isGroupCall &&
                session.callType == CallType.video &&
                session.isCameraEnabled)
              Positioned(
                right: 16,
                top: session.state == CallState.reconnecting ? 132 : 16,
                width: 112,
                height: 168,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: VideoStreamView(
                    renderer: calls.media.localRenderer,
                    mirror: session.isUsingFrontCamera,
                  ),
                ),
              ),
            if (session.state == CallState.reconnecting)
              Positioned(
                left: 16,
                right: 16,
                top: 8,
                child: ReconnectingBanner(
                  label: context.l10n.reconnecting,
                  disableVideoLabel:
                      session.callType == CallType.video &&
                          session.isCameraEnabled
                      ? context.l10n.weak_connection_disable_video
                      : null,
                  onDisableVideo:
                      session.callType == CallType.video &&
                          session.isCameraEnabled
                      ? () => _runCallAction(calls.toggleCamera)
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _groupVideoGrid(CallSession session, CallManager calls) {
    final groupMedia = calls.groupMedia;
    if (groupMedia == null) return const SizedBox.shrink();
    final entries = groupMedia.remoteRenderers.entries.toList();
    final renderers = [
      if (session.isCameraEnabled)
        (context.l10n.you, groupMedia.localRenderer, true),
      ...entries.map(
        (entry) => (
          entry.key.startsWith('sfu:') ? entry.key.substring(4) : entry.key,
          entry.value,
          false,
        ),
      ),
    ];
    if (renderers.isEmpty) return const SizedBox.shrink();
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 72, 12, 190),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: renderers.length == 1 ? 1 : 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.78,
      ),
      itemCount: renderers.length,
      itemBuilder: (context, index) {
        final entry = renderers[index];
        return ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            fit: StackFit.expand,
            children: [
              VideoStreamView(
                renderer: entry.$2,
                mirror: entry.$3 && session.isUsingFrontCamera,
              ),
              Positioned(
                left: 10,
                bottom: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Text(
                      entry.$1,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _activeControls(CallSession session, CallManager calls) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 22,
        runSpacing: 18,
        children: [
          _round(
            session.isMuted ? Icons.mic_off : Icons.mic,
            session.isMuted ? Colors.white : Colors.white12,
            session.isMuted ? Colors.black : Colors.white,
            label: session.isMuted ? context.l10n.unmute : context.l10n.mute,
            onTap: calls.toggleMute,
            haptic: true,
          ),
          _round(
            Icons.volume_up_outlined,
            session.isSpeakerOn ? Colors.white : Colors.white12,
            session.isSpeakerOn ? Colors.black : Colors.white,
            label: context.l10n.speaker,
            onTap: calls.toggleSpeaker,
            haptic: true,
          ),
          if (session.callType == CallType.video)
            _round(
              session.isCameraEnabled ? Icons.videocam : Icons.videocam_off,
              session.isCameraEnabled ? Colors.white12 : Colors.white,
              session.isCameraEnabled ? Colors.white : Colors.black,
              label: context.l10n.camera,
              onTap: calls.toggleCamera,
              haptic: true,
            ),
          if (session.callType == CallType.video)
            _round(
              Icons.cameraswitch_outlined,
              Colors.white12,
              Colors.white,
              label: context.l10n.flip_camera,
              onTap: calls.switchCamera,
              haptic: true,
            ),
          _round(
            Icons.call_end,
            const Color(0xFFFF5E87),
            Colors.white,
            label: context.l10n.end_call,
            onTap: calls.endCall,
            haptic: true,
          ),
        ],
      ),
    );
  }

  Widget _round(
    IconData icon,
    Color bg,
    Color fg, {
    required String label,
    required FutureOr<void> Function() onTap,
    bool haptic = false,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: InkResponse(
        onTap: () {
          if (haptic) unawaited(SecureChatHaptics.longPress());
          _runCallAction(onTap);
        },
        child: CircleAvatar(
          radius: 30,
          backgroundColor: bg,
          child: Icon(icon, color: fg),
        ),
      ),
    );
  }

  Future<void> _runCallAction(FutureOr<dynamic> Function() action) async {
    try {
      final result = await action();
      if (result == false && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.connection_failed)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.connection_failed)));
      }
    }
  }

  static String _status(
    BuildContext context,
    CallSession session,
    Duration? duration,
  ) {
    if (session.state == CallState.active && duration != null) {
      final hours = duration.inHours;
      final minutes = duration.inMinutes
          .remainder(60)
          .toString()
          .padLeft(2, '0');
      final seconds = duration.inSeconds
          .remainder(60)
          .toString()
          .padLeft(2, '0');
      return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
    }
    return switch (session.state) {
      CallState.initiating => context.l10n.call_preparing,
      CallState.ringing =>
        session.direction == CallDirection.incoming
            ? context.l10n.incoming_call
            : context.l10n.ringing,
      CallState.connecting => context.l10n.connecting,
      CallState.reconnecting => context.l10n.reconnecting,
      CallState.ended => context.l10n.call_ended,
      CallState.rejected => context.l10n.call_rejected,
      CallState.busy => context.l10n.busy,
      CallState.failed => context.l10n.connection_failed,
      CallState.idle || CallState.active => '',
    };
  }
}
