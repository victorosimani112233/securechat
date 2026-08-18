import 'package:flutter/material.dart';

import '../../bulk/bulk_message_service.dart';
import '../../l10n/l10n.dart';
import '../../services/app_container.dart';
import '../../storage/storage_entities.dart';
import '../../widgets/avatar.dart';
import '../../widgets/azure_backdrop.dart';

class BulkMessageScreen extends StatefulWidget {
  const BulkMessageScreen({super.key});
  @override
  State<BulkMessageScreen> createState() => _BulkMessageScreenState();
}

class _BulkMessageScreenState extends State<BulkMessageScreen> {
  final _message = TextEditingController();
  final _selected = <String>{};
  bool _busy = false;
  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = AppContainerScope.of(context).bulkRuntime?.service;
    return AzureBackdrop(
      child: Scaffold(
        appBar: AppBar(title: Text(context.l10n.settings_bulk_message)),
        body: service == null
            ? Center(child: Text(context.l10n.bulk_unavailable))
            : StreamBuilder<List<ConversationEntity>>(
                stream: service.watchConversations(),
                builder: (context, snapshot) {
                  final conversations = snapshot.data ?? const [];
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: TextField(
                          controller: _message,
                          minLines: 3,
                          maxLines: 6,
                          decoration: InputDecoration(
                            labelText: context.l10n.message_content,
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(context.l10n.recipients),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => setState(() {
                              _selected.length == conversations.length
                                  ? _selected.clear()
                                  : _selected.addAll(
                                      conversations.map((c) => c.id),
                                    );
                            }),
                            child: Text(
                              _selected.length == conversations.length
                                  ? context.l10n.cd_clear
                                  : context.l10n.select_all,
                            ),
                          ),
                        ],
                      ),
                      Expanded(
                        child: ListView(
                          children: [
                            for (final c in conversations)
                              CheckboxListTile(
                                secondary: GeneratedAvatar(
                                  name: c.peerName,
                                  size: 40,
                                ),
                                title: Text(c.peerName),
                                subtitle: Text(
                                  c.isGroup ? context.l10n.group : c.peerPhone,
                                ),
                                value: _selected.contains(c.id),
                                onChanged: _busy
                                    ? null
                                    : (value) => setState(
                                        () => value == true
                                            ? _selected.add(c.id)
                                            : _selected.remove(c.id),
                                      ),
                              ),
                          ],
                        ),
                      ),
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: FilledButton.icon(
                            onPressed: _busy || _selected.isEmpty
                                ? null
                                : () => _send(service),
                            icon: _busy
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.send),
                            label: Text(
                              context.l10n.send_to_recipients(_selected.length),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }

  Future<void> _send(BulkMessageService service) async {
    if (_message.text.trim().isEmpty) return;
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
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
