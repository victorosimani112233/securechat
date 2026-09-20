import 'package:flutter/material.dart';

import '../../chat/chat_info_service.dart';
import '../../core/models.dart';
import '../../l10n/l10n.dart';
import '../../widgets/azure_options.dart';
import '../../settings/settings_service.dart';
import '../../widgets/notification_sound_picker.dart';
import '../../widgets/text_controller_scope.dart';
import '../../services/app_container.dart';
import '../../storage/storage_entities.dart';
import '../../widgets/avatar.dart';
import '../../widgets/azure_backdrop.dart';
import '../../widgets/chat_lock_dialog.dart';

enum _InfoTab { main, search, starred, media, documents }

class ChatInfoResult {
  const ChatInfoResult.focusMessage(this.messageId) : lockEnabled = false;
  const ChatInfoResult.lockEnabled() : messageId = null, lockEnabled = true;

  final String? messageId;
  final bool lockEnabled;
}

class ChatInfoScreen extends StatefulWidget {
  const ChatInfoScreen({super.key});
  @override
  State<ChatInfoScreen> createState() => _ChatInfoScreenState();
}

class _ChatInfoScreenState extends State<ChatInfoScreen> {
  var _tab = _InfoTab.main;
  var _query = '';
  var _changingLock = false;

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context)?.settings.arguments as Conversation?;
    final service = AppContainerScope.of(context).chatInfoRuntime?.service;
    if (route == null || service == null) {
      return Scaffold(body: Center(child: Text(context.l10n.chat_not_found)));
    }
    return StreamBuilder<ConversationEntity?>(
      stream: service.watchConversation(route.id),
      builder: (context, snapshot) {
        final conversation = snapshot.data;
        if (conversation == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return AzureBackdrop(
          child: Scaffold(
            appBar: AppBar(
              leading: BackButton(
                onPressed: _tab == _InfoTab.main
                    ? null
                    : () => setState(() {
                        _tab = _InfoTab.main;
                        _query = '';
                      }),
              ),
              title: Text(_title(context)),
            ),
            body: _body(service, conversation),
          ),
        );
      },
    );
  }

  String _title(BuildContext context) => switch (_tab) {
    _InfoTab.main => context.l10n.contact_info,
    _InfoTab.search => context.l10n.chat_search_in_chat,
    _InfoTab.starred => context.l10n.starred_messages,
    _InfoTab.media => context.l10n.media,
    _InfoTab.documents => context.l10n.documents,
  };

  Widget _body(ChatInfoService service, ConversationEntity conversation) {
    return switch (_tab) {
      _InfoTab.main => _main(service, conversation),
      _InfoTab.search => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: context.l10n.chat_info_search_placeholder,
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: _messageList(
              _query.isEmpty
                  ? const Stream.empty()
                  : service.search(conversation.id, _query),
            ),
          ),
        ],
      ),
      _InfoTab.starred => _messageList(service.watchStarred(conversation.id)),
      _InfoTab.media => _messageList(service.watchMedia(conversation.id)),
      _InfoTab.documents => _messageList(
        service.watchDocuments(conversation.id),
      ),
    };
  }

  Widget _main(ChatInfoService service, ConversationEntity c) => ListView(
    children: [
      Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            GeneratedAvatar(name: c.peerName, size: 96, isGroup: c.isGroup),
            const SizedBox(height: 12),
            Text(c.peerName, style: Theme.of(context).textTheme.headlineSmall),
            Text(c.peerPhone),
          ],
        ),
      ),
      _tile(
        Icons.search,
        context.l10n.chat_search_in_chat,
        () => setState(() => _tab = _InfoTab.search),
      ),
      _tile(
        Icons.image_outlined,
        context.l10n.media,
        () => setState(() => _tab = _InfoTab.media),
      ),
      _tile(
        Icons.description_outlined,
        context.l10n.documents,
        () => setState(() => _tab = _InfoTab.documents),
      ),
      _tile(
        Icons.star_outline,
        context.l10n.starred_messages,
        () => setState(() => _tab = _InfoTab.starred),
      ),
      const Divider(),
      ListTile(
        leading: const Icon(Icons.schedule),
        title: Text(context.l10n.disappearing_messages),
        subtitle: Text(_duration(context, c.disappearingDuration)),
        onTap: () => _timerDialog(service, c),
      ),
      ListTile(
        leading: const Icon(Icons.note_outlined),
        title: Text(context.l10n.contact_note),
        subtitle: Text(
          c.contactNote?.isNotEmpty == true
              ? c.contactNote!
              : context.l10n.tap_to_add_note,
        ),
        onTap: () => _noteDialog(service, c),
      ),
      SwitchListTile(
        secondary: const Icon(Icons.notifications_off_outlined),
        title: Text(context.l10n.mute),
        value: c.isMuted,
        onChanged: (value) => service.setMuted(c.id, value),
      ),
      SwitchListTile(
        secondary: const Icon(Icons.lock_outline),
        title: Text(context.l10n.chat_lock),
        subtitle: Text(context.l10n.chat_lock_desc),
        value: c.isLocked,
        onChanged: _changingLock
            ? null
            : (value) => _setLocked(service, c, value),
      ),
      // Sohbete ozel ses. Susturulmus bir sohbette anlamsiz oldugu icin
      // satir orada gizleniyor: susturma daha guclu bir karar ve ikisini
      // ayni anda gostermek celiskili goruntu veriyor.
      if (!c.isMuted)
        ListTile(
          leading: const Icon(Icons.music_note_outlined),
          title: Text(context.l10n.settings_notification_sound),
          subtitle: Text(
            c.customNotificationUri == null
                ? context.l10n.sound_inherit
                : soundName(
                    context,
                    NotificationSoundPreference.fromStorage(
                      c.customNotificationUri!,
                    ),
                  ),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _soundSheet(service, c),
        ),
    ],
  );

  /// Sohbete ozel bildirim sesi secimi.
  ///
  /// Uygulama genelindeki secimle AYNI sayfa kullaniliyor; tek farki
  /// "uygulama ayarini kullan" secenegi. Ayri yazilsalardi listeler zamanla
  /// ayrisirdi.
  Future<void> _soundSheet(ChatInfoService service, ConversationEntity c) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) => NotificationSoundPicker(
          allowInherit: true,
          selected: c.customNotificationUri == null
              ? null
              : NotificationSoundPreference.fromStorage(
                  c.customNotificationUri!,
                ),
          onSelected: (value) {
            service.setNotificationSound(c.id, value?.name);
            Navigator.pop(sheetContext);
          },
        ),
      );

  Widget _tile(IconData icon, String title, VoidCallback onTap) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );

  Widget _messageList(
    Stream<List<MessageEntity>> stream,
  ) => StreamBuilder<List<MessageEntity>>(
    stream: stream,
    builder: (context, snapshot) {
      final messages = snapshot.data ?? const [];
      if (messages.isEmpty) return Center(child: Text(context.l10n.no_records));
      return ListView.builder(
        itemCount: messages.length,
        itemBuilder: (_, index) {
          final message = messages[index];
          return ListTile(
            key: ValueKey('chat-info-message-${message.id}'),
            leading: Icon(switch (message.contentType) {
              StorageMessageContentType.image => Icons.image_outlined,
              StorageMessageContentType.file => Icons.description_outlined,
              _ => Icons.chat_bubble_outline,
            }),
            title: Text(
              message.content,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              DateTime.fromMillisecondsSinceEpoch(
                message.timestamp,
              ).toLocal().toString(),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () =>
                Navigator.pop(context, ChatInfoResult.focusMessage(message.id)),
          );
        },
      );
    },
  );

  Future<void> _noteDialog(
    ChatInfoService service,
    ConversationEntity c,
  ) async {
    final note = await showDialog<String>(
      context: context,
      // Controller dialog'un yasam dongusune ait; cikis animasyonu
      // surerken dispose edilmemeli (bkz TextControllerScope).
      builder: (context) => TextControllerScope(
        initialText: c.contactNote ?? '',
        builder: (context, controller) => AlertDialog(
          title: Text(context.l10n.add_contact_note),
          content: TextField(controller: controller, maxLines: 5),
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
      ),
    );
    if (note != null) await service.updateNote(c.id, note);
  }

  Future<void> _setLocked(
    ChatInfoService service,
    ConversationEntity conversation,
    bool locked,
  ) async {
    final runtime = AppContainerScope.of(context).chatAccessRuntime;
    final credentials = runtime.credentials;
    if (credentials == null) {
      await service.setLocked(conversation.id, locked);
      return;
    }
    setState(() => _changingLock = true);
    try {
      if (locked) {
        final password = await showCreateChatPasswordDialog(context);
        if (password == null) return;
        await credentials.setPassword(conversation.id, password);
        try {
          await service.setLocked(conversation.id, true);
        } catch (_) {
          await credentials.clear(conversation.id);
          rethrow;
        }
        if (mounted) {
          Navigator.pop(context, const ChatInfoResult.lockEnabled());
        }
        return;
      }

      final hasPassword = await credentials.hasCredential(conversation.id);
      final authorized = hasPassword
          ? await showVerifyChatPasswordDialog(
              context,
              chatName: conversation.peerName,
              verify: (password) =>
                  credentials.verifyPassword(conversation.id, password),
            )
          : await runtime.service.authorize(_asConversation(conversation));
      if (!authorized) return;
      await service.setLocked(conversation.id, false);
      await credentials.clear(conversation.id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.chat_lock_update_failed)),
        );
      }
    } finally {
      if (mounted) setState(() => _changingLock = false);
    }
  }

  static Conversation _asConversation(ConversationEntity entity) =>
      Conversation(
        id: entity.id,
        peerId: entity.peerId,
        peerName: entity.peerName,
        peerPhone: entity.peerPhone,
        isGroup: entity.isGroup,
        isLocked: entity.isLocked,
        groupMembers: entity.groupMembers?.split(',') ?? const [],
        groupAdmins: entity.groupAdmins?.split(',') ?? const [],
      );

  Future<void> _timerDialog(
    ChatInfoService service,
    ConversationEntity c,
  ) async {
    final options = <Duration>[
      Duration.zero,
      const Duration(hours: 1),
      const Duration(days: 1),
      const Duration(days: 7),
      const Duration(days: 30),
    ];
    // Secili sure satirda isaretlensin; oncesinde hicbir secenek secili
    // gorunmuyordu ve kullanici mevcut ayarini goremiyordu.
    final current = Duration(milliseconds: c.disappearingDuration);
    final value = await showDialog<Duration>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(context.l10n.disappearing_messages),
        contentPadding: const EdgeInsets.only(bottom: 12),
        children: [
          for (final option in options)
            AzureOptionTile(
              selected: option == current,
              icon: option == Duration.zero
                  ? Icons.timer_off_outlined
                  : Icons.timer_outlined,
              title: _duration(context, option.inMilliseconds),
              onTap: () => Navigator.pop(context, option),
            ),
        ],
      ),
    );
    if (value != null) await service.setDisappearingTimer(c, value);
  }

  static String _duration(BuildContext context, int milliseconds) =>
      switch (Duration(milliseconds: milliseconds)) {
        Duration(inMilliseconds: 0) => context.l10n.off,
        Duration(inHours: 1) => context.l10n.hours(1),
        Duration(inDays: 1) => context.l10n.days(1),
        Duration(inDays: 7) => context.l10n.days(7),
        Duration(inDays: 30) => context.l10n.days(30),
        final value => context.l10n.hours(value.inHours),
      };
}
