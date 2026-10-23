import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../security/pbkdf2_isolate.dart';

/// Yedek dosyasinin parolayla sifrelenmis kabi.
///
/// v2 (yeni yedekler):
/// `"ELCB"` + `0x02` + kdf(1 = Argon2id) + bellek KiB (u32) + tur (u32) +
/// paralellik (u8) + tuz(16) + IV(12) + sifreli metin + GCM etiketi(16).
/// Baslik AES-GCM ek verisidir; parametreler sessizce degistirilemez.
///
/// v1 (eski yedekler, Kotlin BackupCrypto ile uyumlu, yalniz acilir):
/// tuz(32) + IV(12) + sifreli metin + GCM etiketi(16), PBKDF2-SHA256
/// 120 000 tur. GPU ile parola denemeye karsi zayif kaldigi icin yeni
/// yedeklerde bellek isteyen Argon2id kullanilir.
class BackupCrypto {
  BackupCrypto({
    Random? random,
    this.memoryKiB = defaultMemoryKiB,
    this.iterations = defaultIterations,
  }) : _random = random ?? Random.secure();

  static final _magic = ascii.encode('ELCB');
  static const _version = 2;
  static const _kdfArgon2id = 1;
  static const _headerLength = 4 + 1 + 1 + 4 + 4 + 1;
  static const _saltV2 = 16;

  /// RFC 9106'nin ikinci onerisi: 64 MiB, 3 tur, 1 hat.
  static const defaultMemoryKiB = 64 * 1024;
  static const defaultIterations = 3;

  /// Saldirgan bicimli bir dosyayla cihazi asiri bellege zorlayamasin.
  static const _maximumMemoryKiB = 256 * 1024;
  static const _maximumIterations = 10;

  static const saltLength = 32;
  static const nonceLength = 12;
  static const macLength = 16;
  static const legacyIterations = 120000;

  final Random _random;
  final int memoryKiB;
  final int iterations;
  final AesGcm _cipher = AesGcm.with256bits();

  Future<Uint8List> encrypt(List<int> plaintext, String password) async {
    final salt = _bytes(_saltV2);
    final nonce = _bytes(nonceLength);
    final header =
        (BytesBuilder()
              ..add(_magic)
              ..addByte(_version)
              ..addByte(_kdfArgon2id)
              ..add(_u32(memoryKiB))
              ..add(_u32(iterations))
              ..addByte(1))
            .toBytes();
    final key = await _argon2id(password, salt, memoryKiB, iterations);
    final box = await _cipher.encrypt(
      plaintext,
      secretKey: key,
      nonce: nonce,
      aad: [...header, ...salt],
    );
    return Uint8List.fromList([
      ...header,
      ...salt,
      ...nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
  }

  Future<Uint8List?> decrypt(List<int> encrypted, String password) async {
    if (_isV2(encrypted)) {
      final opened = await _decryptV2(encrypted, password);
      if (opened != null) return opened;
      // Rastgele tuzu tesadufen "ELCB\x02" ile baslayan v1 dosyasi.
    }
    return _decryptV1(encrypted, password);
  }

  bool _isV2(List<int> data) =>
      data.length > _headerLength + _saltV2 + nonceLength + macLength &&
      data[0] == _magic[0] &&
      data[1] == _magic[1] &&
      data[2] == _magic[2] &&
      data[3] == _magic[3] &&
      data[4] == _version;

  Future<Uint8List?> _decryptV2(List<int> data, String password) async {
    final view = ByteData.sublistView(Uint8List.fromList(data));
    final kdf = data[5];
    final memory = view.getUint32(6);
    final rounds = view.getUint32(10);
    final lanes = data[14];
    if (kdf != _kdfArgon2id ||
        lanes != 1 ||
        memory < 8 ||
        memory > _maximumMemoryKiB ||
        rounds < 1 ||
        rounds > _maximumIterations) {
      return null;
    }
    final aad = data.sublist(0, _headerLength + _saltV2);
    final salt = data.sublist(_headerLength, _headerLength + _saltV2);
    final nonceStart = _headerLength + _saltV2;
    final nonce = data.sublist(nonceStart, nonceStart + nonceLength);
    final body = data.sublist(nonceStart + nonceLength);
    try {
      final clear = await _cipher.decrypt(
        SecretBox(
          body.sublist(0, body.length - macLength),
          nonce: nonce,
          mac: Mac(body.sublist(body.length - macLength)),
        ),
        secretKey: await _argon2id(password, salt, memory, rounds),
        aad: aad,
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      return null;
    }
  }

  Future<Uint8List?> _decryptV1(List<int> encrypted, String password) async {
    if (encrypted.length < saltLength + nonceLength + macLength + 1) {
      return null;
    }
    try {
      final salt = encrypted.sublist(0, saltLength);
      final nonce = encrypted.sublist(saltLength, saltLength + nonceLength);
      final body = encrypted.sublist(saltLength + nonceLength);
      final cipherText = body.sublist(0, body.length - macLength);
      final mac = body.sublist(body.length - macLength);
      final clear = await _cipher.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: SecretKey(
          await pbkdf2Sha256(
            password: password,
            salt: salt,
            iterations: legacyIterations,
          ),
        ),
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  /// Argon2id ayri isolate'te: 64 MiB'lik hesap arayuzu dondurmasin.
  static Future<SecretKey> _argon2id(
    String password,
    List<int> salt,
    int memoryKiB,
    int iterations,
  ) async {
    final saltCopy = List<int>.of(salt, growable: false);
    final bytes = await Isolate.run(() async {
      final kdf = Argon2id(
        parallelism: 1,
        memory: memoryKiB,
        iterations: iterations,
        hashLength: 32,
      );
      final key = await kdf.deriveKey(
        secretKey: SecretKey(utf8.encode(password)),
        nonce: saltCopy,
      );
      return key.extractBytes();
    }, debugName: 'argon2id');
    return SecretKey(bytes);
  }

  static List<int> _u32(int value) =>
      (ByteData(4)..setUint32(0, value)).buffer.asUint8List();

  List<int> _bytes(int length) =>
      List<int>.generate(length, (_) => _random.nextInt(256));
}
