import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../widgets/avatar.dart';
import '../../widgets/azure_backdrop.dart';
import '../../widgets/azure_surface.dart';

class RecipientChoice {
  const RecipientChoice({
    required this.id,
    required this.name,
    this.detail = '',
    this.isGroup = false,
  });
  final String id;
  final String name;
  final String detail;
  final bool isGroup;
}

/// Selection is local to this route; cancelling never changes the caller's draft.
class RecipientPickerScreen extends StatefulWidget {
  const RecipientPickerScreen({
    super.key,
    required this.title,
    required this.actionLabel,
    required this.choices,
    this.initial = const [],
    this.allowEmpty = false,
    this.onConfirm,
  });
  final String title;
  final String actionLabel;
  final Stream<List<RecipientChoice>> choices;
  final List<RecipientChoice> initial;
  final bool allowEmpty;
  final Future<bool> Function(List<RecipientChoice>)? onConfirm;

  @override
  State<RecipientPickerScreen> createState() => _RecipientPickerScreenState();
}

class _RecipientPickerScreenState extends State<RecipientPickerScreen> {
  late final _selected = {for (final item in widget.initial) item.id: item};
  String _query = '';
  bool _busy = false;

  Future<void> _confirm() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final selected = _selected.values.toList(growable: false);
      final close = await widget.onConfirm?.call(selected) ?? true;
      if (mounted && close) Navigator.pop(context, selected);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.recipient_action_failed)),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AzureBackdrop(
      child: Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: TextField(
                  key: const ValueKey('recipient-search'),
                  enabled: !_busy,
                  onChanged: (value) =>
                      setState(() => _query = value.trim().toLowerCase()),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: context.l10n.create_group_search_placeholder,
                  ),
                ),
              ),
              if (_selected.isNotEmpty)
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * .22,
                  ),
                  child: SingleChildScrollView(
                    key: const ValueKey('selected-recipients'),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          for (final item in _selected.values)
                            InputChip(
                              key: ValueKey('recipient-chip-${item.id}'),
                              avatar: GeneratedAvatar(
                                name: item.name,
                                size: 24,
                                isGroup: item.isGroup,
                              ),
                              label: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth:
                                      (MediaQuery.sizeOf(context).width - 150)
                                          .clamp(60, 180),
                                ),
                                child: Text(
                                  item.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              onDeleted: _busy
                                  ? null
                                  : () => setState(
                                      () => _selected.remove(item.id),
                                    ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: StreamBuilder<List<RecipientChoice>>(
                  stream: widget.choices,
                  builder: (context, snapshot) {
                    if (snapshot.hasError)
                      return Center(
                        child: Text(context.l10n.recipient_action_failed),
                      );
                    if (!snapshot.hasData)
                      return const Center(child: CircularProgressIndicator());
                    final unique = {
                      for (final item in snapshot.data!) item.id: item,
                    };
                    final visible = unique.values
                        .where(
                          (item) =>
                              item.name.toLowerCase().contains(_query) ||
                              item.detail.toLowerCase().contains(_query),
                        )
                        .toList();
                    if (visible.isEmpty)
                      return Center(child: Text(context.l10n.bulk_no_results));
                    return ListView.separated(
                      key: const ValueKey('recipient-list'),
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 7),
                      itemBuilder: (context, index) {
                        final item = visible[index];
                        return AzureSurface(
                          child: CheckboxListTile(
                            key: ValueKey('recipient-${item.id}'),
                            value: _selected.containsKey(item.id),
                            secondary: GeneratedAvatar(
                              name: item.name,
                              isGroup: item.isGroup,
                              size: 40,
                            ),
                            title: Text(item.name),
                            subtitle: item.detail.isEmpty
                                ? null
                                : Text(item.detail),
                            onChanged: _busy
                                ? null
                                : (checked) => setState(() {
                                    if (checked == true) {
                                      _selected[item.id] = item;
                                    } else {
                                      _selected.remove(item.id);
                                    }
                                  }),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const ValueKey('recipient-confirm'),
                    onPressed:
                        _busy || (_selected.isEmpty && !widget.allowEmpty)
                        ? null
                        : _confirm,
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text(
                      widget.actionLabel,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
