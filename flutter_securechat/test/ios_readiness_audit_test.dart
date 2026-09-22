import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/audit_ios_readiness.dart';

void main() {
  test(
    'Dart methods include typed calls and wrapper calls, not cue values',
    () {
      expect(
        dartChannelMethods('''
      _channel.invokeMethod<bool>('startNativeCallRingback');
      _invoke("stopNativeCallTones");
      _invoke('playNativeCallCue', {'cue': 'connected'});
      _invoke('playNativeCallCue', {'cue': 'ended'});
      channel.invokeMapMethod<String, Map<String, Object?>>('readContacts');
      channel.invokeListMethod<Object?>('readList');
      Future<void> _invoke(String method) => channel.invokeMethod(method);
      // _invoke('commentOnly');
      /* nested /* _invoke('nestedComment'); */ _invoke('comment'); */
      final example = "_invoke('stringOnly')";
    '''),
        {
          'startNativeCallRingback',
          'stopNativeCallTones',
          'playNativeCallCue',
          'readContacts',
          'readList',
        },
      );
    },
  );

  test('Dart type argument length does not limit method detection', () {
    final type = 'VeryLongTypeName' * 10;
    expect(dartChannelMethods("channel.invokeMethod<$type>('realMethod');"), {
      'realMethod',
    });
  });

  test('Swift channel cases are scoped to direct method dispatch', () {
    expect(
      swiftChannelMethods(r'''
      // switch call.method { case "comment": break }
      /* outer /* case "nestedComment": */ case "comment": */
      let example = "switch call.method { case \"string\": }"
      switch call.method {
        case "startNativeCallRingback": result(true)
        case "stopNativeCallTones", "playNativeCallCue":
          switch cue {
            case "connected": play("}")
            case "ended": play("{")
            default: break
          }
        default: result(FlutterMethodNotImplemented)
      }
      switch cue {
        case "connected": return true
        case "ended": return true
        default: return false
      }
    '''),
      {'startNativeCallRingback', 'stopNativeCallTones', 'playNativeCallCue'},
    );
  });

  test('Swift reads multiple dispatch blocks across formatting changes', () {
    expect(
      swiftChannelMethods('''
      switch /* comment */ call.method { case "one": break }
      switch call
        .method
      { case "two": break }
    '''),
      {'one', 'two'},
    );
  });

  group('complete audit', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('ios_readiness_');
      for (final path in _auditInputs) {
        final target = File('${root.path}/$path');
        target.parent.createSync(recursive: true);
        File(path).copySync(target.path);
      }
      // Only presence is checked for the vendored amalgamation, not contents.
      File('${root.path}/ios/SQLCipher/Sources/CSQLCipher/sqlite3.c')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('');
    });

    tearDown(() => root.deleteSync(recursive: true));

    void replace(String path, String before, String after) {
      final file = File('${root.path}/$path');
      final source = file.readAsStringSync();
      expect(source, contains(before), reason: 'fixture drift in $path');
      file.writeAsStringSync(source.replaceFirst(before, after));
    }

    test('current contract passes without writing the readiness report', () {
      final result = auditIosReadiness(root);
      expect(result.failures, isEmpty);
      expect(
        File('${root.path}/docs/IOS_READINESS_AUDIT.md').existsSync(),
        isFalse,
      );
    });

    for (final method in [
      'startNativeCallRingback',
      'stopNativeCallTones',
      'playNativeCallCue',
      'reportOutgoingCall',
    ]) {
      test('removing $method is a real audit failure', () {
        replace(
          'ios/Runner/AppDelegate.swift',
          'case "$method":',
          'case "removed":',
        );
        final result = auditIosReadiness(root);
        expect(result.passed, isFalse);
        expect(result.failures, contains('Swift channel eksigi: {$method}'));
        final counts = RegExp(
          r'iOS method eslesmesi: (\d+)/(\d+)',
        ).firstMatch(result.report)!;
        expect(int.parse(counts[1]!), int.parse(counts[2]!) - 1);
      });
    }

    test('unexpected channel methods still fail', () {
      replace('ios/Runner/AppDelegate.swift', 'switch call.method {', '''
        switch call.method {
        case "orphanMethod": result(nil)
      ''');
      expect(
        auditIosReadiness(root).failures,
        contains(
          'Dart sozlesmesi olmayan Swift channel metodu: {orphanMethod}',
        ),
      );
    });

    for (final cue in ['connected', 'ended']) {
      test('a real $cue channel case is not hidden by a cue allowlist', () {
        replace('ios/Runner/AppDelegate.swift', 'switch call.method {', '''
          switch call.method {
          case "$cue": result(nil)
        ''');
        expect(
          auditIosReadiness(root).failures,
          contains('Dart sozlesmesi olmayan Swift channel metodu: {$cue}'),
        );
      });
    }

    test('missing call tone Dart source does not silently pass', () {
      File('${root.path}/lib/src/media/call_tone_service.dart').deleteSync();
      expect(
        auditIosReadiness(root).failures,
        contains('Eksik dosya: lib/src/media/call_tone_service.dart'),
      );
    });

    test('missing outgoing CallKit capability fails, even in a comment', () {
      replace(
        'ios/Runner/Info.plist',
        '<string>voip</string>',
        '<!-- <string>voip</string> -->',
      );
      expect(
        auditIosReadiness(root).failures,
        contains('CallKit outgoing calls require UIBackgroundModes voip'),
      );
    });

    test('an unrelated voip plist value cannot satisfy CallKit capability', () {
      replace('ios/Runner/Info.plist', '<string>voip</string>', '');
      replace(
        'ios/Runner/Info.plist',
        '<key>CFBundleName</key>',
        '<key>Unrelated</key><string>voip</string><key>CFBundleName</key>',
      );
      expect(auditIosReadiness(root).passed, isFalse);
    });

    test('missing real Android channel method remains an audit failure', () {
      replace(
        'android/app/src/main/kotlin/com/securechat/app/MainActivity.kt',
        '"playNativeCallCue" ->',
        '"removed" ->',
      );
      expect(
        auditIosReadiness(root).failures,
        contains('Android channel eksigi: {playNativeCallCue}'),
      );
    });

    test('check mode exits nonzero on failure without rewriting docs', () async {
      replace('ios/Runner/Info.plist', '<string>voip</string>', '');
      final report = File('${root.path}/docs/IOS_READINESS_AUDIT.md')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('existing user report');
      final configFile = File('.dart_tool/package_config.json');
      final config = jsonDecode(configFile.readAsStringSync()) as Map;
      final flutterPackage = (config['packages'] as List)
          .cast<Map>()
          .singleWhere((package) => package['name'] == 'flutter');
      final flutterRoot = Directory.fromUri(
        configFile.absolute.uri.resolve(flutterPackage['rootUri'] as String),
      ).parent.parent;
      final dart = File(
        '${flutterRoot.path}/bin/cache/dart-sdk/bin/dart${Platform.isWindows ? '.exe' : ''}',
      );
      final result = await Process.run(dart.path, [
        File('tool/audit_ios_readiness.dart').absolute.path,
        '--check',
      ], workingDirectory: root.path);
      expect(result.exitCode, 1);
      expect(result.stdout, contains('iOS readiness: FAIL'));
      expect(result.stderr, contains('UIBackgroundModes voip'));
      expect(report.readAsStringSync(), 'existing user report');
    });
  });
}

const _auditInputs = [
  'lib/src/platform/native_bridge.dart',
  'lib/src/media/native_call_integration.dart',
  'lib/src/media/call_tone_service.dart',
  'lib/src/diagnostics/crash_reporter.dart',
  'lib/src/storage/legacy_room_importer.dart',
  'lib/src/background/background_scheduler.dart',
  'lib/src/storage/encrypted_record_store.dart',
  'lib/src/push/push_service.dart',
  'ios/Runner/AppDelegate.swift',
  'ios/Runner/Info.plist',
  'ios/Runner/Runner.entitlements',
  'ios/Flutter/Debug.xcconfig',
  'ios/Flutter/Release.xcconfig',
  'ios/Runner/PrivacyInfo.xcprivacy',
  'ios/Runner.xcodeproj/project.pbxproj',
  'ios/SQLCipher/Package.swift',
  'ios/RunnerTests/RunnerTests.swift',
  'ios/Runner/GeneratedPluginRegistrant.m',
  'android/app/src/main/kotlin/com/securechat/app/MainActivity.kt',
];
