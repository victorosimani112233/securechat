/// Sifreli mesajin uzunlugunu gizleyen dolgu.
///
/// Olm/Megolm sifreli metni duz metinle ayni uzunlukta oldugu icin sunucu
/// "evet" ile uzun bir paragrafi, ya da okundu bilgisi ile dosya isaretcisini
/// boyutundan ayirt edebiliyordu. Duz metin sifrelenmeden once sabit
/// kovalara yuvarlanir:
///
/// `\u0000P1:<uzunluk>:<metin>\u0000...`
///
/// Normal duz metin NUL ile baslamaz; isaret bu yuzden belirsiz degildir.
/// Cozen taraf dolguyu HER ZAMAN soker; gonderen yalniz karsi taraf
/// [plaintextPaddingCapability] bildirdiyse dolgu ekler, cunku eski surum
/// NUL'lari metnin parcasi sanardi.
library;

import 'dart:convert';

/// Dolgulu duz metni cozebilme yetenegi (teslim makbuzunda bildirilir).
const plaintextPaddingCapability = 'pad-v1';

const _marker = '\u0000P1:';

/// 4 KB'a kadar 256 baytlik, 64 KB'a kadar 4 KB'lik kovalar. Daha buyuk
/// govdeler (eski parcali dosya yolu) yalniz baslik alir: sabit boyutlu
/// parcalar zaten ayni uzunlukta ve WebSocket cercevesi 256 KB ile sinirli.
int _bucketFor(int bytes) {
  if (bytes <= 4096) return 256;
  if (bytes <= 65536) return 4096;
  return 0;
}

String padPlaintext(String plaintext) {
  final header = '$_marker${plaintext.length}:';
  final total = header.length + utf8.encode(plaintext).length;
  final block = _bucketFor(total);
  if (block == 0) return '$header$plaintext';
  final target = (total + block - 1) ~/ block * block;
  return '$header$plaintext${'\u0000' * (target - total)}';
}

/// Dolgulu metni acar; dolgusuz metni aynen dondurur.
///
/// Bozuk baslik ya da sifir olmayan dolgu [FormatException] atar: ayni
/// zarfin farkli bicimde okunmasina izin verilmez.
String unpadPlaintext(String value) {
  if (!value.startsWith(_marker)) return value;
  final separator = value.indexOf(':', _marker.length);
  final length = separator < 0
      ? null
      : int.tryParse(value.substring(_marker.length, separator));
  final start = separator + 1;
  if (length == null || length < 0 || start + length > value.length) {
    throw const FormatException('Invalid padded plaintext');
  }
  for (var i = start + length; i < value.length; i++) {
    if (value.codeUnitAt(i) != 0) {
      throw const FormatException('Invalid plaintext padding');
    }
  }
  return value.substring(start, start + length);
}
