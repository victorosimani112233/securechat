import 'package:flutter/material.dart';

import '../../calls/call_history_service.dart';
import '../../core/models.dart';
import '../../media/call_models.dart';
import '../../l10n/l10n.dart';
import '../../services/app_container.dart';
import '../../widgets/avatar.dart';
import '../../widgets/azure_backdrop.dart';
import 'call_screen.dart';
import '../../widgets/azure_surface.dart';
import '../../widgets/azure_empty_state.dart';

enum _CallFilter { all, missed, incoming, outgoing, video, group }

class CallHistoryScreen extends StatefulWidget {
  const CallHistoryScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  _CallFilter _filter = _CallFilter.all;
  bool _deleting = false;

  @override
  Widget build(BuildContext context) {
    final container = AppContainerScope.of(context);
    final runtime = container.mediaRuntime;
    return AzureBackdrop(
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !widget.embedded,
          title: Text(context.l10n.nav_calls),
        ),
        body: SafeArea(
          top: false,
          child: StreamBuilder<List<Conversation>>(
            stream: container.conversations.watchConversations(),
            builder: (context, conversations) {
              final groups = {
                for (final conversation
                    in conversations.data ?? <Conversation>[])
                  if (conversation.isGroup) conversation.id: conversation,
              };
              return StreamBuilder<List<CallHistoryEntry>>(
                stream: runtime?.callHistory.watchAll(),
                builder: (context, snapshot) => _content(
                  snapshot.data ?? const [],
                  groups,
                  container.session.userId,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  String? _groupId(CallHistoryEntry call, Map<String, Conversation> groups) =>
      call.groupId ?? (groups.containsKey(call.peerId) ? call.peerId : null);

  Widget _content(
    List<CallHistoryEntry> source,
    Map<String, Conversation> groups,
    String? userId,
  ) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final calls = source
        .where(
          (call) => switch (_filter) {
            _CallFilter.all => true,
            _CallFilter.missed => _isMissed(call),
            _CallFilter.incoming => call.direction == CallDirection.incoming,
            _CallFilter.outgoing => call.direction == CallDirection.outgoing,
            _CallFilter.video => call.callType == CallType.video,
            _CallFilter.group => _groupId(call, groups) != null,
          },
        )
        .toList(growable: false);
    final labels = {
      _CallFilter.all: l10n.conv_filter_all,
      _CallFilter.missed: l10n.missed,
      _CallFilter.incoming: l10n.incoming,
      _CallFilter.outgoing: l10n.outgoing,
      _CallFilter.video: l10n.calls_filter_video,
      _CallFilter.group: l10n.group,
    };
    return Column(
      children: [
        SizedBox(
          height: (MediaQuery.textScalerOf(context).scale(14) + 28).clamp(
            48,
            double.infinity,
          ),
          child: ListView(
            key: const ValueKey('call-history-filters'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final entry in labels.entries)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: FilterChip(
                    key: ValueKey('call-filter-${entry.key.name}'),
                    label: Text(entry.value),
                    selected: _filter == entry.key,
                    showCheckmark: true,
                    onSelected: (_) => setState(() => _filter = entry.key),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: calls.isEmpty
              ? AzureEmptyState(
                  icon: Icons.call_outlined,
                  title: source.isEmpty
                      ? l10n.no_call_history
                      : l10n.calls_filter_empty,
                  message: source.isEmpty ? l10n.calls_empty_body : null,
                )
              : ListView.separated(
                  key: ValueKey('call-history-${_filter.name}'),
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                  itemCount: calls.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 7),
                  itemBuilder: (context, index) {
                    final call = calls[index];
                    final missed = _isMissed(call);
                    final outgoing = call.direction == CallDirection.outgoing;
                    final statusColor = missed
                        ? (dark ? Colors.red.shade300 : Colors.red.shade700)
                        : outgoing
                        ? (dark ? Colors.green.shade300 : Colors.green.shade700)
                        : (dark ? Colors.blue.shade300 : Colors.blue.shade700);
                    final background = Color.alphaBlend(
                      statusColor.withValues(alpha: dark ? .10 : .08),
                      AzureSurface.colorOf(context),
                    );
                    final accent = Color.lerp(
                      theme.colorScheme.onSurfaceVariant,
                      statusColor,
                      .60,
                    )!;
                    final video = call.callType == CallType.video;
                    final groupId = _groupId(call, groups);
                    final group = groups[groupId];
                    final canCall =
                        groupId == null ||
                        (userId != null &&
                            group != null &&
                            !group.hasLeftGroup(userId));
                    return AzureSurface(
                      key: ValueKey('call-history-entry-${call.id}'),
                      backgroundColor: background,
                      child: ListTile(
                        onLongPress: _deleting
                            ? null
                            : () => _confirmDelete(call),
                        leading: GeneratedAvatar(name: call.peerName),
                        title: Text(call.peerName),
                        subtitle: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsetsDirectional.only(
                                top: 2,
                                end: 6,
                              ),
                              child: Icon(
                                missed
                                    ? Icons.call_missed
                                    : outgoing
                                    ? Icons.call_made
                                    : Icons.call_received,
                                size: 16,
                                color: accent,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                [
                                  if (groupId != null) l10n.group,
                                  _description(context, call),
                                ].join(' · '),
                              ),
                            ),
                          ],
                        ),
                        trailing: IconButton(
                          tooltip: video ? l10n.video_call : l10n.voice_call,
                          icon: Icon(
                            video
                                ? Icons.videocam_outlined
                                : Icons.call_outlined,
                          ),
                          onPressed: _deleting || !canCall
                              ? null
                              : () => Navigator.of(context).pushNamed(
                                  '/calls',
                                  arguments: CallRouteArguments(
                                    peerId: groupId ?? call.peerId,
                                    peerName: call.peerName,
                                    callType: call.callType,
                                    isGroupCall: groupId != null,
                                    peerIds:
                                        group?.groupMembers
                                            .where((id) => id != userId)
                                            .toList() ??
                                        const [],
                                  ),
                                ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(CallHistoryEntry call) async {
    if (_deleting) return;
    final history = AppContainerScope.of(context).mediaRuntime?.callHistory;
    if (history == null) return;
    setState(() => _deleting = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          scrollable: true,
          title: Text(context.l10n.conv_delete),
          content: Text('${call.peerName}\n${_description(context, call)}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(context.l10n.cancel),
            ),
            FilledButton.icon(
              key: const ValueKey('call-history-delete-confirm'),
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.delete_outline),
              label: Text(context.l10n.msg_action_delete_for_me),
            ),
          ],
        ),
      );
      if (confirmed == true && mounted) await history.delete(call.id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.recipient_action_failed)),
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  static bool _isMissed(CallHistoryEntry call) =>
      call.status == CallHistoryStatus.missed ||
      (call.status == CallHistoryStatus.busy &&
          call.direction == CallDirection.incoming);

  static String _description(BuildContext context, CallHistoryEntry call) {
    final direction = call.direction == CallDirection.outgoing
        ? context.l10n.outgoing
        : context.l10n.incoming;
    final type = call.callType == CallType.video
        ? context.l10n.video
        : context.l10n.voice;
    final status = switch (call.status) {
      CallHistoryStatus.missed => ' · ${context.l10n.missed}',
      CallHistoryStatus.rejected => ' · ${context.l10n.rejected}',
      CallHistoryStatus.busy => ' · ${context.l10n.busy}',
      CallHistoryStatus.failed => ' · ${context.l10n.failed}',
      CallHistoryStatus.completed =>
        call.duration > Duration.zero ? ' · ${_duration(call.duration)}' : '',
    };
    return context.l10n.call_description(direction, type, status);
  }

  static String _duration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
