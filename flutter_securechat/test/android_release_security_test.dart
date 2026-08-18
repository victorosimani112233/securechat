import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android release manifest is no-backup and no-cleartext', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, contains('android:fullBackupContent="false"'));
    expect(manifest, contains('android:usesCleartextTraffic="false"'));
    expect(manifest, contains('@xml/network_security_config'));
    expect(
      File(
        'android/app/src/main/res/xml/network_security_config.xml',
      ).readAsStringSync(),
      contains('cleartextTrafficPermitted="false"'),
    );
  });

  test(
    'screen capture opt-out is debug-only and release remains fail-closed',
    () {
      final mainManifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      final debugManifest = File(
        'android/app/src/debug/AndroidManifest.xml',
      ).readAsStringSync();
      final activity = File(
        'android/app/src/main/kotlin/com/securechat/app/MainActivity.kt',
      ).readAsStringSync();

      expect(mainManifest, isNot(contains('DEBUG_ALLOW_SCREEN_CAPTURE')));
      expect(debugManifest, contains('DEBUG_ALLOW_SCREEN_CAPTURE'));
      expect(activity, contains('ApplicationInfo.FLAG_DEBUGGABLE'));
      expect(activity, contains('if (!debuggable) return false'));
      expect(activity, contains('WindowManager.LayoutParams.FLAG_SECURE'));
    },
  );

  test(
    'device QA auth server is loopback-only and absent from runtime code',
    () {
      final server = File(
        'tool/local_device_qa_server.dart',
      ).readAsStringSync();
      expect(server, contains('InternetAddress.loopbackIPv4'));
      expect(server, isNot(contains('InternetAddress.anyIPv4')));
      expect(server, isNot(contains('request body:')));
      for (final source in Directory('lib').listSync(recursive: true)) {
        if (source is! File || !source.path.endsWith('.dart')) continue;
        expect(
          source.readAsStringSync(),
          isNot(contains('local_device_qa_server')),
          reason: '${source.path} must not import the local QA server',
        );
      }
    },
  );

  test(
    'debug notification tap hook is immutable and excluded from release',
    () {
      final mainManifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      final debugManifest = File(
        'android/app/src/debug/AndroidManifest.xml',
      ).readAsStringSync();
      final receiver = File(
        'android/app/src/debug/kotlin/com/securechat/app/debug/'
        'TestNotificationReceiver.kt',
      ).readAsStringSync();

      expect(mainManifest, isNot(contains('TestNotificationReceiver')));
      expect(debugManifest, contains('TestNotificationReceiver'));
      expect(receiver, contains('PendingIntent.FLAG_IMMUTABLE'));
      expect(receiver, contains('action = "SELECT_NOTIFICATION"'));
      expect(receiver, contains('putExtra("payload"'));
      expect(receiver, contains('.setContentIntent(contentIntent)'));
    },
  );

  test('release build enables native and Dart obfuscation controls', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('isMinifyEnabled = true'));
    expect(gradle, contains('isShrinkResources = true'));
    expect(gradle, contains('proguard-android-optimize.txt'));
    final script = File(
      'tool/build_hardened_android_release.sh',
    ).readAsStringSync();
    expect(script, contains('--obfuscate'));
    expect(script, contains('--split-debug-info='));
    expect(
      script,
      isNot(contains('--no-pub')),
      reason: 'Flutter must regenerate a release registrant without dev plugins',
    );
    expect(script, contains('sha256sum'));
  });
}
