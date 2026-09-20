import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../security/chat_lock_credential_service.dart';

Future<String?> showCreateChatPasswordDialog(BuildContext context) =>
    showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _CreateChatPasswordDialog(),
    );

Future<bool> showVerifyChatPasswordDialog(
  BuildContext context, {
  required String chatName,
  required Future<bool> Function(String password) verify,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _VerifyChatPasswordDialog(chatName: chatName, verify: verify),
    ) ??
    false;

class _CreateChatPasswordDialog extends StatefulWidget {
  const _CreateChatPasswordDialog();

  @override
  State<_CreateChatPasswordDialog> createState() =>
      _CreateChatPasswordDialogState();
}

class _CreateChatPasswordDialogState extends State<_CreateChatPasswordDialog> {
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  void _submit() {
    final password = _password.text;
    if (password.length < ChatLockCredentialService.minPasswordLength) {
      setState(() => _error = context.l10n.password_too_short);
      return;
    }
    if (password != _repeat.text) {
      setState(() => _error = context.l10n.password_mismatch);
      return;
    }
    Navigator.pop(context, password);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.l10n.chat_lock_create_title),
    content: AutofillGroup(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(context.l10n.chat_lock_create_body),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('chat-lock-password'),
            controller: _password,
            autofocus: true,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            autofillHints: const [AutofillHints.newPassword],
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: context.l10n.password,
              helperText: context.l10n.password_min_length,
              errorText: _error,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('chat-lock-password-repeat'),
            controller: _repeat,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            autofillHints: const [AutofillHints.newPassword],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: context.l10n.password_repeat,
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
      FilledButton(
        key: const ValueKey('chat-lock-create-submit'),
        onPressed: _submit,
        child: Text(context.l10n.confirm),
      ),
    ],
  );
}

class _VerifyChatPasswordDialog extends StatefulWidget {
  const _VerifyChatPasswordDialog({
    required this.chatName,
    required this.verify,
  });

  final String chatName;
  final Future<bool> Function(String password) verify;

  @override
  State<_VerifyChatPasswordDialog> createState() =>
      _VerifyChatPasswordDialogState();
}

class _VerifyChatPasswordDialogState extends State<_VerifyChatPasswordDialog> {
  final _password = TextEditingController();
  bool _checking = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_checking || _password.text.isEmpty) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    final valid = await widget.verify(_password.text);
    if (!mounted) return;
    if (valid) {
      Navigator.pop(context, true);
      return;
    }
    _password.clear();
    setState(() {
      _checking = false;
      _error = context.l10n.chat_lock_wrong_password;
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.l10n.chat_lock_unlock_title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(context.l10n.chat_lock_unlock_body(widget.chatName)),
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey('chat-unlock-password'),
          controller: _password,
          autofocus: true,
          obscureText: true,
          enabled: !_checking,
          enableSuggestions: false,
          autocorrect: false,
          autofillHints: const [AutofillHints.password],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: context.l10n.password,
            errorText: _error,
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: _checking ? null : () => Navigator.pop(context, false),
        child: Text(context.l10n.cancel),
      ),
      FilledButton(
        key: const ValueKey('chat-unlock-submit'),
        onPressed: _checking ? null : _submit,
        child: _checking
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(context.l10n.chat_lock_unlock_action),
      ),
    ],
  );
}
