part of 'chat_screen.dart';

class _MediaMessageContent extends StatelessWidget {
  const _MediaMessageContent({required this.message, required this.outgoing});

  final LocalMessage message;
  final bool outgoing;

  @override
  Widget build(BuildContext context) {
    final foreground = outgoing
        ? Theme.of(context).colorScheme.onPrimary
        : Theme.of(context).colorScheme.onSurface;
    final consumed =
        message.isViewOnce && (message.isOutgoing || message.isViewed);
    if (message.isViewOnce) {
      return SizedBox(
        width: 210,
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: foreground.withValues(alpha: 0.12),
              child: Text('1', style: TextStyle(color: foreground)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    consumed
                        ? context.l10n.opened
                        : context.l10n.view_once_photo,
                    style: TextStyle(color: foreground),
                  ),
                  Text(
                    consumed
                        ? context.l10n.media_no_longer_available
                        : context.l10n.tap_to_open,
                    style: TextStyle(
                      color: foreground.withValues(alpha: 0.65),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final path = message.filePath;
    final isImage = message.fileMimeType?.startsWith('image/') ?? false;
    return SizedBox(
      width: 240,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isImage && path != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(
                File(path),
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            )
          else
            Row(
              children: [
                Icon(Icons.insert_drive_file, color: foreground),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message.fileName ?? context.l10n.file,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: foreground),
                  ),
                ),
              ],
            ),
          if (message.caption?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Text(message.caption!.trim(), style: TextStyle(color: foreground)),
          ],
        ],
      ),
    );
  }
}

class _PollMessageContent extends StatelessWidget {
  const _PollMessageContent({required this.message, required this.onVote});

  final LocalMessage message;
  final ValueChanged<int> onVote;

  @override
  Widget build(BuildContext context) {
    PollData poll;
    try {
      poll = PollData.parse(message.content);
    } catch (_) {
      return Text(context.l10n.poll_load_failed);
    }
    final userId = AppContainerScope.of(context).session.userId ?? '';
    final foreground = message.isOutgoing
        ? Theme.of(context).colorScheme.onPrimary
        : Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      width: 260,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.poll, color: Colors.purple, size: 17),
              const SizedBox(width: 6),
              Text(
                context.l10n.poll,
                style: const TextStyle(
                  color: Colors.purple,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            poll.question,
            style: TextStyle(color: foreground, fontWeight: FontWeight.w600),
          ),
          Text(
            poll.singleChoice
                ? context.l10n.single_choice
                : context.l10n.multiple_choice,
            style: TextStyle(
              color: foreground.withValues(alpha: 0.6),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 6),
          for (var index = 0; index < poll.options.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: InkWell(
                key: Key('poll-option-$index'),
                onTap: () => onVote(index),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: (poll.votes[index]?.contains(userId) ?? false)
                          ? Colors.lightBlue
                          : foreground.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        poll.singleChoice
                            ? (poll.votes[index]?.contains(userId) ?? false)
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked
                            : (poll.votes[index]?.contains(userId) ?? false)
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                        size: 18,
                        color: foreground,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          poll.options[index],
                          style: TextStyle(color: foreground),
                        ),
                      ),
                      if ((poll.votes[index]?.length ?? 0) > 0)
                        Text(
                          '${poll.votes[index]!.length}',
                          style: TextStyle(color: foreground),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          Text(
            context.l10n.total_votes(poll.totalVotes),
            style: TextStyle(
              color: foreground.withValues(alpha: 0.6),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageInfoDialog extends StatelessWidget {
  const _MessageInfoDialog({
    required this.message,
    required this.conversation,
    required this.localUserId,
  });

  final LocalMessage message;
  final Conversation conversation;
  final String localUserId;

  @override
  Widget build(BuildContext context) {
    final recipients = conversation.isGroup
        ? conversation.groupMembers
              .where((member) => member != localUserId)
              .toList(growable: false)
        : [conversation.peerName];
    final delivered =
        message.status == MessageStatus.delivered ||
        message.status == MessageStatus.read;
    final read = message.status == MessageStatus.read;
    final localizations = MaterialLocalizations.of(context);
    final sentAt =
        '${localizations.formatFullDate(message.timestamp)} · '
        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(message.timestamp))}';
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.info_outline),
          const SizedBox(width: 8),
          Text(context.l10n.message_info),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.l10n.sent,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 4),
              Text(sentAt),
              const Divider(height: 24),
              _ReceiptSection(
                icon: Icons.done_all,
                title: context.l10n.read,
                active: read,
                recipients: recipients,
              ),
              const Divider(height: 24),
              _ReceiptSection(
                icon: Icons.done_all,
                title: context.l10n.delivered,
                active: delivered,
                recipients: recipients,
              ),
              if (message.status == MessageStatus.failed) ...[
                const Divider(height: 24),
                Text(
                  context.l10n.send_failed_no_plaintext,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.action_close),
        ),
      ],
    );
  }
}

class _ReceiptSection extends StatelessWidget {
  const _ReceiptSection({
    required this.icon,
    required this.title,
    required this.active,
    required this.recipients,
  });

