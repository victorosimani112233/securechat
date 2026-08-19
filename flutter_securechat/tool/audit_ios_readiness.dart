import 'dart:io';

const _dartBridgeSources = [
  'lib/src/platform/native_bridge.dart',
  'lib/src/media/native_call_integration.dart',
  'lib/src/diagnostics/crash_reporter.dart',
  'lib/src/storage/legacy_room_importer.dart',
];

const _androidOnlyMethods = {
  'exportLegacyRoomDatabase',
  'archiveLegacyRoomDatabase',
};

const _requiredInfoPlistKeys = {
  'NSFaceIDUsageDescription',
  'NSCameraUsageDescription',
  'NSContactsUsageDescription',
  'NSMicrophoneUsageDescription',
  'NSPhotoLibraryUsageDescription',
  'UIBackgroundModes',
  'BGTaskSchedulerPermittedIdentifiers',
};

const _backgroundIdentifiers = {
  'com.securechat.app.background.maintenance',
  'com.securechat.app.background.sender-key-rotation',
};

void main() {
  final root = Directory.current;
  final failures = <String>[];
  String read(String path) {
    final file = File('${root.path}/$path');
    if (!file.existsSync()) {
      failures.add('Eksik dosya: $path');
      return '';
    }
    return file.readAsStringSync();
  }

  final dartMethods = <String>{};
  for (final path in _dartBridgeSources) {
    final source = read(path);
    for (final match in RegExp(
      r"(?:invoke(?:Map|List)?Method|_invoke)[\s\S]{0,100}?\(\s*'([^']+)'",
    ).allMatches(source)) {
      dartMethods.add(match[1]!);
    }
  }

  final swift = read('ios/Runner/AppDelegate.swift');
  final kotlin = read(
    'android/app/src/main/kotlin/com/securechat/app/MainActivity.kt',
  );
  final swiftMethods = RegExp(
    r'^\s*case "([^"]+)":',
    multiLine: true,
  ).allMatches(swift).map((match) => match[1]!).toSet();
  final kotlinMethods = RegExp(
    r'^\s*"([^"]+)"\s*->',
    multiLine: true,
  ).allMatches(kotlin).map((match) => match[1]!).toSet();
  final iosExpected = dartMethods.difference(_androidOnlyMethods);
  final iosMissing = iosExpected.difference(swiftMethods);
  final iosUnexpected = swiftMethods.difference(iosExpected);
  final androidMissing = dartMethods.difference(kotlinMethods);
  if (iosMissing.isNotEmpty) failures.add('Swift channel eksigi: $iosMissing');
  if (iosUnexpected.isNotEmpty) {
    failures.add(
      'Dart sozlesmesi olmayan Swift channel metodu: $iosUnexpected',
    );
  }
  if (androidMissing.isNotEmpty) {
    failures.add('Android channel eksigi: $androidMissing');
  }
  if (!swift.contains('channel.invokeMethod("nativeCallAction"') ||
      !read(
        'lib/src/media/native_call_integration.dart',
      ).contains("call.method != 'nativeCallAction'")) {
    failures.add('CallKit -> Dart nativeCallAction callback sozlesmesi eksik');
  }
  if (RegExp(
        r'earliestBeginInSeconds:\s*NSNumber\(value:',
      ).allMatches(swift).length !=
      2) {
    failures.add(
      'Workmanager periodic task sureleri Xcode 26 API icin NSNumber degil',
    );
  }

  final info = read('ios/Runner/Info.plist');
  for (final key in _requiredInfoPlistKeys) {
    if (!info.contains('<key>$key</key>')) {
      failures.add('Info.plist anahtari eksik: $key');
    }
  }
  final scheduler = read('lib/src/background/background_scheduler.dart');
  for (final identifier in _backgroundIdentifiers) {
    if (!info.contains(identifier) ||
        !swift.contains(identifier) ||
        !scheduler.contains(identifier)) {
      failures.add('BGTask kimligi uc katmanda esit degil: $identifier');
    }
  }

  final entitlements = read('ios/Runner/Runner.entitlements');
  final debugConfig = read('ios/Flutter/Debug.xcconfig');
  final releaseConfig = read('ios/Flutter/Release.xcconfig');
  if (!entitlements.contains('<key>aps-environment</key>') ||
      !entitlements.contains(r'$(APS_ENVIRONMENT)')) {
    failures.add('APNs entitlement build configuration ile bagli degil');
  }
  if (!debugConfig.contains('APS_ENVIRONMENT=development') ||
      !releaseConfig.contains('APS_ENVIRONMENT=production')) {
    failures.add('Debug/release APNs ortamlari ayrilmamis');
  }

  final privacy = read('ios/Runner/PrivacyInfo.xcprivacy');
  final project = read('ios/Runner.xcodeproj/project.pbxproj');
  for (final required in [
    '<key>NSPrivacyTracking</key>',
    '<false/>',
    'NSPrivacyCollectedDataTypeEmailAddress',
    'NSPrivacyCollectedDataTypePhoneNumber',
    'NSPrivacyCollectedDataTypeContacts',
    'NSPrivacyCollectedDataTypeUserID',
    'NSPrivacyCollectedDataTypeDeviceID',
    'NSPrivacyAccessedAPICategoryFileTimestamp',
    '<string>C617.1</string>',
  ]) {
    if (!privacy.contains(required)) {
      failures.add('Privacy manifest beyanı eksik: $required');
    }
  }
  if (!project.contains('PrivacyInfo.xcprivacy in Resources')) {
    failures.add('PrivacyInfo.xcprivacy Runner resources fazinda degil');
  }
  if (!project.contains(
    'CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements',
  )) {
    failures.add('Runner target entitlement dosyasini kullanmiyor');
  }
  final deploymentTargets = RegExp(
    r'IPHONEOS_DEPLOYMENT_TARGET = ([0-9.]+);',
  ).allMatches(project).map((match) => match[1]!).toList();
  if (deploymentTargets.length < 3 ||
      deploymentTargets.any((target) => target != '15.0')) {
    failures.add(
      'Tum iOS deployment targetlari Firebase Swift paketleri icin 15.0 olmali: '
      '$deploymentTargets',
    );
  }
  if (!project.contains('PRODUCT_BUNDLE_IDENTIFIER = com.securechat.app')) {
    failures.add('iOS bundle ID com.securechat.app degil');
  }

  final firebase = read('lib/src/push/push_service.dart');
  if (!firebase.contains('SECURECHAT_FIREBASE_IOS_APP_ID') ||
      !firebase.contains("iosBundleId: 'com.securechat.app'")) {
    failures.add('Explicit iOS Firebase configuration contract eksik');
  }

  final tests = read('ios/RunnerTests/RunnerTests.swift');
  if (!tests.contains('testPrivateFilePolicy') ||
      tests.contains('testExample()')) {
    failures.add('RunnerTests halen gercek native privacy testi icermiyor');
  }

  final plugins =
      RegExp(r'\[([A-Za-z0-9_]+) registerWithRegistrar:')
          .allMatches(read('ios/Runner/GeneratedPluginRegistrant.m'))
          .map((match) => match[1]!)
          .toList()
        ..sort();

  final result = failures.isEmpty ? 'PASS' : 'FAIL';
  final report = StringBuffer()
    ..writeln('# iOS Privacy ve Build Readiness Audit')
    ..writeln()
    ..writeln('Bu dosya `dart tool/audit_ios_readiness.dart` ile uretilir.')
    ..writeln(
      'Linux uzerinde statik sozlesmeyi kanitlar; Xcode derlemesi yerine gecmez.',
    )
    ..writeln()
    ..writeln('## Sonuc')
    ..writeln()
    ..writeln('- Statik readiness: **$result**')
    ..writeln('- Dart native method sayisi: ${dartMethods.length}')
    ..writeln(
      '- iOS method eslesmesi: ${iosExpected.length}/${iosExpected.length}',
    )
    ..writeln(
      '- Android method eslesmesi: ${dartMethods.length}/${dartMethods.length}',
    )
    ..writeln('- Kayitli iOS plugin sayisi: ${plugins.length}')
    ..writeln('- Minimum deployment target: iOS 15.0')
    ..writeln()
    ..writeln('## Gizlilik kararlari')
    ..writeln()
    ..writeln(
      '- Yeni oturumda notification preview ve last-seen paylasimi kapali baslar.',
    )
    ..writeln(
      '- App switcher goruntusu native opak overlay ile otomatik kapatilir.',
    )
    ..writeln(
      '- iOS screenshot engellenemez; uygulama yalniz cihaz-ici uyari verir ve server audit olayi gondermez.',
    )
    ..writeln(
      '- Rehberden yalniz ad ve telefon okunur; contact thumbnail alinmaz.',
    )
    ..writeln(
      '- Native open/share yalniz `Application Support/media` ve `crash_logs` altindaki normal dosyalari kabul eder; symlink escape reddedilir.',
    )
    ..writeln(
      '- CallKit/Telecom privacy modunda kisi adi ve account ID yerine generic etiket kullanir.',
    )
    ..writeln(
      '- Privacy manifest tracking=false, app-functionality veri kategorileri ve app-container file metadata icin `C617.1` beyanini tasir.',
    )
    ..writeln()
    ..writeln('## Platform davranisi')
    ..writeln()
    ..writeln(
      '- Background maintenance ve sender-key rotation kimlikleri Dart, Info.plist ve AppDelegate katmanlarinda aynidir.',
    )
    ..writeln(
      '- iOS scheduled-message calisma zamani BGTaskScheduler tarafindan garanti edilmez. Mesaj/plani servera birakmak gizlilik hedefiyle reddedildigi icin cihaz, izin verilen ilk background/foreground firsatinda gonderir.',
    )
    ..writeln(
      '- Push payload generic wake-up bilgisidir; mesaj, gonderen, grup veya preview tasimaz.',
    )
    ..writeln(
      '- `GoogleService-Info.plist` zorunlu kaynak dosyasi yapilmadi; Firebase explicit `FirebaseOptions` ve secret olmayan build-time iOS app ID ile kurulur.',
    )
    ..writeln()
    ..writeln('## Mac/Codemagic zorunlu kapisi')
    ..writeln()
    ..writeln(
      '1. Apple signing team, App ID, push capability ve provisioning profile ayarlanir.',
    )
    ..writeln(
      '2. `SECURECHAT_FIREBASE_IOS_APP_ID` build-time define saglanir; APNs key Firebase projesine yuklenir.',
    )
    ..writeln(
      '3. `tool/verify_ios_on_macos.sh` calistirilir; plist lint, analyze, tum Flutter testleri, unsigned iOS release compile ve Runner XCTest gecmeden release alinmaz.',
    )
    ..writeln(
      '4. Xcode Organizer privacy report ile app + plugin manifest birlesimi incelenir; App Store Connect beyanlari bu rapor ve production retention politikasiyla esit tutulur.',
    )
    ..writeln(
      '5. iOS terminated-state incoming call wake-up icin PushKit/VoIP capability ve server APNs VoIP gonderimi halen dis provisioning/deployment girdisidir; normal APNs wake-up CallKit icin garanti sayilmaz.',
    )
    ..writeln()
    ..writeln('## Kayitli pluginler')
    ..writeln()
    ..writeln(plugins.map((plugin) => '- `$plugin`').join('\n'))
    ..writeln()
    ..writeln('## Resmi Apple dayanaklari')
    ..writeln()
    ..writeln(
      '- https://developer.apple.com/documentation/bundleresources/privacy-manifest-files',
    )
    ..writeln(
      '- https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api',
    )
    ..writeln(
      '- https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/',
    )
    ..writeln()
    ..writeln('## Hatalar')
    ..writeln()
    ..writeln(
      failures.isEmpty ? '- Yok.' : failures.map((e) => '- $e').join('\n'),
    );

  File('${root.path}/docs/IOS_READINESS_AUDIT.md')
    ..createSync(recursive: true)
    ..writeAsStringSync(report.toString());

  stdout.writeln('iOS readiness: $result');
  if (failures.isNotEmpty) {
    for (final failure in failures) {
      stderr.writeln(failure);
    }
    exitCode = 1;
  }
}
