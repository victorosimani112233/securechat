import 'dart:io';

import 'package:flutter/widgets.dart';

class LocalImageView extends StatelessWidget {
  const LocalImageView({
    super.key,
    required this.path,
    this.fit,
    this.errorBuilder,
    this.maxDecodeSize,
  });

  final String path;
  final BoxFit? fit;
  final ImageErrorWidgetBuilder? errorBuilder;
  final int? maxDecodeSize;

  @override
  Widget build(BuildContext context) {
    final file = FileImage(File(path));
    final size = maxDecodeSize;
    return Image(
      image: size == null
          ? file
          : ResizeImage(
              file,
              width: size,
              height: size,
              policy: ResizeImagePolicy.fit,
            ),
      fit: fit,
      errorBuilder: errorBuilder,
    );
  }
}
