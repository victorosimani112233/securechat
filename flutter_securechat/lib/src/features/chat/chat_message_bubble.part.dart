part of 'chat_screen.dart';

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.onTap,
    required this.onVote,
    required this.onLongPress,
    this.replyMessage,
    this.senderLabel,
    this.replySenderLabel,
    this.onReplyTap,
    this.highlighted = false,
    this.searchQuery = '',
  });

  final LocalMessage message;
  final LocalMessage? replyMessage;
  final String? senderLabel;
  final String? replySenderLabel;
  final VoidCallback? onReplyTap;
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
                // SAYDAM DEGIL: gorunum aynidir ama renk zemine harmanlanmis
                // halde verilir. Yari saydam birakilinca kayan arka plan
                // deseni mesaj yazisinin altindan geciyordu.
                color: Color.alphaBlend(
                  outgoing
                      ? scheme.primary.withValues(alpha: .19)
                      : scheme.surface.withValues(alpha: .72),
                  AzureTokens.ground(
                    Theme.of(context).brightness == Brightness.dark,
                  ),
                ),
                elevation: 1,
                shadowColor: Colors.black.withValues(alpha: .35),
                surfaceTintColor: Colors.transparent,
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
                        if (senderLabel != null) ...[
                          Text(
                            senderLabel!,
                            key: ValueKey('message-sender-${message.id}'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 3),
                        ],
                        if (replyMessage != null)
                          _BubbleReplyPreview(
                            message: replyMessage!,
                            sender: replySenderLabel ?? replyMessage!.senderId,
                            onTap: onReplyTap,
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
  const _BubbleReplyPreview({
    required this.message,
    required this.sender,
    this.onTap,
  });

  final LocalMessage message;
  final String sender;

  /// Alintiya dokununca kaynak mesaja gidilir. `null` ise alinti pasiftir.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => _wrap(context, _quote(context));

  Widget _wrap(BuildContext context, Widget quote) {
    if (onTap == null) return quote;
    return Semantics(
      button: true,
      label: context.l10n.chat_jump_to_replied_message,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: quote,
      ),
    );
  }

  Widget _quote(BuildContext context) => Container(
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

/// Cevaplamak icin kaydirma: balon sinirli bir mesafe kayar, esik asilinca
/// cevap moduna gecer ve yerine yaylanir.
///
/// Onceki uygulama `Dismissible` idi. `confirmDismiss` her zaman `false`
/// donduruyordu, ancak kullanici balonu birakana kadar EKRANIN SONUNA kadar
/// surukleyebiliyordu: hareketin bir siniri yoktu ve ne kadar kaydirinca
/// tetiklenecegi belli olmuyordu. Burada mesafe [_maxDrag] ile sinirlanir,
/// [_triggerDistance] asildiginda ikon doludur ve birakilinca cevap acilir.
class _SwipeToReply extends StatefulWidget {
  const _SwipeToReply({super.key, required this.child, required this.onReply});

  final Widget child;
  final VoidCallback onReply;

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply>
    with SingleTickerProviderStateMixin {
  /// Balonun kayabilecegi en fazla mesafe.
  static const _maxDrag = 72.0;

  /// Cevabin tetiklenmesi icin gereken mesafe.
  static const _triggerDistance = 52.0;

  late final AnimationController _spring = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  )..addListener(() => setState(() {}));

  double _offset = 0;
  double _releaseOffset = 0;
  bool _armed = false;

  @override
  void dispose() {
    _spring.dispose();
    super.dispose();
  }

  double get _currentOffset => _spring.isAnimating
      ? _releaseOffset * (1 - _spring.value)
      : _offset;

  void _onUpdate(DragUpdateDetails details) {
    final direction = Directionality.of(context) == TextDirection.rtl ? -1 : 1;
    final delta = details.primaryDelta! * direction;
    // Esigi gectikten sonra direnc artar: hareket sinira dogru yavaslar.
    final next = (_offset + delta).clamp(0.0, _maxDrag);
    final armed = next >= _triggerDistance;
    if (armed != _armed) {
      _armed = armed;
      if (armed) HapticFeedback.selectionClick();
    }
    setState(() => _offset = next);
  }

  void _onEnd(DragEndDetails details) {
    final shouldReply = _offset >= _triggerDistance;
    _releaseOffset = _offset;
    _offset = 0;
    _armed = false;
    _spring.forward(from: 0);
    if (shouldReply) widget.onReply();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final offset = _currentOffset;
    final progress = (offset / _triggerDistance).clamp(0.0, 1.0);
    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onHorizontalDragUpdate: _onUpdate,
      onHorizontalDragEnd: _onEnd,
      onHorizontalDragCancel: () {
        _releaseOffset = _offset;
        _offset = 0;
        _armed = false;
        _spring.forward(from: 0);
      },
      child: Stack(
        children: [
          if (offset > 0)
            PositionedDirectional(
              start: 14,
              top: 0,
              bottom: 0,
              child: Center(
                child: Opacity(
                  opacity: progress,
                  child: Transform.scale(
                    scale: .7 + (progress * .3),
                    child: Icon(
                      Icons.reply,
                      size: 20,
                      color: scheme.primary,
                    ),
                  ),
                ),
              ),
            ),
          Transform.translate(
            offset: Offset(
              Directionality.of(context) == TextDirection.rtl
                  ? -offset
                  : offset,
              0,
            ),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
