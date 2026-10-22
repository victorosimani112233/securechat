import 'dart:async';

import 'package:flutter/material.dart';

import '../../bulk/broadcast_lists.dart';
import '../../bulk/bulk_message_service.dart';
import '../../l10n/l10n.dart';
import '../../services/app_container.dart';
import '../../widgets/azure_backdrop.dart';
import '../../widgets/text_controller_scope.dart';
import '../contacts/recipient_picker_screen.dart';
import '../contacts/conversation_recipients.dart';

class BulkMessageScreen extends StatefulWidget {
  const BulkMessageScreen({super.key});
  @override
  State<BulkMessageScreen> createState() => _BulkMessageScreenState();
}

class _BulkMessageScreenState extends State<BulkMessageScreen> {
  String? _message;
  ConversationRecipients? _recipients;
  final _sent = <String>{};

  /// Kayitli listeler; liste yoksa dogrudan kisi secimine gecilir.
  List<BroadcastList> _lists = const [];
  StreamSubscription<List<BroadcastList>>? _listSubscription;

  /// Kisi secicisi acik mi; kapaliyken kayitli listeler gosterilir.
  bool _picking = false;

  /// Secici bir listeden acildiysa o listenin adi ve uyeleri.
  BroadcastList? _fromList;
  List<RecipientChoice> _initial = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _compose());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _listSubscription ??= AppContainerScope.of(context).bulkRuntime?.lists
        ?.watch()
        .listen((lists) {
          if (mounted) setState(() => _lists = lists);
        });
  }

  @override
  void dispose() {
    _listSubscription?.cancel();
    super.dispose();
  }

  Future<void> _compose() async {
    if (!mounted) return;
    final message = await showDialog<String>(
      context: context,
      builder: (context) => TextControllerScope(
        builder: (context, controller) => AlertDialog(
          title: Text(context.l10n.conv_bulk_message),
          content: TextField(
            key: const ValueKey('bulk-message-input'),
            controller: controller,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            maxLength: 10000,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: context.l10n.message_content,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.cancel),
            ),
            ValueListenableBuilder(
              valueListenable: controller,
              builder: (context, value, _) => FilledButton(
                onPressed: value.text.trim().isEmpty
                    ? null
                    : () => Navigator.pop(context, value.text.trim()),
                child: Text(context.l10n.continue_action),
              ),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (message == null) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _message = message;
      _recipients = ConversationRecipients(
        AppContainerScope.of(context),
        unknownLabel: context.l10n.unknown_contact,
      );
    });
  }

  Future<void> _openList(BroadcastList? list) async {
    var initial = const <RecipientChoice>[];
    if (list != null) {
      final byId = await _choicesCovering(list.memberIds);
      // Silinen sohbetler sessizce dusulur; kalanlar secili gelir.
      initial = [for (final id in list.memberIds) ?byId[id]];
    }
    if (!mounted) return;
    setState(() {
      _fromList = list;
      _initial = initial;
      _picking = true;
    });
  }

  /// Sohbetler ve rehber ayri akislardan gelir; ilk yayinda rehber
  /// kisileri henuz olmayabilir. Listedeki herkes bulunana ya da kisa bir
  /// sure dolana kadar beklenir.
  Future<Map<String, RecipientChoice>> _choicesCovering(
    List<String> ids,
  ) async {
    var latest = <String, RecipientChoice>{};
    final done = Completer<void>();
    final subscription = _recipients!.choices.listen((choices) {
      latest = {for (final choice in choices) choice.id: choice};
      if (ids.every(latest.containsKey) && !done.isCompleted) done.complete();
    });
    try {
      await done.future.timeout(
        const Duration(milliseconds: 800),
        onTimeout: () {},
      );
    } finally {
      // Kapanis alt akislarin bitmesini bekler; sonuc zaten elimizde.
      unawaited(subscription.cancel());
    }
    return latest;
  }

  Future<void> _saveList(
    BroadcastListStore store,
    List<RecipientChoice> selected,
  ) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => TextControllerScope(
        initialText: _fromList?.name ?? '',
        builder: (context, controller) => AlertDialog(
          title: Text(context.l10n.bulk_list_save),
          content: TextField(
            key: const ValueKey('bulk-list-name'),
            controller: controller,
            autofocus: true,
            maxLength: maxBroadcastListNameLength,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: context.l10n.bulk_list_name),
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
      ),
    );
    if (name == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      final saved = await store.save(name, selected.map((item) => item.id));
      if (mounted) setState(() => _fromList = saved);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.bulk_list_saved(saved.name))),
      );
    } on BroadcastListException catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(switch (error.reason) {
            BroadcastListError.emptyName => l10n.bulk_list_error_name,
            BroadcastListError.noMembers => l10n.recipient_action_failed,
            BroadcastListError.tooManyMembers ||
            BroadcastListError.tooManyLists => l10n.bulk_list_error_limit,
          }),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final runtime = AppContainerScope.of(context).bulkRuntime;
    final BulkMessageSender? service = runtime?.service;
    if (_message == null || service == null) {
      return Scaffold(
        appBar: AppBar(title: Text(context.l10n.conv_bulk_message)),
        body: service == null
            ? Center(child: Text(context.l10n.bulk_unavailable))
            : const SizedBox.shrink(),
      );
    }
    final store = runtime?.lists;
    if (!_picking && _lists.isNotEmpty && store != null) {
      return _BroadcastListChooser(
        lists: _lists,
        onSelected: _openList,
        onDelete: (list) => store.delete(list.id),
      );
    }
    final picker = RecipientPickerScreen(
      // Listeden acilan secici yeni bir secimle yeniden kurulmali.
      key: ValueKey('bulk-picker-${_fromList?.id}'),
      title: _fromList?.name ?? context.l10n.conv_bulk_message,
      actionLabel: context.l10n.send,
      choices: _recipients!.choices,
      initial: _initial,
      selectionAction: store == null
          ? null
          : RecipientSelectionAction(
              icon: Icons.bookmark_add_outlined,
              tooltip: context.l10n.bulk_list_save,
              onPressed: (selected) => _saveList(store, selected),
            ),
      onConfirm: (selected) async {
        final resolved = await _recipients!.resolve(selected);
        final pending = resolved
            .map((item) => item.id)
            .toSet()
            .difference(_sent);
        if (pending.isEmpty) return true;
        final result = await service.send(_message!, pending);
        _sent.addAll(pending.difference(result.failed.keys.toSet()));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.l10n.bulk_result(result.sent, result.failed.length),
              ),
            ),
          );
        }
        return result.failed.isEmpty;
      },
    );
    if (_lists.isEmpty) return picker;
    // Geri tusu once kayitli listelere doner.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _picking = false);
      },
      child: picker,
    );
  }
}

