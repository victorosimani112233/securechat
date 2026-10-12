import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Medya dosyalarinin cihazdaki sifreli (at-rest) kabi.
///
/// Veritabani SQLCipher ile sifreliyken alinan ve gonderilen dosyalar
/// `files/media` altinda duz duruyordu; root/adli imaj/debug erisimiyle
/// okunabiliyordu (QA 2026-10-12 Bulgu 11). Artik her medya dosyasi bu kapla
/// yazilir; goruntuleyen, oynatan ya da disa veren kod dosyayi [openForUse]
/// ile `media/.open` altina gecici olarak cozer. Gecici kopyalar uygulama
/// acilisinda ve on plana donuste (yasina gore) silinir.
///
/// Bicim (`SCMEDIA1`):
///  * baslik: 8 bayt sihirli deger + 12 bayt rastgele temel nonce + 4 bayt
///    (big-endian) kayit boyu;
///  * kayitlar: duz metin [recordSize] baytlik parcalar halinde
///    ChaCha20-Poly1305 ile sifrelenir (her kayit + 16 bayt etiket). Nonce,
///    temel nonce'un son 4 baytinin kayit sirasiyla XOR'udur; AAD baslik +
///    sira + "son kayit" bayragidir. Boylece kayitlar yer degistiremez,
///    dosya kesilemez, sona kayit eklenemez.
///
/// AES-GCM yerine ChaCha20-Poly1305: saf Dart'ta yaklasik 3 kat hizli
/// (100 MB'lik dosya sinirinda belirgin). Agir is [Isolate.run] ile UI
/// isolate'inin disinda yapilir.
class MediaVault {
  MediaVault({required List<int> keyBytes, required this.mediaDirectory})
    : _keyBytes = List<int>.unmodifiable(keyBytes) {
    if (keyBytes.length != 32) {
      throw ArgumentError.value(keyBytes.length, 'keyBytes', 'must be 32');
    }
  }

  final List<int> _keyBytes;
  final Directory mediaDirectory;

  /// Ayni dosyanin es zamanli cozumleri tek ise baglanir (sohbet balonu ve
  /// goruntuleyici ayni anda isteyebilir; ayni gecici dosyaya yazmasinlar).
  final _opening = <String, Future<File>>{};

  /// Yarida kalmis yazimlar bu sureden eskiyse goc sirasinda silinir; daha
  /// yenisi baska bir islemin suren yazimidir.
  static const staleWriteAge = Duration(hours: 1);

  static const _magic = <int>[0x53, 0x43, 0x4D, 0x45, 0x44, 0x49, 0x41, 0x31];
  static const headerLength = 8 + 12 + 4;
  static const recordSize = 64 * 1024;
  static const tagLength = 16;

  /// Gecici duz kopyalarin dizini. Native acma/paylasma/onizleme yalniz
  /// `files/media` altini kabul eder; bu yuzden orada.
  Directory get openDirectory => Directory('${mediaDirectory.path}/.open');

  /// Sifreli kap olarak yazilmis mi (sihirli degere bakar).
  static Future<bool> isSealed(File file) async {
    RandomAccessFile? handle;
    try {
      handle = await file.open();
      final head = await handle.read(_magic.length);
      if (head.length != _magic.length) return false;
      for (var i = 0; i < _magic.length; i++) {
        if (head[i] != _magic[i]) return false;
      }
      return true;
    } on FileSystemException {
      return false;
    } finally {
      await handle?.close();
    }
  }

  /// Kap boyundan duz metin boyu (kayit boyu sabit).
  static int plaintextLength(int sealedLength, {int record = recordSize}) {
    final body = sealedLength - headerLength;
    if (body < tagLength) throw const FormatException('Truncated media file');
    final records = (body + record + tagLength - 1) ~/ (record + tagLength);
    return body - records * tagLength;
  }

  /// [plaintextFiles] sirayla birlestirilip [target]'a sifreli yazilir.
  /// Hedef once gecici adla yazilip atomik olarak yerine tasinir.
  Future<void> sealFiles(List<File> plaintextFiles, File target) {
    final key = _keyBytes;
    final sources = [for (final file in plaintextFiles) file.path];
    final output = target.path;
    return Isolate.run(() => _sealPaths(key, sources, output, sealed: false));
  }

