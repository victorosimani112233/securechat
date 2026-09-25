import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// Keeps storage previews out of the global image cache, like video thumbnails.
class LocalImageThumbnail extends StatefulWidget {
  const LocalImageThumbnail({
    super.key,
    required this.path,
    required this.isViewOnce,
    required this.fallback,
  });

  final String path;
  final bool isViewOnce;
  final Widget fallback;

  @override
  State<LocalImageThumbnail> createState() => _LocalImageThumbnailState();
}

class _LocalImageThumbnailState extends State<LocalImageThumbnail> {
  ui.Image? _image;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(LocalImageThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.isViewOnce != widget.isViewOnce) {
      _image?.dispose();
      _image = null;
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    if (widget.isViewOnce || widget.path.trim().isEmpty) return;
    try {
      final buffer = await ui.ImmutableBuffer.fromFilePath(widget.path);
      late final ui.Image image;
      try {
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        try {
          final scale = math.min(
            1.0,
            384 / math.max(descriptor.width, descriptor.height),
          );
          final codec = await descriptor.instantiateCodec(
            targetWidth: math.max(1, (descriptor.width * scale).round()),
            targetHeight: math.max(1, (descriptor.height * scale).round()),
          );
          try {
            image = (await codec.getNextFrame()).image;
          } finally {
            codec.dispose();
          }
        } finally {
          descriptor.dispose();
        }
      } finally {
        buffer.dispose();
      }
      if (!mounted || generation != _generation) {
        image.dispose();
        return;
      }
      setState(() => _image = image);
    } catch (_) {
      // A missing or unsupported file must remain selectable for cleanup.
    }
  }

  @override
  void dispose() {
    ++_generation;
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _image == null || widget.isViewOnce
      ? widget.fallback
      : RawImage(image: _image, fit: BoxFit.contain);
}
