import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../l10n/l10n.dart';
import '../../services/app_container.dart';
import '../../storage/storage_entities.dart';
import '../../widgets/text_controller_scope.dart';
import 'recipient_picker_screen.dart';

Future<void> showCreateGroupFlow(BuildContext context) async {
  final service = AppContainerScope.of(context).contacts;
  if (service == null) return;
  final name = await showDialog<String>(
    context: context,
    builder: (context) => TextControllerScope(
      builder: (context, controller) => AlertDialog(
        title: Text(context.l10n.create_group_title),
        content: TextField(
          key: const ValueKey('new-group-name'),
          controller: controller,
          autofocus: true,
          maxLength: 100,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: context.l10n.group_name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.cancel),
          ),
          ValueListenableBuilder(
            valueListenable: controller,
            builder: (context, value, _) => FilledButton(
              onPressed: value.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(context, value.text.trim()),
              child: Text(context.l10n.continue_action),
            ),
          ),
        ],
      ),
    ),
  );
  if (name == null || !context.mounted) return;
  ConversationEntity? group;
  final contacts = <String, ContactEntity>{};
  final result = await Navigator.of(context).push<List<RecipientChoice>>(
    MaterialPageRoute(
      builder: (_) => RecipientPickerScreen(
        title: context.l10n.conv_new_group,
        actionLabel: context.l10n.create_group_and_add,
        choices: service.watchRegistered().map((items) {
          contacts
            ..clear()
            ..addEntries(items.map((item) => MapEntry(item.id, item)));
          return items
              .map(
                (item) => RecipientChoice(
                  id: item.id,
                  name: item.displayName,
                  detail: item.phoneNumber,
                ),
              )
              .toList();
        }),
        onConfirm: (selected) async {
          if (selected.any((item) => !contacts.containsKey(item.id)))
            throw StateError('Contact unavailable');
          group = await service.createGroup(
            name,
            selected.map((item) => contacts[item.id]!).toList(),
          );
          return true;
        },
      ),
    ),
  );
  final created = group;
  if (result == null || created == null || !context.mounted) return;
  Navigator.of(context).pushNamed(
    '/chat',
    arguments: Conversation(
      id: created.id,
      peerId: created.peerId,
      peerName: created.peerName,
      peerPhone: '',
      isGroup: true,
      groupMembers: created.groupMembers?.split(',') ?? const [],
      groupAdmins: created.groupAdmins?.split(',') ?? const [],
    ),
  );
}
