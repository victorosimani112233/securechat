import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../auth/phone_privacy.dart';
import '../../contacts/contact_index.dart';
import '../../contacts/contact_search.dart';
import '../../contacts/contact_service.dart';
import '../../contacts/private_contact_discovery.dart';
import '../../core/models.dart';
import '../../l10n/l10n.dart';
import '../../services/app_container.dart';
import '../../storage/storage_entities.dart';
import '../../widgets/avatar.dart';
import '../../widgets/azure_backdrop.dart';
import '../../widgets/azure_empty_state.dart';
import '../../widgets/azure_surface.dart';
import '../../widgets/invite_sender.dart';
import '../../widgets/text_controller_scope.dart';
import 'create_group_flow.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({
    super.key,
    this.embedded = false,
    this.newChat = false,
  });

  final bool embedded;
  final bool newChat;

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final _search = TextEditingController();
  String _query = '';
  bool _syncing = false;
  _ContactSyncFailure? _failure;

  /// Rehberde olup ELÇİM kullanmayanlar. Yalniz bellekte tutulur.
  List<DeviceContact> _invitable = const [];

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
          title: Text(
            widget.newChat
                ? context.l10n.conv_new_chat
                : context.l10n.nav_contacts,
          ),
          actions: [
            IconButton(
              key: const Key('contacts-invite-friends'),
              onPressed: () => _invite(),
              icon: const Icon(Icons.person_add_alt_1_outlined),
              tooltip: context.l10n.contacts_invite_friends,
            ),
            IconButton(
              onPressed: _syncing ? null : () => _syncContacts(force: true),
              icon: const Icon(Icons.sync),
              tooltip: context.l10n.contacts_sync,
            ),
          ],
        ),
        body: service == null
            ? Center(child: Text(context.l10n.contacts_permission_body))
            : StreamBuilder<List<ContactEntity>>(
                stream: service.watchRegistered(),
                builder: (context, snapshot) {
                  final registered = snapshot.data ?? const <ContactEntity>[];
                  final contacts = registered
                      .where(
                        (contact) => matchesContactQuery(
                          name: contact.displayName,
                          phone: contact.phoneNumber,
                          query: _query,
                        ),
                      )
                      .toList(growable: false);
                  final invitable = _invitable
                      .where(
                        (contact) => matchesContactQuery(
                          name: contact.displayName,
                          phone: contact.phoneNumber,
                          query: _query,
                        ),
                      )
                      .toList(growable: false);
                  final noSearchResults =
                      (registered.isNotEmpty || _invitable.isNotEmpty) &&
                      contacts.isEmpty &&
                      invitable.isEmpty;
                  final registeredGroups = groupContactsByLetter(
                    contacts,
                    (contact) => contact.displayName,
                  );
                  final inviteGroups = groupContactsByLetter(
                    invitable,
                    (contact) => contact.displayName,
                  );
                  final letters = {
                    for (final group in registeredGroups) group.letter,
                    for (final group in inviteGroups) group.letter,
                  }.toList()..sort(_compareLetters);
                  // Aramada liste kisadir; harf cubugu yalniz tam listede.
                  final showRail = _query.isEmpty && letters.length >= 2;
                  return Stack(
                    children: [
                      SingleChildScrollView(
                        key: const Key('contacts-scroll'),
                        padding: EdgeInsetsDirectional.fromSTEB(
                          16,
                          16,
                          showRail ? 32 : 16,
                          16,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _search,
                              onChanged: (value) =>
                                  setState(() => _query = value.trim()),
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.search),
                                hintText: context
                                    .l10n
                                    .create_group_search_placeholder,
                                suffixIcon: IconButton(
                                  tooltip: context.l10n.dialpad,
                                  onPressed: () => _openDialpad(service),
                                  icon: const Icon(Icons.dialpad),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (!widget.newChat)
                              FilledButton.icon(
                                onPressed: () => showCreateGroupFlow(context),
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
                                key: const Key(
                                  'contacts-private-directory-status',
                                ),
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      _failure!.icon,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
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
                                                : () => _syncContacts(
                                                    force: true,
                                                  ),
                                            icon: const Icon(
                                              Icons.refresh,
                                              size: 18,
                                            ),
                                            label: Text(
                                              context.l10n.action_retry,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            if (contacts.isNotEmpty && invitable.isNotEmpty)
                              _SectionHeader(
                                title: context.l10n.contacts_on_elcim_section(
                                  contacts.length,
                                ),
                              ),
                            if (!_syncing &&
                                contacts.isEmpty &&
                                invitable.isEmpty)
                              AzureEmptyState(
                                icon: noSearchResults
                                    ? Icons.search_off
                                    : Icons.contacts_outlined,
                                title: noSearchResults
                                    ? context.l10n.conversations_no_results
                                    : context.l10n.no_registered_contacts,
                                message: noSearchResults
                                    ? context.l10n.conversations_no_results_body
                                    : context.l10n.contacts_empty_body,
                                topPadding: 48,
                              ),
                            // Satirlar kayan desenin uzerinde ciplak
                            // duruyordu; sohbet listesiyle ayni malzeme dili.
                            for (final group in registeredGroups) ...[
                              _LetterDivider(
                                key: _letterKey('registered', group.letter),
                                letter: group.letter,
                              ),
                              for (final contact in group.items) ...[
                                AzureSurface(
                                  child: ListTile(
                                    leading: GeneratedAvatar(
                                      name: contact.displayName,
                                    ),
                                    title: Text(contact.displayName),
                                    subtitle: Text(contact.phoneNumber),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => _openContact(service, contact),
                                  ),
                                ),
                                const SizedBox(height: 7),
                              ],
                            ],
                            if (invitable.isNotEmpty) ...[
                              _SectionHeader(
                                key: const Key('contacts-invite-section'),
                                title: context.l10n.contacts_invite_section(
                                  invitable.length,
                                ),
                              ),
                              for (final group in inviteGroups) ...[
                                _LetterDivider(
                                  key: _letterKey('invite', group.letter),
                                  letter: group.letter,
                                ),
                                for (final contact in group.items) ...[
                                  AzureSurface(
                                    child: ListTile(
                                      leading: GeneratedAvatar(
                                        name: contact.displayName,
                                      ),
                                      title: Text(contact.displayName),
                                      subtitle: Text(contact.phoneNumber),
                                      trailing: TextButton(
                                        onPressed: () => _invite(
                                          phone: contact.phoneNumber,
                                          name: contact.displayName,
                                        ),
                                        child: Text(
                                          context.l10n.contacts_invite_short,
                                        ),
                                      ),
                                      onTap: () => _invite(
                                        phone: contact.phoneNumber,
                                        name: contact.displayName,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 7),
                                ],
                              ],
                            ],
                          ],
                        ),
                      ),
                      if (showRail)
                        PositionedDirectional(
                          end: 0,
                          top: 0,
                          bottom: 0,
                          child: _LetterIndexRail(
                            key: const Key('contacts-index-rail'),
                            letters: letters,
                            onSelected: _jumpToLetter,
                          ),
                        ),
                    ],
                  );
                },
              ),
      ),
    );
  }

  final _letterKeys = <String, GlobalKey>{};

  GlobalKey _letterKey(String section, String letter) =>
      _letterKeys.putIfAbsent('$section:$letter', GlobalKey.new);

  static int _compareLetters(String left, String right) {
    int rank(String letter) {
      final index = contactIndexAlphabet.indexOf(letter);
      return index < 0 ? contactIndexAlphabet.length : index;
    }

    return rank(left) - rank(right);
  }

  /// Harf cubugundan secilen harfin ilk kisisine gider. Harf ELÇİM'deki
  /// kisilerde yoksa davet listesindeki ayni harfe gidilir.
  void _jumpToLetter(String letter) {
    final target =
        _letterKeys['registered:$letter']?.currentContext ??
        _letterKeys['invite:$letter']?.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(target);
  }

  /// Ekran acilisinda [force] yok: kisa surede ve rehber degismeden
  /// tekrarlanan eslesme sunucuya gitmez. Yenile dugmesi her zaman gider.
  Future<void> _syncContacts({bool force = false}) async {
    final service = AppContainerScope.of(context).contacts;
    if (service == null || _syncing) return;
    setState(() {
      _syncing = true;
      _failure = null;
    });
    if (_invitable.isEmpty) {
      // Davet listesi yalniz cihazda hesaplanir; sunucu eslemesi beklenmeden
      // gosterilir, esleme bitince yeniden hesaplanir.
      try {
        final local = await service.loadInvitableContacts();
        if (mounted) setState(() => _invitable = local);
      } catch (_) {
        // Rehber okunamadiysa esleme hatasi asagida gosterilir.
      }
    }
    try {
      await service.importAndDiscover(force: force);
    } catch (error) {
      if (mounted) setState(() => _failure = _presentFailure(error));
    }
    // Eslesme basarisiz olsa da onceki eslesmeye gore davet listesi
    // gosterilir; liste cihazda hesaplanir, sunucuya bir sey gitmez.
    var invitable = const <DeviceContact>[];
    try {
      invitable = await service.loadInvitableContacts();
    } catch (_) {
      // Rehber okunamadiysa davet listesi bos kalir; hata yukarida gosterildi.
    }
    if (mounted) {
      setState(() {
        _invitable = invitable;
        _syncing = false;
      });
    }
  }

  Future<void> _invite({String? phone, String? name}) =>
      sendInvite(context, phone: phone, name: name);

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
    final conversation = await service.ensureConversation(contact);
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushNamed('/chat', arguments: _conversation(conversation));
  }

  Future<void> _openDialpad(ContactService service) async {
    // Controller sheet'in kendi yasam dongusune ait: cikis animasyonu
    // surerken dispose edilirse TextField dispose edilmis notifier'a
    // listener baglamaya calisiyor (bkz TextControllerScope).
    final value = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => TextControllerScope(
        initialText: '+90',
        builder: (context, controller) {
          void submit() {
            final phone = controller.text.trim();
            if (normalizePhoneDigits(phone).length < 8) return;
            Navigator.pop(context, phone);
          }

          return AnimatedPadding(
            key: const Key('phone-number-sheet'),
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      context.l10n.conv_new_chat,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      key: const Key('phone-number-input'),
                      controller: controller,
                      autofocus: true,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.done,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.phone_outlined),
                        labelText: context.l10n.register_phone_label,
                        hintText: '+90 5XX XXX XX XX',
                      ),
                      onSubmitted: (_) => submit(),
                    ),
                    const SizedBox(height: 16),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: controller,
                      builder: (context, value, _) => FilledButton.icon(
                        key: const Key('phone-number-submit'),
                        onPressed: normalizePhoneDigits(value.text).length >= 8
                            ? submit
                            : null,
                        icon: const Icon(Icons.chat_bubble_outline),
                        label: Text(context.l10n.cd_new_chat_action),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    if (value == null || !mounted) return;
    try {
      final contact = await service.resolvePhone(value);
      if (!mounted) return;
      if (contact == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 8),
            content: Text(context.l10n.contacts_number_not_on_elcim),
            action: SnackBarAction(
              label: context.l10n.contacts_invite_short,
              onPressed: () => _invite(phone: value),
            ),
          ),
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

  Conversation _conversation(ConversationEntity conversation) => Conversation(
    id: conversation.id,
    peerId: conversation.peerId,
    peerName: conversation.peerName,
    peerPhone: conversation.peerPhone,
    isGroup: conversation.isGroup,
    groupMembers: conversation.groupMembers?.split(',') ?? const [],
    groupAdmins: conversation.groupAdmins?.split(',') ?? const [],
    isLocked: conversation.isLocked,
    isReadOnly: conversation.isReadOnly,
    isExportEnabled: conversation.isExportEnabled,
    groupDescription: conversation.groupDescription,
    groupPhoto: conversation.groupPhoto,
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
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

/// Harf grubunun basindaki ayrac: harf ve ince cizgi.
class _LetterDivider extends StatelessWidget {
  const _LetterDivider({super.key, required this.letter});

  final String letter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(6, 10, 0, 6),
      child: Row(
        children: [
          Text(
            letter,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Divider(
              height: 1,
              thickness: 1,
              color: theme.colorScheme.outlineVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Sag kenardaki harf cubugu. Dokunulan ya da parmakla uzerinden gecilen
/// harfe atlanir; surukleme sirasinda secili harf buyuk gosterilir.
class _LetterIndexRail extends StatefulWidget {
  const _LetterIndexRail({
    super.key,
    required this.letters,
    required this.onSelected,
  });

  final List<String> letters;
  final ValueChanged<String> onSelected;

  @override
  State<_LetterIndexRail> createState() => _LetterIndexRailState();
}

class _LetterIndexRailState extends State<_LetterIndexRail> {
  String? _active;

  void _select(double dy, double height) {
    final letters = widget.letters;
    final slot = height / letters.length;
    final index = (dy / slot).floor().clamp(0, letters.length - 1);
    final letter = letters[index];
    if (letter == _active) return;
    setState(() => _active = letter);
    HapticFeedback.selectionClick();
    widget.onSelected(letter);
  }

  void _release() => setState(() => _active = null);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Harfler ekranin ortasinda, harf basina en cok 20 px yer kaplar.
        final slot = (constraints.maxHeight / widget.letters.length).clamp(
          0.0,
          20.0,
        );
        final height = slot * widget.letters.length;
        final active = _active;
        return SizedBox(
          width: 28,
          child: Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) =>
                      _select(details.localPosition.dy, height),
                  onTapUp: (_) => _release(),
                  onTapCancel: _release,
                  onVerticalDragStart: (details) =>
                      _select(details.localPosition.dy, height),
                  onVerticalDragUpdate: (details) =>
                      _select(details.localPosition.dy, height),
                  onVerticalDragEnd: (_) => _release(),
                  onVerticalDragCancel: _release,
                  child: SizedBox(
                    width: 28,
                    height: height,
                    child: Column(
                      children: [
                        for (final letter in widget.letters)
                          SizedBox(
                            height: slot,
                            child: Center(
                              child: Text(
                                letter,
                                key: ValueKey('contacts-index-$letter'),
                                textScaler: TextScaler.noScaling,
                                style: TextStyle(
                                  fontSize: (slot * .62).clamp(8.0, 12.0),
                                  height: 1,
                                  fontWeight: letter == active
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (active != null)
                  PositionedDirectional(
                    end: 40,
                    top: (widget.letters.indexOf(active) + .5) * slot - 28,
                    child: IgnorePointer(
                      child: Container(
                        width: 56,
                        height: 56,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          active,
                          style: TextStyle(
                            color: theme.colorScheme.onPrimary,
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
