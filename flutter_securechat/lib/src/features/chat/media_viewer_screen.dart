import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../l10n/l10n.dart';
import '../../media/local_file_actions.dart';
import '../../widgets/local_image_view.dart';
import 'media_preview_screen.dart';

class MediaViewerScreen extends StatelessWidget {
  const MediaViewerScreen({
    super.key,
    required this.message,
    required this.fileActions,
  });

  final LocalMessage message;
  final LocalFileActions fileActions;

  @override
  Widget build(BuildContext context) {
    final path = message.filePath;
    final mime = message.fileMimeType ?? 'application/octet-stream';
    final isImage = mime.startsWith('image/');
    final exists = path != null && fileActions.exists(path);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(
          message.isViewOnce
              ? context.l10n.view_once_protected
              : (message.fileName ?? context.l10n.media),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (!message.isViewOnce && exists)
            IconButton(
              tooltip: context.l10n.share,
              onPressed: () => _share(context, path, mime),
              icon: const Icon(Icons.share_outlined),
            ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: message.isViewOnce ? () => Navigator.pop(context) : null,
        child: Center(
          child: !exists
              ? const _UnavailableMedia()
              : isImage
              ? InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 5,
                  child: LocalImageView(
                    path: path,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const _UnavailableMedia(),
                  ),
                )
              : _DocumentViewer(
                  message: message,
                  onOpen: () => _open(context, path, mime),
                ),
        ),
      ),
      bottomNavigationBar: message.isViewOnce
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  context.l10n.tap_to_close_view_once,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54),
                ),
              ),
            )
          : null,
    );
  }

  Future<void> _open(BuildContext context, String path, String mime) async {
    try {
      await fileActions.open(path: path, mimeType: mime);
    } catch (error) {
      if (context.mounted) {
        _showError(context, context.l10n.file_open_failed('$error'));
      }
    }
  }

  Future<void> _share(BuildContext context, String path, String mime) async {
    try {
      await fileActions.share(
        path: path,
        mimeType: mime,
        fileName: message.fileName ?? context.l10n.file,
      );
    } catch (error) {
      if (context.mounted) {
        _showError(context, context.l10n.file_share_failed('$error'));
      }
    }
  }

  void _showError(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

class _DocumentViewer extends StatelessWidget {
  const _DocumentViewer({required this.message, required this.onOpen});

  final LocalMessage message;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.insert_drive_file,
            size: 88,
            color: Colors.lightBlue,
          ),
          const SizedBox(height: 16),
          Text(
            message.fileName ?? context.l10n.file,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            formatMediaFileSize(message.fileSize ?? 0),
            style: const TextStyle(color: Colors.white54),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onOpen,
            icon: const Icon(Icons.open_in_new),
            label: Text(context.l10n.open_with_app),
          ),
        ],
      ),
    );
  }
}

class _UnavailableMedia extends StatelessWidget {
  const _UnavailableMedia();

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.broken_image_outlined, size: 72, color: Colors.white54),
      const SizedBox(height: 12),
      Text(
        context.l10n.media_not_found,
        style: const TextStyle(color: Colors.white70),
      ),
    ],
  );
}
