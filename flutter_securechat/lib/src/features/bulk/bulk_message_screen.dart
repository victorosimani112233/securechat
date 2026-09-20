import 'package:flutter/material.dart';

import '../../bulk/bulk_message_service.dart';
import '../../l10n/l10n.dart';
import '../../services/app_container.dart';
import '../../storage/storage_entities.dart';
import '../../widgets/avatar.dart';
import '../../widgets/azure_backdrop.dart';
import '../../widgets/azure_empty_state.dart';
import '../../widgets/azure_surface.dart';

class BulkMessageScreen extends StatefulWidget {
  const BulkMessageScreen({super.key});

  @override
  State<BulkMessageScreen> createState() => _BulkMessageScreenState();
}

class _BulkMessageScreenState extends State<BulkMessageScreen> {
  final _message = TextEditingController();
  final _search = TextEditingController();
  final _selected = <String>{};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Gonderim dugmesinin etkinligi mesaj alanina bagli; metin degistikce
    // yeniden cizilmesi gerekiyor.
    _message.addListener(_onChanged);
    _search.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _message.dispose();
    _search.dispose();
    super.dispose();
  }

  List<ConversationEntity> _visible(List<ConversationEntity> all) {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return all;
    return all
        .where(
          (c) =>
              c.peerName.toLowerCase().contains(query) ||
              c.peerPhone.toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final service = AppContainerScope.of(context).bulkRuntime?.service;
    return AzureBackdrop(
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.settings_bulk_message)),
        body: service == null
            ? Center(child: Text(l10n.bulk_unavailable))
            : StreamBuilder<List<ConversationEntity>>(
                stream: service.watchConversations(),
                builder: (context, snapshot) {
                  final all = snapshot.data ?? const <ConversationEntity>[];
                  final visible = _visible(all);
                  return Column(
                    children: [
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                          children: [
                            _explainer(context),
                            const SizedBox(height: 12),
                            _composer(context),
                            const SizedBox(height: 12),
                            _recipientHeader(context, all, visible),
                            const SizedBox(height: 6),
                            if (all.isEmpty)
                              AzureEmptyState(
                                icon: Icons.forum_outlined,
                                title: l10n.bulk_no_recipients,
                              )
                            else if (visible.isEmpty)
                              AzureEmptyState(
                                icon: Icons.search_off,
                                title: l10n.bulk_no_results,
                              )
                            else
                              AzureSurface(
                                child: Column(
                                  children: [
                                    for (final c in visible)
                                      _recipientRow(context, c),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      _sendBar(context, service),
                    ],
                  );
                },
              ),
      ),
    );
  }

  /// Ozelligin ne yaptigini anlatan kart.
  ///
  /// "Toplu mesaj" adi yaniltici olabiliyor: grup kurdugu sanilabilir.
  /// Alicilarin birbirini GORMEDIGI bir gizlilik ayrintisi ve kullanicinin
  /// gondermeden once bilmesi gerekiyor.
  Widget _explainer(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return AzureSurface(
      padding: const EdgeInsets.all(14),
      borderColor: scheme.primary.withValues(alpha: .35),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.call_split, size: 20, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.bulk_explainer_title,
                  style: text.titleSmall?.copyWith(color: scheme.primary),
                ),
                const SizedBox(height: 4),
                Text(
                  context.l10n.bulk_explainer_body,
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _composer(BuildContext context) => AzureSurface(
    padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
    child: TextField(
      controller: _message,
      minLines: 3,
      maxLines: 8,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        labelText: context.l10n.message_content,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
      ),
    ),
  );

  Widget _recipientHeader(
    BuildContext context,
    List<ConversationEntity> all,
    List<ConversationEntity> visible,
  ) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final allSelected =
        visible.isNotEmpty && visible.every((c) => _selected.contains(c.id));
    return Column(
      children: [
        Row(
          children: [
            Text(l10n.recipients, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(width: 8),
            // Secili sayisi listeye bakmadan gorunsun: uzun listede kac kisi
            // secildigi kayboluyordu.
            if (_selected.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  l10n.bulk_selected_count(_selected.length, all.length),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.primary,
                  ),
                ),
              ),
            const Spacer(),
            if (visible.isNotEmpty)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        // Yalniz GORUNEN kayitlari etkiler: arama aciksa
                        // gorunmeyen bir sohbeti secmek sasirtici olurdu.
                        allSelected
                            ? _selected.removeAll(visible.map((c) => c.id))
                            : _selected.addAll(visible.map((c) => c.id));
                      }),
                child: Text(allSelected ? l10n.cd_clear : l10n.select_all),
              ),
          ],
        ),
        if (all.length > 6)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: l10n.bulk_search_hint,
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: _search.clear,
                      ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _recipientRow(BuildContext context, ConversationEntity c) {
    final selected = _selected.contains(c.id);
    return CheckboxListTile(
      value: selected,
      secondary: GeneratedAvatar(
        name: c.peerName,
        size: 40,
        isGroup: c.isGroup,
      ),
      title: Text(c.peerName),
      subtitle: Text(c.isGroup ? context.l10n.group : c.peerPhone),
      onChanged: _busy
          ? null
          : (value) => setState(
              () => value == true
                  ? _selected.add(c.id)
                  : _selected.remove(c.id),
            ),
    );
  }

  Widget _sendBar(BuildContext context, BulkMessageSender service) {
    final l10n = context.l10n;
    final hasMessage = _message.text.trim().isNotEmpty;
    final ready = hasMessage && _selected.isNotEmpty && !_busy;
    return AzureSurface(
      radius: 0,
      elevation: 3,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Dugme neden kapali, yazili olarak soylensin. Oncesinde bos
              // mesajla basildiginda hicbir sey olmuyordu ve sebebi
              // gorunmuyordu.
              if (!hasMessage && _selected.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    l10n.bulk_message_required,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: ready ? () => _send(service) : null,
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  label: Text(l10n.send_to_recipients(_selected.length)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _send(BulkMessageSender service) async {
    setState(() => _busy = true);
    try {
      final result = await service.send(_message.text, _selected);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.bulk_result(result.sent, result.failed.length),
          ),
        ),
      );
      if (result.failed.isEmpty) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
