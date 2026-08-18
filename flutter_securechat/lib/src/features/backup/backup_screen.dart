import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../backup/backup_service.dart';
import '../../l10n/l10n.dart';
import '../../services/app_container.dart';
import '../../widgets/azure_backdrop.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;
  List<File> _backups = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reload();
  }

  Future<void> _reload() async {
    final service = AppContainerScope.of(context).backupRuntime?.service;
    if (service == null) return;
    final files = await service.localBackups();
    if (mounted) setState(() => _backups = files);
  }

  @override
  Widget build(BuildContext context) {
    return AzureBackdrop(
      child: Scaffold(
        appBar: AppBar(title: Text(context.l10n.encrypted_backup)),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(context.l10n.backup_explanation),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _create,
              icon: const Icon(Icons.backup_outlined),
              label: Text(context.l10n.create_backup),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pickRestore,
              icon: const Icon(Icons.restore),
              label: Text(context.l10n.restore_backup_file),
            ),
            if (_busy) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 28),
            Text(
              context.l10n.backups_on_device,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (_backups.isEmpty)
              ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: Text(context.l10n.no_local_backups),
              )
            else
              for (final file in _backups)
                ListTile(
                  leading: const Icon(Icons.enhanced_encryption_outlined),
                  title: Text(file.uri.pathSegments.last),
                  subtitle: Text(_fileInfo(file)),
                  trailing: const Icon(Icons.restore),
                  onTap: _busy ? null : () => _restore(file),
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _create() async {
    final password = await _passwordDialog(
      title: context.l10n.backup_password,
      confirm: true,
    );
    if (password == null || !mounted) return;
    final service = AppContainerScope.of(context).backupRuntime?.service;
    if (service == null) return _notice(context.l10n.backup_unavailable);
    setState(() => _busy = true);
    try {
      final file = await service.createBackup(password);
      await FilePicker.platform.saveFile(
        dialogTitle: context.l10n.save_encrypted_backup,
        fileName: file.uri.pathSegments.last,
        type: FileType.custom,
        allowedExtensions: const [BackupService.extension],
        bytes: await file.readAsBytes(),
      );
      if (mounted) _notice(context.l10n.backup_created);
    } on FormatException catch (error) {
      if (mounted) _notice(error.message);
    } catch (error) {
      if (mounted) _notice(context.l10n.backup_create_failed('$error'));
    } finally {
      if (mounted) setState(() => _busy = false);
      await _reload();
    }
  }

  Future<void> _pickRestore() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [BackupService.extension],
      allowMultiple: false,
    );
    final path = result?.files.single.path;
    if (path != null) await _restore(File(path));
  }

  Future<void> _restore(File file) async {
    final password = await _passwordDialog(title: context.l10n.backup_password);
    if (password == null || !mounted) return;
    final service = AppContainerScope.of(context).backupRuntime?.service;
    if (service == null) return _notice(context.l10n.backup_unavailable);
    setState(() => _busy = true);
    final result = await service.restoreBackup(file, password);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result) {
      case BackupRestoreSuccess():
        _notice(context.l10n.backup_restored);
        await _reload();
      case BackupWrongPassword():
        _notice(context.l10n.wrong_password_attempts(result.remainingAttempts));
      case BackupAttemptsExhausted():
        _notice(
          result.deleted
              ? context.l10n.backup_deleted_after_attempts
              : context.l10n.backup_delete_failed_after_attempts,
        );
      case BackupRestoreFailure():
        _notice(result.message);
    }
  }

  Future<String?> _passwordDialog({
    required String title,
    bool confirm = false,
  }) async {
    final first = TextEditingController();
    final second = TextEditingController();
    String? error;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: first,
                obscureText: true,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: context.l10n.password,
                  helperText: context.l10n.password_min_length,
                ),
              ),
              if (confirm)
                TextField(
                  controller: second,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: context.l10n.password_repeat,
                  ),
                ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () {
                if (first.text.length < 8) {
                  setDialogState(() => error = context.l10n.password_too_short);
                } else if (confirm && first.text != second.text) {
                  setDialogState(() => error = context.l10n.password_mismatch);
                } else {
                  Navigator.pop(dialogContext, first.text);
                }
              },
              child: Text(
                confirm
                    ? context.l10n.create_group_action
                    : context.l10n.restore,
              ),
            ),
          ],
        ),
      ),
    );
    first.dispose();
    second.dispose();
    return result;
  }

  void _notice(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  static String _fileInfo(File file) {
    final kb = file.lengthSync() / 1024;
    final date = file.lastModifiedSync().toLocal();
    return '${kb.toStringAsFixed(1)} KB · '
        '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
