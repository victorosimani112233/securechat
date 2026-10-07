import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../safety/abuse_report.dart';
import '../../services/app_container.dart';

String reportReasonLabel(BuildContext context, ReportReason reason) =>
    switch (reason) {
      ReportReason.spam => context.l10n.safety_reason_spam,
      ReportReason.harassment => context.l10n.safety_reason_harassment,
      ReportReason.inappropriate => context.l10n.safety_reason_inappropriate,
      ReportReason.childSafety => context.l10n.safety_reason_child_safety,
      ReportReason.impersonation => context.l10n.safety_reason_impersonation,
      ReportReason.other => context.l10n.safety_reason_other,
    };

/// Kullanicinin sectigi bildirim; iptal edilirse null.
class ReportChoice {
  const ReportChoice({
    required this.reason,
    required this.note,
    required this.alsoBlock,
  });

  final ReportReason reason;
  final String note;
  final bool alsoBlock;
}

Future<ReportChoice?> showReportSheet(
  BuildContext context, {
  required bool offerBlock,
}) => showModalBottomSheet<ReportChoice>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _ReportSheet(offerBlock: offerBlock),
);

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({required this.offerBlock});

  final bool offerBlock;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  final _note = TextEditingController();
  ReportReason? _reason;
  var _alsoBlock = true;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.safety_report_title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.safety_report_e2ee_note,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              RadioGroup<ReportReason>(
                groupValue: _reason,
                onChanged: (value) => setState(() => _reason = value),
                child: Column(
                  children: [
                    for (final reason in ReportReason.values)
                      RadioListTile<ReportReason>(
                        key: ValueKey('report-reason-${reason.wire}'),
                        value: reason,
                        contentPadding: EdgeInsets.zero,
                        title: Text(reportReasonLabel(context, reason)),
                      ),
                  ],
                ),
              ),
              TextField(
                key: const ValueKey('report-note'),
                controller: _note,
                maxLength: AbuseReportService.maxNoteLength,
                maxLines: 3,
                minLines: 1,
                decoration: InputDecoration(
                  hintText: l10n.safety_report_note_hint,
                ),
              ),
              if (widget.offerBlock)
                CheckboxListTile(
                  key: const ValueKey('report-also-block'),
                  value: _alsoBlock,
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.safety_report_also_block),
                  onChanged: (value) =>
                      setState(() => _alsoBlock = value ?? false),
                ),
              const SizedBox(height: 8),
              FilledButton(
                key: const ValueKey('report-submit'),
                onPressed: _reason == null
                    ? null
                    : () => Navigator.pop(
                        context,
                        ReportChoice(
                          reason: _reason!,
                          note: _note.text,
                          alsoBlock: widget.offerBlock && _alsoBlock,
                        ),
                      ),
                child: Text(l10n.safety_report_submit),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<bool> confirmBlock(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.safety_block_confirm_title),
        content: Text(context.l10n.safety_block_confirm_body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            key: const ValueKey('block-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.safety_block),
          ),
        ],
      ),
    ) ??
    false;

/// Bir kisiyi bildirir; istenirse engeller. Sonucu snackbar ile gosterir.
Future<void> reportUserFlow(BuildContext context, String userId) async {
  final safety = AppContainerScope.of(context).safety;
  if (safety == null) return;
  final choice = await showReportSheet(context, offerBlock: true);
  if (choice == null || !context.mounted) return;
  await _submitWithFeedback(
    context,
    () => safety.reportUser(
      userId,
      reason: choice.reason,
      note: choice.note,
      alsoBlock: choice.alsoBlock,
    ),
  );
}

Future<void> reportGroupFlow(
  BuildContext context, {
  required List<String> admins,
  required List<String> members,
}) async {
  final safety = AppContainerScope.of(context).safety;
  if (safety == null) return;
  final choice = await showReportSheet(context, offerBlock: false);
  if (choice == null || !context.mounted) return;
  await _submitWithFeedback(
    context,
    () => safety.reportGroup(
      admins: admins,
      members: members,
      reason: choice.reason,
      note: choice.note,
    ),
  );
}

Future<void> _submitWithFeedback(
  BuildContext context,
  Future<void> Function() submit,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  try {
    await submit();
    messenger.showSnackBar(SnackBar(content: Text(l10n.safety_report_sent)));
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.safety_report_failed)));
  }
}

/// Engelle / engeli kaldir. Yeni durumu doner; islem iptal edildiyse null.
Future<bool?> toggleBlockFlow(BuildContext context, String userId) async {
  final safety = AppContainerScope.of(context).safety;
  if (safety == null) return null;
  final blockList = safety.blockList;
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  if (await blockList.isBlocked(userId)) {
    await blockList.unblock(userId);
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.safety_unblocked_notice)),
    );
    return false;
  }
  if (!context.mounted || !await confirmBlock(context)) return null;
  await blockList.block(userId);
  messenger.showSnackBar(SnackBar(content: Text(l10n.safety_blocked_notice)));
  return true;
}

class BlockedContactsScreen extends StatefulWidget {
  const BlockedContactsScreen({super.key});

  @override
  State<BlockedContactsScreen> createState() => _BlockedContactsScreenState();
}

class _BlockedContactsScreenState extends State<BlockedContactsScreen> {
  Future<List<(String, String)>>? _entries;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _entries ??= _load();
  }

  Future<List<(String, String)>> _load() async {
    final container = AppContainerScope.of(context);
    final ids = await container.safety?.blockList.all() ?? const <String>[];
    final names = {
      for (final conversation
          in await container.conversations.watchConversations().first)
        if (!conversation.isGroup) conversation.id: conversation.peerName,
    };
    return [for (final id in ids) (id, names[id] ?? id)];
  }

  Future<void> _unblock(String userId) async {
    await AppContainerScope.of(context).safety?.blockList.unblock(userId);
    if (!mounted) return;
    setState(() => _entries = _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.safety_blocked_contacts)),
      body: FutureBuilder<List<(String, String)>>(
        future: _entries,
        builder: (context, snapshot) {
          final entries = snapshot.data;
          if (entries == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (entries.isEmpty) {
            return Center(
              child: Text(context.l10n.safety_blocked_contacts_empty),
            );
          }
          return ListView(
            children: [
              for (final (id, name) in entries)
                ListTile(
                  key: ValueKey('blocked-$id'),
                  leading: const Icon(Icons.block),
                  title: Text(name),
                  trailing: TextButton(
                    onPressed: () => _unblock(id),
                    child: Text(context.l10n.safety_unblock),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
