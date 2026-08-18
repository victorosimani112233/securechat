import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String source(String relativePath) =>
      File('${Directory.current.path}/$relativePath').readAsStringSync();

  Map<String, String> directHostedDependencies(String pubspec) {
    final dependencies = <String, String>{};
    var inDependencySection = false;
    for (final line in pubspec.split('\n')) {
      if (line.isNotEmpty && !line.startsWith(' ')) {
        inDependencySection =
            line == 'dependencies:' || line == 'dev_dependencies:';
        continue;
      }
      if (!inDependencySection) continue;
      final match = RegExp(
        r'^  ([A-Za-z0-9_]+):(?:\s+([^#\s]+))?\s*(?:#.*)?$',
      ).firstMatch(line);
      if (match == null || match.group(2) == null) continue;
      dependencies[match.group(1)!] = match.group(2)!;
    }
    return dependencies;
  }

  Map<String, String> lockBlocks(String lock) {
    final headers = RegExp(
      r'^  ([A-Za-z0-9_]+):\n',
      multiLine: true,
    ).allMatches(lock).toList(growable: false);
    final blocks = <String, String>{};
    for (var index = 0; index < headers.length; index += 1) {
      final header = headers[index];
      final end = index + 1 < headers.length
          ? headers[index + 1].start
          : lock.length;
      blocks[header.group(1)!] = lock.substring(header.end, end);
    }
    return blocks;
  }

  test('direct Pub dependencies are exact and match the checksum lock', () {
    final direct = directHostedDependencies(source('pubspec.yaml'));
    final blocks = lockBlocks(source('pubspec.lock'));
    final exactVersion = RegExp(
      r'^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$',
    );

    expect(direct, isNotEmpty);
    for (final entry in direct.entries) {
      expect(
        entry.value,
        matches(exactVersion),
        reason: '${entry.key} must use one exact reviewed version',
      );
      final block = blocks[entry.key];
      expect(
        block,
        isNotNull,
        reason: '${entry.key} is absent from pubspec.lock',
      );
      expect(block, contains('dependency: "direct main"'));
      expect(block, contains('source: hosted'));
      expect(
        block,
        matches(RegExp('version: "?${RegExp.escape(entry.value)}"?')),
      );
    }
  });

  test('every hosted Pub artifact has a SHA-256 and no mutable source', () {
    final blocks = lockBlocks(source('pubspec.lock'));
    var hostedCount = 0;
    for (final entry in blocks.entries) {
      final block = entry.value;
      expect(block, isNot(contains('source: git')), reason: entry.key);
      expect(block, isNot(contains('source: path')), reason: entry.key);
      if (!block.contains('source: hosted')) continue;
      hostedCount += 1;
      expect(
        block,
        matches(RegExp(r'sha256: "?[0-9a-f]{64}"?')),
        reason: '${entry.key} has no locked SHA-256',
      );
    }
    expect(hostedCount, greaterThan(50));
  });

  test('Gradle wrappers and every Maven artifact are checksum verified', () {
    for (final root in ['android', 'server_hardened']) {
      final wrapper = source('$root/gradle/wrapper/gradle-wrapper.properties');
      expect(wrapper, contains(r'distributionUrl=https\://'));
      expect(wrapper, matches(RegExp(r'distributionSha256Sum=[0-9a-f]{64}')));

      final metadataFile = File(
        '${Directory.current.path}/$root/gradle/verification-metadata.xml',
      );
      expect(metadataFile.existsSync(), isTrue, reason: root);
      final metadata = metadataFile.readAsStringSync();
      expect(metadata, contains('<verify-metadata>true</verify-metadata>'));
      expect(metadata, contains('<sha256 value='));
      expect(metadata, isNot(contains('<trusted-artifacts>')));
      expect(metadata, isNot(contains('<trusted-artifact ')));
      expect(metadata, isNot(contains('<ignored-key ')));
    }
  });

  test('repository and offline bundle policy has no mutable bypass', () {
    final repositorySources = [
      source('android/settings.gradle.kts'),
      source('android/build.gradle.kts'),
      source('server_hardened/settings.gradle.kts'),
    ].join('\n');
    expect(repositorySources, isNot(contains('mavenLocal(')));
    expect(repositorySources, isNot(matches(RegExp(r'http(?:\\)?:\/\/'))));
    expect(
      repositorySources.toLowerCase(),
      isNot(matches(RegExp(r'''url\s*=?\s*(?:uri\()?['"]https://jitpack'''))),
    );
    expect(repositorySources, contains('RepositoriesMode.PREFER_SETTINGS'));
    expect(repositorySources, contains('securechatVendored'));
    expect(
      repositorySources,
      contains('https://storage.googleapis.com/download.flutter.io'),
    );
    expect(repositorySources, contains('includeGroup("io.flutter")'));

    const coordinate =
        'android/vendor/maven/com/github/davidliu/audioswitch/'
        '039a35aefab7747c557242fa216c9ea11743b604/'
        'audioswitch-039a35aefab7747c557242fa216c9ea11743b604';
    final aar = File('${Directory.current.path}/$coordinate.aar');
    final pom = File('${Directory.current.path}/$coordinate.pom');
    expect(aar.existsSync(), isTrue);
    expect(pom.existsSync(), isTrue);
    expect(
      sha256.convert(aar.readAsBytesSync()).toString(),
      'c8240221daa9a96d4ea01a4dc6f6f6b10b4903d2a71f9b57f838bdfeb6c3fcbc',
    );
    expect(
      sha256.convert(pom.readAsBytesSync()).toString(),
      'b01278803fe0a007591a44143e1919a406c0c529794b13aa30e86a87532095fd',
    );

    final bundle = source('tool/make_offline_bundle.sh');
    expect(bundle, contains('maven_local_repo.tar.gz'));
    expect(bundle, contains('LOCAL_MAVEN_REPO'));
    expect(bundle, contains('verification-metadata.xml'));
    expect(bundle, contains(':signaling-server:test :bot-api:test --offline'));

    final libsignalFixtures = source('tool/prepare_libsignal_compat.sh');
    expect(libsignalFixtures, isNot(contains('http://')));
    for (final checksum in [
      'b19db36839ab008fdccefc7f8c005f2ea43dc7c7298a209bc424e6f9b6d5617b',
      '0aadd43cf01d11e9b58f867b3c4f25c3194e8b0623d1953d32dfbfbee009e38d',
      '215a94dbe100130295906b531bb72a26965c7ac8fcd9a75bf8054a8ac2abf4b4',
    ]) {
      expect(libsignalFixtures, contains(checksum));
    }
  });

  test('iOS Swift packages have a deterministic macOS resolution gate', () {
    final project = source('ios/Runner.xcodeproj/project.pbxproj');
    expect(project, contains('XCLocalSwiftPackageReference'));
    expect(project, contains('FlutterGeneratedPluginSwiftPackage'));

    final macGate = source('tool/verify_ios_on_macos.sh');
    expect(macGate, contains('Package.resolved.lock'));
    expect(macGate, contains('-onlyUsePackageVersionsFromResolvedFile'));
    expect(macGate, contains('-disableAutomaticPackageResolution'));
    expect(macGate, contains('IOS_OFFLINE'));
    expect(
      macGate,
      contains('dart tool/validate_swift_package_lock.dart "$resolved_lock"'),
    );
    expect(macGate, isNot(contains('plutil -lint "$resolved_lock"')));
    expect(macGate, contains('flutter build ios --release --no-codesign'));

    final settings = source('lib/src/features/settings/settings_screen.dart');
    expect(settings, contains('showLicensePage('));
    expect(source('docs/SUPPLY_CHAIN_AUDIT.md'), contains('GPL-3.0'));
  });
}
