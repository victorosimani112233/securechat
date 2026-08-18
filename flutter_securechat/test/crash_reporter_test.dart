import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_securechat/src/diagnostics/crash_reporter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'crash report is private, bounded and strips content and credentials',
    () async {
      final root = await Directory.systemTemp.createTemp('crash_reporter_');
      addTearDown(() => root.delete(recursive: true));
      final gateway = _FakeDiagnosticsPlatformGateway();
      final reporter = await PrivacyCrashReporter.open(
        directory: Directory('${root.path}/reports'),
        platform: gateway,
        maximumFiles: 2,
      );
      reporter.setUserId('private-user-id');
      reporter.setCustomKey('component', 'signaling');
      reporter.setCustomKey('token', 'access-secret');

      for (var index = 0; index < 3; index++) {
        await reporter.recordException(
          StateError('private-message access-secret +905551112233'),
          StackTrace.fromString(
            '#0 send (file:///Users/private/source/send.dart:1:2)\n'
            '#1 main (package:app/main.dart:2:3)',
          ),
          context: 'send-message',
          metadata: {
            'operation': 'retry',
            'retryCount': index,
            'message': 'private-message',
            'token': 'access-secret',
          },
          fatal: index == 2,
        );
        await Future<void>.delayed(const Duration(microseconds: 2));
      }

      final reports = await reporter.listReports();
      expect(reports, hasLength(2));
      final payload = await reports.first.readAsString();
      expect(payload, isNot(contains('private-message')));
      expect(payload, isNot(contains('access-secret')));
      expect(payload, isNot(contains('+905551112233')));
      expect(payload, isNot(contains('/Users/private')));
      expect(payload, isNot(contains('private-user-id')));
      expect(payload, contains(sha256ForTest('private-user-id')));
      final json = jsonDecode(payload) as Map<String, dynamic>;
      expect(json['errorType'], 'StateError');
      expect(json['fatal'], isTrue);
      expect((json['metadata'] as Map)['retryCount'], 2);
      expect((json['metadata'] as Map).containsKey('message'), isFalse);
      expect((json['custom'] as Map).containsKey('token'), isFalse);
    },
  );

  test(
    'latest report shares through platform gateway and clear is scoped',
    () async {
      final root = await Directory.systemTemp.createTemp('crash_share_');
      addTearDown(() => root.delete(recursive: true));
      final gateway = _FakeDiagnosticsPlatformGateway();
      final directory = Directory('${root.path}/reports');
      final reporter = await PrivacyCrashReporter.open(
        directory: directory,
        platform: gateway,
      );
      final unrelated = File('${directory.path}/keep.bin');
      await unrelated.writeAsBytes([1]);
      expect(await reporter.shareLatest(), isFalse);

      await reporter.recordException(
        Exception('hidden'),
        StackTrace.fromString('#0 main (package:app/main.dart:1:1)'),
        fatal: false,
      );
      expect(await reporter.shareLatest(), isTrue);
      expect(gateway.shared?.path, (await reporter.listReports()).single.path);
      expect(await reporter.clearAll(), 1);
      expect(await unrelated.exists(), isTrue);
    },
  );
}

class _FakeDiagnosticsPlatformGateway implements DiagnosticsPlatformGateway {
  File? shared;

  @override
  Future<CrashMetadata> metadata() async => const CrashMetadata(
    versionName: '1.0.76',
    versionCode: '76',
    operatingSystem: 'test',
    osVersion: '1',
    deviceModel: 'fixture',
    manufacturer: 'fixture',
  );

  @override
  Future<bool> share(File file) async {
    shared = file;
    return true;
  }
}

String sha256ForTest(String value) {
  return sha256.convert(utf8.encode(value)).toString();
}
