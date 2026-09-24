import 'package:flutter/material.dart';
import '../../bulk/bulk_message_service.dart';

import '../../l10n/l10n.dart';
import '../../services/app_container.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _compose());
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
      _recipients = ConversationRecipients(AppContainerScope.of(context));
    });
  }

  @override
  Widget build(BuildContext context) {
    final BulkMessageSender? service = AppContainerScope.of(
      context,
    ).bulkRuntime?.service;
    if (_message == null || service == null)
      return Scaffold(
        appBar: AppBar(title: Text(context.l10n.conv_bulk_message)),
        body: service == null
            ? Center(child: Text(context.l10n.bulk_unavailable))
            : const SizedBox.shrink(),
      );
    return RecipientPickerScreen(
      title: context.l10n.conv_bulk_message,
      actionLabel: context.l10n.send,
      choices: _recipients!.choices,
      onConfirm: (selected) async {
        final resolved = await _recipients!.resolve(selected);
        final pending = resolved
            .map((item) => item.id)
            .toSet()
            .difference(_sent);
        if (pending.isEmpty) return true;
        final result = await service.send(_message!, pending);
        _sent.addAll(pending.difference(result.failed.keys.toSet()));
        if (context.mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.l10n.bulk_result(result.sent, result.failed.length),
              ),
            ),
          );
        return result.failed.isEmpty;
      },
    );
  }
}
