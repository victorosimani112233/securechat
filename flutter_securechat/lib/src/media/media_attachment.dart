import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

class MediaAttachment {
  const MediaAttachment({
    required this.path,
    required this.fileName,
    required this.mimeType,
    required this.fileSize,
  });

  final String path;
  final String fileName;
  final String mimeType;
  final int fileSize;

  bool get isImage => mimeType.startsWith('image/');
  bool get isVideo => mimeType.startsWith('video/');

  static Future<MediaAttachment> fromPath(
    String path, {
    String? fileName,
    String? mimeType,
    int? fileSize,
  }) async {
    final file = File(path);
    if (!await file.exists()) {
      throw const FileSystemException('Seçilen medya dosyası bulunamadı');
    }
    final name = sanitizeMediaFileName(
      fileName ?? file.uri.pathSegments.lastOrNull ?? 'dosya',
    );
    return MediaAttachment(
      path: file.absolute.path,
      fileName: name,
      mimeType: mimeType?.trim().isNotEmpty == true
          ? mimeType!.trim().toLowerCase()
          : mediaMimeType(name),
      fileSize: fileSize ?? await file.length(),
    );
  }
}

class MediaSelectionException implements Exception {
  const MediaSelectionException(this.message);
  final String message;

  @override
  String toString() => message;
}

abstract interface class MediaSelectionService {
  Future<List<MediaAttachment>> pickGallery();
  Future<List<MediaAttachment>> pickDocuments();
  Future<List<MediaAttachment>> takePhoto();
  Future<List<MediaAttachment>> recoverLostSelection();
}

class PluginMediaSelectionService implements MediaSelectionService {
  PluginMediaSelectionService({ImagePicker? imagePicker})
    : _imagePicker = imagePicker ?? ImagePicker();

  final ImagePicker _imagePicker;

  @override
  Future<List<MediaAttachment>> pickGallery() async => _fromXFiles(
    await _imagePicker.pickMultiImage(requestFullMetadata: false),
  );

  @override
  Future<List<MediaAttachment>> takePhoto() async {
    final selected = await _imagePicker.pickImage(
      source: ImageSource.camera,
      requestFullMetadata: false,
      preferredCameraDevice: CameraDevice.rear,
    );
    return selected == null ? const [] : _fromXFiles([selected]);
  }

  @override
  Future<List<MediaAttachment>> pickDocuments() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: true,
      withData: false,
      withReadStream: false,
    );
    if (result == null) return const [];
    final attachments = <MediaAttachment>[];
    for (final selected in result.files) {
      final path = selected.path;
      if (path == null || path.isEmpty) {
        throw const MediaSelectionException(
          'Seçilen belge için yerel dosya yolu alınamadı.',
        );
      }
      attachments.add(
        await MediaAttachment.fromPath(
          path,
          fileName: selected.name,
          fileSize: selected.size,
        ),
      );
    }
    return attachments;
  }

  @override
  Future<List<MediaAttachment>> recoverLostSelection() async {
    if (!Platform.isAndroid) return const [];
    final response = await _imagePicker.retrieveLostData();
    if (response.isEmpty) return const [];
    if (response.exception != null) {
      throw MediaSelectionException(
        response.exception!.message ??
            'Yarım kalan medya seçimi kurtarılamadı.',
      );
    }
    return _fromXFiles(response.files ?? const []);
  }

  Future<List<MediaAttachment>> _fromXFiles(List<XFile> files) async {
    final attachments = <MediaAttachment>[];
    for (final selected in files) {
      attachments.add(
        await MediaAttachment.fromPath(
          selected.path,
          fileName: selected.name,
          mimeType: selected.mimeType,
          fileSize: await selected.length(),
        ),
      );
    }
    return attachments;
  }
}

String sanitizeMediaFileName(String raw) {
  final leaf = raw.replaceAll('\\', '/').split('/').last.trim();
  final safe = leaf.replaceAll(RegExp(r'[^A-Za-z0-9._() -]'), '_');
  return safe.isEmpty || safe == '.' || safe == '..' ? 'dosya' : safe;
}

String mediaMimeType(String fileName) {
  final extension = fileName.toLowerCase().split('.').last;
  return switch (extension) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'heic' || 'heif' => 'image/heic',
    'mp4' || 'm4v' => 'video/mp4',
    'mov' => 'video/quicktime',
    'webm' => 'video/webm',
    'pdf' => 'application/pdf',
    'txt' => 'text/plain',
    'json' => 'application/json',
    'zip' => 'application/zip',
    'doc' => 'application/msword',
    'docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls' => 'application/vnd.ms-excel',
    'xlsx' =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    _ => 'application/octet-stream',
  };
}

extension on List<String> {
  String? get lastOrNull => isEmpty ? null : last;
}
