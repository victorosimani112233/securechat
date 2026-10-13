import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Dart paketleri Flutter'in NOTICES dosyasindan otomatik gelir; native
/// kutuphaneler (WebRTC, SQLCipher, Firebase SDK'lari, Rust kripto cekirdegi)
/// gelmez. BSD/MIT lisanslari binary dagitimda bildirimin yeniden
/// uretilmesini istedigi icin bunlar lisans ekranina burada eklenir.
const _apacheAsset = 'assets/licenses/audioswitch_APACHE-2.0.txt';
const _rustCratesAsset = 'assets/licenses/native_rust_crates.txt';

const _staticLicenses = <(List<String>, String)>[
  (['audioswitch'], _apacheAsset),
  (
    [
      'Firebase SDK',
      'AndroidX',
      'AndroidX Media3',
      'Google Tink',
      'Apache Tika',
      'Kotlin',
      'Abseil (WebRTC)',
    ],
    _apacheAsset,
  ),
  (['WebRTC'], 'assets/licenses/webrtc_BSD-3-Clause.txt'),
  // WebRTC ikili dosyasinin icine derlenen ucuncu taraf kutuphaneler; metinler
  // ust kaynak depolarindan alindi (2026-10-13).
  (['BoringSSL (WebRTC)'], 'assets/licenses/boringssl_LICENSE.txt'),
  (['libvpx (WebRTC)'], 'assets/licenses/libvpx_BSD-3-Clause.txt'),
  (['libaom (WebRTC)'], 'assets/licenses/libaom_BSD-2-Clause.txt'),
  (['dav1d (WebRTC)'], 'assets/licenses/dav1d_BSD-2-Clause.txt'),
  (['Opus (WebRTC)'], 'assets/licenses/opus_BSD-3-Clause.txt'),
  (['libsrtp (WebRTC)'], 'assets/licenses/libsrtp_BSD-3-Clause.txt'),
  (['libyuv (WebRTC)'], 'assets/licenses/libyuv_BSD-3-Clause.txt'),
  (['SQLCipher'], 'assets/licenses/sqlcipher_BSD-3-Clause.txt'),
];

void registerNativeLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final (packages, asset) in _staticLicenses) {
      yield LicenseEntryWithLineBreaks(
        packages,
        await rootBundle.loadString(asset),
      );
    }
    final crates = await rootBundle.loadString(_rustCratesAsset);
    for (final entry in parseRustCrateLicenses(crates)) {
      yield entry;
    }
  });
}

/// `tool/generate_native_licenses.py` ciktisini crate basina bir girdiye
/// ayirir. Bolum basligi: `=== <crate> <surum> (<SPDX ifadesi>)`.
Iterable<LicenseEntry> parseRustCrateLicenses(String text) sync* {
  final header = RegExp(r'^=== (\S+) ', multiLine: true);
  final matches = header.allMatches(text).toList();
  for (var i = 0; i < matches.length; i++) {
    final end = i + 1 < matches.length ? matches[i + 1].start : text.length;
    final body = text.substring(matches[i].start, end).trim();
    yield LicenseEntryWithLineBreaks([matches[i].group(1)!], body);
  }
}
