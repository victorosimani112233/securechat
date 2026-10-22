import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

/// Grup fotografi secer; kullanici vazgecerse null.
typedef GroupPhotoPicker = Future<Uint8List?> Function();

/// Galeriden secilen fotograf kucultulmus olarak doner. Fotograf her uyeye
/// ayri sifrelenip gonderildigi icin kucuk tutulur (384 px, JPEG %72);
/// boylece genelde 64 KB sinirinin cok altinda kalir.
Future<Uint8List?> pickGroupPhotoFromGallery() async {
  final file = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 384,
    maxHeight: 384,
    imageQuality: 72,
    requestFullMetadata: false,
  );
  return file?.readAsBytes();
}
