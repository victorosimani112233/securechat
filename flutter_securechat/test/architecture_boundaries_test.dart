import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('feature widgets do not import low-level infrastructure', () {
    const forbiddenImports = <String>[
      "package:cryptography/",
      "package:firebase_",
      "package:http/",
      "package:flutter_webrtc/",
      "package:web_socket_channel/",
      "../../crypto/",
      "../../network/",
      "../../platform/",
      "../../storage/legacy_room_importer.dart",
      "../../storage/secure_chat_database.dart",
      "../../services/crypto_service.dart",
      "../../services/key_material_store.dart",
      "../../services/signaling_service.dart",
    ];
    final violations = <String>[];
    for (final file in _dartFiles(Directory('lib/src/features'))) {
      final source = file.readAsStringSync();
      for (final forbidden in forbiddenImports) {
        if (source.contains(forbidden)) {
          violations.add('${file.path}: $forbidden');
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('composition root does not leak into domain and infrastructure', () {
    final violations = <String>[];
    for (final file in _dartFiles(Directory('lib/src'))) {
      final normalized = file.path.replaceAll('\\', '/');
      final allowed =
          normalized == 'lib/src/app.dart' ||
          normalized.startsWith('lib/src/features/') ||
          normalized.startsWith('lib/src/widgets/') ||
          normalized == 'lib/src/services/app_container.dart';
      if (!allowed && file.readAsStringSync().contains('app_container.dart')) {
        violations.add(normalized);
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('feature widgets do not force unwrap optional app runtimes', () {
    final violations = <String>[];
    final pattern = RegExp(
      r'\.(?:cryptoRuntime|networkRuntime|mediaRuntime|backgroundRuntime|'
      r'pushRuntime|backupRuntime|auditRuntime|groupRuntime|storageRuntime|'
      r'chatInfoRuntime|forwardRuntime|readReceiptRuntime|onboardingRuntime|'
      r'bulkRuntime|settingsRuntime|accountDataRuntime|notificationRuntime|'
      r'diagnosticsRuntime|debugRuntime|auth|contacts)!',
    );
    for (final file in _dartFiles(Directory('lib/src/features'))) {
      if (pattern.hasMatch(file.readAsStringSync())) {
        violations.add(file.path);
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test(
    'test fixtures and test constructors stay outside production callers',
    () {
      final productionSources = _dartFiles(Directory('lib'))
          .where(
            (file) => !file.path
                .replaceAll('\\', '/')
                .endsWith('lib/src/services/app_container.dart'),
          )
          .map((file) => file.readAsStringSync())
          .join('\n');
      expect(productionSources, isNot(contains('AppContainer.demo')));
      expect(productionSources, isNot(contains('demoConversations')));
      expect(productionSources, isNot(contains('demoMessages')));
      expect(productionSources, isNot(contains('demo-access-token')));
      expect(productionSources, isNot(contains('demo-refresh-token')));
      expect(productionSources, isNot(contains('AppContainer.testing(')));
    },
  );

  test('production composition owns one stuck-message recovery instance', () {
    final source = File(
      'lib/src/services/app_container.dart',
    ).readAsStringSync();
    expect(_occurrences(source, 'StuckMessageRecovery(database)'), 1);
    expect(source, contains('AppContainer.production('));
  });

  test('production composition owns and tears down runtime resources', () {
    final container = File(
      'lib/src/services/app_container.dart',
    ).readAsStringSync();
    final app = File('lib/src/app.dart').readAsStringSync();
    final background = File(
      'lib/src/background/background_tasks.dart',
    ).readAsStringSync();

    expect(container, contains('required AppResourceScope resources'));
    expect(container, contains("resources.register('secure-database'"));
    expect(container, contains("'websocket-signaling', signaling.dispose"));
    expect(container, contains("'application-lifecycle', lifecycle.dispose"));
    expect(container, contains('if (!bootstrapComplete)'));
    expect(app, contains('widget.container.dispose()'));
    expect(background, contains('await _resources.dispose()'));
  });
}

Iterable<File> _dartFiles(Directory root) sync* {
  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is File && entity.path.endsWith('.dart')) yield entity;
  }
}

int _occurrences(String source, String pattern) {
  var count = 0;
  var start = 0;
  while (true) {
    final index = source.indexOf(pattern, start);
    if (index < 0) return count;
    count += 1;
    start = index + pattern.length;
  }
}
