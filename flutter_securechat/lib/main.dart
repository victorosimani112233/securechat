import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
