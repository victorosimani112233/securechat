import 'dart:io';

import 'package:flutter_securechat/src/storage/secure_chat_database.dart';

/// Diskteki depo dosyasinin ham icerigi.
///
/// Depo artik tek bir sifreli JSON dosyasi degil, SQLCipher veritabani.
/// "Diskte duz metin yok" degismezini sinayan testler artik bu dosyaya
/// bakmali. Baytlar gecerli UTF-8 olmadigi icin `readAsString` kullanilamaz;
/// arama Latin-1 uzerinden yapilir, ASCII icin bu yeterlidir.
Future<String> storageAtRest(File legacyFile) async {
  final file = SecureChatDatabase.storeFileFor(legacyFile);
  if (!await file.exists()) return '';
  return String.fromCharCodes(await file.readAsBytes());
}
