import 'package:flutter/material.dart';

import '../../background/scheduled_message_service.dart';
import '../../core/models.dart';
import '../../l10n/l10n.dart';
import '../../services/app_container.dart';
import '../../storage/storage_entities.dart';
import '../../widgets/azure_backdrop.dart';

class ScheduledMessagesScreen extends StatefulWidget {
  const ScheduledMessagesScreen({super.key});

  @override
  State<ScheduledMessagesScreen> createState() =>
      _ScheduledMessagesScreenState();
}

class _ScheduledMessagesScreenState extends State<ScheduledMessagesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _content = TextEditingController();
  final _selectedRecipients = <String, String>{};
  final _days = <int>{};
  TimeOfDay _time = const TimeOfDay(hour: 9, minute: 0);
  ScheduledRepeat _repeat = ScheduledRepeat.once;
  String? _editingId;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final runtime = AppContainerScope.of(context).backgroundRuntime;
    return AzureBackdrop(
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.l10n.sched_title),
          bottom: TabBar(
            controller: _tabs,
            tabs: [
              Tab(text: context.l10n.sched_tab_create),
              Tab(text: context.l10n.sched_tab_existing),
            ],
          ),
        ),
        body: runtime == null
            ? Center(child: Text(context.l10n.background_unavailable))
            : TabBarView(
                controller: _tabs,
                children: [
                  _buildForm(runtime.scheduledMessages),
                  _buildList(runtime.scheduledMessages),
                ],
              ),
      ),
    );
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
          Wrap(
            spacing: 6,
            children: List.generate(7, (index) {
              final day = index + 1;
              return FilterChip(
                label: Text(context.l10n.weekdays_short.split(',')[index]),
                selected: _days.contains(day),
                onSelected: (_) => setState(() {
                  _days.contains(day) ? _days.remove(day) : _days.add(day);
                }),
              );
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
          onPressed: () => _save(service),
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
            return Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.schedule)),
                title: Text(
                  item.messageContent,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${_formatTrigger(item.nextTriggerTime)} · ${item.recipientNames}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: item.isEnabled,
                      onChanged: (value) => service.setEnabled(item.id, value),
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

  Future<void> _pickRecipients() async {
    final conversations = AppContainerScope.of(context).conversations;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.sched_pick_recipient),
        content: SizedBox(
          width: 420,
          child: StreamBuilder<List<Conversation>>(
            stream: conversations.watchConversations(),
            builder: (context, snapshot) {
              final items = snapshot.data ?? const [];
              return StatefulBuilder(
                builder: (context, setDialogState) => ListView.builder(
                  shrinkWrap: true,
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return CheckboxListTile(
                      value: _selectedRecipients.containsKey(item.id),
                      title: Text(item.peerName),
                      secondary: Icon(
                        item.isGroup ? Icons.group : Icons.person,
                      ),
                      onChanged: (_) {
                        setDialogState(() {
                          _selectedRecipients.containsKey(item.id)
                              ? _selectedRecipients.remove(item.id)
                              : _selectedRecipients[item.id] = item.peerName;
                        });
                        setState(() {});
                      },
                    );
                  },
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.l10n.action_ok),
          ),
        ],
      ),
    );
  }

  Future<void> _save(ScheduledMessageService service) async {
    try {
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
    }
  }

  void _edit(ScheduledMessageEntity item) {
    setState(() {
      _editingId = item.id;
      _content.text = item.messageContent;
      _time = TimeOfDay(hour: item.hour, minute: item.minute);
      _repeat = ScheduledMessageService.parseRepeat(item.repeatType);
      _days
        ..clear()
        ..addAll(ScheduledMessageService.parseDays(item.repeatDays));
      _selectedRecipients.clear();
      final ids = item.recipientIds.split(',');
      final names = item.recipientNames.split(',');
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
