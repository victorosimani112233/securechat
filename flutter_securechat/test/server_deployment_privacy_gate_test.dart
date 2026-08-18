import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/audit_server_deployment_privacy.dart';

void main() {
  test('hardened deployment has no persistent operational metadata path', () {
    expect(
      auditServerDeploymentPrivacy(projectRoot: Directory.current),
      isEmpty,
    );
  });

  test('secret source is wired into every cryptographic server boundary', () {
    String source(String path) => File(path).readAsStringSync();

    final signalingRoot =
        'server_hardened/signaling-server/src/main/kotlin/'
        'com/securechat/signaling';
    expect(
      source('$signalingRoot/ServerPrivacy.kt'),
      contains('SecretSource.required(name, environment)'),
    );
    expect(
      source('$signalingRoot/FcmTokenCipher.kt'),
      contains(
        'SecretSource.required("FCM_TOKEN_ENCRYPTION_KEY", environment)',
      ),
    );
    expect(
      source('$signalingRoot/Application.kt'),
      contains('PurposeSeparatedSecrets.validate()'),
    );
    expect(
      source(
        'server_hardened/bot-api/src/main/kotlin/'
        'com/securechat/botapi/BotApiConfig.kt',
      ),
      allOf(
        contains('SecretSource.required(name)'),
        contains('requirePurposeSeparatedSecrets()'),
      ),
    );
  });

  test('production deploy gate is immutable and non-mutating by default', () {
    final deploy = File(
      'server_hardened/deploy/deploy_privacy_stack.sh',
    ).readAsStringSync();

    expect(
      deploy,
      allOf(
        contains(r'mode="${1:---check-only}"'),
        contains('require_digest REDIS_IMAGE'),
        contains('require_digest SIGNALING_IMAGE'),
        contains('require_digest BOT_API_IMAGE'),
        contains('sslmode=verify-full'),
        contains('secret_fingerprints'),
        contains('DATABASE_URL must not embed a database password'),
      ),
    );
    expect(deploy, contains('SECURECHAT_DEPLOY_CONFIRMATION'));
    expect(deploy, isNot(contains('infra/docker-compose.yml')));
  });
}