  /// Sifreli parca dosyalari ([sealBytes] ile yazilmis) cozulup tek bir
  /// kapta birlestirilir; arada duz metin diske yazilmaz.
  Future<void> sealSealedParts(List<File> sealedParts, File target) {
    final key = _keyBytes;
    final sources = [for (final file in sealedParts) file.path];
    final output = target.path;
    return Isolate.run(() => _sealPaths(key, sources, output, sealed: true));
  }

  /// Dosya duzse yerinde sifreler (eski surumden kalan dosyalar). Zaten
  /// sifreliyse dokunmaz.
  Future<bool> sealInPlace(File file) async {
    if (!await file.exists() || await isSealed(file)) return false;
    await sealFiles([file], file);
    return true;
  }

  /// Kucuk veriyi (aktarim parcasi) bellekte kaba cevirir.
  Future<Uint8List> sealBytes(List<int> plaintext) =>
      _sealBuffer(_keyBytes, plaintext);

  /// Kucuk bir kabi bellekte cozer.
  Future<Uint8List> openBytes(List<int> sealed) =>
      _openBuffer(_keyBytes, sealed);

  /// Kullanilabilir (duz) dosya: sifreli degilse kendisi, sifreliyse
  /// `media/.open` altindaki gecici kopya. Kopya guncelse yeniden cozulmez.
  Future<File> openForUse(File stored) async {
    if (!await isSealed(stored)) return stored;
    final target = _openedFileFor(stored.path);
    final running = _opening[target.path];
    if (running != null) return running;
    final task = _open(stored, target);
    _opening[target.path] = task;
    try {
      return await task;
    } finally {
      if (identical(_opening[target.path], task)) _opening.remove(target.path);
    }
  }

  Future<File> _open(File stored, File target) async {
    if (await target.exists()) {
      final storedStat = await stored.stat();
      final openedStat = await target.stat();
      if (!openedStat.modified.isBefore(storedStat.modified)) {
        // Kullanimda: yasa gore temizlik bu kopyayi hemen silmesin.
        try {
          await target.setLastModified(DateTime.now());
        } on FileSystemException {
          // Zaman damgasi guncellenemese de kopya gecerli.
        }
        return target;
      }
    }
    await target.parent.create(recursive: true);
    final key = _keyBytes;
    final source = stored.path;
    final output = target.path;
    await Isolate.run(() => _openPath(key, source, output));
    return target;
  }

