import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../l10n/l10n.dart';
import '../../services/app_container.dart';
import '../../storage/storage_management_service.dart';
import '../../widgets/azure_backdrop.dart';
import '../../widgets/chat_lock_dialog.dart';
import '../../widgets/local_image_thumbnail.dart';
import '../../widgets/local_video_thumbnail.dart';

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
  Timer? _expiryTimer;
  StreamSubscription<List<LocalMessage>>? _messagesSubscription;
  Map<String, LocalMessage>? _latestMessages;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    _messagesSubscription?.cancel();
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
        _expiryTimer?.cancel();
        _messagesSubscription?.cancel();
        _messagesSubscription = null;
        _latestMessages = null;
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
      _observeMessages();
      final files = await widget.service.filesForChat(widget.conversationId);
      if (mounted && revision == _accessRevision)
        setState(() {
          _files = _reconcile(files);
          _selected.retainAll(_retained.map((file) => file.message.id));
          _scheduleExpiryRefresh();
        });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _observeMessages() {
    if (_messagesSubscription != null) return;
    _messagesSubscription = widget.service
        .watchChatMessages(widget.conversationId)
        .listen(
          (messages) {
            if (!mounted || !_authorized) return;
            setState(() {
              _latestMessages = {
                for (final message in messages) message.id: message,
              };
              _files = _reconcile(_files);
              _selected.retainAll(_retained.map((file) => file.message.id));
              _scheduleExpiryRefresh();
            });
          },
          onError: (Object _, StackTrace _) {
            if (!mounted) return;
            setState(() {
              _files = const [];
              _selected.clear();
              _failed = true;
              _messagesSubscription = null;
            });
          },
          cancelOnError: true,
        );
  }

  List<ChatStorageFile> _reconcile(List<ChatStorageFile> files) {
    final latest = _latestMessages;
    if (latest == null) return files;
    return [
      for (final file in files)
        if (latest[file.message.id] case final message?
            when message.isFileMessage)
          ChatStorageFile(
            message: message,
            diskBytes: file.diskBytes,
            available:
                file.available && message.filePath == file.message.filePath,
          ),
    ];
  }

  Iterable<ChatStorageFile> get _retained => _files.where((file) {
    final expiry = file.message.expiresAt;
    return !file.message.isDeleted &&
        (expiry == null || expiry.isAfter(DateTime.now()));
  });

  List<ChatStorageFile> get _visible => _retained
      .where((file) => _filter == null || file.category == _filter)
      .toList();

  void _scheduleExpiryRefresh() {
    _expiryTimer?.cancel();
    final now = DateTime.now();
    final deadlines =
        _files
            .map((file) => file.message.expiresAt)
            .whereType<DateTime>()
            .where((time) => time.isAfter(now))
            .toList()
          ..sort();
    if (deadlines.isEmpty) return;
    _expiryTimer = Timer(deadlines.first.difference(now), () {
      if (!mounted) return;
      setState(() {
        _selected.retainAll(_retained.map((file) => file.message.id));
      });
      _scheduleExpiryRefresh();
    });
  }

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
            : SafeArea(
                top: false,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final scaler = MediaQuery.textScalerOf(context);
                    final columns =
                        (constraints.maxWidth /
                                (scaler.scale(14) > 20 ? 240 : 150))
                            .floor()
                            .clamp(1, 6);
                    final width =
                        (constraints.maxWidth - 32 - (columns - 1) * 12) /
                        columns;
                    return RefreshIndicator(
                      onRefresh: _load,
                      child: GridView.builder(
                        key: const ValueKey('storage-files-grid'),
                        padding: const EdgeInsets.all(16),
                        physics: const AlwaysScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          mainAxisExtent:
                              width * .8 +
                              scaler.scale(14) * 2.6 +
                              scaler.scale(12) * 1.3 +
                              28,
                        ),
                        itemCount: files.length,
                        itemBuilder: (context, index) {
                          final file = files[index];
                          return _StorageFileTile(
                            file: file,
                            selected: _selected.contains(file.message.id),
                            onSelect: () => setState(() {
                              if (!_selected.add(file.message.id)) {
                                _selected.remove(file.message.id);
                              }
                            }),
                          );
                        },
                      ),
                    );
                  },
                ),
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
}

