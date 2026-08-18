import 'package:flutter/material.dart';

import '../../chat/chat_info_service.dart';
import '../../core/models.dart';
import '../../l10n/l10n.dart';
import '../../services/app_container.dart';
import '../../storage/storage_entities.dart';
import '../../widgets/avatar.dart';
import '../../widgets/azure_backdrop.dart';

enum _InfoTab { main, search, starred, media, documents }

class ChatInfoScreen extends StatefulWidget {
  const ChatInfoScreen({super.key});
  @override
  State<ChatInfoScreen> createState() => _ChatInfoScreenState();
}

class _ChatInfoScreenState extends State<ChatInfoScreen> {
  var _tab = _InfoTab.main;
  var _query = '';

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
            GeneratedAvatar(name: c.peerName, size: 96),
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
        value: c.isLocked,
        onChanged: (value) => service.setLocked(c.id, value),
      ),
    ],
  );

  Widget _tile(IconData icon, String title, VoidCallback onTap) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );

  Widget _messageList(Stream<List<MessageEntity>> stream) =>
      StreamBuilder<List<MessageEntity>>(
        stream: stream,
        builder: (context, snapshot) {
          final messages = snapshot.data ?? const [];
          if (messages.isEmpty)
            return Center(child: Text(context.l10n.no_records));
          return ListView.builder(
            itemCount: messages.length,
            itemBuilder: (_, index) {
              final message = messages[index];
              return ListTile(
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
              );
            },
          );
        },
      );

  Future<void> _noteDialog(
    ChatInfoService service,
    ConversationEntity c,
  ) async {
    final controller = TextEditingController(text: c.contactNote);
    final note = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
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
    );
    controller.dispose();
    if (note != null) await service.updateNote(c.id, note);
  }

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
    final value = await showDialog<Duration>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(context.l10n.disappearing_messages),
        children: [
          for (final option in options)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, option),
              child: Text(_duration(context, option.inMilliseconds)),
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
