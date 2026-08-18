part of 'chat_screen.dart';

class _ChatSearchBar extends StatelessWidget {
  const _ChatSearchBar({
    required this.controller,
    required this.resultCount,
    required this.currentIndex,
    required this.onChanged,
    required this.onPrevious,
    required this.onNext,
    required this.onClose,
  });

  final TextEditingController controller;
  final int resultCount;
  final int currentIndex;
  final ValueChanged<String> onChanged;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface.withValues(alpha: .92),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('chat-search-field'),
              controller: controller,
              autofocus: true,
              onChanged: onChanged,
              decoration: InputDecoration(
                hintText: context.l10n.chat_search_in_chat,
                prefixIcon: const Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 46,
            child: Text(
              resultCount == 0 ? '0 / 0' : '${currentIndex + 1} / $resultCount',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
          IconButton(
            tooltip: context.l10n.chat_previous_result,
            onPressed: resultCount == 0 ? null : onPrevious,
            icon: const Icon(Icons.keyboard_arrow_up),
          ),
          IconButton(
            tooltip: context.l10n.chat_next_result,
            onPressed: resultCount == 0 ? null : onNext,
            icon: const Icon(Icons.keyboard_arrow_down),
          ),
          IconButton(
            tooltip: context.l10n.action_close,
            onPressed: onClose,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    ),
  );
}

class _EncryptionInfoPill extends StatelessWidget {
  const _EncryptionInfoPill({this.empty = false});

  final bool empty;

  @override
  Widget build(BuildContext context) => Semantics(
    label: context.l10n.chat_encryption_notice,
    child: AzureGlassPanel(
      radius: 100,
      padding: EdgeInsets.symmetric(
        horizontal: empty ? 18 : 12,
        vertical: empty ? 12 : 8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline,
                size: empty ? 18 : 14,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  context.l10n.chat_encryption_notice,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ],
          ),
          if (empty) ...[
            const SizedBox(height: 6),
            Text(
              context.l10n.chat_empty_secure,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class _ChatDateSeparator extends StatelessWidget {
  const _ChatDateSeparator(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Center(
      child: AzureGlassPanel(
        radius: 100,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    ),
  );
}

class _PinnedMessageBanner extends StatelessWidget {
  const _PinnedMessageBanner({
    required this.message,
    required this.canUnpin,
    required this.onTap,
    required this.onUnpin,
  });

  final LocalMessage message;
  final bool canUnpin;
  final VoidCallback onTap;
  final VoidCallback onUnpin;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface.withValues(alpha: .94),
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 8, 8, 8),
        child: Row(
          children: [
            Icon(
              Icons.push_pin,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.chat_pinned_message,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
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
            ),
            if (canUnpin)
              IconButton(
                tooltip: context.l10n.unpin,
                onPressed: onUnpin,
                icon: const Icon(Icons.close, size: 19),
              ),
          ],
        ),
      ),
    ),
  );
}

class _SystemMessageBanner extends StatelessWidget {
  const _SystemMessageBanner(this.message);

  final LocalMessage message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 7),
    child: Center(
      child: AzureGlassPanel(
        radius: 14,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.info_outline,
              size: 15,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                message.previewText,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ReplyComposerPreview extends StatelessWidget {
  const _ReplyComposerPreview({
    required this.message,
    required this.sender,
    required this.onClose,
  });

  final LocalMessage message;
  final String sender;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
    child: AzureGlassPanel(
      radius: 16,
      padding: const EdgeInsetsDirectional.fromSTEB(12, 7, 4, 7),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sender,
                  maxLines: 1,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
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
          ),
          IconButton(
            tooltip: context.l10n.cancel,
            onPressed: onClose,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    ),
  );
}

class _ChatAttachmentTray extends StatelessWidget {
  const _ChatAttachmentTray({
    required this.onCamera,
    required this.onGallery,
    required this.onFile,
    required this.onPoll,
  });

  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onFile;
  final VoidCallback onPoll;

  @override
  Widget build(BuildContext context) => Semantics(
    label: context.l10n.chat_attachment_options,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 2),
      child: AzureGlassPanel(
        radius: 20,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _AttachmentAction(
              icon: Icons.photo_camera_outlined,
              label: context.l10n.camera,
              color: Theme.of(context).colorScheme.primary,
              onTap: onCamera,
            ),
            _AttachmentAction(
              icon: Icons.image_outlined,
              label: context.l10n.gallery,
              color: const Color(0xFF2E7D32),
              onTap: onGallery,
            ),
            _AttachmentAction(
              icon: Icons.insert_drive_file_outlined,
              label: context.l10n.file,
              color: const Color(0xFFEF8C00),
              onTap: onFile,
            ),
            _AttachmentAction(
              icon: Icons.poll_outlined,
              label: context.l10n.poll,
              color: const Color(0xFF8E44AD),
              onTap: onPoll,
            ),
          ],
        ),
      ),
    ),
  );
}

class _AttachmentAction extends StatelessWidget {
  const _AttachmentAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkResponse(
    onTap: onTap,
    radius: 34,
    child: SizedBox(
      width: 68,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: .14),
            foregroundColor: color,
            child: Icon(icon),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    ),
  );
}

