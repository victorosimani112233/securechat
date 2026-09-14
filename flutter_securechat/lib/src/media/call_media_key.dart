import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// Bir grup aramasinin medya anahtari ve kusagi.
///
/// SFU yolunda WebRTC oturumu Janus'ta sonlanir; ayri bir uygulama katmani
/// sifrelemesi olmadan medya sunucunun guven sinirinin icinde kalir. Bu anahtar
/// frame'leri uclarda sifreler, boylece SFU yalniz ciphertext yonlendirir.
///
/// Anahtar sunucudan **gecmez**: her katilimciya mevcut direct Signal zarfi
/// icinde gonderilir. Sunucu ordinary bir `encrypted_message` gorur.
class CallMediaKey {
  const CallMediaKey({
    required this.callId,
    required this.epoch,
    required this.key,
  });

  /// Anahtarin bagli oldugu arama. Baska bir aramaya ait anahtar kabul edilmez.
  final String callId;

  /// Uyelik her degistiginde artan kusak numarasi.
  final int epoch;

  /// 32 byte AES-GCM anahtari.
  final Uint8List key;

  static const int keyLengthBytes = 32;

  /// FrameCryptor anahtar halkasi 16 slot tasir; kusak bu halkaya yerlesir.
  static const int keyRingSize = 16;

  /// Wire on eki. Ic payload zaten E2EE'dir; bu on ek yalniz alicinin
  /// cozdukten sonra turu ayirt etmesi icindir.
  static const String prefix = 'CALLKEY:v1';

  int get keyIndex => epoch % keyRingSize;

  static CallMediaKey generate({required String callId, int epoch = 0}) {
    final random = Random.secure();
    final bytes = Uint8List(keyLengthBytes);
    for (var i = 0; i < keyLengthBytes; i++) {
      bytes[i] = random.nextInt(256);
    }
    return CallMediaKey(callId: callId, epoch: epoch, key: bytes);
  }

  /// Yeni kusak: uyelik degistiginde cagrilir.
  ///
  /// Katilan uye onceki frame'leri, ayrilan uye sonraki frame'leri cozememeli;
  /// bunun icin her degisimde **yeni anahtar** uretilir, yalniz kusak artmaz.
  CallMediaKey rotate() => generate(callId: callId, epoch: epoch + 1);

  String encode() => '$prefix:$callId:$epoch:${base64Encode(key)}';

  /// Cozulmus payload'dan anahtari okur.
  ///
  /// [expectedCallId] verilirse baska bir aramaya ait anahtar reddedilir;
  /// aksi halde bir katilimci baska bir cagrinin anahtarini enjekte edebilirdi.
  static CallMediaKey? tryParse(String payload, {String? expectedCallId}) {
    if (!payload.startsWith('$prefix:')) return null;
    // callId ':' icerebilir; son iki alan sabit oldugu icin sondan ayristirilir.
    final body = payload.substring(prefix.length + 1);
    final keySeparator = body.lastIndexOf(':');
    if (keySeparator <= 0) return null;
    final epochSeparator = body.lastIndexOf(':', keySeparator - 1);
    if (epochSeparator <= 0) return null;

    final callId = body.substring(0, epochSeparator);
    final epoch = int.tryParse(body.substring(epochSeparator + 1, keySeparator));
    if (callId.isEmpty || epoch == null || epoch < 0) return null;
    if (expectedCallId != null && callId != expectedCallId) return null;

    final Uint8List key;
    try {
      key = base64Decode(body.substring(keySeparator + 1));
    } on FormatException {
      return null;
    }
    if (key.length != keyLengthBytes) return null;
    return CallMediaKey(callId: callId, epoch: epoch, key: key);
  }

  @override
  bool operator ==(Object other) =>
      other is CallMediaKey &&
      other.callId == callId &&
      other.epoch == epoch &&
      _sameBytes(other.key, key);

  @override
  int get hashCode => Object.hash(callId, epoch, base64Encode(key));

  static bool _sameBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
