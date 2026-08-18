import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/models.dart';
import '../../l10n/l10n.dart';
import '../../chat/poll_service.dart';
import '../../chat/message_forwarding_service.dart';
import '../../chat/message_interaction_service.dart';
import '../../domain/send_message_use_case.dart';
import '../../media/call_models.dart';
import '../../media/file_transfer_manager.dart';
import '../../media/media_attachment.dart';
import '../../media/media_message_service.dart';
import '../../media/voice_note_service.dart';
import '../../services/app_container.dart';
import '../../services/conversation_repository.dart';
import '../../services/peer_activity_source.dart';
import '../../widgets/avatar.dart';
import '../../widgets/azure_backdrop.dart';
import '../../widgets/haptics.dart';
import '../calls/call_screen.dart';
import 'media_preview_screen.dart';
import 'media_viewer_screen.dart';

part "chat_message_bubble.part.dart";
part "chat_voice_widgets.part.dart";
part "chat_message_details.part.dart";
part "chat_chrome.part.dart";

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _search = TextEditingController();
  final _messageScroll = ScrollController();
  var _lostSelectionChecked = false;
  var _showSearch = false;
  var _showAttachments = false;
  var _nearBottom = true;
  var _unseenCount = 0;
  var _knownMessageCount = -1;
  var _searchIndex = 0;
  String? _highlightedMessageId;
  List<LocalMessage> _latestMessages = const [];
  final Map<String, GlobalKey> _messageKeys = {};
  Timer? _highlightTimer;
  LocalMessage? _replying;
  AppNotificationRuntime? _notificationRuntime;
  Conversation? _conversation;
  bool _accessGranted = false;
  bool _accessChecking = false;
  bool _markedRead = false;
  final Set<String> _forwardSelection = {};
  Stream<AppPeerActivity>? _peerActivityStream;
  Future<void> Function()? _stopTyping;

  @override
  void initState() {
    super.initState();
    _messageScroll.addListener(_onMessageScroll);
  }

  @override
  void dispose() {
    _notificationRuntime?.coordinator.setActiveConversation(null);
    final stopTyping = _stopTyping;
    if (stopTyping != null) unawaited(stopTyping());
    _highlightTimer?.cancel();
    _messageScroll
      ..removeListener(_onMessageScroll)
      ..dispose();
    _input.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final routeConversation =
        ModalRoute.of(context)?.settings.arguments as Conversation? ??
        const Conversation(
          id: 'peer-ayse',
          peerId: 'peer-ayse',
          peerName: 'Ayse Demir',
          peerPhone: '',
        );
    if (_conversation?.id != routeConversation.id) {
      final container = AppContainerScope.of(context);
      _conversation = routeConversation;
      _peerActivityStream = container.peerActivity?.watch(
        routeConversation.peerId,
      );
      _stopTyping = container.chatInfoRuntime?.activity.stopTyping;
      _accessGranted = !routeConversation.isLocked;
      _accessChecking = routeConversation.isLocked;
      _markedRead = false;
      _knownMessageCount = -1;
      _unseenCount = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (routeConversation.isLocked) {
          _authorizeConversation(routeConversation);
        } else {
          _markRead(routeConversation.id);
        }
      });
    }
    if (_lostSelectionChecked) return;
    _lostSelectionChecked = true;
    final selection = AppContainerScope.of(
      context,
    ).mediaRuntime?.mediaSelection;
    if (selection != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          final recovered = await selection.recoverLostSelection();
          if (mounted && recovered.isNotEmpty) await _previewAndSend(recovered);
        } catch (error) {
          if (mounted) _notice(context, '$error');
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final conversation = _conversation!;
    final container = AppContainerScope.of(context);
    if (!_accessGranted) {
      return Scaffold(
        appBar: AppBar(title: Text(context.l10n.locked_chat)),
        body: Center(
          child: _accessChecking
              ? const CircularProgressIndicator()
              : const Icon(Icons.lock_outline, size: 48),
        ),
      );
    }
    final repo = container.conversations;
    _notificationRuntime = container.notificationRuntime;
    _notificationRuntime?.coordinator.setActiveConversation(conversation.id);
    return AzureBackdrop(
      child: Scaffold(
        appBar: AppBar(
          leading: const BackButton(),
          title: StreamBuilder<AppPeerActivity>(
            stream: _peerActivityStream,
            initialData: const AppPeerActivity(),
            builder: (context, snapshot) => InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => Navigator.pushNamed(
                context,
                conversation.isGroup ? '/group-info' : '/chat-info',
                arguments: conversation,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    GeneratedAvatar(name: conversation.peerName, size: 38),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            conversation.peerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            child: Text(
                              _peerSubtitle(
                                conversation,
                                snapshot.data ?? const AppPeerActivity(),
                              ),
                              key: ValueKey(
                                '${snapshot.data?.isTyping}-'
                                '${snapshot.data?.isOnline}-'
                                '${snapshot.data?.lastSeen}',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: snapshot.data?.isTyping == true
                                        ? Theme.of(context).colorScheme.primary
                                        : snapshot.data?.isOnline == true
                                        ? const Color(0xFF2EAD5B)
                                        : Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            Semantics(
              label: context.l10n.voice_call,
              button: true,
              excludeSemantics: true,
              child: IconButton(
                tooltip: context.l10n.voice_call,
                onPressed: () =>
                    _startCall(context, conversation, CallType.voice),
                icon: const Icon(Icons.call_outlined),
              ),
            ),
            Semantics(
              label: context.l10n.video_call,
              button: true,
              excludeSemantics: true,
              child: IconButton(
                tooltip: context.l10n.video_call,
                onPressed: () =>
                    _startCall(context, conversation, CallType.video),
                icon: const Icon(Icons.videocam_outlined),
              ),
            ),
            PopupMenuButton<String>(
              tooltip: context.l10n.cd_more,
              icon: const Icon(Icons.more_vert),
              onSelected: (value) => _handleMenu(context, conversation, value),
              itemBuilder: (context) {
                final userId = AppContainerScope.of(context).session.userId;
                final isAdmin =
                    conversation.isGroup &&
                    conversation.groupAdmins.contains(userId);
                return [
                  PopupMenuItem(
                    value: 'search',
                    child: Text(context.l10n.chat_search_in_chat),
                  ),
                  PopupMenuItem(
                    value: 'timer',
                    child: Text(context.l10n.disappearing_messages),
                  ),
                  if (conversation.isGroup)
                    PopupMenuItem(
                      value: 'group_info',
                      child: Text(context.l10n.group_info),
                    ),
                  if (!conversation.isGroup)
                    PopupMenuItem(
                      value: 'chat_info',
                      child: Text(context.l10n.view_info),
                    ),
                  PopupMenuItem(value: 'mute', child: Text(context.l10n.mute)),
                  if (!conversation.isGroup || conversation.isExportEnabled)
                    PopupMenuItem(
                      value: 'export',
                      child: Text(context.l10n.chat_export),
                    ),
                  if (isAdmin)
                    PopupMenuItem(
                      value: 'toggle_export',
                      child: Text(
                        conversation.isExportEnabled
                            ? context.l10n.disable_export
                            : context.l10n.enable_export,
                      ),
                    ),
                  if (isAdmin)
                    PopupMenuItem(
                      value: 'export_history',
                      child: Text(context.l10n.export_history),
                    ),
                  PopupMenuItem(
                    value: 'clear',
                    child: Text(context.l10n.clear_chat),
                  ),
                ];
              },
            ),
          ],
        ),
        body: Column(
          children: [
            if (conversation.isReadOnly)
              MaterialBanner(
                content: Text(context.l10n.read_only_announcement),
                actions: const [SizedBox.shrink()],
              ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: _showSearch
                  ? _ChatSearchBar(
                      controller: _search,
                      resultCount: _searchMatches.length,
                      currentIndex: _searchIndex,
                      onChanged: _updateSearch,
                      onPrevious: () => _moveSearch(-1),
                      onNext: () => _moveSearch(1),
                      onClose: _closeSearch,
                    )
                  : const SizedBox(width: double.infinity),
            ),
            Expanded(
              child: StreamBuilder<List<LocalMessage>>(
                stream: repo.watchMessages(conversation.id),
                builder: (context, snapshot) {
                  final allMessages =
                      (snapshot.data ?? const <LocalMessage>[]).toList(
                        growable: false,
                      )..sort((a, b) => a.timestamp.compareTo(b.timestamp));
                  _latestMessages = allMessages;
                  _handleMessageSnapshot(allMessages);
                  if (snapshot.hasData && allMessages.isNotEmpty) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && _accessGranted) {
                        unawaited(_markReadSafely(conversation.id));
                      }
                    });
                  }
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const _ChatShimmerList();
                  }
                  if (allMessages.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: _EncryptionInfoPill(empty: true),
                      ),
                    );
                  }
                  final pinned = allMessages
                      .where((message) => message.isPinned)
                      .lastOrNull;
                  final canUnpin =
                      !conversation.isGroup ||
                      conversation.groupAdmins.contains(
                        container.session.userId,
                      );
                  return Column(
                    children: [
                      if (pinned != null)
                        _PinnedMessageBanner(
                          message: pinned,
                          canUnpin: canUnpin,
                          onTap: () => _scrollToMessage(pinned.id),
                          onUnpin: () => _unpinMessage(pinned),
                        ),
                      Expanded(
                        child: Stack(
                          children: [
                            ListView(
                              key: const ValueKey('chat-message-list'),
                              controller: _messageScroll,
                              padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
                              children: _messageListChildren(
                                context,
                                allMessages,
                              ),
                            ),
                            PositionedDirectional(
                              end: 16,
                              bottom: 16,
                              child: AnimatedScale(
                                duration: const Duration(milliseconds: 180),
                                scale: _nearBottom ? 0 : 1,
                                child: IgnorePointer(
                                  ignoring: _nearBottom,
                                  child: _ScrollToBottomAction(
                                    unseenCount: _unseenCount,
                                    onPressed: _scrollToBottom,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            if (_forwardSelection.isNotEmpty)
              SafeArea(
                top: false,
                child: Material(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: context.l10n.cancel_selection,
                          onPressed: () => setState(_forwardSelection.clear),
                          icon: const Icon(Icons.close),
                        ),
                        Expanded(
                          child: Text(
                            context.l10n.messages_selected(
                              _forwardSelection.length,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        IconButton(
                          tooltip: context.l10n.forward_selected,
                          onPressed: _forwardSelectedMessages,
                          icon: const Icon(Icons.send_outlined),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (_replying != null)
              _ReplyComposerPreview(
                message: _replying!,
                sender: _replying!.isOutgoing
                    ? context.l10n.chat_you
                    : conversation.peerName,
                onClose: () => setState(() => _replying = null),
              ),
            if (_forwardSelection.isEmpty && _showAttachments)
              _ChatAttachmentTray(
                onCamera: () =>
                    _selectAttachment((selection) => selection.takePhoto()),
                onGallery: () =>
                    _selectAttachment((selection) => selection.pickGallery()),
                onFile: () =>
                    _selectAttachment((selection) => selection.pickDocuments()),
                onPoll: () {
                  setState(() => _showAttachments = false);
                  unawaited(_showPollDialog(context, conversation));
                },
              ),
            if (_forwardSelection.isEmpty)
              _ChatComposer(
                controller: _input,
                onChanged: (value) => _onComposerChanged(conversation, value),
                onAttach: () =>
                    setState(() => _showAttachments = !_showAttachments),
                onRecord: () => _recordVoiceNote(conversation),
                onSend: (isViewOnce) =>
                    _sendComposerText(repo, conversation, isViewOnce),
                readOnly: _readOnlyForLocalUser(container, conversation),
              ),
          ],
        ),
      ),
    );
  }

  String _peerSubtitle(Conversation conversation, AppPeerActivity activity) {
    if (activity.isTyping) return context.l10n.conversation_typing;
    if (conversation.isGroup) {
      return context.l10n.members_count(conversation.groupMembers.length);
    }
    if (activity.isOnline) return context.l10n.chat_online;
    final lastSeen = activity.lastSeen;
    if (lastSeen != null) {
      final local = lastSeen.toLocal();
      final now = DateTime.now();
      final material = MaterialLocalizations.of(context);
      final formatted = _sameCalendarDay(local, now)
          ? material.formatTimeOfDay(TimeOfDay.fromDateTime(local))
          : material.formatShortDate(local);
      return context.l10n.chat_last_seen(formatted);
    }
    return context.l10n.chat_e2ee;
  }

  void _onMessageScroll() {
    if (!_messageScroll.hasClients) return;
    final distance =
        _messageScroll.position.maxScrollExtent - _messageScroll.offset;
    final nearBottom = distance <= 72;
    if (nearBottom == _nearBottom && (!nearBottom || _unseenCount == 0)) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _nearBottom = nearBottom;
      if (nearBottom) _unseenCount = 0;
    });
  }

  void _handleMessageSnapshot(List<LocalMessage> messages) {
    final previousCount = _knownMessageCount;
    final nextCount = messages.length;
    if (nextCount == previousCount) return;
    _knownMessageCount = nextCount;
    final added = previousCount < 0
        ? 0
        : (nextCount - previousCount).clamp(0, nextCount).toInt();
    final shouldFollow = previousCount < 0 || _nearBottom;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_messageScroll.hasClients) return;
      if (shouldFollow) {
        _messageScroll.jumpTo(_messageScroll.position.maxScrollExtent);
        if (!_nearBottom || _unseenCount != 0) {
          setState(() {
            _nearBottom = true;
            _unseenCount = 0;
          });
        }
      } else if (added > 0) {
        setState(() => _unseenCount += added);
      }
    });
  }

  List<LocalMessage> get _searchMatches {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return const [];
    return _latestMessages
        .where((message) => message.previewText.toLowerCase().contains(query))
        .toList(growable: false);
  }

  void _updateSearch(String _) {
    final matches = _searchMatches;
    setState(() {
      _searchIndex = 0;
      _highlightedMessageId = matches.firstOrNull?.id;
    });
    if (matches.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollToMessage(matches.first.id, transient: false),
      );
    }
  }

  void _moveSearch(int delta) {
    final matches = _searchMatches;
    if (matches.isEmpty) return;
    setState(() {
      _searchIndex = (_searchIndex + delta) % matches.length;
      if (_searchIndex < 0) _searchIndex += matches.length;
      _highlightedMessageId = matches[_searchIndex].id;
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToMessage(matches[_searchIndex].id, transient: false),
    );
  }

  void _closeSearch() {
    _search.clear();
    setState(() {
      _showSearch = false;
      _searchIndex = 0;
      _highlightedMessageId = null;
    });
  }

  List<Widget> _messageListChildren(
    BuildContext context,
    List<LocalMessage> messages,
  ) {
    final replyById = {for (final message in messages) message.id: message};
    final children = <Widget>[
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 32, vertical: 8),
        child: Center(child: _EncryptionInfoPill()),
      ),
    ];
    DateTime? previousDay;
    for (final message in messages) {
      final local = message.timestamp.toLocal();
      if (previousDay == null || !_sameCalendarDay(previousDay, local)) {
        children.add(_ChatDateSeparator(_dateLabel(local)));
        previousDay = local;
      }
      final key = _messageKeys.putIfAbsent(message.id, GlobalKey.new);
      children.add(
        KeyedSubtree(
          key: key,
          child: message.contentType == MessageContentType.system
              ? _SystemMessageBanner(message)
              : _messageRow(message, replyById[message.replyToId]),
        ),
      );
    }
    return children;
  }

  Widget _messageRow(LocalMessage message, LocalMessage? replyMessage) {
    final selecting = _forwardSelection.isNotEmpty;
    final canForward = _canForward(message);
    final bubble = _MessageBubble(
      message: message,
      replyMessage: replyMessage,
      replySenderLabel: replyMessage == null
          ? null
          : replyMessage.isOutgoing
          ? context.l10n.chat_you
          : (_conversation?.peerName ?? replyMessage.senderId),
      highlighted: _highlightedMessageId == message.id,
      searchQuery: _showSearch ? _search.text.trim() : '',
      onTap: selecting
          ? () => _toggleForwardSelection(message)
          : () => _openMessage(context, message),
      onVote: selecting
          ? (_) => _toggleForwardSelection(message)
          : (option) => _votePoll(message, option),
      onLongPress: selecting
          ? () => _toggleForwardSelection(message)
          : () {
              unawaited(SecureChatHaptics.longPress());
              _showMessageActions(message);
            },
    );
    final selectable = selecting
        ? Row(
            children: [
              Checkbox(
                value: _forwardSelection.contains(message.id),
                onChanged: canForward
                    ? (_) => _toggleForwardSelection(message)
                    : null,
              ),
              Expanded(child: bubble),
            ],
          )
        : bubble;
    if (selecting || !_canReply(message)) return selectable;
    return Dismissible(
      key: ValueKey('chat-reply-${message.id}'),
      direction: DismissDirection.startToEnd,
      confirmDismiss: (_) async {
        setState(() {
          _replying = message;
          _showAttachments = false;
        });
        return false;
      },
      background: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: 22),
          child: Icon(
            Icons.reply,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
      child: selectable,
    );
  }

  bool _canReply(LocalMessage message) =>
      !message.isViewOnce &&
      !message.isDeleted &&
      message.contentType != MessageContentType.system;

  String _dateLabel(DateTime date) {
    final now = DateTime.now();
    if (_sameCalendarDay(date, now)) return context.l10n.chat_today;
    if (_sameCalendarDay(date, now.subtract(const Duration(days: 1)))) {
      return context.l10n.chat_yesterday;
    }
    return MaterialLocalizations.of(context).formatFullDate(date);
  }

  bool _sameCalendarDay(DateTime first, DateTime second) =>
      first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;

  void _scrollToBottom() {
    if (!_messageScroll.hasClients) return;
    _messageScroll.animateTo(
      _messageScroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
    setState(() {
      _nearBottom = true;
      _unseenCount = 0;
    });
  }

  void _scrollToMessage(String messageId, {bool transient = true}) {
    final target = _messageKeys[messageId]?.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      alignment: 0.45,
    );
    if (!transient) return;
    _highlightTimer?.cancel();
    setState(() => _highlightedMessageId = messageId);
    _highlightTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted && !_showSearch) {
        setState(() => _highlightedMessageId = null);
      }
    });
  }

  Future<void> _unpinMessage(LocalMessage message) async {
    final interactions = AppContainerScope.of(
      context,
    ).chatInfoRuntime?.interactions;
    if (interactions == null) return;
    if (!await interactions.setPinned(message.id, false) && mounted) {
      _notice(context, context.l10n.pin_failed);
    }
  }

  bool _readOnlyForLocalUser(
    AppContainer container,
    Conversation conversation,
  ) =>
      conversation.isReadOnly &&
      !conversation.groupAdmins.contains(container.session.userId);

  void _onComposerChanged(Conversation conversation, String value) {
    final clean = value
        .replaceAll(RegExp(r'[\x00-\x09\x0B\x0C\x0E-\x1F\x7F]'), '')
        .characters
        .take(10000)
        .join();
    if (clean != value) {
      _input.value = TextEditingValue(
        text: clean,
        selection: TextSelection.collapsed(offset: clean.length),
      );
    }
    final activity = AppContainerScope.of(context).chatInfoRuntime?.activity;
    if (activity != null) {
      unawaited(activity.updateTyping(conversation, clean.trim().isNotEmpty));
    }
  }

  Future<void> _sendComposerText(
    ConversationRepository repo,
    Conversation conversation,
    bool isViewOnce,
  ) async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    unawaited(SecureChatHaptics.light());
    final replyToId = _replying?.id;
    _input.clear();
    setState(() {
      _replying = null;
      _showAttachments = false;
    });
    await AppContainerScope.of(context).chatInfoRuntime?.activity.stopTyping();
    await repo.sendText(
      conversation.id,
      text,
      replyToId: replyToId,
      isViewOnce: isViewOnce,
    );
  }

  Future<void> _selectAttachment(
    Future<List<MediaAttachment>> Function(MediaSelectionService) select,
  ) async {
    final selection = AppContainerScope.of(
      context,
    ).mediaRuntime?.mediaSelection;
    if (selection == null) {
      _notice(context, context.l10n.file_transfer_unavailable);
      return;
    }
    setState(() => _showAttachments = false);
    await _selectMedia(context, () => select(selection));
  }

  Future<void> _authorizeConversation(Conversation conversation) async {
    final allowed = await AppContainerScope.of(
      context,
    ).chatAccessRuntime.service.authorize(conversation);
    if (!mounted) return;
    if (!allowed) {
      setState(() => _accessChecking = false);
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _accessGranted = true;
      _accessChecking = false;
    });
    await _markRead(conversation.id);
  }

  Future<void> _markRead(String conversationId) async {
    final container = AppContainerScope.of(context);
    final receipts = container.readReceiptRuntime?.service;
    if (receipts != null) {
      await receipts.markConversationRead(conversationId);
      _markedRead = true;
    } else {
      if (_markedRead) return;
      _markedRead = true;
      await container.conversations.markConversationRead(conversationId);
    }
  }

  Future<void> _markReadSafely(String conversationId) async {
    try {
      await _markRead(conversationId);
    } catch (_) {
      // A later frame/reconnect retries the receipt. Rendering must not create
      // an uncaught asynchronous failure.
    }
  }

  Future<void> _recordVoiceNote(Conversation conversation) async {
    final runtime = AppContainerScope.of(context).mediaRuntime;
    if (runtime == null) {
      _notice(context, context.l10n.voice_service_unavailable);
      return;
    }
    final draft = await showModalBottomSheet<VoiceNoteDraft>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      showDragHandle: true,
      builder: (_) => _VoiceRecorderSheet(recorder: runtime.voiceNotes),
    );
    if (!mounted || draft == null) return;
    _notice(context, context.l10n.voice_encrypting);
    try {
      final outcome = await runtime.mediaMessages.sendVoiceNote(
        conversationId: conversation.id,
        recipientId: conversation.peerId,
        draft: draft,
        isGroup: conversation.isGroup,
        groupMembers: conversation.groupMembers,
      );
      if (!mounted) return;
      if (outcome.result is FileTransferSuccess) {
        _notice(context, context.l10n.voice_sent);
      } else {
        final failure = outcome.result as FileTransferFailure;
        _notice(context, context.l10n.voice_send_failed(failure.message));
      }
    } catch (error) {
      if (mounted) {
        _notice(context, context.l10n.voice_send_failed('$error'));
      }
    }
  }

  Future<void> _selectMedia(
    BuildContext context,
    Future<List<MediaAttachment>> Function() select,
  ) async {
    if (AppContainerScope.of(context).mediaRuntime == null) {
      _notice(context, context.l10n.file_transfer_unavailable);
      return;
    }
    try {
      final selected = await select();
      if (mounted && selected.isNotEmpty) await _previewAndSend(selected);
    } catch (error) {
      if (mounted) _notice(context, context.l10n.media_pick_failed('$error'));
    }
  }

  Future<void> _previewAndSend(List<MediaAttachment> attachments) async {
    final conversation =
        ModalRoute.of(context)?.settings.arguments as Conversation? ??
        const Conversation(
          id: 'peer-ayse',
          peerId: 'peer-ayse',
          peerName: 'Ayse Demir',
          peerPhone: '',
        );
    final request = await Navigator.push<MediaSendRequest>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => MediaPreviewScreen(attachments: attachments),
      ),
    );
    if (!mounted || request == null) return;
    final runtime = AppContainerScope.of(context).mediaRuntime;
    if (runtime == null) return;
    _notice(context, context.l10n.media_encrypting);
    late final List<MediaSendOutcome> outcomes;
    try {
      outcomes = await runtime.mediaMessages.send(
        conversationId: conversation.id,
        recipientId: conversation.peerId,
        attachments: request.attachments,
        isGroup: conversation.isGroup,
        groupMembers: conversation.groupMembers,
        caption: request.caption,
        isViewOnce: request.isViewOnce,
      );
    } catch (error) {
      if (mounted) _notice(context, context.l10n.media_send_failed('$error'));
      return;
    }
    if (!mounted) return;
    final failures = outcomes
        .where((outcome) => outcome.result is FileTransferFailure)
        .toList();
    if (failures.isEmpty) {
      _notice(context, context.l10n.media_sent(outcomes.length));
    } else {
      final first = failures.first.result as FileTransferFailure;
      _notice(
        context,
        context.l10n.media_failed(failures.length, first.message),
      );
    }
  }

  Future<void> _openMessage(BuildContext context, LocalMessage message) async {
    if (message.isViewOnce && message.contentType == MessageContentType.text) {
      if (message.isOutgoing || message.isViewed || message.content.isEmpty) {
        return;
      }
      final runtime = AppContainerScope.of(context).mediaRuntime;
      if (runtime == null) return;
      final snapshot = message.content;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (viewerContext) => Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              leading: IconButton(
                tooltip: viewerContext.l10n.action_close,
                onPressed: () => Navigator.pop(viewerContext),
                icon: const Icon(Icons.close),
              ),
              title: Text(viewerContext.l10n.view_once_protected),
            ),
            body: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(28),
                  child: Text(
                    snapshot,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 20),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await runtime.mediaMessages.markViewOnceViewed(message);
      return;
    }
    if (!message.isFileMessage) return;
    if (message.isViewOnce && (message.isOutgoing || message.isViewed)) return;
    final runtime = AppContainerScope.of(context).mediaRuntime;
    if (runtime == null) {
      _notice(context, context.l10n.media_not_found);
      return;
    }
    if (message.isViewOnce) {
      await runtime.mediaMessages.markViewOnceViewed(message);
    }
    if (!context.mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => MediaViewerScreen(
          message: message,
          fileActions: runtime.localFiles,
        ),
      ),
    );
  }

  Future<void> _showPollDialog(
    BuildContext context,
    Conversation conversation,
  ) async {
    final poll = await showDialog<PollData>(
      context: context,
      builder: (_) => const _CreatePollDialog(),
    );
    if (!mounted || poll == null) return;
    final service = AppContainerScope.of(context).chatInfoRuntime?.polls;
    if (service == null) return _notice(context, context.l10n.poll_unavailable);
    final outcome = await service.create(conversation.id, poll);
    if (!mounted) return;
    _notice(
      context,
      outcome == SendMessageOutcome.sent
          ? context.l10n.poll_sent
          : context.l10n.poll_send_failed,
    );
  }

  Future<void> _votePoll(LocalMessage message, int option) async {
    final service = AppContainerScope.of(context).chatInfoRuntime?.polls;
    if (service == null) return;
    if (!await service.vote(message.id, option) && mounted) {
      _notice(context, context.l10n.vote_send_failed);
    }
  }

  Future<void> _showMessageActions(LocalMessage message) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.reply),
              title: Text(context.l10n.msg_action_reply),
              onTap: () => Navigator.pop(context, 'reply'),
            ),
            ListTile(
              leading: const Icon(Icons.emoji_emotions_outlined),
              title: Text(context.l10n.add_reaction),
              onTap: () => Navigator.pop(context, 'reaction'),
            ),
            if (!message.isViewOnce &&
                !message.isDeleted &&
                message.contentType != MessageContentType.system)
              ListTile(
                leading: const Icon(Icons.forward_outlined),
                title: Text(context.l10n.msg_action_forward),
                onTap: () => Navigator.pop(context, 'forward'),
              ),
            if (message.isOutgoing)
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(context.l10n.msg_action_info),
                onTap: () => Navigator.pop(context, 'info'),
              ),
            ListTile(
              leading: Icon(message.isStarred ? Icons.star : Icons.star_border),
              title: Text(
                message.isStarred
                    ? context.l10n.remove_star
                    : context.l10n.add_star,
              ),
              onTap: () => Navigator.pop(context, 'star'),
            ),
            ListTile(
              leading: Icon(
                message.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
              ),
              title: Text(
                message.isPinned ? context.l10n.unpin : context.l10n.pin,
              ),
              onTap: () => Navigator.pop(context, 'pin'),
            ),
            if (message.isOutgoing &&
                message.contentType == MessageContentType.text &&
                !message.isViewOnce &&
                DateTime.now().difference(message.timestamp) <=
                    const Duration(minutes: 15))
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(context.l10n.msg_action_edit),
                onTap: () => Navigator.pop(context, 'edit'),
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(context.l10n.conv_delete),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'forward') {
      setState(() {
        _replying = null;
        _forwardSelection.add(message.id);
      });
      return;
    }
    if (action == 'info') {
      await _showMessageInfo(message);
      return;
    }
    final service = AppContainerScope.of(context).chatInfoRuntime?.interactions;
    if (service == null) return;
    switch (action) {
      case 'reply':
        setState(() => _replying = message);
        return;
      case 'reaction':
        await _chooseReaction(service, message);
        return;
      case 'star':
        await service.setStarred(message.id, !message.isStarred);
        return;
      case 'pin':
        if (!await service.setPinned(message.id, !message.isPinned) &&
            mounted) {
          _notice(context, context.l10n.pin_failed);
        }
        return;
      case 'edit':
        await _editMessage(service, message);
        return;
      case 'delete':
        await _deleteMessage(service, message);
        return;
    }
  }

  bool _canForward(LocalMessage message) =>
      !message.isViewOnce &&
      !message.isDeleted &&
      message.contentType != MessageContentType.system;

  void _toggleForwardSelection(LocalMessage message) {
    if (!_canForward(message)) return;
    setState(() {
      if (!_forwardSelection.remove(message.id)) {
        _forwardSelection.add(message.id);
      }
    });
  }

  Future<void> _forwardSelectedMessages() async {
    final container = AppContainerScope.of(context);
    final service = container.forwardRuntime?.service;
    if (service == null) {
      _notice(context, context.l10n.forward_service_unavailable);
      return;
    }
    final target = await showDialog<Conversation>(
      context: context,
      builder: (_) => _ForwardConversationDialog(
        conversations: container.conversations.watchConversations(),
      ),
    );
    if (!mounted || target == null) return;
    final selectedIds = Set<String>.from(_forwardSelection);
    final messages = await container.conversations
        .watchMessages(_conversation!.id)
        .first;
    final selected = messages
        .where((message) => selectedIds.contains(message.id))
        .where(_canForward)
        .toList(growable: false);
    if (!mounted || selected.isEmpty) return;
    _notice(
      context,
      context.l10n.forward_encrypting(selected.length, target.peerName),
    );
    final outcomes = await service.forwardAll(
      sources: selected,
      target: target,
    );
    if (!mounted) return;
    setState(_forwardSelection.clear);
    final sent = outcomes
        .where((outcome) => outcome == ForwardMessageOutcome.sent)
        .length;
    final encryptionFailures = outcomes
        .where((outcome) => outcome == ForwardMessageOutcome.encryptionFailed)
        .length;
    _notice(
      context,
      encryptionFailures > 0
          ? context.l10n.forward_encryption_result(sent, encryptionFailures)
          : sent == outcomes.length
          ? context.l10n.forward_sent(sent)
          : context.l10n.forward_partial(sent, outcomes.length - sent),
    );
  }

  Future<void> _showMessageInfo(LocalMessage message) => showDialog<void>(
    context: context,
    builder: (_) => _MessageInfoDialog(
      message: message,
      conversation: _conversation!,
      localUserId: AppContainerScope.of(context).session.userId ?? '',
    ),
  );

  Future<void> _chooseReaction(
    MessageInteractionService service,
    LocalMessage message,
  ) async {
    final emoji = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(context.l10n.choose_reaction),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              children: ['👍', '❤️', '😂', '😮', '😢', '🙏']
                  .map(
                    (value) => IconButton(
                      onPressed: () => Navigator.pop(context, value),
                      icon: Text(value, style: const TextStyle(fontSize: 25)),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ],
      ),
    );
    if (emoji != null &&
        !await service.toggleReaction(message.id, emoji) &&
        mounted) {
      _notice(context, context.l10n.reaction_failed);
    }
  }

  Future<void> _editMessage(
    MessageInteractionService service,
    LocalMessage message,
  ) async {
    final controller = TextEditingController(text: message.content);
    final content = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.msg_edit_title),
        content: TextField(
          controller: controller,
          maxLength: 10000,
          maxLines: 5,
        ),
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
    if (content != null &&
        !await service.edit(message.id, content) &&
        mounted) {
      _notice(context, context.l10n.edit_failed);
    }
  }

  Future<void> _deleteMessage(
    MessageInteractionService service,
    LocalMessage message,
  ) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(context.l10n.msg_delete_title),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'local'),
            child: Text(context.l10n.msg_action_delete_for_me),
          ),
          if (message.isOutgoing)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 'everyone'),
              child: Text(context.l10n.delete_for_everyone),
            ),
        ],
      ),
    );
    if (choice == 'local') await service.deleteLocally(message.id);
    if (choice == 'everyone' &&
        !await service.deleteForEveryone(message.id) &&
        mounted) {
      _notice(context, context.l10n.delete_signal_failed);
    }
  }

  void _startCall(
    BuildContext context,
    Conversation conversation,
    CallType type,
  ) {
    Navigator.of(context).pushNamed(
      '/calls',
      arguments: CallRouteArguments(
        peerId: conversation.peerId,
        peerName: conversation.peerName,
        callType: type,
        isGroupCall: conversation.isGroup,
        peerIds: conversation.groupMembers,
      ),
    );
  }

  void _notice(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handleMenu(
    BuildContext context,
    Conversation conversation,
    String value,
  ) async {
    final container = AppContainerScope.of(context);
    final audit = container.auditRuntime?.service;
    if (value == 'export') {
      if (audit == null)
        return _notice(context, context.l10n.export_unavailable);
      try {
        final exported = await audit.exportConversation(conversation.id);
        await FilePicker.platform.saveFile(
          dialogTitle: context.l10n.chat_export,
          fileName: exported.fileName,
          type: FileType.custom,
          allowedExtensions: const ['txt'],
          bytes: Uint8List.fromList(utf8.encode(exported.text)),
        );
        if (context.mounted) _notice(context, context.l10n.chat_exported);
      } catch (error) {
        if (context.mounted) _notice(context, '$error');
      }
      return;
    }
    if (value == 'group_info') {
      await Navigator.pushNamed(
        context,
        '/group-info',
        arguments: conversation,
      );
      return;
    }
    if (value == 'chat_info') {
      await Navigator.pushNamed(context, '/chat-info', arguments: conversation);
      return;
    }
    if (value == 'toggle_export') {
      if (audit == null) {
        return _notice(context, context.l10n.group_policy_unavailable);
      }
      try {
        await audit.toggleGroupExport(
          conversation.id,
          !conversation.isExportEnabled,
        );
        if (context.mounted) {
          _notice(
            context,
            conversation.isExportEnabled
                ? context.l10n.export_disabled
                : context.l10n.export_enabled,
          );
        }
      } catch (error) {
        if (context.mounted) _notice(context, '$error');
      }
      return;
    }
    if (value == 'export_history') {
      await Navigator.pushNamed(
        context,
        '/export-history',
        arguments: conversation,
      );
      return;
    }
    final chatInfo = container.chatInfoRuntime?.service;
    if (value == 'search') {
      setState(() {
        _showSearch = true;
        _showAttachments = false;
      });
      return;
    }
    if (value == 'timer') {
      await _showDisappearingTimer(conversation);
      return;
    }
    if (value == 'mute') {
      await chatInfo?.setMuted(conversation.id, !conversation.isMuted);
      if (context.mounted) {
        _notice(
          context,
          conversation.isMuted
              ? context.l10n.chat_unmuted
              : context.l10n.chat_muted,
        );
      }
      return;
    }
    if (value == 'clear') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.clear_chat_confirm),
          content: Text(context.l10n.clear_chat_body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.l10n.cd_clear),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await chatInfo?.clearMessages(conversation.id);
        if (context.mounted) _notice(context, context.l10n.chat_cleared);
      }
    }
  }

  Future<void> _showDisappearingTimer(Conversation conversation) async {
    final options = <Duration>[
      Duration.zero,
      const Duration(hours: 24),
      const Duration(days: 7),
      const Duration(days: 30),
    ];
    final selected = await showModalBottomSheet<Duration>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: AzureGlassPanel(
          strong: true,
          padding: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: Text(context.l10n.disappearing_messages),
              ),
              for (final duration in options)
                ListTile(
                  leading: Icon(
                    duration == Duration.zero
                        ? Icons.timer_off_outlined
                        : Icons.timer_outlined,
                  ),
                  title: Text(
                    duration == Duration.zero
                        ? context.l10n.off
                        : duration.inHours == 24
                        ? context.l10n.hours(24)
                        : context.l10n.days(duration.inDays),
                  ),
                  trailing: duration == conversation.disappearingDuration
                      ? Icon(
                          Icons.check_circle,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                  onTap: () => Navigator.pop(sheetContext, duration),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || selected == null) return;
    await AppContainerScope.of(context).chatInfoRuntime?.service
        .setDisappearingTimerForConversation(conversation.id, selected);
  }
}