  /// Bir dosyanin gecici duz kopyasini (varsa) siler.
  Future<void> discardOpened(String storedPath) async {
    final directory = _openedFileFor(storedPath).parent;
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  /// Gecici duz kopyalari siler; [olderThan] verilirse yalniz eskileri.
  Future<void> purgeOpened({Duration? olderThan, DateTime? now}) async {
    final root = openDirectory;
    if (!await root.exists()) return;
    if (olderThan == null) {
      await root.delete(recursive: true);
      return;
    }
    final limit = (now ?? DateTime.now()).subtract(olderThan);
    final directories = <Directory>[];
    await for (final entry in root.list(recursive: true)) {
      if (entry is Directory) {
        directories.add(entry);
        continue;
      }
      try {
        final stat = await entry.stat();
        if (stat.modified.isBefore(limit) &&
            !_opening.containsKey(entry.path)) {
          await entry.delete();
        }
      } on FileSystemException {
        // Baska bir islem silmis olabilir.
      }
    }
    // Bosalan dosya dizinleri de kalkar.
    for (final directory in directories.reversed) {
      try {
        if (await directory.list().isEmpty) await directory.delete();
      } on FileSystemException {
        // Arada yeni kopya acilmis olabilir.
      }
    }
  }

  /// [directories] altindaki duz dosyalari sifreler (eski surum gocu).
  /// Gecici kopya ve aktarim dizinlerine dokunmaz.
  Future<int> sealExisting(Iterable<Directory> directories) async {
    var sealed = 0;
    for (final directory in directories) {
      if (!await directory.exists()) continue;
      await for (final entry in directory.list(recursive: true)) {
        if (entry is! File) continue;
        final name = entry.uri.pathSegments.last;
        if (name.endsWith('.sealing')) {
          // Yarida kalmis eski bir yazim silinir; yenisi suren bir yazimdir
          // (gonderim kopyasi, alim birlestirmesi) ve dokunulmaz.
          final age = DateTime.now().difference((await entry.stat()).modified);
          if (age > staleWriteAge) await entry.delete();
          continue;
        }
        if (await sealInPlace(entry)) sealed++;
      }
    }
    return sealed;
  }

  File _openedFileFor(String storedPath) {
    final absolute = File(storedPath).absolute.path;
    final digest = _fnv1a64(utf8.encode(absolute));
    final name = File(absolute).uri.pathSegments.last;
    return File('${openDirectory.path}/$digest/$name');
  }

  /// Dizin adi icin kararli kisa ozet (gizlilik degil, carpisma onleme).
  static String _fnv1a64(List<int> bytes) {
    var hash = 0xcbf29ce484222325;
    const prime = 0x100000001b3;
    for (final byte in bytes) {
      hash ^= byte;
      hash *= prime; // 64 bit sarmalar (VM).
    }
    return hash.toUnsigned(64).toRadixString(16).padLeft(16, '0');
  }
}

final _cipher = Chacha20.poly1305Aead();

List<int> _header(List<int> baseNonce, int record) => [
  ...MediaVault._magic,
  ...baseNonce,
  (record >> 24) & 0xFF,
  (record >> 16) & 0xFF,
  (record >> 8) & 0xFF,
  record & 0xFF,
];

List<int> _nonceFor(List<int> baseNonce, int index) {
  final nonce = List<int>.of(baseNonce);
  nonce[8] ^= (index >> 24) & 0xFF;
  nonce[9] ^= (index >> 16) & 0xFF;
  nonce[10] ^= (index >> 8) & 0xFF;
  nonce[11] ^= index & 0xFF;
  return nonce;
}

List<int> _aad(List<int> header, int index, bool last) => [
  ...header,
  (index >> 24) & 0xFF,
  (index >> 16) & 0xFF,
  (index >> 8) & 0xFF,
  index & 0xFF,
  last ? 1 : 0,
];

List<int> _randomNonce() {
  final random = Random.secure();
  return List<int>.generate(12, (_) => random.nextInt(256));
}

/// Duz metni kayitlara bolup yazan akis sifreleyicisi.
class _SealWriter {
  _SealWriter(this._key, this._sink)
    : _baseNonce = _randomNonce(),
      _buffer = BytesBuilder(copy: false) {
    _headerBytes = _header(_baseNonce, MediaVault.recordSize);
  }

  final SecretKey _key;
  final RandomAccessFile _sink;
  final List<int> _baseNonce;
  final BytesBuilder _buffer;
  late final List<int> _headerBytes;
  var _index = 0;
  var _started = false;

  Future<void> add(List<int> bytes) async {
    if (!_started) {
      _started = true;
      await _sink.writeFrom(_headerBytes);
    }
    _buffer.add(bytes);
    while (_buffer.length > MediaVault.recordSize) {
      final all = _buffer.takeBytes();
      await _writeRecord(all.sublist(0, MediaVault.recordSize), last: false);
      _buffer.add(all.sublist(MediaVault.recordSize));
    }
  }

  Future<void> close() async {
    if (!_started) {
      _started = true;
      await _sink.writeFrom(_headerBytes);
    }
    // Son kayit bos olabilir (bos dosya ya da tam kat); her zaman yazilir.
    await _writeRecord(_buffer.takeBytes(), last: true);
  }

