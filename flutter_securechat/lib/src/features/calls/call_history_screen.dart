import 'package:flutter/material.dart';

import '../../calls/call_history_service.dart';
import '../../media/call_models.dart';
import '../../l10n/l10n.dart';
import '../../services/app_container.dart';
import '../../widgets/avatar.dart';
import '../../widgets/azure_backdrop.dart';
import 'call_screen.dart';

class CallHistoryScreen extends StatelessWidget {
  const CallHistoryScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final runtime = AppContainerScope.of(context).mediaRuntime;
    return AzureBackdrop(
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !embedded,
          title: Text(context.l10n.nav_calls),
        ),
        body: runtime == null
            ? Center(child: Text(context.l10n.no_call_history))
            : StreamBuilder<List<CallHistoryEntry>>(
                stream: runtime.callHistory.watchAll(),
                builder: (context, snapshot) {
                  final calls = snapshot.data ?? const [];
                  if (calls.isEmpty) {
                    return Center(child: Text(context.l10n.no_call_history));
                  }
                  return ListView.separated(
                    itemCount: calls.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final call = calls[index];
                      final video = call.callType == CallType.video;
                      return ListTile(
                        leading: GeneratedAvatar(name: call.peerName),
                        title: Text(call.peerName),
                        subtitle: Text(_description(context, call)),
                        trailing: IconButton(
                          tooltip: video
                              ? context.l10n.video_call
                              : context.l10n.voice_call,
                          icon: Icon(
                            video
                                ? Icons.videocam_outlined
                                : Icons.call_outlined,
                          ),
                          onPressed: () => Navigator.of(context).pushNamed(
                            '/calls',
                            arguments: CallRouteArguments(
                              peerId: call.peerId,
                              peerName: call.peerName,
                              callType: video ? CallType.video : CallType.voice,
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
      ),
    );
  }

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