class _ChatComposer extends StatefulWidget {
  const _ChatComposer({
    required this.controller,
    required this.onChanged,
    required this.onAttach,
    required this.onRecord,
    required this.onSend,
    required this.readOnly,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onAttach;
  final VoidCallback onRecord;
  final ValueChanged<bool> onSend;
  final bool readOnly;

  @override
  State<_ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<_ChatComposer> {
  bool _viewOnce = false;

  @override
  Widget build(BuildContext context) {
    if (widget.readOnly) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
          child: AzureGlassPanel(
            radius: 20,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.campaign_outlined, size: 19),
                const SizedBox(width: 8),
                Flexible(child: Text(context.l10n.chat_admins_only)),
              ],
            ),
          ),
        ),
      );
    }
    final hasText = widget.controller.text.trim().isNotEmpty;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 5, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: AzureGlassPanel(
                key: const ValueKey('chat-composer-input-surface'),
                radius: 26,
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 52),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Semantics(
                        label: context.l10n.attachment,
                        button: true,
                        excludeSemantics: true,
                        child: IconButton(
                          tooltip: context.l10n.attachment,
                          onPressed: widget.onAttach,
                          icon: const Icon(Icons.attach_file),
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('chat-message-composer'),
                          controller: widget.controller,
                          minLines: 1,
                          maxLines: 4,
                          maxLength: 10000,
                          buildCounter:
                              (
                                _, {
                                required currentLength,
                                required isFocused,
                                maxLength,
                              }) => null,
                          onChanged: (value) {
                            widget.onChanged(value);
                            setState(() {});
                          },
                          keyboardType: TextInputType.multiline,
                          textCapitalization: TextCapitalization.sentences,
                          textInputAction: TextInputAction.newline,
                          decoration: InputDecoration(
                            hintText: context.l10n.chat_message_hint,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 14,
                            ),
                          ),
                        ),
                      ),
                      Semantics(
                        label: context.l10n.view_once,
                        button: true,
                        toggled: _viewOnce,
                        excludeSemantics: true,
                        child: Tooltip(
                          message: context.l10n.view_once,
                          child: InkResponse(
                            key: const ValueKey('chat-view-once-action'),
                            onTap: () => setState(() => _viewOnce = !_viewOnce),
                            radius: 24,
                            child: SizedBox.square(
                              dimension: 48,
                              child: Center(
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  width: 34,
                                  height: 34,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _viewOnce
                                        ? Theme.of(context).colorScheme.primary
                                              .withValues(alpha: .16)
                                        : Colors.transparent,
                                    border: Border.all(
                                      width: 1.4,
                                      color: _viewOnce
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.primary
                                          : Theme.of(
                                              context,
                                            ).colorScheme.outlineVariant,
                                    ),
                                  ),
                                  child: Text(
                                    '1',
                                    style: TextStyle(
                                      color: _viewOnce
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.primary
                                          : Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox.square(
              dimension: 48,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: hasText
                    ? Semantics(
                        key: const ValueKey('chat-send-action'),
                        label: context.l10n.send,
                        button: true,
                        excludeSemantics: true,
                        child: IconButton.filled(
                          key: const ValueKey('chat-send-button'),
                          tooltip: context.l10n.send,
                          onPressed: () {
                            final choice = _viewOnce;
                            setState(() => _viewOnce = false);
                            widget.onSend(choice);
                          },
                          icon: const Icon(Icons.send, size: 20),
                        ),
                      )
                    : Semantics(
                        key: const ValueKey('chat-record-action'),
                        label: context.l10n.record_voice_message,
                        button: true,
                        excludeSemantics: true,
                        child: IconButton.filledTonal(
                          key: const ValueKey('chat-record-button'),
                          tooltip: context.l10n.record_voice_message,
                          onPressed: widget.onRecord,
                          icon: const Icon(Icons.mic_none),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScrollToBottomAction extends StatelessWidget {
  const _ScrollToBottomAction({
    required this.unseenCount,
    required this.onPressed,
  });

  final int unseenCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    label: context.l10n.chat_scroll_bottom,
    button: true,
    child: Badge(
      isLabelVisible: unseenCount > 0,
      label: Text(unseenCount > 99 ? '99+' : '$unseenCount'),
      child: FloatingActionButton.small(
        heroTag: 'chat-scroll-bottom',
        tooltip: context.l10n.chat_scroll_bottom,
        onPressed: onPressed,
        child: const Icon(Icons.keyboard_arrow_down),
      ),
    ),
  );
}

class _ChatShimmerList extends StatefulWidget {
  const _ChatShimmerList();

  @override
  State<_ChatShimmerList> createState() => _ChatShimmerListState();
}

class _ChatShimmerListState extends State<_ChatShimmerList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) => ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: 6,
      itemBuilder: (context, index) => Align(
        alignment: index.isEven ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: index % 3 == 0 ? 230 : 170,
          height: index % 2 == 0 ? 64 : 50,
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withValues(
              alpha: .18 + (_controller.value * .12),
            ),
            borderRadius: BorderRadiusDirectional.only(
              topStart: const Radius.circular(20),
              topEnd: const Radius.circular(20),
              bottomStart: Radius.circular(index.isEven ? 20 : 4),
              bottomEnd: Radius.circular(index.isEven ? 4 : 20),
            ),
          ),
        ),
      ),
    ),
  );
}
