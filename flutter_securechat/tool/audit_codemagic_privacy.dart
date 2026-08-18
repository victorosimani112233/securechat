import 'dart:io';

List<String> auditCodemagicPrivacy({Directory? projectRoot}) {
  final project = projectRoot ?? Directory.current;
  final yaml = File('${project.parent.path}/codemagic.yaml');
  final macGate = File('${project.path}/tool/verify_ios_on_macos.sh');
  final failures = <String>[];
  if (!yaml.existsSync()) return ['repo-root codemagic.yaml is missing'];
  if (!macGate.existsSync()) return ['macOS verification gate is missing'];
  final source = yaml.readAsStringSync();
  final gate = macGate.readAsStringSync();

  void requireText(String value, String message) {
    if (!source.contains(value)) failures.add(message);
  }

  void forbidText(String value, String message) {
    if (source.contains(value)) failures.add(message);
  }

  void requireWorkflowVar(String name) {
    final pattern = RegExp('^\\s+$name:\\s+"[^"]+"\\s*\$', multiLine: true);
    if (pattern.allMatches(source).length != 2) {
      failures.add('$name must be pinned once in each Codemagic workflow');
    }
  }

  requireText(
    'working_directory: flutter_securechat',
    'Codemagic must target only the Flutter migration directory',
  );
  requireText('flutter: 3.44.9', 'Flutter must be version-pinned');
  requireText('xcode: 26.0', 'Xcode must be version-pinned');
  requireText(
    'appstore_credentials',
    'signed workflow must use encrypted Codemagic credential variables',
  );
  requireText(
    'IOS_SKIP_FLUTTER_CHECKS=1 IOS_SIGNED_BUILD=1',
    'signed build must follow the complete macOS verification gate',
  );
  requireText(
    'dart tool/audit_codemagic_privacy.dart',
    'Codemagic must audit its own privacy boundary',
  );
  forbidText('publishing:', 'candidate workflow must never auto-publish');
  forbidText('printenv', 'workflow must never dump the environment');
  forbidText('set -x', 'workflow must never echo secret-bearing commands');
  forbidText('eval ', 'workflow must never evaluate environment data as code');
  requireText(
    'set -euo pipefail',
    'configuration gates must fail on errors, unset variables and pipe failures',
  );
  forbidText(
    'APP_STORE_CONNECT_PRIVATE_KEY: ',
    'App Store private key values must not be committed to the workflow',
  );

  for (final input in [
    'SECURECHAT_FIREBASE_IOS_APP_ID',
    'SECURECHAT_API_BASE_URL',
    'SECURECHAT_SIGNALING_URL',
    'SECURECHAT_CERT_PIN_HOST',
    'SECURECHAT_CERT_PIN_SHA256',
    'SECURECHAT_CERT_PIN_SHA256_BACKUP',
  ]) {
    requireWorkflowVar(input);
    if (!gate.contains(input)) {
      failures.add('macOS gate does not require $input');
    }
  }
  if (!gate.contains(r'dart_defines+=("--dart-define=$name=$value")')) {
    failures.add('macOS gate does not forward every validated build input');
  }
  return failures;
}

void main() {
  final failures = auditCodemagicPrivacy();
  if (failures.isEmpty) {
    stdout.writeln('Codemagic privacy audit: PASS');
    return;
  }
  for (final failure in failures) {
    stderr.writeln('FAIL: $failure');
  }
  exitCode = 1;
}
