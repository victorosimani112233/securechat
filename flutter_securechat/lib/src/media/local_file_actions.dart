import 'dart:io';

import '../platform/native_bridge.dart';

abstract interface class LocalFileActions {
  bool exists(String path);

  Future<void> open({required String path, required String mimeType});

  Future<void> share({
    required String path,
    required String mimeType,
    required String fileName,
  });
}

class NativeLocalFileActions implements LocalFileActions {
  const NativeLocalFileActions({NativeBridge bridge = const NativeBridge()})
    : _bridge = bridge;

  final NativeBridge _bridge;

  @override
  bool exists(String path) => File(path).existsSync();

  @override
  Future<void> open({required String path, required String mimeType}) =>
      _bridge.openLocalFile(path: path, mimeType: mimeType);

  @override
  Future<void> share({
    required String path,
    required String mimeType,
    required String fileName,
  }) => _bridge.shareLocalFile(
    path: path,
    mimeType: mimeType,
    fileName: fileName,
  );
}