  final IconData icon;
  final String title;
  final bool active;
  final List<String> recipients;

  @override
  Widget build(BuildContext context) {
    final color = active
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (!active || recipients.isEmpty)
          const Text('—')
        else
          for (final recipient in recipients)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  GeneratedAvatar(name: recipient, size: 32),
                  const SizedBox(width: 10),
                  Expanded(child: Text(recipient)),
                ],
              ),
            ),
      ],
    );
  }
}

class _ForwardConversationDialog extends StatefulWidget {
  const _ForwardConversationDialog({required this.conversations});

  final Stream<List<Conversation>> conversations;

  @override
  State<_ForwardConversationDialog> createState() =>
      _ForwardConversationDialogState();
}

class _ForwardConversationDialogState
    extends State<_ForwardConversationDialog> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.forward_to_chat),
      content: SizedBox(
        width: 420,
        height: 440,
        child: Column(
          children: [
            TextField(
              key: const Key('forward-conversation-search'),
              controller: _search,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: context.l10n.conversations_search,
                prefixIcon: const Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: StreamBuilder<List<Conversation>>(
                stream: widget.conversations,
                builder: (context, snapshot) {
                  final query = _search.text.trim().toLowerCase();
                  final conversations = (snapshot.data ?? const [])
                      .where((item) => !item.isArchived)
                      .where(
                        (item) =>
                            query.isEmpty ||
                            item.peerName.toLowerCase().contains(query) ||
                            item.peerPhone.toLowerCase().contains(query),
                      )
                      .toList(growable: false);
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (conversations.isEmpty) {
                    return Center(child: Text(context.l10n.chat_not_found));
                  }
                  return ListView.builder(
                    itemCount: conversations.length,
                    itemBuilder: (context, index) {
                      final conversation = conversations[index];
                      return ListTile(
                        enabled: !conversation.isReadOnly,
                        leading: GeneratedAvatar(
                          name: conversation.peerName,
                          size: 40,
                        ),
                        title: Text(conversation.peerName),
                        subtitle: Text(
                          conversation.isReadOnly
                              ? context.l10n.read_only_chat
                              : conversation.isGroup
                              ? context.l10n.participant_count(
                                  conversation.groupMembers.length,
                                )
                              : conversation.peerPhone,
                        ),
                        trailing: conversation.isLocked
                            ? const Icon(Icons.lock_outline, size: 18)
                            : null,
                        onTap: conversation.isReadOnly
                            ? null
                            : () => Navigator.pop(context, conversation),
                      );
                    },
                  );
                },
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
      ],
    );
  }
}

class _CreatePollDialog extends StatefulWidget {
  const _CreatePollDialog();

  @override
  State<_CreatePollDialog> createState() => _CreatePollDialogState();
}

class _CreatePollDialogState extends State<_CreatePollDialog> {
  final _question = TextEditingController();
  final _options = List.generate(4, (_) => TextEditingController());
  var _optionCount = 2;
  var _singleChoice = true;

  @override
  void dispose() {
    _question.dispose();
    for (final option in _options) {
      option.dispose();
    }
    super.dispose();
  }

  bool get _valid =>
      _question.text.trim().isNotEmpty &&
      _options
              .take(_optionCount)
              .where((item) => item.text.trim().isNotEmpty)
              .length >=
          2;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.poll, color: Colors.purple),
          const SizedBox(width: 8),
          Text(context.l10n.create_poll),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('poll-question'),
              controller: _question,
              maxLength: 500,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: context.l10n.question),
            ),
            for (var index = 0; index < _optionCount; index++)
              TextField(
                key: Key('poll-create-option-$index'),
                controller: _options[index],
                maxLength: 200,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: context.l10n.option_number(index + 1),
                  suffixIcon: _optionCount > 2
                      ? IconButton(
                          tooltip: context.l10n.remove_option,
                          onPressed: () => setState(() {
                            for (
                              var move = index;
                              move < _optionCount - 1;
                              move++
                            ) {
                              _options[move].text = _options[move + 1].text;
                            }
                            _options[_optionCount - 1].clear();
                            _optionCount--;
                          }),
                          icon: const Icon(Icons.close),
                        )
                      : null,
                ),
              ),
            if (_optionCount < 4)
              TextButton.icon(
                onPressed: () => setState(() => _optionCount++),
                icon: const Icon(Icons.add),
                label: Text(context.l10n.add_option),
              ),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: true,
                  label: Text(context.l10n.single_choice),
                ),
                ButtonSegment(
                  value: false,
                  label: Text(context.l10n.multiple_choice),
                ),
              ],
              selected: {_singleChoice},
              onSelectionChanged: (value) =>
                  setState(() => _singleChoice = value.single),
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
          onPressed: !_valid
              ? null
              : () => Navigator.pop(
                  context,
                  PollData(
                    question: _question.text.trim(),
                    options: _options
                        .take(_optionCount)
                        .map((item) => item.text.trim())
                        .where((value) => value.isNotEmpty)
                        .toList(growable: false),
                    singleChoice: _singleChoice,
                  ),
                ),
          child: Text(context.l10n.create_group_action),
        ),
      ],
    );
  }
}
