import 'dart:async';

import 'package:flutter/material.dart';

import '../../background/scheduled_message_service.dart';
import '../../core/models.dart';
import '../../l10n/l10n.dart';
import '../contacts/recipient_picker_screen.dart';
import '../contacts/conversation_recipients.dart';
import '../../services/app_container.dart';
import '../../settings/settings_service.dart';
import '../../storage/storage_entities.dart';
import '../../widgets/azure_backdrop.dart';
import '../../widgets/chat_lock_dialog.dart';

class ScheduledMessagesScreen extends StatefulWidget {
  const ScheduledMessagesScreen({super.key});

  @override
  State<ScheduledMessagesScreen> createState() =>
      _ScheduledMessagesScreenState();
}

class _ScheduledMessagesScreenState extends State<ScheduledMessagesScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tabs;
  final _content = TextEditingController();
  final _selectedRecipients = <String, String>{};
  final _editingSourceRecipients = <String>{};
  final _days = <int>{};
  TimeOfDay _time = const TimeOfDay(hour: 9, minute: 0);
  ScheduledRepeat _repeat = ScheduledRepeat.once;
  String? _editingId;
  bool _savingEnabled = false;
  bool _saving = false;
  bool _checkingAccess = false;
  bool _foreground = true;
  int _accessRevision = 0;
  StreamSubscription<List<Conversation>>? _conversationSubscription;
  Map<String, Conversation>? _conversations;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _conversationSubscription ??= AppContainerScope.of(context).conversations
        .watchConversations()
        .listen(
          (items) {
            if (!mounted) return;
            final next = {for (final item in items) item.id: item};
            final accessChanged =
                _conversations == null ||
                next.length != _conversations!.length ||
                next.entries.any(
                  (entry) =>
                      _conversations?[entry.key]?.isLocked !=
                      entry.value.isLocked,
                );
            if (accessChanged) {
              _accessRevision++;
              if (_editingId != null &&
                  {
                    ..._editingSourceRecipients,
                    ..._selectedRecipients.keys,
                  }.any(
                    (id) =>
                        next[id] == null ||
                        _conversations?[id]?.isLocked != next[id]?.isLocked,
                  )) {
                _clearForm();
              }
            }
            setState(() => _conversations = next);
          },
          onError: (Object _) {
            if (!mounted) return;
            _accessRevision++;
            if (_editingId != null) _clearForm();
            setState(() => _conversations = null);
          },
        );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    setState(() => _foreground = state == AppLifecycleState.resumed);
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _accessRevision++;
      if (_editingId != null) _clearForm();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _conversationSubscription?.cancel();
    _tabs.dispose();
    _content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final container = AppContainerScope.of(context);
    final runtime = container.backgroundRuntime;
    final settings = container.settingsRuntime?.service;
    return AzureBackdrop(
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.l10n.sched_title),
          bottom: TabBar(
            controller: _tabs,
            isScrollable: false,
            tabAlignment: TabAlignment.fill,
            padding: EdgeInsets.zero,
            labelPadding: const EdgeInsets.symmetric(horizontal: 8),
            indicatorSize: TabBarIndicatorSize.tab,
            tabs: [
              Tab(text: context.l10n.sched_tab_create),
              Tab(text: context.l10n.sched_tab_existing),
              Tab(text: context.l10n.sched_tab_history),
            ],
          ),
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              if (settings != null)
                StreamBuilder<AppSettingsState>(
                  stream: settings.states,
                  initialData: settings.current,
                  builder: (context, snapshot) => SwitchListTile(
                    key: const ValueKey('scheduled-messages-enabled'),
                    tileColor: Theme.of(context).colorScheme.surface,
                    secondary: const Icon(Icons.schedule_send_outlined),
                    title: Text(context.l10n.settings_scheduled_messages),
                    subtitle: Text(
                      context.l10n.settings_scheduled_enabled_desc,
                    ),
                    value: (snapshot.data ?? settings.current)
                        .scheduledMessagesEnabled,
                    onChanged: _savingEnabled
                        ? null
                        : (value) => _setEnabled(settings, value),
                  ),
                ),
              Expanded(
                child: !_foreground
                    ? const SizedBox.shrink()
                    : runtime == null
                    ? Center(child: Text(context.l10n.background_unavailable))
                    : TabBarView(
                        controller: _tabs,
                        children: [
                          AbsorbPointer(
                            absorbing: _saving || _checkingAccess,
                            child: _buildForm(runtime.scheduledMessages),
                          ),
                          _buildList(runtime.scheduledMessages),
                          _buildHistory(runtime.scheduledMessages),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _setEnabled(SettingsService service, bool value) async {
    setState(() => _savingEnabled = true);
    try {
      await service.setScheduledMessagesEnabled(value);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _savingEnabled = false);
    }
  }

  Widget _buildForm(ScheduledMessageService service) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_editingId != null)
          Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.edit_mode,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(
                onPressed: _clearForm,
                child: Text(context.l10n.cancel),
              ),
            ],
          ),
        SegmentedButton<ScheduledRepeat>(
          segments: [
            ButtonSegment(
              value: ScheduledRepeat.once,
              label: Text(context.l10n.repeat_once),
            ),
            ButtonSegment(
              value: ScheduledRepeat.daily,
              label: Text(context.l10n.repeat_daily),
            ),
            ButtonSegment(
              value: ScheduledRepeat.custom,
              label: Text(context.l10n.repeat_custom),
            ),
          ],
          selected: {_repeat},
          onSelectionChanged: (selection) {
            setState(() => _repeat = selection.single);
          },
        ),
        if (_repeat == ScheduledRepeat.custom) ...[
          const SizedBox(height: 12),
          _WeekdayField(
            selected: _days,
            onChanged: (days) => setState(() {
              _days
                ..clear()
                ..addAll(days);
            }),
          ),
        ],
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.access_time),
          title: Text(context.l10n.delivery_time),
          subtitle: Text(_time.format(context)),
          trailing: const Icon(Icons.chevron_right),
          onTap: _pickTime,
        ),
        TextField(
          controller: _content,
          minLines: 3,
          maxLines: 8,
          maxLength: 4096,
          decoration: InputDecoration(
            labelText: context.l10n.message_content,
            alignLabelWithHint: true,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.person_add_alt_1),
          title: Text(context.l10n.recipients),
          subtitle: Text(
            _selectedRecipients.isEmpty
                ? context.l10n.recipient_required
                : _selectedRecipients.values.join(', '),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: _pickRecipients,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const ValueKey('scheduled-save'),
          onPressed: _saving || _checkingAccess ? null : () => _save(service),
          icon: const Icon(Icons.schedule_send),
          label: Text(
            _editingId == null ? context.l10n.schedule : context.l10n.update,
          ),
        ),
      ],
    );
  }

  Widget _buildList(ScheduledMessageService service) {
    return StreamBuilder<List<ScheduledMessageEntity>>(
      stream: service.watchAll(),
      builder: (context, snapshot) {
        final items = snapshot.data ?? const [];
        if (items.isEmpty) {
          return Center(child: Text(context.l10n.no_scheduled_messages));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final item = items[index];
            final locked = _planRecipients(item).any(
              (id) =>
                  _conversations?[id] == null || _conversations![id]!.isLocked,
            );
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  child: Icon(locked ? Icons.lock_outline : Icons.schedule),
                ),
                title: Text(
                  locked
                      ? context.l10n.sched_history_locked
                      : item.messageContent,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  locked
                      ? _formatTrigger(item.nextTriggerTime)
                      : '${_formatTrigger(item.nextTriggerTime)} · ${item.recipientNames}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: item.isEnabled,
                      onChanged: _saving || _checkingAccess
                          ? null
                          : (value) => service.setEnabled(item.id, value),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (action) {
                        if (action == 'edit') _edit(item);
                        if (action == 'delete') _confirmDelete(service, item);
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'edit',
                          child: Text(context.l10n.sched_action_edit),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(context.l10n.sched_action_delete),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _pickTime() async {
    final value = await showTimePicker(context: context, initialTime: _time);
    if (value != null && mounted) setState(() => _time = value);
  }

  Widget _buildHistory(ScheduledMessageService service) {
    return StreamBuilder<List<Conversation>>(
      stream: AppContainerScope.of(context).conversations.watchConversations(),
      builder: (context, conversations) =>
          StreamBuilder<List<ScheduledMessageHistoryEntity>>(
            stream: service.watchHistory(),
            builder: (context, snapshot) {
              if (snapshot.hasError || conversations.hasError) {
                return Center(child: Text(context.l10n.background_unavailable));
              }
              if (!snapshot.hasData || !conversations.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final items = snapshot.data!;
              final byId = {
                for (final conversation in conversations.data!)
                  conversation.id: conversation,
              };
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      context.l10n.sched_history_note,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  Expanded(
                    child: items.isEmpty
                        ? Center(child: Text(context.l10n.sched_history_empty))
                        : ListView.separated(
                            key: const ValueKey('scheduled-history-list'),
                            itemCount: items.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final item = items[index];
                              final locked = item.recipients.any(
                                (recipient) => _historyNeedsAccess(
                                  recipient,
                                  byId[recipient.recipientId],
                                ),
                              );
                              return ListTile(
                                key: ValueKey('scheduled-history-${item.id}'),
                                leading: Icon(
                                  locked
                                      ? Icons.lock_outline
                                      : _historyIcon(item.status),
                                ),
                                title: Text(
                                  locked
                                      ? context.l10n.sched_history_locked
                                      : item.contentRetained
                                      ? item.messageContent
                                      : context
                                            .l10n
                                            .sched_history_content_omitted,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  '${_historyTime(context, item.executedAt)}\n'
                                  '${_historyStatus(context, item.status)}'
                                  '${locked ? '' : '\n${item.recipients.map((r) => r.recipientName).join(', ')}'}',
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => Navigator.of(context).push<void>(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        _ScheduledHistoryDetails(item: item),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          ),
    );
  }

  Future<void> _pickRecipients() async {
    final recipients = ConversationRecipients(AppContainerScope.of(context));
    List<RecipientChoice>? resolved;
    final selected = await Navigator.of(context).push<List<RecipientChoice>>(
      MaterialPageRoute(
        builder: (_) => RecipientPickerScreen(
          title: context.l10n.sched_pick_recipient,
          actionLabel: context.l10n.action_ok,
          allowEmpty: true,
          initial: [
            for (final item in _selectedRecipients.entries)
              RecipientChoice(id: item.key, name: item.value),
          ],
          choices: recipients.choices,
          onConfirm: (selected) async {
            resolved = await recipients.resolve(selected);
            return true;
          },
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _selectedRecipients
        ..clear()
        ..addEntries(resolved!.map((item) => MapEntry(item.id, item.name)));
    });
  }

  Future<void> _save(ScheduledMessageService service) async {
    if (_saving || _checkingAccess) return;
    setState(() => _saving = true);
    try {
      if (!await _authorizeRecipients(
        {..._editingSourceRecipients, ..._selectedRecipients.keys}.toList(),
      ))
        return;
      await service.save(
        ScheduledMessageDraft(
          content: _content.text,
          recipients: _selectedRecipients.keys.toList(),
          recipientNames: _selectedRecipients.values.toList(),
          hour: _time.hour,
          minute: _time.minute,
          repeat: _repeat,
          days: _days,
        ),
        id: _editingId,
      );
      if (!mounted) return;
      _clearForm();
      _tabs.animateTo(1);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.schedule_saved)));
    } on ArgumentError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.message?.toString() ?? context.l10n.form_incomplete,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.background_unavailable)),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<String> _planRecipients(ScheduledMessageEntity item) => item.recipientIds
      .split(',')
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toList();

  Future<bool> _authorizeRecipients(List<String> ids) async {
    if (_conversations == null || !_foreground) return false;
    final revision = _accessRevision;
    final runtime = AppContainerScope.of(context).chatAccessRuntime;
    try {
      for (final id in ids) {
        final conversation = _conversations?[id];
        if (conversation == null) return false;
        if (!conversation.isLocked) continue;
        final credentials = runtime.credentials;
        final hasPassword =
            credentials != null && await credentials.hasCredential(id);
        if (!mounted || revision != _accessRevision) return false;
        final allowed = hasPassword
            ? await showVerifyChatPasswordDialog(
                context,
                chatName: conversation.peerName,
                verify: (password) => credentials.verifyPassword(id, password),
              )
            : await runtime.service.authorize(conversation);
        if (!mounted || !allowed || revision != _accessRevision) return false;
      }
      return mounted && _foreground && revision == _accessRevision;
    } catch (_) {
      return false;
    }
  }

  Future<void> _edit(ScheduledMessageEntity item) async {
    if (_saving || _checkingAccess) return;
    setState(() => _checkingAccess = true);
    late final bool allowed;
    try {
      allowed = await _authorizeRecipients(_planRecipients(item));
    } finally {
      if (mounted) setState(() => _checkingAccess = false);
    }
    if (!mounted || !allowed) return;
    setState(() {
      _editingId = item.id;
      _editingSourceRecipients
        ..clear()
        ..addAll(_planRecipients(item));
      _content.text = item.messageContent;
      _time = TimeOfDay(hour: item.hour, minute: item.minute);
      _repeat = ScheduledMessageService.parseRepeat(item.repeatType);
      _days
        ..clear()
        ..addAll(ScheduledMessageService.parseDays(item.repeatDays));
      _selectedRecipients.clear();
      final ids = item.recipientIds.split(',');
      final names = item.recipientNameList;
      for (var index = 0; index < ids.length; index++) {
        final id = ids[index].trim();
        if (id.isEmpty) continue;
        _selectedRecipients[id] = index < names.length ? names[index] : id;
      }
    });
    _tabs.animateTo(0);
  }

  Future<void> _confirmDelete(
    ScheduledMessageService service,
    ScheduledMessageEntity item,
  ) async {
    if (_saving || _checkingAccess) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.sched_delete_title),
        content: Text(context.l10n.sched_delete_body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.sched_action_delete),
          ),
        ],
      ),
    );
    if (confirmed == true) await service.delete(item.id);
  }

  void _clearForm() {
    setState(() {
      _editingId = null;
      _editingSourceRecipients.clear();
      _content.clear();
      _selectedRecipients.clear();
      _days.clear();
      _repeat = ScheduledRepeat.once;
      _time = const TimeOfDay(hour: 9, minute: 0);
    });
  }

  String _formatTrigger(int milliseconds) {
    final date = DateTime.fromMillisecondsSinceEpoch(milliseconds);
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

bool _historyNeedsAccess(
  ScheduledMessageRecipientResult recipient,
  Conversation? conversation,
) => recipient.wasLocked || conversation == null || conversation.isLocked;

String _historyStatus(BuildContext context, ScheduledHistoryStatus status) =>
    switch (status) {
      ScheduledHistoryStatus.sent => context.l10n.sched_history_sent,
      ScheduledHistoryStatus.partialFailure =>
        context.l10n.sched_history_partial_failure,
      ScheduledHistoryStatus.failed => context.l10n.sched_history_failed,
    };

String _recipientStatus(
  BuildContext context,
  ScheduledRecipientOutcome outcome,
) => switch (outcome) {
  ScheduledRecipientOutcome.sent => context.l10n.sched_history_sent,
  ScheduledRecipientOutcome.encryptionFailed =>
    context.l10n.sched_history_encryption_failed,
  ScheduledRecipientOutcome.deliveryFailed =>
    context.l10n.sched_history_delivery_failed,
  ScheduledRecipientOutcome.failed => context.l10n.sched_history_failed,
};

IconData _historyIcon(ScheduledHistoryStatus status) => switch (status) {
  ScheduledHistoryStatus.sent => Icons.check_circle_outline,
  ScheduledHistoryStatus.partialFailure => Icons.warning_amber_outlined,
  ScheduledHistoryStatus.failed => Icons.error_outline,
};

String _historyTime(BuildContext context, int timestamp) {
  final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
  final l10n = MaterialLocalizations.of(context);
  return '${l10n.formatFullDate(date)} '
      '${l10n.formatTimeOfDay(TimeOfDay.fromDateTime(date), alwaysUse24HourFormat: true)}'
      ':${date.second.toString().padLeft(2, '0')}';
}

class _ScheduledHistoryDetails extends StatefulWidget {
  const _ScheduledHistoryDetails({required this.item});

  final ScheduledMessageHistoryEntity item;

  @override
  State<_ScheduledHistoryDetails> createState() =>
      _ScheduledHistoryDetailsState();
}

class _ScheduledHistoryDetailsState extends State<_ScheduledHistoryDetails>
    with WidgetsBindingObserver {
  StreamSubscription<List<Conversation>>? _subscription;
  Map<String, Conversation>? _conversations;
  final _authorized = <String>{};
  bool _checking = false;
  bool _foreground = true;
  bool _loadFailed = false;
  int _accessRevision = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscription ??= AppContainerScope.of(context).conversations
        .watchConversations()
        .listen(
          (items) {
            if (!mounted) return;
            final next = {for (final item in items) item.id: item};
            setState(() {
              for (final recipient in widget.item.recipients) {
                final id = recipient.recipientId;
                if (_conversations?[id]?.isLocked != next[id]?.isLocked) {
                  _authorized.remove(id);
                  _accessRevision++;
                }
              }
              _conversations = next;
              _loadFailed = false;
            });
          },
          onError: (Object _) {
            if (!mounted) return;
            setState(() {
              _conversations = null;
              _authorized.clear();
              _accessRevision++;
              _loadFailed = true;
            });
          },
        );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      _foreground = state == AppLifecycleState.resumed;
      if (!_foreground) _authorized.clear();
      if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.hidden) {
        _accessRevision++;
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool get _locked => widget.item.recipients.any(
    (recipient) =>
        _historyNeedsAccess(
          recipient,
          _conversations?[recipient.recipientId],
        ) &&
        !_authorized.contains(recipient.recipientId),
  );

  Future<void> _unlock() async {
    if (_checking || _conversations == null) return;
    final runtime = AppContainerScope.of(context).chatAccessRuntime;
    final revision = _accessRevision;
    setState(() => _checking = true);
    final authorized = <String>{};
    try {
      for (final recipient in widget.item.recipients) {
        final conversation = _conversations?[recipient.recipientId];
        if (!_historyNeedsAccess(recipient, conversation)) continue;
        final credentials = runtime.credentials;
        final hasPassword =
            credentials != null &&
            await credentials.hasCredential(recipient.recipientId);
        if (!mounted) return;
        final allowed = hasPassword
            ? await showVerifyChatPasswordDialog(
                context,
                chatName: recipient.recipientName,
                verify: (password) =>
                    credentials.verifyPassword(recipient.recipientId, password),
              )
            : await runtime.service.authorize(
                Conversation(
                  id: recipient.recipientId,
                  peerId: recipient.recipientId,
                  peerName: recipient.recipientName,
                  peerPhone: '',
                  isLocked: true,
                ),
              );
        if (!mounted || !allowed) return;
        authorized.add(recipient.recipientId);
      }
      if (mounted && revision == _accessRevision) {
        setState(() => _authorized.addAll(authorized));
      }
    } catch (_) {
      // Credential/plugin failures must leave the history content hidden.
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return AzureBackdrop(
      child: Scaffold(
        appBar: AppBar(title: Text(context.l10n.sched_history_details)),
        body: !_foreground
            ? const SizedBox.shrink()
            : _loadFailed
            ? Center(child: Text(context.l10n.background_unavailable))
            : _conversations == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    context.l10n.sched_history_executed_at,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  Text(_historyTime(context, item.executedAt)),
                  const SizedBox(height: 16),
                  Text(
                    context.l10n.sched_history_status,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  Text(_historyStatus(context, item.status)),
                  const Divider(height: 32),
                  if (_locked) ...[
                    Text(context.l10n.sched_history_locked),
                    const SizedBox(height: 12),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: FilledButton.icon(
                        key: const ValueKey('scheduled-history-unlock'),
                        onPressed: _checking ? null : _unlock,
                        icon: const Icon(Icons.lock_open),
                        label: Text(context.l10n.chat_lock_unlock_action),
                      ),
                    ),
                  ] else ...[
                    Text(
                      context.l10n.message_content,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    if (item.contentRetained)
                      SelectableText(item.messageContent)
                    else
                      Text(context.l10n.sched_history_content_omitted),
                    const Divider(height: 32),
                    Text(
                      context.l10n.recipients,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    for (final recipient in item.recipients)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SelectableText(recipient.recipientName),
                            SelectableText(recipient.recipientId),
                            Text(_recipientStatus(context, recipient.outcome)),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
      ),
    );
  }
}

/// Haftanin gunlerini secen acilir alan.
///
/// Onceden yedi ayri `FilterChip` yan yana duruyordu: dar ekranda iki satira
/// sariyor, secili olanlar dagilinca "hangi gunler secili" tek bakista
/// okunamiyordu. Burada alan kapaliyken secimi OZETLIYOR.
///
/// Tek secimlik bir `DropdownButton` kullanilamaz: zamanlama modeli birden
/// cok gun tasiyor (`ScheduledDraft.days` bir `Set<int>`), yani secim
/// coklu olmak zorunda. Bu yuzden acilir gorunumlu bir alan, iceride onay
/// kutulariyla birlikte.
class _WeekdayField extends StatelessWidget {
  const _WeekdayField({required this.selected, required this.onChanged});

  /// ISO 8601 gun numaralari: 1 = Pazartesi ... 7 = Pazar.
  final Set<int> selected;
  final ValueChanged<Set<int>> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final names = l10n.weekdays_short.split(',');
    final ordered = selected.toList()..sort();
    final summary = ordered.isEmpty
        ? l10n.schedule_days_empty
        : ordered.map((day) => names[day - 1]).join(', ');
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () async {
        final result = await showDialog<Set<int>>(
          context: context,
          builder: (dialogContext) => _WeekdayDialog(selected: selected),
        );
        if (result != null) onChanged(result);
      },
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: l10n.schedule_days_label,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.arrow_drop_down),
        ),
        child: Text(
          summary,
          style: ordered.isEmpty
              ? TextStyle(color: scheme.onSurfaceVariant)
              : null,
        ),
      ),
    );
  }
}

class _WeekdayDialog extends StatefulWidget {
  const _WeekdayDialog({required this.selected});

  final Set<int> selected;

  @override
  State<_WeekdayDialog> createState() => _WeekdayDialogState();
}

class _WeekdayDialogState extends State<_WeekdayDialog> {
  late final Set<int> _draft = {...widget.selected};

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final names = l10n.weekdays_short.split(',');
    return AlertDialog(
      title: Text(l10n.schedule_days_label),
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (var day = 1; day <= 7; day++)
              CheckboxListTile(
                value: _draft.contains(day),
                title: Text(names[day - 1]),
                onChanged: (checked) => setState(() {
                  checked == true ? _draft.add(day) : _draft.remove(day);
                }),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => setState(() {
            // Hepsi seciliyse temizler, degilse tamamlar: tek dugmeyle iki
            // yonlu, ayri bir "temizle" dugmesine gerek kalmiyor.
            if (_draft.length == 7) {
              _draft.clear();
            } else {
              _draft.addAll([for (var day = 1; day <= 7; day++) day]);
            }
          }),
          child: Text(l10n.select_all),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _draft),
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
