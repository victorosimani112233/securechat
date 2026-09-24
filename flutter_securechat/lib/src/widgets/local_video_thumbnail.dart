import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../platform/native_bridge.dart';

/// Owns a decoded frame without adding it to Flutter's global image cache.
class LocalVideoThumbnail extends StatefulWidget {
  const LocalVideoThumbnail({
    super.key,
    required this.path,
    required this.isViewOnce,
    required this.fallback,
    this.preserveAspectRatio = false,
    this.bridge = const NativeBridge(),
  });

  final String path;
  final bool isViewOnce;
  final Widget fallback;
  final bool preserveAspectRatio;
  final NativeBridge bridge;

  @override
  State<LocalVideoThumbnail> createState() => _LocalVideoThumbnailState();
}

class _LocalVideoThumbnailState extends State<LocalVideoThumbnail> {
  ui.Image? _image;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(LocalVideoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.isViewOnce != widget.isViewOnce ||
        oldWidget.bridge != widget.bridge) {
      _image?.dispose();
      _image = null;
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    // This check must precede the bridge call, not just image rendering.
    if (widget.isViewOnce || widget.path.trim().isEmpty) return;
    try {
      final bytes = await widget.bridge.localVideoThumbnail(
        path: widget.path,
        isViewOnce: widget.isViewOnce,
      );
      if (!mounted || generation != _generation || bytes == null) return;
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      late final ui.Image image;
      try {
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        try {
          final scale = math.min(
            1.0,
            NativeBridge.videoThumbnailMaxSize /
                math.max(descriptor.width, descriptor.height),
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
      // Missing files, unsupported codecs and corrupt bytes keep the fallback.
    }
  }

  @override
  void dispose() {
    ++_generation;
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null || widget.isViewOnce) return widget.fallback;
    final preview = Stack(
      fit: StackFit.expand,
      children: [
        RawImage(
          image: image,
          fit: widget.preserveAspectRatio ? BoxFit.contain : BoxFit.cover,
        ),
        const Positioned(
          right: 8,
          bottom: 8,
          child: Icon(
            Icons.play_circle_outline,
            color: Colors.white,
            shadows: [Shadow(blurRadius: 4, color: Colors.black)],
          ),
        ),
      ],
    );
    return widget.preserveAspectRatio
        ? AspectRatio(aspectRatio: image.width / image.height, child: preview)
        : preview;
  }
}