  Future<void> _writeRecord(List<int> plain, {required bool last}) async {
    final box = await _cipher.encrypt(
      plain,
      secretKey: _key,
      nonce: _nonceFor(_baseNonce, _index),
      aad: _aad(_headerBytes, _index, last),
    );
    await _sink.writeFrom(box.cipherText);
    await _sink.writeFrom(box.mac.bytes);
    _index++;
  }
}

Future<void> _sealPaths(
  List<int> keyBytes,
  List<String> sources,
  String output, {
  required bool sealed,
}) async {
  final key = SecretKey(keyBytes);
  final temporary = File('$output.sealing');
  final sink = await temporary.open(mode: FileMode.writeOnly);
  try {
    final writer = _SealWriter(key, sink);
    for (final source in sources) {
      if (sealed) {
        await _readSealed(key, File(source), writer.add);
      } else {
        await for (final chunk in File(source).openRead()) {
          await writer.add(chunk);
        }
      }
    }
    await writer.close();
    await sink.flush();
  } catch (_) {
    await sink.close();
    if (await temporary.exists()) await temporary.delete();
    rethrow;
  }
  await sink.close();
  await temporary.rename(output);
}

Future<void> _openPath(List<int> keyBytes, String source, String output) async {
  final key = SecretKey(keyBytes);
  final temporary = File('$output.opening');
  final sink = await temporary.open(mode: FileMode.writeOnly);
  try {
    await _readSealed(key, File(source), sink.writeFrom);
    await sink.flush();
  } catch (_) {
    await sink.close();
    if (await temporary.exists()) await temporary.delete();
    rethrow;
  }
  await sink.close();
  await temporary.rename(output);
}

/// Kabi kayit kayit cozer; her duz parca [emit]'e verilir.
Future<void> _readSealed(
  SecretKey key,
  File file,
  Future<void> Function(List<int>) emit,
) async {
  final handle = await file.open();
  try {
    await _parseSealed(
      key,
      await handle.length(),
      (length) async => handle.read(length),
      emit,
    );
  } finally {
    await handle.close();
  }
}

Future<void> _parseSealed(
  SecretKey key,
  int total,
  Future<List<int>> Function(int length) read,
  Future<void> Function(List<int>) emit,
) async {
  final header = await read(MediaVault.headerLength);
  if (header.length != MediaVault.headerLength) {
    throw const FormatException('Truncated media header');
  }
  for (var i = 0; i < MediaVault._magic.length; i++) {
    if (header[i] != MediaVault._magic[i]) {
      throw const FormatException('Not a sealed media file');
    }
  }
  final baseNonce = header.sublist(8, 20);
  final record =
      (header[20] << 24) | (header[21] << 16) | (header[22] << 8) | header[23];
  if (record <= 0 || record > 16 * 1024 * 1024) {
    throw const FormatException('Invalid media record size');
  }
  var offset = MediaVault.headerLength;
  var index = 0;
  var sawLast = false;
  while (offset < total) {
    final remaining = total - offset;
    final length = min(remaining, record + MediaVault.tagLength);
    if (length < MediaVault.tagLength) {
      throw const FormatException('Truncated media record');
    }
    final bytes = await read(length);
    if (bytes.length != length) {
      throw const FormatException('Short media read');
    }
    offset += length;
    final last = offset == total;
    final box = SecretBox(
      bytes.sublist(0, length - MediaVault.tagLength),
      nonce: _nonceFor(baseNonce, index),
      mac: Mac(bytes.sublist(length - MediaVault.tagLength)),
    );
    final plain = await _cipher.decrypt(
      box,
      secretKey: key,
      aad: _aad(header, index, last),
    );
    await emit(plain);
    index++;
    sawLast = last;
  }
  if (!sawLast) throw const FormatException('Missing final media record');
}

Future<Uint8List> _sealBuffer(List<int> keyBytes, List<int> plaintext) async {
  final key = SecretKey(keyBytes);
  final baseNonce = _randomNonce();
  final header = _header(baseNonce, MediaVault.recordSize);
  final out = BytesBuilder(copy: false)..add(header);
  var index = 0;
  var offset = 0;
  do {
    final end = min(offset + MediaVault.recordSize, plaintext.length);
    final last = end == plaintext.length;
    final box = await _cipher.encrypt(
      plaintext.sublist(offset, end),
      secretKey: key,
      nonce: _nonceFor(baseNonce, index),
      aad: _aad(header, index, last),
    );
    out
      ..add(box.cipherText)
      ..add(box.mac.bytes);
    offset = end;
    index++;
    if (last) break;
  } while (true);
  return out.takeBytes();
}

Future<Uint8List> _openBuffer(List<int> keyBytes, List<int> sealed) async {
  final out = BytesBuilder(copy: false);
  var position = 0;
  await _parseSealed(SecretKey(keyBytes), sealed.length, (length) async {
    final end = min(position + length, sealed.length);
    final slice = sealed.sublist(position, end);
    position = end;
    return slice;
  }, (bytes) async => out.add(bytes));
  return out.takeBytes();
}
