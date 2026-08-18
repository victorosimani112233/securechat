import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../media/call_models.dart';

class OngoingCallAppFrame extends StatelessWidget {
  const OngoingCallAppFrame({
    super.key,
    required this.child,
    required this.activeRoute,
    required this.onReturnToCall,
    this.initialSession,
    this.sessions,
  });

  final Widget child;
  final ValueListenable<String?> activeRoute;
  final VoidCallback onReturnToCall;
  final CallSession? initialSession;
  final Stream<CallSession?>? sessions;

  @override
  Widget build(BuildContext context) {
    final updates = sessions;
    if (updates == null) return child;
    return ValueListenableBuilder<String?>(
      valueListenable: activeRoute,
      builder: (context, route, _) => StreamBuilder<CallSession?>(
        stream: updates,
        initialData: initialSession,
        builder: (context, snapshot) {
          final session = snapshot.data;
          final visible =
              session != null &&
              _isOngoing(session.state) &&
              !_routesWithoutBanner.contains(route);
          if (!visible) return child;
          return Column(
            children: [
              OngoingCallBar(session: session, onPressed: onReturnToCall),
              Expanded(
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  child: child,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class OngoingCallBar extends StatefulWidget {
  const OngoingCallBar({
    super.key,
    required this.session,
    required this.onPressed,
  });

  final CallSession session;
  final VoidCallback onPressed;

  @override
  State<OngoingCallBar> createState() => _OngoingCallBarState();
}

class _OngoingCallBarState extends State<OngoingCallBar> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant OngoingCallBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.callId != widget.session.callId ||
        oldWidget.session.startTime != widget.session.startTime) {
      _syncTicker();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _syncTicker() {
    _ticker?.cancel();
    if (widget.session.startTime == null) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final status = switch (session.state) {
      CallState.reconnecting => context.l10n.reconnecting,
      CallState.connecting => context.l10n.connecting,
      _ => _formatDuration(session.startTime),
    };
    return Material(
      key: const ValueKey('ongoing-call-bar'),
      color: const Color(0xFF087A55),
      child: SafeArea(
        bottom: false,
        child: Semantics(
          label: '${context.l10n.return_to_call}: ${session.peerName}',
          button: true,
          excludeSemantics: true,
          child: InkWell(
            onTap: widget.onPressed,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final textScale = MediaQuery.textScalerOf(context).scale(1);
                  final showReturnLabel =
                      constraints.maxWidth >= 340 && textScale <= 1.4;
                  return Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(14, 7, 10, 7),
                    child: Row(
                      children: [
                        Icon(
                          session.callType == CallType.video
                              ? Icons.videocam
                              : Icons.call,
                          color: Colors.white,
                          size: 21,
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                session.peerName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                              Text(
                                status,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        if (showReturnLabel) ...[
                          Text(
                            context.l10n.return_to_call,
                            maxLines: 1,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: Colors.white,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(width: 2),
                        ],
                        const Icon(
                          Icons.chevron_right,
                          color: Colors.white,
                          size: 22,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _routesWithoutBanner = <String?>{
  null,
  '/launch',
  '/onboarding',
  '/permissions',
  '/auth',
  '/calls',
};

bool _isOngoing(CallState state) => const {
  CallState.connecting,
  CallState.active,
  CallState.reconnecting,
}.contains(state);

String _formatDuration(DateTime? startTime) {
  final elapsed = startTime == null
      ? Duration.zero
      : DateTime.now().difference(startTime);
  final seconds = elapsed.inSeconds.clamp(0, 359999);
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final remainder = seconds % 60;
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:'
        '${remainder.toString().padLeft(2, '0')}';
  }
  return '$minutes:${remainder.toString().padLeft(2, '0')}';
}
