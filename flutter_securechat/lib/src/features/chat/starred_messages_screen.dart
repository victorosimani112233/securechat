import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../l10n/l10n.dart';
import '../../services/app_container.dart';
import '../../storage/storage_entities.dart';
import '../../widgets/avatar.dart';
import '../../widgets/azure_backdrop.dart';
import 'chat_screen.dart';

class StarredMessagesScreen extends StatelessWidget {
  const StarredMessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final container = AppContainerScope.of(context);
    final service = container.chatInfoRuntime?.service;
    return AzureBackdrop(
      child: Scaffold(
        appBar: AppBar(title: Text(context.l10n.starred_messages)),
        body: service == null
            ? Center(child: Text(context.l10n.no_records))
            : StreamBuilder<List<Conversation>>(
                stream: container.conversations.watchConversations(),
                builder: (context, chats) => StreamBuilder<List<MessageEntity>>(
                  stream: service.watchAllStarred(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError || chats.hasError)
                      return Center(
                        child: Text(context.l10n.storage_load_failed),
                      );
                    if (!snapshot.hasData || !chats.hasData)
                      return const Center(child: CircularProgressIndicator());
                    final groups = <String, List<LocalMessage>>{};
                    for (final item in snapshot.data!) {
                      if (item.isViewOnce ||
                          item.contentType ==
                              StorageMessageContentType.deleted ||
                          (item.expiresAt != null &&
                              item.expiresAt! <=
                                  DateTime.now().millisecondsSinceEpoch))
                        continue;
                      groups
                          .putIfAbsent(item.conversationId, () => [])
                          .add(LocalMessage.fromJson(item.toJson()));
                    }
                    final conversations = chats.data!
                        .where((chat) => groups.containsKey(chat.id))
                        .toList();
                    if (conversations.isEmpty)
                      return Center(child: Text(context.l10n.no_records));
                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: conversations.length,
                      itemBuilder: (context, index) {
                        final chat = conversations[index];
                        final messages = groups[chat.id]!;
                        if (chat.isLocked)
                          return ListTile(
                            leading: const Icon(Icons.lock_outline),
                            title: Text(chat.peerName),
                            onTap: () => _open(context, chat, starred: true),
                          );
                        return ExpansionTile(
                          key: PageStorageKey('starred-chat-${chat.id}'),
                          initiallyExpanded: true,
                          leading: GeneratedAvatar(
                            name: chat.peerName,
                            isGroup: chat.isGroup,
                            size: 36,
                          ),
                          title: Text(chat.peerName),
                          children: [
                            for (final message in messages)
                              ListTile(
                                key: ValueKey('starred-message-${message.id}'),
                                leading: const Icon(Icons.star_outline),
                                title: Text(
                                  message.previewText,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  MaterialLocalizations.of(
                                    context,
                                  ).formatMediumDate(
                                    message.timestamp.toLocal(),
                                  ),
                                ),
                                onTap: () =>
                                    _open(context, chat, id: message.id),
                              ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
      ),
    );
  }

  void _open(
    BuildContext context,
    Conversation conversation, {
    String? id,
    bool starred = false,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: '/chat', arguments: conversation),
        builder: (_) => ChatScreen(initialMessageId: id, openStarred: starred),
      ),
    );
  }
}
