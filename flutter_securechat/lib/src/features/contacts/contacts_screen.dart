import 'package:flutter/material.dart';

import '../../contacts/contact_service.dart';
import '../../contacts/private_contact_discovery.dart';
import '../../core/models.dart';
import '../../l10n/l10n.dart';
import '../../services/app_container.dart';
import '../../storage/storage_entities.dart';
import '../../widgets/avatar.dart';
import '../../widgets/azure_backdrop.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final _search = TextEditingController();
  String _query = '';
  bool _syncing = false;
  _ContactSyncFailure? _failure;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_syncing && _failure == null) _syncContacts();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = AppContainerScope.of(context).contacts;
    return AzureBackdrop(
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !widget.embedded,
          title: Text(context.l10n.nav_contacts),
          actions: [
            IconButton(
              onPressed: _syncing ? null : _syncContacts,
              icon: const Icon(Icons.sync),
              tooltip: context.l10n.action_retry,
            ),
          ],
        ),
        body: service == null
            ? Center(child: Text(context.l10n.contacts_permission_body))
            : StreamBuilder<List<ContactEntity>>(
                stream: service.watchRegistered(),
                builder: (context, snapshot) {
                  final contacts = (snapshot.data ?? const [])
                      .where(
                        (contact) =>
                            _query.isEmpty ||
                            contact.displayName.toLowerCase().contains(
                              _query.toLowerCase(),
                            ) ||
                            contact.phoneNumber.contains(_query),
                      )
                      .toList(growable: false);
                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      TextField(
                        controller: _search,
                        onChanged: (value) =>
                            setState(() => _query = value.trim()),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          hintText:
                              context.l10n.create_group_search_placeholder,
                          suffixIcon: IconButton(
                            tooltip: context.l10n.dialpad,
                            onPressed: () => _openDialpad(service),
                            icon: const Icon(Icons.dialpad),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: contacts.isEmpty
                            ? null
                            : () => _createGroup(service, contacts),
                        icon: const Icon(Icons.group_add_outlined),
                        label: Text(context.l10n.create_group_title),
                      ),
                      if (_syncing) ...[
                        const SizedBox(height: 16),
                        const LinearProgressIndicator(),
                      ],
                      if (_failure != null) ...[
                        const SizedBox(height: 12),
                        AzureGlassPanel(
                          key: const Key('contacts-private-directory-status'),
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                _failure!.icon,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _failure!.title,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _failure!.body,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                    const SizedBox(height: 8),
                                    TextButton.icon(
                                      onPressed: _syncing
                                          ? null
                                          : _syncContacts,
                                      icon: const Icon(Icons.refresh, size: 18),
                                      label: Text(context.l10n.action_retry),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      if (!_syncing && contacts.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            context.l10n.no_registered_contacts,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      for (final contact in contacts)
                        ListTile(
                          leading: GeneratedAvatar(name: contact.displayName),
                          title: Text(contact.displayName),
                          subtitle: Text(contact.phoneNumber),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _openContact(service, contact),
                        ),
                    ],
                  );
                },
              ),
      ),
    );
  }

  Future<void> _syncContacts() async {
    final service = AppContainerScope.of(context).contacts;
    if (service == null || _syncing) return;
    setState(() {
      _syncing = true;
      _failure = null;
    });
    try {
      await service.importAndDiscover();
    } catch (error) {
      if (mounted) setState(() => _failure = _presentFailure(error));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  _ContactSyncFailure _presentFailure(Object error) {
    if (error is DirectoryServiceUnavailableException) {
      if (error.protocolRouteMissing) {
        return _ContactSyncFailure(
          title: context.l10n.contacts_secure_directory_server_upgrade_title,
          body: context.l10n.contacts_secure_directory_server_upgrade_body,
          icon: Icons.system_update_alt_outlined,
        );
      }
      return _ContactSyncFailure(
        title: context.l10n.contacts_secure_directory_unavailable_title,
        body: context.l10n.contacts_secure_directory_unavailable_body,
        icon: Icons.shield_outlined,
      );
    }
    if (error is PrivateDirectoryException) {
      return _ContactSyncFailure(
        title: context.l10n.contacts_secure_directory_unavailable_title,
        body: context.l10n.contacts_secure_directory_verification_failed_body,
        icon: Icons.gpp_maybe_outlined,
      );
    }
    if (error is StateError) {
      return _ContactSyncFailure(
        title: context.l10n.contacts_permission_title,
        body: context.l10n.contacts_permission_body,
        icon: Icons.contacts_outlined,
      );
    }
    return _ContactSyncFailure(
      title: context.l10n.contacts_secure_directory_unavailable_title,
      body: context.l10n.contacts_sync_failed_body,
      icon: Icons.sync_problem_outlined,
    );
  }

  Future<void> _openContact(
    ContactService service,
    ContactEntity contact,
  ) async {
    await service.ensureConversation(contact);
    if (!mounted) return;
    Navigator.of(context).pushNamed('/chat', arguments: _conversation(contact));
  }

  Future<void> _openDialpad(ContactService service) async {
    final controller = TextEditingController(text: '+90');
    final value = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.phone_outlined),
              hintText: '+90',
            ),
            onSubmitted: (phone) => Navigator.pop(context, phone),
          ),
        ),
      ),
    );
    controller.dispose();
    if (value == null || !mounted) return;
    try {
      final contact = await service.resolvePhone(value);
      if (!mounted) return;
      if (contact == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.create_group_user_not_found)),
        );
      } else {
        await _openContact(service, contact);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _createGroup(
    ContactService service,
    List<ContactEntity> contacts,
  ) async {
    final name = TextEditingController();
    final selected = <String>{};
    final result = await showDialog<List<ContactEntity>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(context.l10n.create_group_title),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: InputDecoration(
                    labelText: context.l10n.group_name,
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final contact in contacts)
                        CheckboxListTile(
                          value: selected.contains(contact.id),
                          title: Text(contact.displayName),
                          onChanged: (checked) => setDialogState(() {
                            checked == true
                                ? selected.add(contact.id)
                                : selected.remove(contact.id);
                          }),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(
                      context,
                      contacts
                          .where((contact) => selected.contains(contact.id))
                          .toList(),
                    ),
              child: Text(context.l10n.create_group_action),
            ),
          ],
        ),
      ),
    );
    if (result == null || result.isEmpty) {
      name.dispose();
      return;
    }
    final group = await service.createGroup(name.text, result);
    name.dispose();
    if (!mounted) return;
    Navigator.of(context).pushNamed(
      '/chat',
      arguments: Conversation(
        id: group.id,
        peerId: group.peerId,
        peerName: group.peerName,
        peerPhone: '',
        isGroup: true,
        groupMembers: group.groupMembers?.split(',') ?? const [],
        groupAdmins: group.groupAdmins?.split(',') ?? const [],
      ),
    );
  }

  Conversation _conversation(ContactEntity contact) => Conversation(
    id: contact.id,
    peerId: contact.id,
    peerName: contact.displayName,
    peerPhone: contact.phoneNumber,
  );
}

class _ContactSyncFailure {
  const _ContactSyncFailure({
    required this.title,
    required this.body,
    required this.icon,
  });

  final String title;
  final String body;
  final IconData icon;
}
