import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final project = Directory.current;
  final repository = project.parent;

  String relative(String path, String root) =>
      path.substring(root.endsWith('/') ? root.length : root.length + 1);

  List<_AuditRow> auditRows() {
    final document = File(
      '${project.path}/docs/SOURCE_AUDIT.md',
    ).readAsLinesSync();
    return document
        .where((line) => line.startsWith('| [`'))
        .map(_AuditRow.parse)
        .toList(growable: false);
  }

  Map<String, Set<String>> dartGraph() {
    final graph = <String, Set<String>>{};
    final directive = RegExp(
      r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]''',
      multiLine: true,
    );
    for (final file
        in Directory('${project.path}/lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))) {
      final source = relative(file.path, project.path);
      final dependencies = <String>{};
      for (final match in directive.allMatches(file.readAsStringSync())) {
        final reference = match.group(1)!;
        if (reference.startsWith('package:flutter_securechat/')) {
          dependencies.add(
            'lib/${reference.substring('package:flutter_securechat/'.length)}',
          );
        } else if (!reference.startsWith('dart:') &&
            !reference.startsWith('package:')) {
          final target = File.fromUri(file.parent.uri.resolve(reference));
          if (target.path.startsWith('${project.path}/lib/')) {
            dependencies.add(relative(target.path, project.path));
          }
        }
      }
      graph[source] = dependencies;
    }
    return graph;
  }

  Set<String> reachableFromMain(Map<String, Set<String>> graph) {
    final reachable = <String>{};
    final pending = <String>['lib/main.dart'];
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      if (!reachable.add(current)) continue;
      pending.addAll(
        (graph[current] ?? const <String>{}).where(graph.containsKey),
      );
    }
    return reachable;
  }

  test('all 271 Kotlin and Java sources have one differential audit row', () {
    final actualSources = <String>{};
    for (final module in const [
      'app',
      'crypto',
      'storage',
      'network',
      'media',
      'contacts',
    ]) {
      final sourceRoot = Directory('${repository.path}/$module/src/main/java');
      actualSources.addAll(
        sourceRoot
            .listSync(recursive: true)
            .whereType<File>()
            .where(
              (file) =>
                  file.path.endsWith('.kt') || file.path.endsWith('.java'),
            )
            .map((file) => relative(file.path, repository.path)),
      );
    }

    final rows = auditRows();
    expect(actualSources, hasLength(271));
    expect(rows, hasLength(271));
    expect(rows.map((row) => row.source).toSet(), actualSources);
    expect(rows.map((row) => row.source).toSet(), hasLength(rows.length));
    expect(rows.where((row) => row.status == 'GAP'), isEmpty);
  });

  test('every implemented Dart target is reachable from production main', () {
    final graph = dartGraph();
    final reachable = reachableFromMain(graph);

    for (final row in auditRows()) {
      if (row.target == '-') {
        expect(row.status, 'DECISION', reason: row.source);
        expect(row.caller, '-', reason: row.source);
        continue;
      }

      final target = File('${project.path}/${row.target}');
      expect(target.existsSync(), isTrue, reason: row.source);
      if (row.testPath != '-') {
        expect(
          File('${project.path}/${row.testPath}').existsSync(),
          isTrue,
          reason: row.source,
        );
      }

      if (row.target.startsWith('test/')) {
        expect(row.status, 'MERGED', reason: row.source);
        expect(row.caller, 'TEST_ONLY', reason: row.source);
        continue;
      }

      expect(row.caller, isNot('-'), reason: row.source);
      if (row.target == 'lib/main.dart') {
        expect(row.caller, 'ENTRYPOINT', reason: row.source);
      } else if (row.target.startsWith('lib/')) {
        expect(reachable, contains(row.target), reason: row.source);
        expect(reachable, contains(row.caller), reason: row.source);
        expect(
          graph[row.caller],
          contains(row.target),
          reason:
              '${row.source}: ${row.caller} must directly load '
              '${row.target}',
        );
      } else {
        final caller = File('${project.path}/${row.caller}');
        expect(caller.existsSync(), isTrue, reason: row.source);
        final className = row.target.split('/').last.replaceAll('.kt', '');
        expect(
          caller.readAsStringSync(),
          contains(className),
          reason: row.source,
        );
      }
    }
  });

  test('every source records a non-empty behavior or privacy invariant', () {
    const acceptedStatuses = {'COVERED', 'MERGED', 'PLATFORM', 'DECISION'};
    final decisions = <String>{};
    for (final row in auditRows()) {
      expect(acceptedStatuses, contains(row.status), reason: row.source);
      expect(row.invariant.trim(), isNotEmpty, reason: row.source);
      if (row.status == 'DECISION') decisions.add(row.source);
    }
    expect(decisions, {
      'app/src/main/java/com/securechat/app/data/BackgroundBlurStore.kt',
      'app/src/main/java/com/securechat/app/diagnostics/HybridLegacyTelemetry.kt',
      'media/src/main/java/com/securechat/media/BackgroundBlurProcessor.kt',
      'network/src/main/java/com/securechat/network/P2PMessageTransport.kt',
    });
  });

  test(
    'production Dart has no executable migration stubs or empty actions',
    () {
      final forbidden = <({RegExp pattern, String label})>[
        (
          pattern: RegExp(r'\bUnsupportedError\s*\('),
          label: 'UnsupportedError',
        ),
        (
          pattern: RegExp(r'\bUnimplementedError\s*\('),
          label: 'UnimplementedError',
        ),
        (pattern: RegExp(r'\b(?:TODO|FIXME)\b'), label: 'TODO/FIXME'),
        (
          pattern: RegExp(r'on(?:Pressed|Tap|LongPress)\s*:\s*\(\)\s*\{\s*\}'),
          label: 'empty UI callback',
        ),
      ];

      for (final file
          in Directory('${project.path}/lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => file.path.endsWith('.dart'))
              .where((file) => !file.path.contains('/l10n/generated/'))) {
        final source = file.readAsStringSync();
        for (final entry in forbidden) {
          expect(
            entry.pattern.hasMatch(source),
            isFalse,
            reason: '${relative(file.path, project.path)}: ${entry.label}',
          );
        }
      }
    },
  );

  test('message send remains fail-closed and group routing stays private', () {
    final sender = File(
      '${project.path}/lib/src/domain/send_message_use_case.dart',
    ).readAsStringSync();
    final encryptionFailure = sender.substring(
      sender.indexOf('} catch (_) {'),
      sender.indexOf('for (var attempt'),
    );

    expect(encryptionFailure, contains('StorageMessageStatus.failed'));
    expect(encryptionFailure, contains('SendMessageOutcome.encryptionFailed'));
    expect(encryptionFailure, isNot(contains('_signaling.send')));
    expect(sender, isNot(contains('GroupMessageFanoutSignal(')));
    expect(sender, contains('encodePrivateGroupRoute('));
    expect(sender, contains('await _crypto.encryptDirect('));
  });

  test('hardened Android release audits delivered code and secret leakage', () {
    final build = File(
      '${project.path}/tool/build_hardened_android_release.sh',
    ).readAsStringSync();
    final audit = File(
      '${project.path}/tool/audit_android_release.sh',
    ).readAsStringSync();

    expect(build, contains('--obfuscate'));
    expect(build, contains('--split-debug-info'));
    expect(build, contains('audit_android_release.sh'));
    expect(audit, contains("\$AUDIT_DIR/base/lib"));
    expect(audit, contains(r'$2 ~ /^\.debug/ || $2 == ".symtab"'));
    expect(
      audit,
      contains(
        'BUNDLE-METADATA/com.android.tools.build.obfuscation/proguard.map',
      ),
    );
    expect(audit, contains('DIRECTORY_OPRF_PRIVATE_KEY='));
    expect(audit, contains('BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY'));
  });
}

class _AuditRow {
  const _AuditRow({
    required this.source,
    required this.status,
    required this.target,
    required this.caller,
    required this.testPath,
    required this.invariant,
  });

  factory _AuditRow.parse(String line) {
    final cells = line.split('|').map((cell) => cell.trim()).toList();
    if (cells.length < 8) {
      throw FormatException('Invalid source audit row: $line');
    }
    return _AuditRow(
      source: _path(cells[1]),
      status: cells[2],
      target: _path(cells[3]),
      caller: _path(cells[4]),
      testPath: _path(cells[5]),
      invariant: cells[6],
    );
  }

  static String _path(String cell) {
    final match = RegExp(r'`([^`]+)`').firstMatch(cell);
    return match?.group(1) ?? cell;
  }

  final String source;
  final String status;
  final String target;
  final String caller;
  final String testPath;
  final String invariant;
}