class _BroadcastListChooser extends StatelessWidget {
  const _BroadcastListChooser({
    required this.lists,
    required this.onSelected,
    required this.onDelete,
  });

  final List<BroadcastList> lists;
  final ValueChanged<BroadcastList?> onSelected;
  final ValueChanged<BroadcastList> onDelete;

  @override
  Widget build(BuildContext context) => AzureBackdrop(
    child: Scaffold(
      appBar: AppBar(title: Text(context.l10n.bulk_choose_recipients)),
      body: SafeArea(
        child: ListView(
          children: [
            ListTile(
              key: const ValueKey('bulk-new-selection'),
              leading: const Icon(Icons.checklist_outlined),
              title: Text(context.l10n.bulk_new_selection),
              onTap: () => onSelected(null),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                context.l10n.bulk_saved_lists,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            for (final list in lists)
              ListTile(
                key: ValueKey('bulk-list-${list.id}'),
                leading: const Icon(Icons.campaign_outlined),
                title: Text(
                  list.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  context.l10n.bulk_list_members(list.memberIds.length),
                ),
                onTap: () => onSelected(list),
                trailing: IconButton(
                  key: ValueKey('bulk-list-delete-${list.id}'),
                  tooltip: context.l10n.bulk_list_delete,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => onDelete(list),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
