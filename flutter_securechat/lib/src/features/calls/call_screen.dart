import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';
import '../../contacts/contact_service.dart';
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
  String? _identityGroupId;
  Stream<Map<String, ContactIdentity>>? _memberIdentities;

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
    final video = session.callType == CallType.video;
    final showMedia = !session.isTerminal && !isIncomingRinging;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: const Color(0xFF101214),
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF101214),
        body: !video
            ? _voiceLayout(session, calls, isIncomingRinging: isIncomingRinging)
            : Stack(
                fit: StackFit.expand,
                children: [
                  if (video &&
                      !session.isGroupCall &&
                      showMedia &&
                      session.isRemoteCameraEnabled)
                    VideoStreamView(
                      key: const ValueKey('call-remote-video'),
                      renderer: calls.media.remoteRenderer,
                      placeholder: const SizedBox.expand(),
                    ),
                  SafeArea(
                    child: Column(
                      children: [
                        _header(session, calls),
                        if (session.state == CallState.reconnecting)
                          _reconnectionNotice(session, calls),
                        Expanded(
                          key: const ValueKey('call-content'),
                          child: session.isGroupCall && video && showMedia
                              ? _groupVideoGrid(session, calls)
                              : _previewArea(
                                  session,
                                  calls,
                                  showMedia: showMedia,
                                ),
                        ),
                        ColoredBox(
                          key: const ValueKey('call-controls'),
                          color: const Color(0xE6101214),
                          child: SizedBox(
                            width: double.infinity,
                            child: session.isTerminal
                                ? Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Center(
                                      child: _round(
                                        Icons.close,
                                        Colors.white24,
                                        Colors.white,
                                        label: context.l10n.action_close,
                                        onTap: () =>
                                            Navigator.of(context).maybePop(),
                                      ),
                                    ),
                                  )
                                : isIncomingRinging
                                ? _incomingControls(calls)
                                : _activeControls(session, calls),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _voiceLayout(
    CallSession session,
    CallManager calls, {
    required bool isIncomingRinging,
  }) => SafeArea(
    child: Column(
      children: [
        const Align(
          alignment: AlignmentDirectional.centerStart,
          child: BackButton(color: Colors.white),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final landscape =
                  constraints.maxWidth > constraints.maxHeight * 1.3;
              final identity = _voiceIdentity(
                session,
                calls,
                compact: constraints.maxHeight < 600,
              );
              final controls = _voiceControls(
                session,
                calls,
                isIncomingRinging: isIncomingRinging,
                compact: landscape,
              );
              if (landscape) {
                return Row(
                  children: [
                    Expanded(child: _scrollableVoicePane(identity)),
                    Expanded(child: _scrollableVoicePane(controls)),
                  ],
                );
              }
              return Column(
                children: [
                  Expanded(
                    child: KeyedSubtree(
                      key: const ValueKey('voice-identity-viewport'),
                      child: _scrollableVoicePane(identity),
                    ),
                  ),
                  controls,
                ],
              );
            },
          ),
        ),
      ],
    ),
  );

  // Large accessibility text and short landscape screens must stay reachable.
  Widget _scrollableVoicePane(Widget child) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: Center(child: child),
      ),
    ),
  );

  Widget _voiceIdentity(
    CallSession session,
    CallManager calls, {
    required bool compact,
  }) {
    final name = Text(
      session.peerName,
      key: const ValueKey('call-peer-name'),
      textAlign: compact ? TextAlign.start : TextAlign.center,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    );
    final avatar = GeneratedAvatar(
      name: session.peerName,
      isGroup: session.isGroupCall,
      size: compact ? 48 : 80,
    );
    final status = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (session.state == CallState.active ||
            session.state == CallState.reconnecting) ...[
          CallQualityIndicator(quality: session.state.callQuality),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            _status(context, session, calls.currentDuration),
            key: const ValueKey('call-status'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: session.state == CallState.reconnecting
                  ? const Color(0xFFFFC977)
                  : const Color(0xFFCDD3DB),
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
    return Padding(
      key: const ValueKey('voice-identity'),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (compact) ...[
            status,
            const SizedBox(height: 8),
            Row(
              children: [
                avatar,
                const SizedBox(width: 12),
                Expanded(child: name),
              ],
            ),
          ] else ...[
            avatar,
            const SizedBox(height: 16),
            name,
            const SizedBox(height: 8),
            status,
          ],
          if (session.isGroupCall) ...[
            const SizedBox(height: 8),
            Text(
              context.l10n.participant_count(
                session.connectedPeerIds.length + 1,
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFCDD3DB), fontSize: 14),
            ),
          ],
        ],
      ),
    );
  }

  Widget _voiceControls(
    CallSession session,
    CallManager calls, {
    required bool isIncomingRinging,
    required bool compact,
  }) {
    final actions = isIncomingRinging
        ? [
            _voiceButton(
              icon: Icons.call_end,
              label: context.l10n.reject,
              background: const Color(0xFFD93951),
              onTap: calls.rejectCall,
              inline: compact,
            ),
            _voiceButton(
              icon: Icons.call,
              label: context.l10n.answer,
              background: const Color(0xFF167C55),
              onTap: calls.acceptCall,
              inline: compact,
            ),
          ]
        : [
            _voiceButton(
              icon: session.isMuted ? Icons.mic_off : Icons.mic,
              label: session.isMuted ? context.l10n.unmute : context.l10n.mute,
              selected: session.isMuted,
              onTap: calls.toggleMute,
              inline: compact,
            ),
            _voiceButton(
              icon: Icons.volume_up_outlined,
              label: context.l10n.speaker,
              selected: session.isSpeakerOn,
              onTap: calls.toggleSpeaker,
              inline: compact,
            ),
          ];
    return Align(
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: Padding(
          key: const ValueKey('call-controls'),
          padding: compact
              ? const EdgeInsets.symmetric(horizontal: 16, vertical: 8)
              : const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!session.isTerminal)
                compact
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          actions[0],
                          const SizedBox(height: 8),
                          actions[1],
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: actions[0]),
                          const SizedBox(width: 16),
                          Expanded(child: actions[1]),
                        ],
                      ),
              if (!isIncomingRinging) ...[
                if (!session.isTerminal) const SizedBox(height: 12),
                SizedBox(
                  width: 144,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: session.isTerminal
                          ? const Color(0xFF30353B)
                          : const Color(0xFFD93951),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      textStyle: Theme.of(context).textTheme.labelLarge
                          ?.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0,
                          ),
                    ),
                    onPressed: () => session.isTerminal
                        ? Navigator.of(context).maybePop()
                        : _runCallAction(calls.endCall),
                    icon: Icon(
                      session.isTerminal ? Icons.close : Icons.call_end,
                    ),
                    label: Text(
                      session.isTerminal
                          ? context.l10n.action_close
                          : context.l10n.end_call,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _voiceButton({
    required IconData icon,
    required String label,
    required FutureOr<dynamic> Function() onTap,
    bool? selected,
    Color? background,
    bool inline = false,
  }) {
    void press() {
      unawaited(SecureChatHaptics.longPress());
      _runCallAction(onTap);
    }

    final symbol = Container(
      width: inline ? 40 : 48,
      height: inline ? 40 : 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color:
            background ??
            (selected == true ? Colors.white : const Color(0xFF30353B)),
      ),
      child: Icon(
        icon,
        size: 24,
        color: selected == true ? const Color(0xFF101214) : Colors.white,
      ),
    );
    final caption = Text(
      label,
      textAlign: inline ? TextAlign.start : TextAlign.center,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );

    return Semantics(
      label: label,
      button: true,
      toggled: selected,
      onTap: press,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: press,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: inline
                ? Row(
                    children: [
                      symbol,
                      const SizedBox(width: 12),
                      Expanded(child: caption),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [symbol, const SizedBox(height: 6), caption],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _avatar(CallSession session) => Center(
    child: LayoutBuilder(
      builder: (context, constraints) => constraints.maxHeight < 80
          ? const SizedBox.expand()
          : GeneratedAvatar(
              name: session.peerName,
              isGroup: session.isGroupCall,
              size: math.min(104, constraints.maxHeight * .6),
            ),
    ),
  );

  Widget _header(CallSession session, CallManager calls) => ColoredBox(
    key: const ValueKey('call-header'),
    color: const Color(0xD9101214),
    child: Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(4, 8, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BackButton(color: Colors.white),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  session.peerName,
                  key: const ValueKey('call-peer-name'),
                  maxLines: MediaQuery.sizeOf(context).height < 400 ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (session.state == CallState.active ||
                        session.state == CallState.reconnecting) ...[
                      CallQualityIndicator(quality: session.state.callQuality),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        _status(context, session, calls.currentDuration),
                        key: const ValueKey('call-status'),
                        maxLines: MediaQuery.sizeOf(context).height < 400
                            ? 1
                            : 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFCDD3DB),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                if (session.isGroupCall)
                  Text(
                    context.l10n.participant_count(
                      session.connectedPeerIds.length + 1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFCDD3DB),
                      fontSize: 13,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _reconnectionNotice(CallSession session, CallManager calls) =>
      ColoredBox(
        key: const ValueKey('call-reconnection-notice'),
        color: const Color(0xFF633B16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: session.callType == CallType.video && session.isCameraEnabled
              ? TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  icon: const Icon(Icons.videocam_off_outlined, size: 20),
                  onPressed: () => _runCallAction(calls.toggleCamera),
                  label: Text(
                    context.l10n.weak_connection_disable_video,
                    maxLines: MediaQuery.sizeOf(context).height < 400 ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              : const SizedBox(width: double.infinity, height: 2),
        ),
      );

  Widget _previewArea(
    CallSession session,
    CallManager calls, {
    required bool showMedia,
  }) {
    final video = session.callType == CallType.video;
    final showPreview =
        showMedia && !session.isGroupCall && video && session.isCameraEnabled;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = math.min(
          160.0,
          math.max(0.0, constraints.maxHeight - 16),
        );
        final width = math.min(104.0, height * 2 / 3);
        final fallback = showPreview && height >= 48
            ? Padding(
                padding: EdgeInsets.only(top: height + 16),
                child: _avatar(session),
              )
            : _avatar(session);
        return Stack(
          fit: StackFit.expand,
          children: [
            if (showMedia &&
                !session.isGroupCall &&
                video &&
                session.isRemoteCameraEnabled)
              ValueListenableBuilder(
                valueListenable: calls.media.remoteRenderer,
                builder: (context, value, _) =>
                    calls.media.remoteRenderer.hasVideoFrame
                    ? const SizedBox.expand()
                    : fallback,
              )
            else
              fallback,
            if (showPreview && height >= 48)
              Align(
                alignment: AlignmentDirectional.topEnd,
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(top: 8, end: 12),
                  child: SizedBox(
                    key: const ValueKey('call-local-preview'),
                    width: width,
                    height: height,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: ColoredBox(
                        color: const Color(0xFF292D31),
                        child: VideoStreamView(
                          renderer: calls.media.localRenderer,
                          mirror: session.isUsingFrontCamera,
                          placeholder: const Center(
                            child: Icon(
                              Icons.videocam_outlined,
                              color: Colors.white54,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _incomingControls(CallManager calls) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _round(
          Icons.call_end,
          const Color(0xFFD93951),
          Colors.white,
          label: context.l10n.reject,
          onTap: calls.rejectCall,
        ),
        _round(
          Icons.call,
          const Color(0xFF168754),
          Colors.white,
          label: context.l10n.answer,
          onTap: calls.acceptCall,
        ),
      ],
    ),
  );

  Widget _groupVideoGrid(CallSession session, CallManager calls) {
    final groupMedia = calls.groupMedia;
    if (groupMedia == null) return _avatar(session);
    final entries = groupMedia.remoteRenderers.entries
        .take(maxGroupCallParticipants - 1)
        .toList();
    final renderers = [
      (context.l10n.you, groupMedia.localRenderer, true),
      ...entries.map((entry) => (entry.key, entry.value, false)),
    ];
    if (_identityGroupId != session.groupId) {
      _identityGroupId = session.groupId;
      _memberIdentities = session.groupId == null
          ? null
          : AppContainerScope.of(
              context,
            ).groupRuntime?.service.watchMemberIdentities(session.groupId!);
    }
    return StreamBuilder<Map<String, ContactIdentity>>(
      stream: _memberIdentities,
      builder: (context, snapshot) => LayoutBuilder(
        builder: (context, constraints) => GridView.builder(
          key: const ValueKey('call-group-grid'),
          padding: const EdgeInsets.all(8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: renderers.length == 1
                ? 1
                : constraints.maxWidth >= 600
                ? 3
                : 2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 0.78,
          ),
          itemCount: renderers.length,
          itemBuilder: (context, index) {
            final entry = renderers[index];
            final identity = snapshot.data?[entry.$1];
            final name = entry.$3
                ? context.l10n.you
                : identity?.displayName.isNotEmpty == true &&
                      identity!.displayName != entry.$1
                ? identity.displayName
                : context.l10n.group_unknown_member;
            return ClipRRect(
              key: ValueKey('call-participant-$index'),
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (!entry.$3 || session.isCameraEnabled)
                    VideoStreamView(
                      renderer: entry.$2,
                      mirror: entry.$3 && session.isUsingFrontCamera,
                      placeholder: ColoredBox(
                        color: const Color(0xFF292D31),
                        child: Center(
                          child: GeneratedAvatar(name: name, size: 48),
                        ),
                      ),
                    )
                  else
                    ColoredBox(
                      color: const Color(0xFF292D31),
                      child: Center(
                        child: GeneratedAvatar(name: name, size: 48),
                      ),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(color: Color(0xCC101214)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _activeControls(CallSession session, CallManager calls) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          _round(
            session.isMuted ? Icons.mic_off : Icons.mic,
            session.isMuted ? Colors.white : Colors.white12,
            session.isMuted ? Colors.black : Colors.white,
            label: session.isMuted ? context.l10n.unmute : context.l10n.mute,
            onTap: calls.toggleMute,
            haptic: true,
            toggled: session.isMuted,
          ),
          _round(
            Icons.volume_up_outlined,
            session.isSpeakerOn ? Colors.white : Colors.white12,
            session.isSpeakerOn ? Colors.black : Colors.white,
            label: context.l10n.speaker,
            onTap: calls.toggleSpeaker,
            haptic: true,
            toggled: session.isSpeakerOn,
          ),
          if (session.callType == CallType.video)
            _round(
              session.isCameraEnabled ? Icons.videocam : Icons.videocam_off,
              session.isCameraEnabled ? Colors.white12 : Colors.white,
              session.isCameraEnabled ? Colors.white : Colors.black,
              label: context.l10n.camera,
              onTap: calls.toggleCamera,
              haptic: true,
              toggled: session.isCameraEnabled,
            ),
          if (session.callType == CallType.video)
            _round(
              Icons.cameraswitch_outlined,
              Colors.white12,
              Colors.white,
              label: context.l10n.flip_camera,
              onTap: session.isCameraEnabled ? calls.switchCamera : null,
              haptic: true,
            ),
          _round(
            Icons.call_end,
            const Color(0xFFD93951),
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
    required FutureOr<void> Function()? onTap,
    bool haptic = false,
    bool? toggled,
  }) {
    final VoidCallback? press = onTap == null
        ? null
        : () {
            if (haptic) unawaited(SecureChatHaptics.longPress());
            _runCallAction(onTap);
          };
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      // Ac/kapa kontrolleri durumlarini da bildirmeli: yalniz ikon degisimi
      // TalkBack kullanicisina hicbir sey soylemiyor, ayrica erisilebilirlik
      // agacinda durum gorunmedigi icin otomatik testle de dogrulanamiyordu.
      toggled: toggled,
      excludeSemantics: true,
      onTap: press,
      child: Tooltip(
        message: label,
        child: IconButton(
          onPressed: press,
          style: IconButton.styleFrom(
            backgroundColor: bg,
            foregroundColor: fg,
            fixedSize: const Size(52, 52),
            minimumSize: const Size(52, 52),
            maximumSize: const Size(52, 52),
            padding: EdgeInsets.zero,
          ),
          icon: Icon(icon),
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
