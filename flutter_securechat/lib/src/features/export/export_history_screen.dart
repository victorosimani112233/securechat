import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../l10n/l10n.dart';
import '../../services/app_container.dart';
import '../../storage/storage_entities.dart';
import '../../widgets/azure_backdrop.dart';

class ExportHistoryScreen extends StatelessWidget {
  const ExportHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final conversation =
        ModalRoute.of(context)?.settings.arguments as Conversation?;
    final audit = AppContainerScope.of(context).auditRuntime?.service;
    return AzureBackdrop(
      child: Scaffold(
        appBar: AppBar(title: Text(context.l10n.export_history)),
        body: conversation == null || audit == null
            ? Center(child: Text(context.l10n.group_not_found))
            : FutureBuilder<bool>(
                future: audit.isLocalAdmin(conversation.id),
                builder: (context, adminSnapshot) {
                  if (adminSnapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (adminSnapshot.data != true) {
                    return const _UnauthorizedNotice();
                  }
                  return StreamBuilder<List<ExportLogEntity>>(
                    stream: audit.watchHistory(conversation.id),
                    builder: (context, snapshot) {
                      final entries = snapshot.data ?? const [];
                      if (entries.isEmpty) {
                        return Center(child: Text(context.l10n.no_exports_yet));
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: entries.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, index) =>
                            _ExportLogRow(entries[index]),
                      );
                    },
                  );
                },
              ),
      ),
    );
  }
}

class _ExportLogRow extends StatelessWidget {
  const _ExportLogRow(this.entry);
  final ExportLogEntity entry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.share_outlined, color: Color(0xFFEF6C00)),
        title: Text(entry.actorDisplayName),
        subtitle: Text(
          '${_format(entry.timestamp)} · '
          '${context.l10n.message_count(entry.messageCount)}\n'
          '${entry.firstMsgTs == null || entry.lastMsgTs == null ? context.l10n.entire_chat : '${_date(entry.firstMsgTs!)} → ${_date(entry.lastMsgTs!)}'}',
        ),
        isThreeLine: true,
      ),
    );
  }

  static String _format(int timestamp) {
    final d = DateTime.fromMillisecondsSinceEpoch(timestamp).toLocal();
    return '${_two(d.day)}.${_two(d.month)}.${d.year} '
        '${_two(d.hour)}:${_two(d.minute)}';
  }

  static String _date(int timestamp) {
    final d = DateTime.fromMillisecondsSinceEpoch(timestamp).toLocal();
    return '${_two(d.day)}.${_two(d.month)}.${d.year}';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}

class _UnauthorizedNotice extends StatelessWidget {
  const _UnauthorizedNotice();

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.block, size: 48),
        const SizedBox(height: 12),
        Text(context.l10n.admin_only_screen),
      ],
    ),
  );
}
