import 'package:flutter/material.dart';

import '../../chat/chat_info_service.dart';
import '../../chat/message_search.dart';
import '../../chat/private_chat_control.dart';
import '../../l10n/l10n.dart';
import '../../storage/storage_entities.dart';
import '../../widgets/azure_backdrop.dart';
import '../../widgets/local_image_view.dart';
import '../../widgets/local_video_thumbnail.dart';

enum SharedContentSection {
  search(Icons.search),
  media(Icons.image_outlined),
  documents(Icons.description_outlined),
  starred(Icons.star_outline);

  const SharedContentSection(this.icon);
  final IconData icon;

  String title(BuildContext context) => switch (this) {
    search => context.l10n.chat_search_in_chat,
    media => context.l10n.media,
    documents => context.l10n.documents,
    starred => context.l10n.starred_messages,
  };
}

class SharedContentEntries extends StatelessWidget {
  const SharedContentEntries({super.key, required this.onSelected});

  final ValueChanged<SharedContentSection>? onSelected;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final section in SharedContentSection.values)
        ListTile(
          key: ValueKey('shared-content-${section.name}'),
          leading: Icon(section.icon),
          title: Text(section.title(context)),
          trailing: const Icon(Icons.chevron_right),
          onTap: onSelected == null ? null : () => onSelected!(section),
        ),
    ],
  );
}

/// Returns the selected message ID; the info route forwards it to its chat.
class SharedContentBrowser extends StatefulWidget {
  const SharedContentBrowser({
    super.key,
    required this.service,
    required this.conversationId,
    required this.section,
    this.closeOnBackground = false,
  });

  final ChatInfoService service;
  final String conversationId;
  final SharedContentSection section;
  final bool closeOnBackground;

  @override
  State<SharedContentBrowser> createState() => _SharedContentBrowserState();
}

