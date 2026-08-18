part of 'chat_screen.dart';

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.onTap,
    required this.onVote,
    required this.onLongPress,
    this.replyMessage,
    this.replySenderLabel,
    this.highlighted = false,
    this.searchQuery = '',
  });

  final LocalMessage message;
  final LocalMessage? replyMessage;
  final String? replySenderLabel;
  final bool highlighted;
  final String searchQuery;
  final VoidCallback onTap;
  final ValueChanged<int> onVote;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final outgoing = message.isOutgoing;
    final scheme = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadiusDirectional.only(
        topStart: const Radius.circular(20),
        topEnd: const Radius.circular(20),
        bottomStart: Radius.circular(outgoing ? 20 : 4),
        bottomEnd: Radius.circular(outgoing ? 4 : 20),
      ),
      side: BorderSide(
        color: outgoing
            ? scheme.primary.withValues(alpha: .34)
            : scheme.outlineVariant.withValues(alpha: .48),
      ),
    );
    final reactions = parseReactions(message.reactions);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 380),
      color: highlighted
          ? scheme.primary.withValues(alpha: .14)
          : Colors.transparent,
      padding: EdgeInsetsDirectional.only(
        start: outgoing ? 48 : 4,
        end: outgoing ? 4 : 48,
        top: 2,
        bottom: 2,
      ),
      child: Align(
        alignment: outgoing
            ? AlignmentDirectional.centerEnd
            : AlignmentDirectional.centerStart,
        child: Column(
          crossAxisAlignment: outgoing
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Material(
                color: outgoing
                    ? scheme.primary.withValues(alpha: .19)
                    : scheme.surface.withValues(alpha: .72),
                shape: shape,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap:
                      message.isFileMessage ||
                          (message.isViewOnce &&
                              message.contentType == MessageContentType.text)
                      ? onTap
                      : null,
                  onLongPress: message.isDeleted ? null : onLongPress,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(11, 7, 10, 5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (replyMessage != null)
                          _BubbleReplyPreview(
                            message: replyMessage!,
                            sender: replySenderLabel ?? replyMessage!.senderId,
                          ),
                        if (message.contentType == MessageContentType.poll)
                          _PollMessageContent(message: message, onVote: onVote)
                        else if (message.contentType ==
                            MessageContentType.voiceNote)
                          _VoiceNoteContent(
                            message: message,
                            outgoing: outgoing,
                          )
                        else if (message.isFileMessage)
                          _MediaMessageContent(
                            message: message,
                            outgoing: outgoing,
                          )
                        else if (message.isDeleted)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.block,
                                size: 15,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  message.previewText,
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            ],
                          )
                        else if (message.isViewOnce)
                          _ViewOnceTextContent(message: message)
                        else
                          _HighlightedMessageText(
                            text: message.previewText,
                            query: searchQuery,
                          ),
                        const SizedBox(height: 3),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (message.isEdited) ...[
                              Text(
                                context.l10n.chat_edited,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 4),
                            ],
                            if (message.isStarred) ...[
                              const Icon(
                                Icons.star,
                                size: 13,
                                color: Color(0xFFFFC107),
                              ),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              _time(message.timestamp),
                              style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            if (outgoing) ...[
                              const SizedBox(width: 4),
                              Icon(
                                _statusIcon(message.status),
                                semanticLabel: _statusLabel(context),
                                size: 15,
                                color: message.status == MessageStatus.failed
                                    ? scheme.error
                                    : message.status == MessageStatus.read
                                    ? scheme.primary
                                    : scheme.onSurfaceVariant,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (reactions.isNotEmpty)
              Transform.translate(
                offset: const Offset(0, -3),
                child: Material(
                  color: scheme.surface.withValues(alpha: .94),
                  shape: StadiumBorder(
                    side: BorderSide(color: scheme.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    child: Wrap(
                      spacing: 6,
                      children: [
                        for (final entry in reactions.entries)
                          Text(
                            '${entry.key} ${entry.value.length}',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(BuildContext context) => switch (message.status) {
    MessageStatus.sending => context.l10n.sending,
    MessageStatus.sent => context.l10n.sent,
    MessageStatus.delivered => context.l10n.delivered,
    MessageStatus.read => context.l10n.read,
    MessageStatus.failed => context.l10n.failed,
  };

  static String _time(DateTime time) {
    final local = time.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  static IconData _statusIcon(MessageStatus status) => switch (status) {
    MessageStatus.sending => Icons.schedule,
    MessageStatus.sent => Icons.check,
    MessageStatus.delivered || MessageStatus.read => Icons.done_all,
    MessageStatus.failed => Icons.error_outline,
  };
}

class _BubbleReplyPreview extends StatelessWidget {
  const _BubbleReplyPreview({required this.message, required this.sender});

  final LocalMessage message;
  final String sender;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 5),
    padding: const EdgeInsetsDirectional.fromSTEB(7, 5, 8, 5),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .07),
      borderRadius: BorderRadius.circular(8),
      border: BorderDirectional(
        start: BorderSide(
          width: 3,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          sender,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          message.previewText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}

class _ViewOnceTextContent extends StatelessWidget {
  const _ViewOnceTextContent({required this.message});

  final LocalMessage message;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        message.isViewed || message.isOutgoing
            ? Icons.visibility_off_outlined
            : Icons.looks_one_outlined,
        size: 19,
        color: Theme.of(context).colorScheme.primary,
      ),
      const SizedBox(width: 7),
      Flexible(
        child: Text(
          message.isViewed || message.isOutgoing
              ? context.l10n.media_no_longer_available
              : context.l10n.tap_to_open,
        ),
      ),
    ],
  );
}

class _HighlightedMessageText extends StatelessWidget {
  const _HighlightedMessageText({required this.text, required this.query});

  final String text;
  final String query;

  @override
  Widget build(BuildContext context) {
    final clean = query.trim();
    if (clean.isEmpty) return Text(text);
    final lower = text.toLowerCase();
    final needle = clean.toLowerCase();
    final spans = <InlineSpan>[];
    var cursor = 0;
    while (cursor < text.length) {
      final match = lower.indexOf(needle, cursor);
      if (match < 0) {
        spans.add(TextSpan(text: text.substring(cursor)));
        break;
      }
      if (match > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match)));
      }
      spans.add(
        TextSpan(
          text: text.substring(match, match + needle.length),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSecondary,
            backgroundColor: Theme.of(context).colorScheme.secondary,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      cursor = match + needle.length;
    }
    return Text.rich(TextSpan(children: spans));
  }
}
