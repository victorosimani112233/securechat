import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 2026-10-14: Rust kripto cekirdegi iOS'ta hic baglanmiyordu. Paket Xcode
/// projesinde yoktu, dogrulama betigi onu derlemiyordu ve Dart simgeleri
/// dlsym ile aradigi icin derleme yine geciyordu; uygulama ilk sifreleme
/// cagrisinda cokecekti. Bu testler baglantinin her parcasini sabitler.
void main() {
  Set<String> headerSymbols() => RegExp(r'\b(sc_[a-z_0-9]+)\s*\(')
      .allMatches(
        File(
          'native/securechat_crypto/include/securechat_crypto.h',
        ).readAsStringSync(),
      )
      .map((match) => match[1]!)
      .toSet();

  test('every C ABI symbol is forced into the iOS binary', () {
    final xcconfig = File(
      'ios/Flutter/SecureChatCrypto.xcconfig',
    ).readAsStringSync();
    final forced = RegExp(
      r'-Wl,-u,_(sc_[a-z_0-9]+)',
    ).allMatches(xcconfig).map((match) => match[1]!).toSet();
    final dartLookups = RegExp(r"'(sc_[a-z_0-9]+)'")
        .allMatches(
          File(
            'lib/src/crypto/vodozemac/securechat_crypto_ffi.dart',
          ).readAsStringSync(),
        )
        .map((match) => match[1]!)
        .toSet();

    expect(headerSymbols(), isNotEmpty);
    expect(forced, headerSymbols());
    expect(dartLookups.difference(forced), isEmpty);
    expect(xcconfig, contains(r'OTHER_LDFLAGS = $(inherited)'));
    for (final config in ['Debug', 'Release']) {
      expect(
        File('ios/Flutter/$config.xcconfig').readAsStringSync(),
        contains('#include "SecureChatCrypto.xcconfig"'),
        reason: config,
      );
    }
  });

  test('the Runner target links the SecureChatCrypto package', () {
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    expect(project, contains('relativePath = SecureChatCrypto;'));
    expect(project, contains('productName = SecureChatCrypto;'));
    expect(project, contains('/* SecureChatCrypto in Frameworks */,'));
    expect(project, contains('-Wl,-export_dynamic'));
    expect(
      File('ios/SecureChatCrypto/Package.swift').readAsStringSync(),
      contains('Artifacts/SecureChatCrypto.xcframework'),
    );
  });

  test('the macOS gate builds the core and checks the exported symbols', () {
    final gate = File('tool/verify_ios_on_macos.sh').readAsStringSync();
    final build = gate.indexOf('tool/build_native_crypto.sh ios');
    final resolve = gate.indexOf('xcodebuild -resolvePackageDependencies');
    expect(build, greaterThanOrEqualTo(0));
    expect(build, lessThan(resolve));
    expect(gate, contains('Kripto cekirdegi simgeleri Runner ikilisinde yok'));
  });
}