class _StorageFileTile extends StatelessWidget {
  const _StorageFileTile({
    required this.file,
    required this.selected,
    required this.onSelect,
  });

  final ChatStorageFile file;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final message = file.message;
    final scheme = Theme.of(context).colorScheme;
    final name = message.isViewOnce
        ? context.l10n.view_once_protected
        : (message.fileName?.trim().isNotEmpty == true
              ? message.fileName!
              : context.l10n.file);
    final date = MaterialLocalizations.of(
      context,
    ).formatShortDate(message.timestamp.toLocal());
    final details = '${formatStorageBytes(file.diskBytes)} · $date';
    final missing = file.available ? '' : context.l10n.storage_local_missing;
    return Semantics(
      key: ValueKey('storage-file-${message.id}'),
      container: true,
      checked: selected,
      label: [name, details, if (missing.isNotEmpty) missing].join(', '),
      onTap: onSelect,
      child: ExcludeSemantics(
        child: Material(
          color: scheme.surfaceContainerLow,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: 2,
            ),
          ),
          child: InkWell(
            onTap: onSelect,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(
                        color: scheme.surfaceContainerHighest,
                        child: _preview(context),
                      ),
                      PositionedDirectional(
                        top: 6,
                        end: 6,
                        child: Checkbox(
                          value: selected,
                          onChanged: (_) => onSelect(),
                          shape: const CircleBorder(),
                          fillColor: WidgetStateProperty.resolveWith(
                            (states) => states.contains(WidgetState.selected)
                                ? scheme.primary
                                : scheme.surface,
                          ),
                        ),
                      ),
                      if (!file.available)
                        PositionedDirectional(
                          bottom: 6,
                          start: 6,
                          end: 6,
                          child: Text(
                            missing,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height:
                            MediaQuery.textScalerOf(context).scale(14) * 2.6,
                        child: Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.3,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        details,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _preview(BuildContext context) {
    final message = file.message;
    final path = message.filePath?.trim() ?? '';
    // Never construct a decoder for one-time or deferred media.
    if (message.isViewOnce ||
        message.isMediaPreviewDeferred ||
        !file.available ||
        path.isEmpty) {
      return _fileType(context);
    }
    return switch (file.category) {
      StorageFileCategory.photo => LocalImageThumbnail(
        key: ValueKey('storage-preview-${message.id}'),
        path: path,
        isViewOnce: false,
        fallback: _fileType(context),
      ),
      StorageFileCategory.video => Center(
        child: LocalVideoThumbnail(
          key: ValueKey('storage-preview-${message.id}'),
          path: path,
          isViewOnce: false,
          preserveAspectRatio: true,
          fallback: _fileType(context),
        ),
      ),
      _ => _fileType(context),
    };
  }

  Widget _fileType(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hidden = file.message.isViewOnce;
    final icon = hidden
        ? Icons.visibility_off_outlined
        : switch (file.category) {
            StorageFileCategory.photo => Icons.image_outlined,
            StorageFileCategory.video => Icons.videocam_outlined,
            StorageFileCategory.audio => Icons.audiotrack_outlined,
            StorageFileCategory.document => Icons.description_outlined,
          };
    final name = hidden ? '' : file.message.fileName ?? '';
    final extension = name.contains('.')
        ? name.split('.').last.toUpperCase()
        : '';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: scheme.onSurfaceVariant),
            if (!hidden && RegExp(r'^[A-Z0-9]{1,8}$').hasMatch(extension)) ...[
              const SizedBox(height: 6),
              Text(
                extension,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String formatStorageBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024)
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
