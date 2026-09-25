import 'dart:async';

import 'package:flutter/material.dart';

import '../../calls/call_readiness_service.dart';
import '../../chat/conversation_preview.dart';
import '../../core/models.dart';
import '../../l10n/l10n.dart';
import '../../services/app_container.dart';
import '../../services/app_connection_status.dart';
import '../../services/conversation_repository.dart';
import '../../widgets/avatar.dart';
import '../../widgets/azure_backdrop.dart';
import '../../widgets/haptics.dart';
import '../../widgets/azure_empty_state.dart';
import '../contacts/contacts_screen.dart';
import '../contacts/create_group_flow.dart';
import '../chat/starred_messages_screen.dart';

enum ConversationFilter { none, unread, groups, favorites }

enum _ConversationMenuAction { newChat, newGroup, bulk, scheduled, starred }

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  ConversationFilter _filter = ConversationFilter.none;
  final _searchFocus = FocusNode();
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _query = '';
  int _searchGeneration = 0;
  bool _searchVisible = false;
  bool _showArchived = false;
  final _swipeThresholds = <String>{};
  List<LocalMessage> _globalResults = const [];
  Future<CallReadinessState>? _readiness;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _readiness ??= AppContainerScope.of(
      context,
    ).callReadinessRuntime.service.refresh();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final container = AppContainerScope.of(context);
    final repo = container.conversations;
    final connectionStatus = container.connectionStatus;
    return StreamBuilder<AppConnectionStatus>(
      stream: connectionStatus.statuses,
      initialData: connectionStatus.current,
      builder: (context, statusSnapshot) {
        final status = statusSnapshot.data ?? connectionStatus.current;
        return AzureBackdrop(
          child: Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: !widget.embedded,
              title: Semantics(
                label: context.l10n.conversations_title,
                header: true,
                excludeSemantics: true,
                child: const AzureBrandTitle(),
              ),
              actions: [
                if (!status.isConnected)
                  IconButton(
                    key: const ValueKey('conversation-connection-status'),
                    tooltip: context.l10n.cd_connection_status,
                    onPressed: () =>
                        _showConnectionStatus(connectionStatus, status),
                    icon: Icon(
                      _connectionIcon(status.phase),
                      color: _connectionColor(context, status.phase),
                    ),
                  ),
                Semantics(
                  label: context.l10n.cd_search,
                  button: true,
                  excludeSemantics: true,
                  child: IconButton(
                    key: const ValueKey('conversation-search-toggle'),
                    tooltip: context.l10n.cd_search,
                    onPressed: () => _toggleSearch(repo),
                    icon: Icon(_searchVisible ? Icons.close : Icons.search),
                  ),
                ),
                Semantics(
                  label: context.l10n.cd_more,
                  button: true,
                  excludeSemantics: true,
                  child: PopupMenuButton<_ConversationMenuAction>(
                    key: const ValueKey('conversation-more-menu'),
                    tooltip: context.l10n.cd_more,
                    icon: const Icon(Icons.more_vert),
                    onSelected: _handleMenu,
                    itemBuilder: (context) => [
                      _menuItem(
                        _ConversationMenuAction.starred,
                        Icons.star_outline,
                        context.l10n.starred_messages,
                      ),
                      _menuItem(
                        _ConversationMenuAction.newChat,
                        Icons.person_add_outlined,
                        context.l10n.conv_new_chat,
                      ),
                      _menuItem(
                        _ConversationMenuAction.newGroup,
                        Icons.group_add_outlined,
                        context.l10n.conv_new_group,
                      ),
                      _menuItem(
                        _ConversationMenuAction.bulk,
                        Icons.forum_outlined,
                        context.l10n.conv_bulk_message,
                      ),
                      _menuItem(
                        _ConversationMenuAction.scheduled,
                        Icons.edit_calendar_outlined,
                        context.l10n.conv_scheduled_messages,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            body: StreamBuilder<List<Conversation>>(
              stream: repo.watchConversations(),
              builder: (context, conversationSnapshot) {
                final all = conversationSnapshot.data ?? const <Conversation>[];
                final active = all
                    .where((conversation) => !conversation.isArchived)
                    .toList(growable: false);
                final archived = all
                    .where((conversation) => conversation.isArchived)
                    .toList(growable: false);
                final source = _showArchived ? archived : active;
                final filtered = _applyFilter(source);
                final typingStream =
                    container.networkRuntime?.incomingMessages.typingStates;
                return StreamBuilder<Map<String, bool>>(
                  stream: typingStream,
                  initialData: const {},
                  builder: (context, typingSnapshot) => _content(
                    container: container,
                    repo: repo,
                    all: all,
                    filtered: filtered,
                    archived: archived,
                    typing: typingSnapshot.data ?? const {},
                    loading:
                        conversationSnapshot.connectionState ==
                            ConnectionState.waiting &&
                        !conversationSnapshot.hasData,
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _content({
    required AppContainer container,
    required ConversationRepository repo,
    required List<Conversation> all,
    required List<Conversation> filtered,
    required List<Conversation> archived,
    required Map<String, bool> typing,
    required bool loading,
  }) {
    final names = {
      for (final conversation in all) conversation.id: conversation,
    };
    return Column(
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: !_searchVisible
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: TextField(
                    key: const ValueKey('conversation-global-search'),
                    controller: _searchController,
                    focusNode: _searchFocus,
                    onChanged: (value) => _updateQuery(repo, value),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: context.l10n.conversations_search,
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: context.l10n.clear_search,
                              onPressed: () {
                                _searchController.clear();
                                _updateQuery(repo, '');
                              },
                              icon: const Icon(Icons.close),
                            ),
                    ),
                  ),
                ),
        ),
        if (_showArchived) _archivedHeader(archived.length) else _filterBar(),
        Expanded(
          child: loading
              ? const _ConversationShimmerList()
              : ListView(
                  key: ValueKey(
                    _showArchived
                        ? 'archived-conversation-list'
                        : 'active-conversation-list',
                  ),
                  // Alt gezinme cubugu Scaffold tarafindan zaten paylanir
                  // (extendBody kapali) ve ekranda yuzen bir oge yok; 112 px
                  // liste sonunda olu bosluk biraktiriyordu.
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                  children: [
                    if (!_showArchived) _readinessBanner(),
                    if (!_showArchived &&
                        archived.isNotEmpty &&
                        _query.isEmpty &&
                        _filter == ConversationFilter.none) ...[
                      _archiveBanner(archived.length),
                      const SizedBox(height: 8),
                    ],
                    if (filtered.isEmpty && _globalResults.isEmpty)
                      _emptyState(
                        searching:
                            _query.isNotEmpty ||
                            _filter != ConversationFilter.none,
                      ),
                    for (final conversation in filtered) ...[
                      _conversationCard(
                        repo,
                        conversation,
                        typing[conversation.peerId] == true,
                      ),
                      const SizedBox(height: 7),
                    ],
                    if (!_showArchived &&
                        _query.trim().length >= 2 &&
                        _globalResults.isNotEmpty) ...[
                      _messageSearchHeader(_globalResults.length),
                      for (final message in _globalResults) ...[
                        _messageSearchResult(
                          message,
                          names[message.conversationId],
                        ),
                        const SizedBox(height: 7),
                      ],
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _readinessBanner() {
    return FutureBuilder<CallReadinessState>(
      future: _readiness,
      builder: (context, snapshot) {
        final state = snapshot.data;
        if (state == null || state.allGranted) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AzureGlassPanel(
            padding: EdgeInsets.zero,
            child: ListTile(
              key: const ValueKey('conversation-call-readiness'),
              leading: Icon(
                Icons.phone_callback_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text(context.l10n.calls_readiness_missing),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, '/call-readiness'),
            ),
          ),
        );
      },
    );
  }

  Widget _archiveBanner(int count) => AzureGlassPanel(
    padding: EdgeInsets.zero,
    child: ListTile(
      key: const ValueKey('conversation-archive-banner'),
      leading: CircleAvatar(
        backgroundColor: Theme.of(
          context,
        ).colorScheme.primary.withValues(alpha: .12),
        child: Icon(
          Icons.archive_outlined,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      title: Text(context.l10n.conversations_archived_title),
      trailing: Badge(label: Text('$count')),
      onTap: () => setState(() => _showArchived = true),
    ),
  );

  Widget _archivedHeader(int count) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
    child: Row(
      children: [
        IconButton(
          tooltip: context.l10n.nav_back,
          onPressed: () => setState(() => _showArchived = false),
          icon: const Icon(Icons.arrow_back),
        ),
        Expanded(
          child: Text(
            context.l10n.conversations_archived_title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        Badge(label: Text('$count')),
      ],
    ),
  );

  Widget _emptyState({required bool searching}) => AzureEmptyState(
    icon: searching ? Icons.search_off : Icons.forum_outlined,
    title: searching
        ? context.l10n.conversations_no_results
        : context.l10n.no_chats_yet,
    message: searching
        ? context.l10n.conversations_no_results_body
        : context.l10n.conversations_empty_body,
    topPadding: 88,
  );

  Widget _conversationCard(
    ConversationRepository repo,
    Conversation conversation,
    bool typing,
  ) {
    final subtitle = typing
        ? context.l10n.conversation_typing
        : conversation.isLocked
        ? context.l10n.conversation_locked_preview
        : conversation.lastMessageType == MessageContentType.poll &&
              conversation.lastMessage != viewOncePreviewLabel
        ? context.l10n.poll
        : _displayLastMessage(conversation.lastMessage ?? '');
    final scheme = Theme.of(context).colorScheme;
    return AzureGlassPanel(
      padding: EdgeInsets.zero,
      radius: 16,
      // Kart zeminden ayrilir. Onceden her sey ayni duzlemdeydi ve sohbetler
      // arka plandan yalnizca 1 px cerceveyle ayirt ediliyordu.
      elevation: conversation.hasUnread ? 3 : 1,
      borderColor: conversation.hasUnread
          ? scheme.primary.withValues(alpha: .45)
          : null,
      child: Dismissible(
        key: ValueKey('conversation-${conversation.id}'),
        dismissThresholds: const {
          DismissDirection.startToEnd: .5,
          DismissDirection.endToStart: .5,
        },
        onUpdate: (details) {
          if (details.reached) {
            if (_swipeThresholds.add(conversation.id)) {
              unawaited(SecureChatHaptics.light());
            }
          } else {
            _swipeThresholds.remove(conversation.id);
          }
        },
        background: _swipeBackground(
          alignment: Alignment.centerLeft,
          icon: conversation.isArchived ? Icons.unarchive : Icons.archive,
          label: conversation.isArchived
              ? context.l10n.archive_remove
              : context.l10n.conv_archive,
          color: Theme.of(context).colorScheme.primary,
        ),
        secondaryBackground: _swipeBackground(
          alignment: Alignment.centerRight,
          icon: Icons.delete_outline,
          label: _keepsGroup(context, conversation)
              ? context.l10n.clear_chat
              : context.l10n.conv_delete,
          color: Theme.of(context).colorScheme.error,
        ),
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.startToEnd) {
            await repo.setArchived(conversation.id, !conversation.isArchived);
          } else if (await _confirmDelete(context, conversation)) {
            await repo.deleteConversation(conversation.id);
          }
          return false;
        },
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onLongPress: () => _showActions(context, repo, conversation),
          onTap: () =>
              Navigator.of(context).pushNamed('/chat', arguments: conversation),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(11, 10, 14, 10),
              child: Row(
                children: [
                  // Aksan rengi yalnizca DURUM icin kullanilir: okunmamis
                  // sohbet. Dekorasyon amaciyla baska yerde gorunmez.
                  Container(
                    width: 3,
                    height: 34,
                    margin: const EdgeInsetsDirectional.only(end: 8),
                    decoration: BoxDecoration(
                      color: conversation.hasUnread
                          ? scheme.primary
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      GeneratedAvatar(
                        name: conversation.peerName,
                        isGroup: conversation.isGroup,
                      ),
                      if (conversation.isLocked)
                        const Positioned(
                          right: -3,
                          bottom: -3,
                          child: CircleAvatar(
                            radius: 9,
                            child: Icon(Icons.lock, size: 11),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                conversation.peerName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(
                                      fontWeight: conversation.hasUnread
                                          ? FontWeight.w700
                                          : FontWeight.w600,
                                      color: scheme.onSurface,
                                    ),
                              ),
                            ),
                            if (conversation.isFavorite)
                              Icon(
                                Icons.star,
                                size: 16,
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                            if (conversation.isPinned)
                              const Padding(
                                padding: EdgeInsetsDirectional.only(start: 4),
                                child: Icon(Icons.push_pin, size: 15),
                              ),
                            if (conversation.isMuted)
                              const Padding(
                                padding: EdgeInsetsDirectional.only(start: 4),
                                child: Icon(
                                  Icons.notifications_off_outlined,
                                  size: 15,
                                ),
                              ),
                          ],
                        ),
                        // Henuz mesajlasilmamis sohbette bos bir satir
                        // birakilmamali: ad dikeyde ortalanir.
                        if (subtitle.isNotEmpty) const SizedBox(height: 3),
                        if (subtitle.isNotEmpty)
                          Row(
                            children: [
                              if (!typing)
                                ..._previewLeading(context, conversation),
                              Expanded(
                                child: Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: typing
                                            ? scheme.primary
                                            : scheme.onSurfaceVariant,
                                        fontWeight: typing
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                      ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 112),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _formatTimestamp(conversation.lastMessageTimestamp),
                          textAlign: TextAlign.end,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: conversation.hasUnread
                                    ? scheme.primary
                                    : scheme.onSurfaceVariant,
                                fontWeight: conversation.hasUnread
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                              ),
                        ),
                        if (conversation.hasUnread) ...[
                          const SizedBox(height: 4),
                          Badge(
                            label: Text(
                              conversation.unreadCount > 0
                                  ? conversation.unreadCount.toString()
                                  : ' ',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Onizlemenin onunde duran isaretler: giden mesajda teslim tiki, medya
  /// mesajinda tur ikonu.
  ///
  /// Onceden ikisi de yoktu: "mesajim gitti mi" sorusu icin sohbeti acmak,
  /// ne geldigini anlamak icin de mesaji acmak gerekiyordu.
  List<Widget> _previewLeading(
    BuildContext context,
    Conversation conversation,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final marks = <Widget>[];
    if (conversation.lastMessageOutgoing) {
      final (icon, color) = switch (conversation.lastMessageStatus) {
        MessageStatus.sending => (Icons.schedule, scheme.onSurfaceVariant),
        MessageStatus.sent => (Icons.done, scheme.onSurfaceVariant),
        MessageStatus.delivered => (Icons.done_all, scheme.onSurfaceVariant),
        MessageStatus.read => (
          Icons.done_all,
          AppContainerScope.of(context).session.shareReadReceipts
              ? scheme.primary
              : scheme.onSurfaceVariant,
        ),
        MessageStatus.failed => (Icons.error_outline, scheme.error),
        null => (Icons.done, scheme.onSurfaceVariant),
      };
      marks.add(Icon(icon, size: 14, color: color));
    }
    final typeIcon = switch (conversation.lastMessageType) {
      MessageContentType.image => Icons.photo_outlined,
      MessageContentType.file => Icons.insert_drive_file_outlined,
      MessageContentType.voiceNote => Icons.mic_none,
      MessageContentType.poll => Icons.bar_chart,
      _ => null,
    };
    if (typeIcon != null) {
      marks.add(Icon(typeIcon, size: 14, color: scheme.onSurfaceVariant));
    }
    if (marks.isEmpty) return const [];
    return [
      for (final mark in marks) ...[mark, const SizedBox(width: 4)],
    ];
  }

  Widget _messageSearchHeader(int count) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
    child: Row(
      children: [
        Icon(
          Icons.forum_outlined,
          size: 18,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Text(
          context.l10n.conversations_messages_section,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 6),
        Badge(label: Text('$count')),
      ],
    ),
  );

  Widget _messageSearchResult(
    LocalMessage message,
    Conversation? conversation,
  ) {
    final title = conversation?.peerName ?? message.conversationId;
    return AzureGlassPanel(
      padding: EdgeInsets.zero,
      radius: 14,
      child: ListTile(
        leading: GeneratedAvatar(name: title),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          message.content,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(
          _formatTimestamp(message.timestamp),
          style: Theme.of(context).textTheme.labelSmall,
        ),
        onTap: conversation == null
            ? null
            : () => Navigator.pushNamed(
                context,
                '/chat',
                arguments: conversation,
              ),
      ),
    );
  }

  PopupMenuItem<_ConversationMenuAction> _menuItem(
    _ConversationMenuAction value,
    IconData icon,
    String label,
  ) => PopupMenuItem(
    value: value,
    child: Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(label)),
      ],
    ),
  );

  void _handleMenu(_ConversationMenuAction action) {
    switch (action) {
      case _ConversationMenuAction.starred:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const StarredMessagesScreen(),
          ),
        );
      case _ConversationMenuAction.newChat:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const ContactsScreen(newChat: true),
          ),
        );
      case _ConversationMenuAction.newGroup:
        showCreateGroupFlow(context);
      case _ConversationMenuAction.bulk:
        Navigator.pushNamed(context, '/bulk-message');
      case _ConversationMenuAction.scheduled:
        Navigator.pushNamed(context, '/scheduled-messages');
    }
  }

  void _toggleSearch(ConversationRepository repo) {
    final visible = !_searchVisible;
    setState(() => _searchVisible = visible);
    if (!visible) {
      _searchController.clear();
      _updateQuery(repo, '');
      _searchFocus.unfocus();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _updateQuery(ConversationRepository repo, String value) {
    _searchDebounce?.cancel();
    final clean = value.trim();
    final generation = ++_searchGeneration;
    setState(() {
      _query = value;
      if (clean.length < 2) _globalResults = const [];
    });
    if (clean.length < 2) return;
    _searchDebounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final matches = await repo.searchAllMessages(clean, limit: 50);
        if (!mounted || generation != _searchGeneration) return;
        setState(() => _globalResults = matches);
      } catch (_) {
        if (!mounted || generation != _searchGeneration) return;
        setState(() => _globalResults = const []);
      }
    });
  }

  Widget _filterBar() {
    final filters = [
      (
        context.l10n.conv_filter_all,
        ConversationFilter.none,
        Icons.forum_outlined,
      ),
      (
        context.l10n.conv_filter_unread,
        ConversationFilter.unread,
        Icons.mark_chat_unread_outlined,
      ),
      (
        context.l10n.conv_filter_groups,
        ConversationFilter.groups,
        Icons.groups_outlined,
      ),
      (
        context.l10n.conv_filter_favorites,
        ConversationFilter.favorites,
        Icons.star_outline,
      ),
    ];
    final style = Theme.of(
      context,
    ).textTheme.labelLarge!.copyWith(fontSize: 13, letterSpacing: 0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final widths = filters.map((entry) {
            final painter = TextPainter(
              text: TextSpan(text: entry.$1, style: style),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
              maxLines: 1,
            )..layout();
            final width = (painter.width + 18).clamp(48.0, double.infinity);
            painter.dispose();
            return width;
          }).toList();
          // Keep one row at large accessibility sizes without shrinking text.
          final compact =
              widths.fold<double>(0, (sum, width) => sum + width) + 16 >
              constraints.maxWidth;
          return Row(
            key: const ValueKey('conversation-filters'),
            children: [
              for (var i = 0; i < filters.length; i++)
                Expanded(
                  flex: compact ? 1 : widths[i].ceil(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Tooltip(
                      message: filters[i].$1,
                      child: FilterChip(
                        key: ValueKey(
                          'conversation-filter-${filters[i].$2.name}',
                        ),
                        padding: EdgeInsets.zero,
                        labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                        label: compact
                            ? Icon(
                                filters[i].$3,
                                size: 20,
                                semanticLabel: filters[i].$1,
                              )
                            : Text(
                                filters[i].$1,
                                maxLines: 1,
                                softWrap: false,
                                style: style,
                              ),
                        selected: _filter == filters[i].$2,
                        showCheckmark: false,
                        onSelected: (_) =>
                            setState(() => _filter = filters[i].$2),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  List<Conversation> _applyFilter(List<Conversation> source) {
    final cleanQuery = _query.trim().toLowerCase();
    return source
        .where((conversation) {
          final matchesQuery =
              cleanQuery.isEmpty ||
              conversation.peerName.toLowerCase().contains(cleanQuery) ||
              (conversation.lastMessage ?? '').toLowerCase().contains(
                cleanQuery,
              );
          final matchesFilter = switch (_filter) {
            ConversationFilter.none => true,
            ConversationFilter.unread => conversation.hasUnread,
            ConversationFilter.groups => conversation.isGroup,
            ConversationFilter.favorites => conversation.isFavorite,
          };
          return matchesQuery && matchesFilter;
        })
        .toList(growable: false);
  }

  Widget _swipeBackground({
    required Alignment alignment,
    required IconData icon,
    required String label,
    required Color color,
  }) => Container(
    decoration: BoxDecoration(
      color: color.withValues(alpha: .88),
      borderRadius: BorderRadius.circular(16),
    ),
    alignment: alignment,
    padding: const EdgeInsets.symmetric(horizontal: 24),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (alignment == Alignment.centerRight) Text(label),
        if (alignment == Alignment.centerRight) const SizedBox(width: 8),
        Icon(icon),
        if (alignment == Alignment.centerLeft) const SizedBox(width: 8),
        if (alignment == Alignment.centerLeft) Text(label),
      ],
    ),
  );

  Future<void> _showConnectionStatus(
    AppConnectionStatusSource connectionStatus,
    AppConnectionStatus status,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: AzureGlassPanel(
            strong: true,
            child: Row(
              children: [
                Icon(
                  _connectionIcon(status.phase),
                  color: _connectionColor(context, status.phase),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _connectionText(status.phase),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (status.phase != AppConnectionPhase.connecting)
                  TextButton(
                    onPressed: () async {
                      Navigator.pop(sheetContext);
                      await connectionStatus.retry();
                    },
                    child: Text(context.l10n.action_retry),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _connectionIcon(AppConnectionPhase state) => switch (state) {
    AppConnectionPhase.connecting => Icons.sync_problem_outlined,
    AppConnectionPhase.connected => Icons.cloud_done_outlined,
    AppConnectionPhase.disconnected => Icons.cloud_off_outlined,
    AppConnectionPhase.error => Icons.wifi_off_outlined,
  };

  Color _connectionColor(BuildContext context, AppConnectionPhase state) =>
      switch (state) {
        AppConnectionPhase.connecting => const Color(0xFFFFA726),
        AppConnectionPhase.connected => const Color(0xFF2E7D32),
        AppConnectionPhase.disconnected ||
        AppConnectionPhase.error => Theme.of(context).colorScheme.error,
      };

  String _connectionText(AppConnectionPhase state) => switch (state) {
    AppConnectionPhase.connecting => context.l10n.connecting,
    AppConnectionPhase.connected => context.l10n.connected,
    AppConnectionPhase.disconnected => context.l10n.signaling_disconnected,
    AppConnectionPhase.error => context.l10n.connection_failed,
  };

  Future<void> _showActions(
    BuildContext context,
    ConversationRepository repo,
    Conversation conversation,
  ) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: AzureGlassPanel(
        strong: true,
        padding: EdgeInsets.zero,
        child: Wrap(
          children: [
            ListTile(
              leading: Icon(
                conversation.isPinned
                    ? Icons.push_pin_outlined
                    : Icons.push_pin,
              ),
              title: Text(
                conversation.isPinned ? context.l10n.unpin : context.l10n.pin,
              ),
              onTap: () async {
                Navigator.pop(sheetContext);
                await repo.setPinned(conversation.id, !conversation.isPinned);
              },
            ),
            ListTile(
              leading: Icon(
                conversation.isFavorite ? Icons.star_outline : Icons.star,
              ),
              title: Text(
                conversation.isFavorite
                    ? context.l10n.remove_favorite
                    : context.l10n.add_favorite,
              ),
              onTap: () async {
                Navigator.pop(sheetContext);
                await repo.setFavorite(
                  conversation.id,
                  !conversation.isFavorite,
                );
              },
            ),
            ListTile(
              leading: Icon(
                conversation.hasUnread
                    ? Icons.mark_email_read
                    : Icons.mark_email_unread,
              ),
              title: Text(
                conversation.hasUnread
                    ? context.l10n.mark_read
                    : context.l10n.mark_unread,
              ),
              onTap: () async {
                Navigator.pop(sheetContext);
                if (conversation.hasUnread) {
                  await repo.markConversationRead(conversation.id);
                } else {
                  await repo.setManuallyUnread(conversation.id, true);
                }
              },
            ),
            ListTile(
              leading: Icon(
                conversation.isArchived ? Icons.unarchive : Icons.archive,
              ),
              title: Text(
                conversation.isArchived
                    ? context.l10n.archive_remove
                    : context.l10n.conv_archive,
              ),
              onTap: () async {
                Navigator.pop(sheetContext);
                await repo.setArchived(
                  conversation.id,
                  !conversation.isArchived,
                );
              },
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                _keepsGroup(context, conversation)
                    ? context.l10n.clear_chat
                    : context.l10n.conv_delete_chat,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () async {
                Navigator.pop(sheetContext);
                if (await _confirmDelete(context, conversation)) {
                  await repo.deleteConversation(conversation.id);
                }
              },
            ),
          ],
        ),
      ),
    ),
  );

  bool _keepsGroup(BuildContext context, Conversation conversation) =>
      conversation.isGroup &&
      !conversation.hasLeftGroup(AppContainerScope.of(context).session.userId);

  Future<bool> _confirmDelete(
    BuildContext context,
    Conversation conversation,
  ) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            _keepsGroup(context, conversation)
                ? context.l10n.clear_chat_confirm
                : context.l10n.conv_delete_chat,
          ),
          content: Text(
            _keepsGroup(context, conversation)
                ? context.l10n.clear_group_history_body
                : context.l10n.delete_chat_body(conversation.peerName),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(context.l10n.conv_delete),
            ),
          ],
        ),
      ) ??
      false;

  String _formatTimestamp(DateTime? value) {
    if (value == null) return '';
    value = value.toLocal();
    final now = DateTime.now();
    if (value.year == now.year &&
        value.month == now.month &&
        value.day == now.day) {
      return '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    }
    return '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year.toString().padLeft(4, '0')}';
  }

  String _displayLastMessage(String value) {
    if (!value.startsWith('CALL|')) return value;
    final parts = value.split('|');
    return parts.length > 5 ? parts[5] : value;
  }
}

class _ConversationShimmerList extends StatefulWidget {
  const _ConversationShimmerList();

  @override
  State<_ConversationShimmerList> createState() =>
      _ConversationShimmerListState();
}

class _ConversationShimmerListState extends State<_ConversationShimmerList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
      lowerBound: .35,
      upperBound: .72,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _pulse,
    builder: (context, _) => ListView.separated(
      key: const ValueKey('conversation-shimmer'),
      padding: const EdgeInsets.all(12),
      itemCount: 8,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, _) => Opacity(
        opacity: _pulse.value,
        child: AzureGlassPanel(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const CircleAvatar(radius: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 13,
                      width: 140,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 10),
                    Container(
                      height: 10,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
