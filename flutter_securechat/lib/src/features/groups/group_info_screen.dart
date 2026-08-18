import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../export/export_audit_service.dart';
import '../../groups/group_management_service.dart';
import '../../l10n/l10n.dart';
import '../../services/app_container.dart';
import '../../storage/storage_entities.dart';
import '../../widgets/avatar.dart';
import '../../widgets/azure_backdrop.dart';

class GroupInfoScreen extends StatelessWidget {
  const GroupInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final argument =
        ModalRoute.of(context)?.settings.arguments as Conversation?;
    final container = AppContainerScope.of(context);
    final groups = container.groupRuntime?.service;
    final audit = container.auditRuntime?.service;
    if (argument == null || groups == null) {
      return Scaffold(body: Center(child: Text(context.l10n.group_not_found)));
    }
    return StreamBuilder<ConversationEntity?>(
      stream: groups.watchGroup(argument.id),
      builder: (context, snapshot) {
        final group = snapshot.data;
        if (group == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return StreamBuilder<List<ContactEntity>>(
          stream: groups.watchContacts(),
          builder: (context, contactsSnapshot) => _GroupInfoBody(
            group: group,
            contacts: contactsSnapshot.data ?? const [],
            groups: groups,
            audit: audit,
            routeArgument: argument,
          ),
        );
      },
    );
  }
}

class _GroupInfoBody extends StatelessWidget {
  const _GroupInfoBody({
    required this.group,
    required this.contacts,
    required this.groups,
    required this.audit,
    required this.routeArgument,
  });
  final ConversationEntity group;
  final List<ContactEntity> contacts;
  final GroupManagementService groups;
  final ExportAuditService? audit;
  final Conversation routeArgument;