class _SharedContentBrowserState extends State<SharedContentBrowser>
    with WidgetsBindingObserver {
  late Stream<List<MessageEntity>> _messages;
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _messages = _stream();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (widget.closeOnBackground &&
        state != AppLifecycleState.resumed &&
        ModalRoute.of(context)?.isCurrent == true)
      Navigator.pop(context);
  }

  Stream<List<MessageEntity>> _stream() => switch (widget.section) {
    SharedContentSection.search =>
      _query.isEmpty
          ? Stream.value(const <MessageEntity>[])
          : widget.service.search(widget.conversationId, _query),
    SharedContentSection.media => widget.service.watchMedia(
      widget.conversationId,
    ),
    SharedContentSection.documents => widget.service.watchDocuments(
      widget.conversationId,
    ),
    SharedContentSection.starred => widget.service.watchStarred(
      widget.conversationId,
    ),
  };

  void _search(String value) {
    final query = value.trim();
    if (query == _query) return;
    setState(() {
      _query = query;
      _messages = _stream();
    });
  }

  @override
  Widget build(BuildContext context) => AzureBackdrop(
    child: Scaffold(
      appBar: AppBar(title: Text(widget.section.title(context))),
      body: Column(
        children: [
          if (widget.section == SharedContentSection.search)
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                autofocus: true,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: context.l10n.chat_info_search_placeholder,
                ),
                onChanged: _search,
              ),
            ),
          Expanded(
            child: StreamBuilder<List<MessageEntity>>(
              // Do not retain results from the previous search while waiting.
              key: ValueKey(_query),
              stream: _messages,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text(context.l10n.storage_load_failed));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                // Filter before metadata parsing or constructing image providers.
                // Older services may still emit view-once and hidden rows.
                final messages = (snapshot.data ?? const <MessageEntity>[])
                    .where(_canBrowse)
                    .toList(growable: false);
                if (messages.isEmpty) {
                  return Center(child: Text(context.l10n.no_records));
                }
                if (widget.section == SharedContentSection.media) {
                  return GridView.builder(
                    padding: const EdgeInsets.all(4),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 180,
                          crossAxisSpacing: 4,
                          mainAxisSpacing: 4,
                        ),
                    itemCount: messages.length,
                    itemBuilder: (context, index) =>
                        _mediaTile(messages[index]),
                  );
                }
                return ListView.builder(
                  itemCount: messages.length,
                  itemBuilder: (context, index) =>
                      _messageTile(messages[index]),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );

  bool _canBrowse(MessageEntity message) =>
      !message.isViewOnce &&
      message.conversationId == widget.conversationId &&
      message.contentType != StorageMessageContentType.deleted &&
      message.contentType != StorageMessageContentType.system &&
      !isPrivateChatControl(message.content) &&
      (message.expiresAt == null ||
          message.expiresAt! > DateTime.now().millisecondsSinceEpoch) &&
      (widget.section != SharedContentSection.search ||
          (_query.isNotEmpty &&
              _searchText(
                message,
              ).toLowerCase().contains(_query.toLowerCase())));

  String _searchText(MessageEntity message) => messageSearchText(
    content: message.content,
    contentType: message.contentType.name,
    isViewOnce: message.isViewOnce,
    caption: message.caption,
  ).trim();

  void _focus(MessageEntity message) => Navigator.pop(context, message.id);

  Widget _mediaTile(MessageEntity message) {
    final attachment = _Attachment(message.content);
    final isImage =
        message.contentType == StorageMessageContentType.image ||
        attachment.mimeType.startsWith('image/');
    final isVideo = attachment.mimeType.startsWith('video/');
    Widget fallback() => ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          message.isMediaPreviewDeferred
              ? Icons.insert_drive_file_outlined
              : isImage
              ? Icons.broken_image_outlined
              : isVideo
              ? Icons.videocam_outlined
              : Icons.audiotrack_outlined,
          size: 32,
        ),
      ),
    );
    return Semantics(
      label: _label(message),
      button: true,
      child: Material(
        key: ValueKey('chat-info-message-${message.id}'),
        child: InkWell(
          onTap: () => _focus(message),
          child: message.isMediaPreviewDeferred
              ? fallback()
              : isImage && attachment.path.isNotEmpty
              ? LocalImageView(
                  path: attachment.path,
                  maxDecodeSize: 384,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => fallback(),
                )
              : isVideo
              ? LocalVideoThumbnail(
                  path: attachment.path,
                  isViewOnce: message.isViewOnce,
                  fallback: fallback(),
                )
              : fallback(),
        ),
      ),
    );
  }

  Widget _messageTile(MessageEntity message) => ListTile(
    key: ValueKey('chat-info-message-${message.id}'),
    leading: Icon(switch (message.contentType) {
      StorageMessageContentType.image => Icons.image_outlined,
      StorageMessageContentType.file => Icons.description_outlined,
      StorageMessageContentType.voiceNote => Icons.mic_outlined,
      StorageMessageContentType.poll => Icons.poll_outlined,
      _ => Icons.chat_bubble_outline,
    }),
    title: Text(
      widget.section == SharedContentSection.search
          ? _searchText(message)
          : _label(message),
      maxLines: widget.section == SharedContentSection.search ? null : 2,
      overflow: widget.section == SharedContentSection.search
          ? TextOverflow.clip
          : TextOverflow.ellipsis,
    ),
    subtitle: Text(
      MaterialLocalizations.of(context).formatMediumDate(
        DateTime.fromMillisecondsSinceEpoch(message.timestamp).toLocal(),
      ),
    ),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => _focus(message),
  );

  String _label(MessageEntity message) => switch (message.contentType) {
    StorageMessageContentType.image || StorageMessageContentType.file =>
      _Attachment(message.content).name.isNotEmpty
          ? _Attachment(message.content).name
          : message.contentType == StorageMessageContentType.image
          ? context.l10n.photos
          : context.l10n.file,
    StorageMessageContentType.voiceNote => context.l10n.voice_message,
    StorageMessageContentType.poll => context.l10n.poll,
    _ => message.content,
  };
}

class _Attachment {
  _Attachment(String content) : _parts = content.split('|');

  final List<String> _parts;
  String get name => _parts.first.replaceAll('\\', '/').split('/').last.trim();
  String get mimeType => (_parts.elementAtOrNull(1) ?? '').trim().toLowerCase();
  String get path => (_parts.elementAtOrNull(3) ?? '').trim();
}
