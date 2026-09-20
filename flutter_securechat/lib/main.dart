import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'src/app.dart';
import 'src/diagnostics/crash_reporter.dart';
import 'src/services/app_container.dart';

Future<void> main() async {
  PrivacyCrashReporter? reporter;
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await _runNotificationSmokeTest();
      LicenseRegistry.addLicense(() async* {
        final license = await rootBundle.loadString(
          'assets/licenses/audioswitch_APACHE-2.0.txt',
        );
        yield LicenseEntryWithLineBreaks(const ['audioswitch'], license);
      });
      final support = await getApplicationSupportDirectory();
      reporter = await PrivacyCrashReporter.open(
        directory: Directory('${support.path}/crash_logs'),
      );
      reporter!.installGlobalHandlers();
      final container = await AppContainer.bootstrap(crashReporter: reporter);
      runApp(SecureChatFlutterApp(container: container));
    },
    (error, stackTrace) {
      final active = reporter;
      if (active != null) {
        unawaited(
          active.recordException(
            error,
            stackTrace,
            context: 'root-zone',
            fatal: true,
          ),
        );
      }
    },
  );
}

/// Opt-in device diagnostic. Production builds remain clean unless the define
/// is explicitly enabled for a smoke-test APK.
Future<void> _runNotificationSmokeTest() async {
  const enabled = bool.fromEnvironment(
    'SECURECHAT_NOTIFICATION_SMOKE_TEST',
    defaultValue: false,
  );
  if (!enabled || kIsWeb || !Platform.isAndroid) return;
  final notifications = FlutterLocalNotificationsPlugin();
  await notifications.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('notification_icon'),
    ),
  );
  await notifications.show(
    id: 999,
    title: 'Test',
    body: 'Bildirim katmani calisiyor',
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        'elcim_smoke_test',
        'Test',
        importance: Importance.high,
        priority: Priority.high,
        icon: 'notification_icon',
      ),
    ),
  );
}