  @override
  Widget build(BuildContext context) {
    final members = _split(group.groupMembers);
    final admins = _split(group.groupAdmins).toSet();
    final isAdmin = groups.isLocalAdmin(group);
    return AzureBackdrop(
      child: Scaffold(
        appBar: AppBar(title: Text(context.l10n.group_info)),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  GeneratedAvatar(name: group.peerName, size: 96),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          group.peerName,
                          style: Theme.of(context).textTheme.headlineSmall,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      if (isAdmin)
                        IconButton(
                          tooltip: context.l10n.edit_group_name,
                          onPressed: () => _editName(context),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                    ],
                  ),
                  Text(context.l10n.members_count(members.length)),
                ],
              ),
            ),
            const Divider(),
            SwitchListTile(
              secondary: const Icon(Icons.campaign_outlined),
              title: Text(context.l10n.group_admin_only),
              subtitle: Text(context.l10n.group_announcement_desc),
              value: group.isReadOnly,
              onChanged: isAdmin
                  ? (value) =>
                        _run(context, () => groups.setReadOnly(group.id, value))
                  : null,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.share_outlined),
              title: Text(context.l10n.chat_export),
              subtitle: Text(
                isAdmin
                    ? context.l10n.member_export_permission
                    : context.l10n.admin_change_only,
              ),
              value: group.isExportEnabled,
              onChanged: isAdmin && audit != null
                  ? (value) => _toggleExport(context, value)
                  : null,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.notifications_off_outlined),
              title: Text(context.l10n.mute),
              value: group.isMuted,
              onChanged: (value) => groups.setMuted(group.id, value),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.lock_outline),
              title: Text(context.l10n.chat_lock),
              subtitle: Text(context.l10n.chat_lock_desc),
              value: group.isLocked,
              onChanged: (value) => groups.setLocked(group.id, value),
            ),
            if (isAdmin)
              ListTile(
                leading: const Icon(Icons.history),
                title: Text(context.l10n.export_history),
                onTap: () => Navigator.pushNamed(
                  context,
                  '/export-history',
                  arguments: routeArgument.copyWith(
                    isExportEnabled: group.isExportEnabled,
                  ),
                ),
              ),
            const Divider(),
            ListTile(
              title: Text('${context.l10n.members_count(members.length)}/256'),
              trailing: isAdmin
                  ? IconButton(
                      tooltip: context.l10n.add_member,
                      onPressed:
                          members.length >=
                              GroupManagementService.maximumMembers
                          ? null
                          : () => _addMembers(context, members),
                      icon: const Icon(Icons.person_add_outlined),
                    )
                  : null,
            ),
            for (final memberId in members)
              ListTile(
                leading: GeneratedAvatar(name: _name(memberId), size: 40),
                title: Text(_name(memberId)),
                subtitle: memberId == groups.localUserId
                    ? Text(context.l10n.you)
                    : Text(memberId),
                trailing: admins.contains(memberId)
                    ? Chip(label: Text(context.l10n.admin))
                    : isAdmin && memberId != groups.localUserId
                    ? PopupMenuButton<String>(
                        onSelected: (action) =>
                            _memberAction(context, action, memberId),
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'promote',
                            child: Text(context.l10n.make_admin),
                          ),
                          PopupMenuItem(
                            value: 'remove',
                            child: Text(context.l10n.remove_from_group),
                          ),
                        ],
                      )
                    : null,
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.exit_to_app, color: Colors.red),
              title: Text(
                context.l10n.group_leave,
                style: const TextStyle(color: Colors.red),
              ),
              onTap: () => _leave(context),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleExport(BuildContext context, bool value) {
    final service = audit;
    if (service == null) return;
    _run(context, () => service.toggleGroupExport(group.id, value));
  }

  String _name(String memberId) =>
      contacts
          .where((contact) => contact.id == memberId)
          .map((contact) => contact.displayName)
          .firstOrNull ??
      memberId;

  Future<void> _editName(BuildContext context) async {
    final controller = TextEditingController(text: group.peerName);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.edit_group_name),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(context.l10n.save),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && context.mounted) {
      await _run(context, () => groups.updateName(group.id, name));
    }
  }

  Future<void> _addMembers(BuildContext context, List<String> members) async {
    final eligible = contacts
        .where(
          (contact) => contact.isRegistered && !members.contains(contact.id),
        )
        .toList();
    final selected = <String>{};
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(context.l10n.add_member),
          content: SizedBox(
            width: 420,
            child: eligible.isEmpty
                ? Text(context.l10n.no_contacts_to_add)
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final contact in eligible)
                        CheckboxListTile(
                          value: selected.contains(contact.id),
                          title: Text(contact.displayName),
                          subtitle: Text(contact.phoneNumber),
                          onChanged: (value) => setState(() {
                            value == true
                                ? selected.add(contact.id)
                                : selected.remove(contact.id);
                          }),
                        ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, selected),
              child: Text('${context.l10n.add} (${selected.length})'),
            ),
          ],
        ),
      ),
    );
    if (result != null && context.mounted) {
      await _run(context, () => groups.addMembers(group.id, result));
    }
  }

  Future<void> _memberAction(
    BuildContext context,
    String action,
    String memberId,
  ) async {
    if (action == 'promote') {
      await _run(context, () => groups.promoteToAdmin(group.id, memberId));
      return;
    }
    final confirmed = await _confirm(
      context,
      context.l10n.remove_member_named(_name(memberId)),
    );
    if (confirmed && context.mounted) {
      await _run(context, () => groups.removeMember(group.id, memberId));
    }
  }

  Future<void> _leave(BuildContext context) async {
    if (!await _confirm(context, context.l10n.leave_group_confirm)) return;
    if (!context.mounted) return;
    try {
      await groups.leaveGroup(group.id);
      if (context.mounted)
        Navigator.popUntil(context, ModalRoute.withName('/'));
    } catch (error) {
      if (context.mounted) _notice(context, '$error');
    }
  }

  static Future<void> _run(
    BuildContext context,
    Future<void> Function() operation,
  ) async {
    try {
      await operation();
    } catch (error) {
      if (context.mounted) _notice(context, '$error');
    }
  }

  static Future<bool> _confirm(BuildContext context, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.confirmation),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.l10n.confirm),
            ),
          ],
        ),
      ) ??
      false;

  static void _notice(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  static List<String> _split(String? value) =>
      value?.split(',').where((id) => id.isNotEmpty).toList() ?? const [];
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
