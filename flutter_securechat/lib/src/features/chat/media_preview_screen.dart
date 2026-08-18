import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../media/media_attachment.dart';
import '../../widgets/local_image_view.dart';

class MediaSendRequest {
  const MediaSendRequest({
    required this.attachments,
    required this.caption,
    required this.isViewOnce,
  });

  final List<MediaAttachment> attachments;
  final String caption;
  final bool isViewOnce;
}

class MediaPreviewScreen extends StatefulWidget {
  const MediaPreviewScreen({super.key, required this.attachments});

  final List<MediaAttachment> attachments;

  @override
  State<MediaPreviewScreen> createState() => _MediaPreviewScreenState();
}

class _MediaPreviewScreenState extends State<MediaPreviewScreen> {
  final _caption = TextEditingController();
  final _page = PageController();
  var _currentPage = 0;
  var _viewOnce = false;

  @override
  void dispose() {
    _caption.dispose();
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff0a0f18),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: widget.attachments.length > 1
            ? Text(context.l10n.files_selected(widget.attachments.length))
            : null,
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _page,
                itemCount: widget.attachments.length,
                onPageChanged: (value) => setState(() => _currentPage = value),
                itemBuilder: (context, index) =>
                    _PreviewContent(attachment: widget.attachments[index]),
              ),
            ),
            if (widget.attachments.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    widget.attachments.length,
                    (index) => AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: index == _currentPage ? 8 : 6,
                      height: index == _currentPage ? 8 : 6,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: index == _currentPage
                            ? const Color(0xff0ea5e9)
                            : const Color(0xff475569),
                      ),
                    ),
                  ),
                ),
              ),
            Container(
              margin: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
              decoration: BoxDecoration(
                color: const Color(0xff1e293b),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _caption,
                      maxLength: 1000,
                      minLines: 1,
                      maxLines: 4,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: context.l10n.add_caption,
                        counterText: '',
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Tooltip(
                    message: context.l10n.view_once,
                    child: InkWell(
                      key: const Key('media-view-once'),
                      onTap: () => setState(() => _viewOnce = !_viewOnce),
                      customBorder: const CircleBorder(),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _viewOnce
                              ? const Color(0xff3e7bfa).withValues(alpha: 0.18)
                              : Colors.white.withValues(alpha: 0.06),
                          border: Border.all(
                            width: 1.5,
                            color: _viewOnce
                                ? const Color(0xff3e7bfa)
                                : Colors.white.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Text(
                          '1',
                          style: TextStyle(
                            color: _viewOnce
                                ? const Color(0xff3e7bfa)
                                : Colors.white70,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    key: const Key('media-send'),
                    onPressed: () => Navigator.pop(
                      context,
                      MediaSendRequest(
                        attachments: widget.attachments,
                        caption: _caption.text.trim(),
                        isViewOnce: _viewOnce,
                      ),
                    ),
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewContent extends StatelessWidget {
  const _PreviewContent({required this.attachment});

  final MediaAttachment attachment;

  @override
  Widget build(BuildContext context) {
    if (attachment.isImage) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: LocalImageView(
          path: attachment.path,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => _FileDetails(attachment: attachment),
        ),
      );
    }
    if (attachment.isVideo) {
      return Stack(
        alignment: Alignment.center,
        children: [
          _FileDetails(attachment: attachment),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.6),
            ),
            child: const Icon(Icons.play_arrow, color: Colors.white, size: 36),
          ),
        ],
      );
    }
    return _FileDetails(attachment: attachment);
  }
}

class _FileDetails extends StatelessWidget {
  const _FileDetails({required this.attachment});

  final MediaAttachment attachment;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: const Color(0xff1e293b),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.insert_drive_file,
                color: Color(0xff0ea5e9),
                size: 48,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              attachment.fileName,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              formatMediaFileSize(attachment.fileSize),
              style: const TextStyle(color: Color(0xff64748b)),
            ),
            const SizedBox(height: 4),
            Text(
              attachment.mimeType,
              style: const TextStyle(color: Color(0xff475569), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

String formatMediaFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${bytes ~/ 1024} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
