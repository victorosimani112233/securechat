import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../l10n/l10n.dart';
import '../../media/local_file_actions.dart';
import '../../services/app_container.dart';
import '../../storage/storage_management_service.dart';
import '../../widgets/azure_backdrop.dart';
import '../../widgets/chat_lock_dialog.dart';
import '../../widgets/local_image_thumbnail.dart';
import '../../widgets/local_video_thumbnail.dart';
import '../chat/media_viewer_screen.dart';

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
  bool _authorizedLocked = false;
  bool _selecting = false;
  bool _opening = false;
  bool _foreground = true;
  final _viewerAllowed = ValueNotifier(false);
  MaterialPageRoute<void>? _viewerRoute;
  String? _viewingId;
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
    _viewerAllowed.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state != AppLifecycleState.resumed) _revokeViewer();
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
        _authorizedLocked = false;
        _selecting = false;
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
        _authorizedLocked = allowed && entity.isLocked;
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
              _checkViewer();
              _selected.retainAll(_retained.map((file) => file.message.id));
              if (_retained.isEmpty) _selecting = false;
              _scheduleExpiryRefresh();
            });
          },
          onError: (Object _, StackTrace _) {
            if (!mounted) return;
            setState(() {
              _files = const [];
              _selected.clear();
              _failed = true;
              _selecting = false;
              _revokeViewer();
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
            localPath: message.filePath == file.message.filePath
                ? file.localPath
                : null,
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
        if (_retained.isEmpty) _selecting = false;
        _checkViewer();
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
            if (_selecting)
              IconButton(
                tooltip: context.l10n.select_all,
                onPressed:
                    !_foreground || !_authorized || _busy || files.isEmpty
                    ? null
                    : () => setState(() {
                        final ids = files
                            .map((file) => file.message.id)
                            .toSet();
                        if (_selected.containsAll(ids)) {
                          _selected.removeAll(ids);
                        } else {
                          _selected.addAll(ids);
                        }
                      }),
                icon: const Icon(Icons.select_all),
              ),
            IconButton(
              key: const ValueKey('storage-selection-mode'),
              tooltip: _selecting
                  ? context.l10n.cancel_selection
                  : context.l10n.clear_media,
              onPressed:
                  !_foreground ||
                      !_authorized ||
                      _busy ||
                      (!_selecting && files.isEmpty)
                  ? null
                  : () => setState(() {
                      _selecting = !_selecting;
                      _selected.clear();
                    }),
              icon: Icon(_selecting ? Icons.close : Icons.delete_outline),
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
                            selecting: _selecting,
                            selected: _selected.contains(file.message.id),
                            onTap: () {
                              if (!_selecting) {
                                _openFile(file);
                                return;
                              }
                              setState(() {
                                if (!_selected.add(file.message.id)) {
                                  _selected.remove(file.message.id);
                                }
                              });
                            },
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
        bottomNavigationBar: !_foreground || !_authorized || !_selecting
            ? null
            : SafeArea(
                minimum: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  key: const ValueKey('storage-delete-selected'),
                  onPressed: _busy || _selected.isEmpty
                      ? null
                      : _deleteSelected,
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
    if (_busy ||
        !_selecting ||
        !_foreground ||
        !_authorized ||
        _selected.isEmpty)
      return;
    final revision = _accessRevision;
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
    if (confirmed != true ||
        !mounted ||
        !_authorized ||
        !_foreground ||
        revision != _accessRevision)
      return;
    setState(() => _busy = true);
    try {
      final result = await widget.service.cleanSelectedFiles(
        widget.conversationId,
        ids,
      );
      if (!mounted) return;
      _selected.clear();
      _selecting = false;
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

  void _checkViewer() {
    final id = _viewingId;
    if (id != null &&
        !_retained.any((file) => file.message.id == id && file.canOpen)) {
      _revokeViewer();
    }
  }

  void _revokeViewer() {
    _viewerAllowed.value = false;
    final route = _viewerRoute;
    if (route == null) return;
    _viewerRoute = null;
    // Revocation cannot wait for a frame: paused apps stop scheduling frames.
    if (route.isActive) route.navigator?.removeRoute(route);
  }

  Future<void> _openFile(ChatStorageFile file) async {
    if (!_foreground || !_authorized || _selecting || _opening || !file.canOpen)
      return;
    final revision = _accessRevision;
    _opening = true;
    try {
      final conversation = await widget.service.getConversation(
        widget.conversationId,
      );
      if (!mounted || !_foreground || revision != _accessRevision) return;
      if (conversation == null) return;
      if (conversation.isLocked && !_authorizedLocked) {
        setState(() {
          _authorized = false;
          _files = const [];
        });
        await _load();
        return;
      }
      final fresh = await widget.service.fileForOpening(
        widget.conversationId,
        file.message.id,
      );
      if (!mounted ||
          !_foreground ||
          !_authorized ||
          _selecting ||
          revision != _accessRevision)
        return;
      if (fresh == null ||
          !fresh.canOpen ||
          !_retained.any(
            (item) => item.message.id == file.message.id && item.canOpen,
          )) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.media_not_found)));
        return;
      }
      final path = fresh.path;
      if (path == null || path.isEmpty) return;
      final actions =
          AppContainerScope.of(context).mediaRuntime?.localFiles ??
          const NativeLocalFileActions();
      final mime = fresh.message.fileMimeType ?? 'application/octet-stream';
      if (!mime.startsWith('image/')) {
        await actions.open(path: path, mimeType: mime);
        return;
      }
      final message = fresh.message.copyWith(
        content: LocalMessage.buildFileContent(
          fileName: fresh.message.fileName ?? '',
          mimeType: mime,
          fileSize: fresh.message.fileSize ?? 0,
          filePath: path,
        ),
      );
      _viewingId = message.id;
      _viewerAllowed.value = true;
      final route = MaterialPageRoute<void>(
        builder: (_) => ValueListenableBuilder<bool>(
          valueListenable: _viewerAllowed,
          builder: (_, allowed, _) => allowed
              ? MediaViewerScreen(message: message, fileActions: actions)
              : const Scaffold(backgroundColor: Colors.black),
        ),
      );
      _viewerRoute = route;
      try {
        await Navigator.of(context).push(route);
      } finally {
        _viewerRoute = null;
        _viewingId = null;
        unawaited(route.completed.then((_) => FileImage(File(path)).evict()));
      }
    } catch (_) {
      if (mounted &&
          _foreground &&
          _authorized &&
          revision == _accessRevision) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.media_not_found)));
      }
    } finally {
      _opening = false;
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
    required this.selecting,
    required this.selected,
    required this.onTap,
  });

  final ChatStorageFile file;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;

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
      checked: selecting ? selected : null,
      button: !selecting,
      label: [name, details, if (missing.isNotEmpty) missing].join(', '),
      onTap: onTap,
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
            onTap: onTap,
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
                      if (selecting)
                        PositionedDirectional(
                          top: 6,
                          end: 6,
                          child: Checkbox(
                            value: selected,
                            onChanged: (_) => onTap(),
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
    final path = file.path ?? '';
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
