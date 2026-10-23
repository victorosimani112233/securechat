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
    _applyWindowPolicy(_session);
    _subscription = calls.sessions.listen((session) {
      if (!mounted) return;
      setState(() => _session = session);
      _applyWindowPolicy(session);
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
    if (_portraitLocked) {
      // Uygulamanin varsayilan yon ayarina donulur.
      unawaited(SystemChrome.setPreferredOrientations(const []));
    }
    super.dispose();
  }

  bool _portraitLocked = false;

  /// Sesli aramada ekran donmez: telefon kulaga goturulurken yatay
  /// yerlesime gecip dugmeleri kaydirmasin.
  void _applyWindowPolicy(CallSession? session) {
    if (session == null) return;
    final lockPortrait = session.callType == CallType.voice;
    if (lockPortrait == _portraitLocked) return;
    _portraitLocked = lockPortrait;
    unawaited(
      SystemChrome.setPreferredOrientations(
        lockPortrait ? const [DeviceOrientation.portraitUp] : const [],
      ),
    );
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
        backgroundColor: _CallPalette.ground,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final calls = runtime.calls;
    final isIncomingRinging =
        session.direction == CallDirection.incoming &&
        session.state == CallState.ringing;
    final video = session.callType == CallType.video;
    final showMedia = !session.isTerminal && !isIncomingRinging;
    final accent = GeneratedAvatar.colorFor(context, session.peerName);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: _CallPalette.ground,
      ),
      child: Scaffold(
        backgroundColor: _CallPalette.ground,
        body: Stack(
          fit: StackFit.expand,
          children: [
            _CallBackdrop(accent: accent),
            if (!video)
              _voiceLayout(session, calls, isIncomingRinging: isIncomingRinging)
            else ...[
              if (!session.isGroupCall &&
                  showMedia &&
                  session.isRemoteCameraEnabled)
                VideoStreamView(
                  key: const ValueKey('call-remote-video'),
                  renderer: calls.media.remoteRenderer,
                  placeholder: const SizedBox.expand(),
                ),
              // Video uzerindeki yazi ve dugmeler okunur kalsin diye ust ve
              // alt kenarlar karartilir; ortadaki goruntu acik kalir.
              const IgnorePointer(child: _VideoScrims()),
              SafeArea(
                child: Column(
                  children: [
                    _header(session, calls),
                    if (session.state == CallState.reconnecting)
                      _reconnectionNotice(session, calls),
                    Expanded(
                      key: const ValueKey('call-content'),
                      child: session.isGroupCall && showMedia
                          ? _groupVideoGrid(session, calls)
                          : _previewArea(
                              session,
                              calls,
                              showMedia: showMedia,
                              isIncomingRinging: isIncomingRinging,
                            ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        12,
                        4,
                        12,
                        MediaQuery.sizeOf(context).height < 400 ? 4 : 12,
                      ),
                      child: KeyedSubtree(
                        key: const ValueKey('call-controls'),
                        child: session.isTerminal
                            ? _actionButton(
                                icon: Icons.close,
                                label: context.l10n.action_close,
                                background: _CallPalette.neutral,
                                onTap: () => Navigator.of(context).maybePop(),
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
        _topBar(),
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

  /// Sesli aramanin ust cubugu: geri ve uctan uca sifreleme etiketi.
  Widget _topBar() => const Padding(
    padding: EdgeInsetsDirectional.fromSTEB(4, 4, 16, 0),
    child: Row(
      children: [
        BackButton(color: Colors.white),
        Expanded(child: Center(child: _EncryptedBadge())),
        // Geri dugmesiyle dengeli dursun diye ayni genislikte bos alan.
        SizedBox(width: 40),
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
      session.isGroupCall
          ? session.peerName
          : context.peerLabel(session.peerName, peerId: session.peerId),
      key: const ValueKey('call-peer-name'),
      textAlign: compact ? TextAlign.start : TextAlign.center,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: Colors.white,
        fontSize: compact ? 22 : 28,
        fontWeight: FontWeight.w600,
        height: 1.2,
        letterSpacing: -0.3,
      ),
    );
    final avatar = _PulsingAvatar(
      name: session.peerName,
      isGroup: session.isGroupCall,
      size: compact ? 64 : 120,
      pulsing: _isWaiting(session),
    );
    final status = _statusLine(session, calls, fontSize: 16);
    return Padding(
      key: const ValueKey('voice-identity'),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (compact) ...[
            status,
            const SizedBox(height: 12),
            Row(
              children: [
                avatar,
                const SizedBox(width: 16),
                Expanded(child: name),
              ],
            ),
          ] else ...[
            avatar,
            const SizedBox(height: 28),
            name,
            const SizedBox(height: 10),
            status,
          ],
          if (session.isGroupCall) ...[
            const SizedBox(height: 8),
            Text(
              context.l10n.participant_count(
                session.connectedPeerIds.length + 1,
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(color: _CallPalette.muted, fontSize: 14),
            ),
          ],
        ],
      ),
    );
  }

  /// Sure ya da durum, bagli aramada baglanti kalitesi gostergesiyle.
  Widget _statusLine(
    CallSession session,
    CallManager calls, {
    required double fontSize,
    bool center = true,
  }) => Row(
    mainAxisSize: center ? MainAxisSize.max : MainAxisSize.min,
    mainAxisAlignment: center
        ? MainAxisAlignment.center
        : MainAxisAlignment.start,
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
          textAlign: center ? TextAlign.center : TextAlign.start,
          maxLines: MediaQuery.sizeOf(context).height < 400 ? 1 : 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: session.state == CallState.reconnecting
                ? _CallPalette.warning
                : _CallPalette.muted,
            fontSize: fontSize,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    ],
  );

  static bool _isWaiting(CallSession session) => switch (session.state) {
    CallState.initiating ||
    CallState.ringing ||
    CallState.connecting ||
    CallState.reconnecting => true,
    _ => false,
  };

  Widget _voiceControls(
    CallSession session,
    CallManager calls, {
    required bool isIncomingRinging,
    required bool compact,
  }) {
    final List<Widget> actions;
    if (session.isTerminal) {
      actions = [
        _actionButton(
          icon: Icons.close,
          label: context.l10n.action_close,
          background: _CallPalette.neutral,
          onTap: () => Navigator.of(context).maybePop(),
          inline: compact,
        ),
      ];
    } else if (isIncomingRinging) {
      actions = [
        _actionButton(
          icon: Icons.call_end,
          label: context.l10n.reject,
          background: _CallPalette.danger,
          onTap: calls.rejectCall,
          inline: compact,
          large: true,
        ),
        _actionButton(
          icon: Icons.call,
          label: context.l10n.answer,
          background: _CallPalette.accept,
          onTap: calls.acceptCall,
          inline: compact,
          large: true,
        ),
      ];
    } else {
      actions = [
        _actionButton(
          icon: Icons.volume_up_rounded,
          label: context.l10n.speaker,
          selected: session.isSpeakerOn,
          onTap: calls.toggleSpeaker,
          inline: compact,
        ),
        _actionButton(
          icon: session.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
          label: session.isMuted ? context.l10n.unmute : context.l10n.mute,
          selected: session.isMuted,
          onTap: calls.toggleMute,
          inline: compact,
        ),
        _actionButton(
          icon: Icons.call_end,
          label: context.l10n.end_call,
          background: _CallPalette.danger,
          onTap: calls.endCall,
          inline: compact,
        ),
      ];
    }
    return Align(
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: compact
              ? const EdgeInsets.symmetric(horizontal: 16, vertical: 8)
              : const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: _ControlDock(
            key: const ValueKey('call-controls'),
            // Gelen aramada iki buyuk dugme panelsiz durur.
            plain: isIncomingRinging,
            child: compact
                ? Column(mainAxisSize: MainAxisSize.min, children: actions)
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (final action in actions) Expanded(child: action),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  /// Etiketli yuvarlak arama dugmesi (sesli arama ve gelen arama).
  Widget _actionButton({
    required IconData icon,
    required String label,
    required FutureOr<dynamic> Function() onTap,
    bool? selected,
    Color? background,
    bool inline = false,
    bool large = false,
  }) {
    void press() {
      unawaited(SecureChatHaptics.longPress());
      _runCallAction(onTap);
    }

    final diameter = inline ? 44.0 : (large ? 72.0 : 60.0);
    final active = selected == true;
    final symbol = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: background ?? (active ? Colors.white : _CallPalette.buttonIdle),
        boxShadow: background == null
            ? null
            : [
                BoxShadow(
                  color: background.withValues(alpha: .45),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Icon(
        icon,
        size: large ? 32 : 26,
        color: active ? _CallPalette.ground : Colors.white,
      ),
    );
    final caption = Text(
      label,
      textAlign: inline ? TextAlign.start : TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
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
          borderRadius: BorderRadius.circular(16),
          onTap: press,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
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
                    children: [symbol, const SizedBox(height: 8), caption],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _header(CallSession session, CallManager calls) => Padding(
    key: const ValueKey('call-header'),
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
                session.isGroupCall
                    ? session.peerName
                    : context.peerLabel(
                        session.peerName,
                        peerId: session.peerId,
                      ),
                key: const ValueKey('call-peer-name'),
                maxLines: MediaQuery.sizeOf(context).height < 400 ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                  shadows: [Shadow(color: Color(0x99000000), blurRadius: 8)],
                ),
              ),
              const SizedBox(height: 4),
              _statusLine(session, calls, fontSize: 14, center: false),
              if (session.isGroupCall)
                Text(
                  context.l10n.participant_count(
                    session.connectedPeerIds.length + 1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _CallPalette.muted,
                    fontSize: 13,
                  ),
                ),
            ],
          ),
        ),
        if (MediaQuery.sizeOf(context).height >= 400)
          const Padding(
            padding: EdgeInsetsDirectional.only(top: 12, start: 8),
            child: _EncryptedBadge(iconOnly: true),
          ),
      ],
    ),
  );

  Widget _reconnectionNotice(CallSession session, CallManager calls) => Padding(
    key: const ValueKey('call-reconnection-notice'),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
    child: session.callType == CallType.video && session.isCameraEnabled
        ? DecoratedBox(
            decoration: BoxDecoration(
              color: _CallPalette.warningSurface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              icon: const Icon(Icons.videocam_off_outlined, size: 20),
              onPressed: () => _runCallAction(calls.toggleCamera),
              label: Text(
                context.l10n.weak_connection_disable_video,
                maxLines: MediaQuery.sizeOf(context).height < 400 ? 1 : 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
        : const SizedBox(width: double.infinity, height: 2),
  );

  Widget _previewArea(
    CallSession session,
    CallManager calls, {
    required bool showMedia,
    required bool isIncomingRinging,
  }) {
    final showPreview =
        showMedia && !session.isGroupCall && session.isCameraEnabled;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = math.min(
          176.0,
          math.max(0.0, constraints.maxHeight - 16),
        );
        final width = math.min(112.0, height * 2 / 3);
        final avatar = _videoAvatar(
          session,
          pulsing: _isWaiting(session),
          maxSize: constraints.maxHeight,
        );
        final fallback = showPreview && height >= 48
            ? Padding(
                padding: EdgeInsets.only(top: height + 16),
                child: avatar,
              )
            : avatar;
        return Stack(
          fit: StackFit.expand,
          children: [
            if (showMedia &&
                !session.isGroupCall &&
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
                  child: Container(
                    key: const ValueKey('call-local-preview'),
                    width: width,
                    height: height,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white24, width: 1.5),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x66000000),
                          blurRadius: 16,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14.5),
                      child: ColoredBox(
                        color: _CallPalette.tile,
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

  /// Karsi tarafin goruntusu yokken (cagri, kamera kapali) ortadaki avatar.
  Widget _videoAvatar(
    CallSession session, {
    required bool pulsing,
    required double maxSize,
  }) => Center(
    child: maxSize < 80
        ? const SizedBox.expand()
        : _PulsingAvatar(
            name: session.peerName,
            isGroup: session.isGroupCall,
            size: math.min(120, maxSize * .5),
            pulsing: pulsing,
          ),
  );

  Widget _incomingControls(CallManager calls) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _actionButton(
          icon: Icons.call_end,
          label: context.l10n.reject,
          background: _CallPalette.danger,
          onTap: calls.rejectCall,
          large: true,
        ),
        _actionButton(
          icon: Icons.videocam_rounded,
          label: context.l10n.answer,
          background: _CallPalette.accept,
          onTap: calls.acceptCall,
          large: true,
        ),
      ],
    ),
  );

  Widget _groupVideoGrid(CallSession session, CallManager calls) {
    final groupMedia = calls.groupMedia;
    if (groupMedia == null) {
      return _videoAvatar(session, pulsing: false, maxSize: 240);
    }
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
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: renderers.length == 1
                ? 1
                : constraints.maxWidth >= 600
                ? 3
                : 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
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
            final placeholder = ColoredBox(
              color: _CallPalette.tile,
              child: Center(child: GeneratedAvatar(name: name, size: 56)),
            );
            return ClipRRect(
              key: ValueKey('call-participant-$index'),
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (!entry.$3 || session.isCameraEnabled)
                    VideoStreamView(
                      renderer: entry.$2,
                      mirror: entry.$3 && session.isUsingFrontCamera,
                      placeholder: placeholder,
                    )
                  else
                    placeholder,
                  PositionedDirectional(
                    start: 8,
                    end: 8,
                    bottom: 8,
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xB3000000),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
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
    final video = session.callType == CallType.video;
    return _ControlDock(
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 10,
        runSpacing: 10,
        children: [
          _round(
            session.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
            session.isMuted ? Colors.white : _CallPalette.buttonIdle,
            session.isMuted ? _CallPalette.ground : Colors.white,
            label: session.isMuted ? context.l10n.unmute : context.l10n.mute,
            onTap: calls.toggleMute,
            haptic: true,
            toggled: session.isMuted,
          ),
          if (video)
            _round(
              session.isCameraEnabled
                  ? Icons.videocam_rounded
                  : Icons.videocam_off_rounded,
              session.isCameraEnabled ? _CallPalette.buttonIdle : Colors.white,
              session.isCameraEnabled ? Colors.white : _CallPalette.ground,
              label: context.l10n.camera,
              onTap: calls.toggleCamera,
              haptic: true,
              toggled: session.isCameraEnabled,
            ),
          if (video)
            _round(
              Icons.cameraswitch_outlined,
              _CallPalette.buttonIdle,
              Colors.white,
              label: context.l10n.flip_camera,
              onTap: session.isCameraEnabled ? calls.switchCamera : null,
              haptic: true,
            ),
          _round(
            Icons.volume_up_rounded,
            session.isSpeakerOn ? Colors.white : _CallPalette.buttonIdle,
            session.isSpeakerOn ? _CallPalette.ground : Colors.white,
            label: context.l10n.speaker,
            onTap: calls.toggleSpeaker,
            haptic: true,
            toggled: session.isSpeakerOn,
          ),
          _round(
            Icons.call_end,
            _CallPalette.danger,
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
            disabledBackgroundColor: bg.withValues(alpha: .08),
            disabledForegroundColor: Colors.white38,
            fixedSize: const Size(56, 56),
            minimumSize: const Size(56, 56),
            maximumSize: const Size(56, 56),
            padding: EdgeInsets.zero,
          ),
          icon: Icon(icon, size: 26),
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
      CallState.noAnswer => context.l10n.call_no_answer,
      CallState.idle || CallState.active => '',
    };
  }
}

/// Arama ekraninin sabit renkleri. Ekran temadan bagimsiz olarak koyudur.
abstract final class _CallPalette {
  static const ground = Color(0xFF080B10);
  static const tile = Color(0xFF1B2129);
  static const neutral = Color(0xFF3A414B);
  static const buttonIdle = Color(0x2EFFFFFF);
  static const dock = Color(0x1FFFFFFF);
  static const dockBorder = Color(0x1AFFFFFF);
  static const muted = Color(0xFFC9D1DB);
  static const warning = Color(0xFFFFC977);
  static const warningSurface = Color(0xCC6B3F12);
  static const danger = Color(0xFFE5484D);
  static const accept = Color(0xFF22A06B);
}

/// Kisinin avatar renginden turetilen koyu degrade ve avatarin arkasinda
/// hafif bir isik.
class _CallBackdrop extends StatelessWidget {
  const _CallBackdrop({required this.accent});
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final top = Color.lerp(accent, _CallPalette.ground, .72)!;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, _CallPalette.ground],
          stops: const [0, .78],
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -.35),
            radius: .9,
            colors: [accent.withValues(alpha: .18), Colors.transparent],
          ),
        ),
      ),
    );
  }
}

/// Goruntulu aramada ustte ve altta yazilarin okunmasini saglayan karartma.
class _VideoScrims extends StatelessWidget {
  const _VideoScrims();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // Yatay ve kisa ekranlarda seritler ekranin yarisini gecmez.
      final top = math.min(180.0, constraints.maxHeight * .35);
      final bottom = math.min(220.0, constraints.maxHeight * .45);
      return Column(
        children: [
          SizedBox(
            height: top,
            width: double.infinity,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xA6000000), Color(0x00000000)],
                ),
              ),
            ),
          ),
          const Spacer(),
          SizedBox(
            height: bottom,
            width: double.infinity,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xBF000000), Color(0x00000000)],
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

/// "Uctan uca sifreli" etiketi; dar basliklarda yalniz kilit simgesi.
class _EncryptedBadge extends StatelessWidget {
  const _EncryptedBadge({this.iconOnly = false});
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final label = context.l10n.chat_e2ee;
    const icon = Icon(Icons.lock_rounded, size: 14, color: _CallPalette.muted);
    if (iconOnly) return Tooltip(message: label, child: icon);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _CallPalette.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Arama dugmelerini tasiyan yari saydam, yuvarlak koseli panel.
class _ControlDock extends StatelessWidget {
  const _ControlDock({super.key, required this.child, this.plain = false});
  final Widget child;
  final bool plain;

  @override
  Widget build(BuildContext context) => plain
      ? child
      : DecoratedBox(
          decoration: BoxDecoration(
            color: _CallPalette.dock,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: _CallPalette.dockBorder),
          ),
          child: Padding(
            // Kisa (yatay) ekranda panel inceltilir, goruntuye yer kalir.
            padding: EdgeInsets.symmetric(
              horizontal: 12,
              vertical: MediaQuery.sizeOf(context).height < 400 ? 6 : 12,
            ),
            child: child,
          ),
        );
}

/// Arama kurulurken ya da calarken avatarin cevresinde yayilan halkalar.
/// Hareket azaltma acikken halkalar durur.
class _PulsingAvatar extends StatefulWidget {
  const _PulsingAvatar({
    required this.name,
    required this.isGroup,
    required this.size,
    required this.pulsing,
  });
  final String name;
  final bool isGroup;
  final double size;
  final bool pulsing;

  @override
  State<_PulsingAvatar> createState() => _PulsingAvatarState();
}

class _PulsingAvatarState extends State<_PulsingAvatar>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_PulsingAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final animate =
        widget.pulsing &&
        !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    if (animate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!animate && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = GeneratedAvatar.colorFor(context, widget.name);
    final ring = widget.size * 1.5;
    return SizedBox.square(
      dimension: ring,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (widget.pulsing)
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => CustomPaint(
                size: Size.square(ring),
                painter: _PulsePainter(
                  progress: _controller.value,
                  color: accent,
                  innerRadius: widget.size / 2,
                ),
              ),
            )
          else
            Container(
              width: widget.size + 16,
              height: widget.size + 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: .16),
              ),
            ),
          GeneratedAvatar(
            name: widget.name,
            isGroup: widget.isGroup,
            size: widget.size,
          ),
        ],
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  _PulsePainter({
    required this.progress,
    required this.color,
    required this.innerRadius,
  });
  final double progress;
  final Color color;
  final double innerRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outer = size.shortestSide / 2;
    for (final offset in const [0.0, 0.5]) {
      final t = (progress + offset) % 1;
      final radius = innerRadius + (outer - innerRadius) * t;
      canvas.drawCircle(
        center,
        radius,
        Paint()..color = color.withValues(alpha: .32 * (1 - t)),
      );
    }
  }

  @override
  bool shouldRepaint(_PulsePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
