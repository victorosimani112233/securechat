import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_securechat/src/settings/native_licenses.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rust crate notices split into one entry per crate', () {
    const text =
        '=== vodozemac 0.9.0 (Apache-2.0)\nApache text\n\n'
        '=== subtle 2.6.1 (BSD-3-Clause)\nBSD text\n';

    final entries = parseRustCrateLicenses(text).toList();

    expect(entries.map((e) => e.packages.single), ['vodozemac', 'subtle']);
    final bsd = entries.last.paragraphs.map((p) => p.text).join('\n');
    expect(bsd, contains('BSD text'));
    expect(bsd, isNot(contains('Apache text')));
  });

  test('generated asset covers the shipped crypto crates', () {
    final text = File(
      'assets/licenses/native_rust_crates.txt',
    ).readAsStringSync();
    final crates = parseRustCrateLicenses(
      text,
    ).map((e) => e.packages.single).toSet();

    expect(
      crates,
      containsAll(['vodozemac', 'curve25519-dalek', 'ed25519-dalek']),
    );
  });

  test('every registered native license asset is bundled', () async {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final source = File(
      'lib/src/settings/native_licenses.dart',
    ).readAsStringSync();
    final assets = RegExp(
      r"'(assets/licenses/[^']+)'",
    ).allMatches(source).map((m) => m.group(1)!);

    for (final asset in assets) {
      expect(File(asset).existsSync(), isTrue, reason: asset);
      expect(pubspec, contains('- $asset'), reason: asset);
    }
  });

  testWidgets('license registry exposes WebRTC and SQLCipher', (tester) async {
    // Varsayilan rootBundle: pubspec'e eklenmemis bir asset burada patlar.
    registerNativeLicenses();
    final packages = <String>{};
    await tester.runAsync(() async {
      await for (final entry in LicenseRegistry.licenses) {
        packages.addAll(entry.packages);
      }
    });

    expect(packages, containsAll(['WebRTC', 'SQLCipher', 'vodozemac']));
    // WebRTC ikilisine derlenen ucuncu taraf kutuphaneler de listelenmeli.
    expect(
      packages,
      containsAll([
        'BoringSSL (WebRTC)',
        'libvpx (WebRTC)',
        'libaom (WebRTC)',
        'dav1d (WebRTC)',
        'Opus (WebRTC)',
        'libsrtp (WebRTC)',
        'libyuv (WebRTC)',
        'Abseil (WebRTC)',
      ]),
    );
  });
}
