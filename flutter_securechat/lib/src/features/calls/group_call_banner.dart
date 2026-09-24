import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../media/call_manager.dart';
import '../../media/call_models.dart';

class GroupCallBanner extends StatefulWidget {
  const GroupCallBanner({
    super.key,
    required this.groupId,
    required this.calls,
  });
  final String groupId;
  final CallManager calls;

  @override
  State<GroupCallBanner> createState() => _GroupCallBannerState();
}

class _GroupCallBannerState extends State<GroupCallBanner>
    with WidgetsBindingObserver {
  ActiveGroupCall? _active;
  Timer? _timer;
  StreamSubscription<CallSession?>? _sessions;
  bool _refreshing = false;
  bool _joining = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessions = widget.calls.sessions.listen((_) {
      if (mounted) setState(() {});
      unawaited(_refresh());
    });
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
    unawaited(_refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (_refreshing ||
        !mounted ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused)
      return;
    _refreshing = true;
    try {
      final active = await widget.calls.activeGroupCall(widget.groupId);
      if (mounted) setState(() => _active = active);
    } catch (_) {
      if (mounted) setState(() => _active = null);
    } finally {
      _refreshing = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _sessions?.cancel();
    super.dispose();
  }

  Future<void> _join() async {
    if (_joining) return;
    final session = widget.calls.currentSession;
    if (session?.groupId == widget.groupId && !session!.isTerminal) {
      if (session.state != CallState.ringing ||
          session.direction != CallDirection.incoming) {
        widget.calls.openCurrentCall();
        return;
      }
    }
    setState(() => _joining = true);
    try {
      final joined =
          session?.groupId == widget.groupId &&
              session?.state == CallState.ringing
          ? await widget.calls.acceptCall()
          : _active != null && await widget.calls.joinActiveGroupCall(_active!);
      if (!mounted) return;
      if (joined) {
        widget.calls.openCurrentCall();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.group_call_join_failed)),
        );
        await _refresh();
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.group_call_join_failed)),
        );
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.calls.currentSession;
    final local = current?.groupId == widget.groupId && !current!.isTerminal
        ? current
        : null;
    final type = local?.callType ?? _active?.callType;
    if (type == null) return const SizedBox.shrink();
    final returning =
        local != null &&
        !(local.direction == CallDirection.incoming &&
            local.state == CallState.ringing);
    final colors = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('group-call-banner'),
      color: colors.secondaryContainer,
      child: InkWell(
        onTap: _joining ? null : _join,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                type == CallType.video
                    ? Icons.videocam_outlined
                    : Icons.call_outlined,
                color: colors.onSecondaryContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  type == CallType.video
                      ? context.l10n.group_call_active_video
                      : context.l10n.group_call_active_voice,
                  style: TextStyle(color: colors.onSecondaryContainer),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _joining ? null : _join,
                icon: _joining
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.call, size: 18),
                label: Text(
                  returning
                      ? context.l10n.group_call_return
                      : context.l10n.group_call_join,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
