import 'dart:io';

import 'package:flutter/widgets.dart';

class LocalImageView extends StatelessWidget {
  const LocalImageView({
    super.key,
    required this.path,
    this.fit,
    this.errorBuilder,
  });

  final String path;
  final BoxFit? fit;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  Widget build(BuildContext context) =>
      Image.file(File(path), fit: fit, errorBuilder: errorBuilder);
}
