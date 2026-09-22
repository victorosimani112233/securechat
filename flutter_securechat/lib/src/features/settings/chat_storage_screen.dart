import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../l10n/l10n.dart';
import '../../services/app_container.dart';
import '../../storage/storage_management_service.dart';
import '../../widgets/azure_backdrop.dart';
import '../../widgets/chat_lock_dialog.dart';

class ChatStorageScreen extends StatefulWidget {
  const ChatStorageScreen({
    super.key,
    required this.conversationId,
    required this.service,
  });
  final String conversationId;
  final StorageManagementService service;

  @override
  State<ChatStorageScreen> createState() => _ChatStorageScreenState();
}

class _ChatStorageScreenState extends State<ChatStorageScreen>
    with WidgetsBindingObserver {
  final _selected = <String>{};
  List<ChatStorageFile> _files = const [];
  StorageFileCategory? _filter;
  String? _title;
  bool _busy = false;
  bool _failed = false;
  bool _authorized = false;
  bool _foreground = true;
  int _accessRevision = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    setState(() {
      _foreground = state == AppLifecycleState.resumed;
      if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.hidden) {
        _accessRevision++;
        _authorized = false;
        _files = const [];
        _selected.clear();
      }
    });
    if (_foreground) _load();
  }

  Future<void> _load() async {
    if (!mounted || _busy) return;
    final revision = _accessRevision;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final entity = await widget.service.getConversation(
        widget.conversationId,
      );
      if (!mounted) return;
      if (entity == null) throw StateError('Conversation no longer exists');
      _title = entity.peerName;
      if (!_authorized) {
        final conversation = Conversation(
          id: entity.id,
          peerId: entity.peerId,
          peerName: entity.peerName,
          peerPhone: entity.peerPhone,
          isLocked: entity.isLocked,
          isGroup: entity.isGroup,
        );
        final runtime = AppContainerScope.of(context).chatAccessRuntime;
        final credentials = runtime.credentials;
        final hasPassword =
            entity.isLocked &&
            credentials != null &&
            await credentials.hasCredential(entity.id);
        if (!mounted) return;
        final allowed = hasPassword
            ? await showVerifyChatPasswordDialog(
                context,
                chatName: entity.peerName,
                verify: (password) =>
                    credentials.verifyPassword(entity.id, password),
              )
            : await runtime.service.authorize(conversation);
        if (!mounted || revision != _accessRevision) return;
        _authorized = allowed;
      }
      if (!_authorized || !mounted) return;
      final files = await widget.service.filesForChat(widget.conversationId);
      if (mounted && revision == _accessRevision)
        setState(() {
          _files = files;
          _selected.retainAll(files.map((file) => file.message.id));
        });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<ChatStorageFile> get _visible => _files
      .where((file) => _filter == null || file.category == _filter)
      .toList();

  @override
  Widget build(BuildContext context) {
    final files = _visible;
    return AzureBackdrop(
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _title ?? context.l10n.settings_storage_usage,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            PopupMenuButton<StorageFileCategory?>(
              tooltip: context.l10n.storage_filter,
              enabled: _foreground && _authorized && !_busy,
              icon: const Icon(Icons.filter_list),
              itemBuilder: (_) => [
                for (final category in [null, ...StorageFileCategory.values])
                  PopupMenuItem<StorageFileCategory?>(
                    value: category,
                    onTap: () => setState(() => _filter = category),
                    child: Row(
                      children: [
                        if (_filter == category)
                          const Icon(Icons.check, size: 18)
                        else
                          const SizedBox(width: 18),
                        const SizedBox(width: 8),
                        Flexible(child: Text(_categoryName(category))),
                      ],
                    ),
                  ),
              ],
            ),
            IconButton(
              tooltip: context.l10n.select_all,
              onPressed: !_foreground || !_authorized || _busy || files.isEmpty
                  ? null
                  : () => setState(() {
                      final ids = files.map((file) => file.message.id).toSet();
                      if (_selected.containsAll(ids)) {
                        _selected.removeAll(ids);
                      } else {
                        _selected.addAll(ids);
                      }
                    }),
              icon: const Icon(Icons.select_all),
            ),
          ],
        ),
        body: !_foreground
            ? const SizedBox.shrink()
            : _busy
            ? const Center(child: CircularProgressIndicator())
            : _failed
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(context.l10n.storage_load_failed),
                    IconButton(
                      onPressed: _load,
                      tooltip: context.l10n.storage_reload,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              )
            : !_authorized
            ? Center(
                child: FilledButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.lock_open),
                  label: Text(context.l10n.chat_lock_unlock_action),
                ),
              )
            : files.isEmpty
            ? Center(child: Text(context.l10n.storage_no_files))
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 16),
                itemCount: files.length,
                itemBuilder: (context, index) {
                  final file = files[index];
                  final message = file.message;
                  final name = message.isViewOnce
                      ? context.l10n.view_once_protected
                      : message.fileName ?? context.l10n.file;
                  return CheckboxListTile(
                    key: ValueKey('storage-file-${message.id}'),
                    value: _selected.contains(message.id),
                    onChanged: (_) => setState(() {
                      if (!_selected.add(message.id))
                        _selected.remove(message.id);
                    }),
                    secondary: Icon(
                      message.isViewOnce
                          ? Icons.visibility_off_outlined
                          : _icon(file.category),
                    ),
                    title: Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${formatStorageBytes(file.diskBytes)} · '
                      '${MaterialLocalizations.of(context).formatShortDate(message.timestamp.toLocal())}'
                      '${!file.available ? ' · ${context.l10n.storage_local_missing}' : ''}',
                    ),
                  );
                },
              ),
        bottomNavigationBar: !_foreground || !_authorized || _selected.isEmpty
            ? null
            : SafeArea(
                minimum: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  key: const ValueKey('storage-delete-selected'),
                  onPressed: _busy ? null : _deleteSelected,
                  icon: const Icon(Icons.delete_outline),
                  label: Text(
                    context.l10n.storage_delete_action(_selected.length),
                  ),
                ),
              ),
      ),
    );
  }

  Future<void> _deleteSelected() async {
    if (_busy || _selected.isEmpty) return;
    final ids = Set<String>.of(_selected);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(context.l10n.clear_media),
        content: Text(context.l10n.storage_delete_selected(ids.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.cd_clear),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || !_authorized || !_foreground) return;
    setState(() => _busy = true);
    try {
      final result = await widget.service.cleanSelectedFiles(
        widget.conversationId,
        ids,
      );
      if (!mounted) return;
      _selected.clear();
      final message = result.failedIds.isEmpty
          ? context.l10n.storage_cleanup_result(
              result.deletedCount,
              formatStorageBytes(result.freedBytes),
            )
          : context.l10n.storage_cleanup_failed(result.failedIds.length);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.storage_cleanup_failed(ids.length)),
          ),
        );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        await _load();
      }
    }
  }

  String _categoryName(StorageFileCategory? category) => switch (category) {
    null => context.l10n.storage_all_files,
    StorageFileCategory.photo => context.l10n.photos,
    StorageFileCategory.video => context.l10n.videos,
    StorageFileCategory.audio => context.l10n.storage_audio,
    StorageFileCategory.document => context.l10n.documents,
  };

  static IconData _icon(StorageFileCategory category) => switch (category) {
    StorageFileCategory.photo => Icons.image_outlined,
    StorageFileCategory.video => Icons.videocam_outlined,
    StorageFileCategory.audio => Icons.audiotrack_outlined,
    StorageFileCategory.document => Icons.description_outlined,
  };
}

String formatStorageBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024)
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
