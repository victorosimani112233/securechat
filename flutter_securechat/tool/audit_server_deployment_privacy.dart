import 'dart:io';

List<String> auditServerDeploymentPrivacy({Directory? projectRoot}) {
  final root = projectRoot ?? Directory.current;
  final failures = <String>[];

  String read(String relativePath) =>
      File('${root.path}/$relativePath').readAsStringSync();

  void requireText(String source, String value, String message) {
    if (!source.contains(value)) failures.add(message);
  }

  void forbidText(String source, String value, String message) {
    if (source.contains(value)) failures.add(message);
  }

  void requirePattern(String source, RegExp pattern, String message) {
    if (!pattern.hasMatch(source)) failures.add(message);
  }

  final signalingLog = read(
    'server_hardened/signaling-server/src/main/resources/logback.xml',
  );
  final botLog = read('server_hardened/bot-api/src/main/resources/logback.xml');
  for (final entry in {'signaling': signalingLog, 'bot-api': botLog}.entries) {
    requireText(
      entry.value,
      '<root level="ERROR">',
      '${entry.key} log level must be fixed at ERROR',
    );
    forbidText(
      entry.value,
      'RollingFileAppender',
      '${entry.key} must not write persistent files',
    );
    forbidText(
      entry.value,
      'LOG_LEVEL',
      '${entry.key} verbosity must not be runtime-configurable',
    );
    forbidText(
      entry.value,
      'LOG_DIR',
      '${entry.key} must not accept a persistent log directory',
    );
    forbidText(
      entry.value,
      'fileNamePattern',
      '${entry.key} must not rotate behavioral logs to disk',
    );
    requireText(
      entry.value,
      '%privacyMessage',
      '${entry.key} must retain fail-safe message redaction',
    );
  }
  requireText(
    signalingLog,
    '<logger name="io.ktor" level="OFF"/>',
    'Ktor request logging must be disabled',
  );

  for (final dockerfile in ['Dockerfile.signaling', 'Dockerfile.bot-api']) {
    final source = read('server_hardened/deploy/$dockerfile');
    requireText(
      source,
      'ARG RUNTIME_IMAGE',
      '$dockerfile needs a digest input',
    );
    requireText(
      source,
      r'FROM ${RUNTIME_IMAGE}',
      '$dockerfile must use the validated runtime image',
    );
    requirePattern(
      source,
      RegExp(r'^USER 1000[12]:1000[12]$', multiLine: true),
      '$dockerfile must use its dedicated non-root UID',
    );
    for (final flag in [
      '-XX:-CreateCoredumpOnCrash',
      '-XX:+DisableAttachMechanism',
      '-XX:ErrorFile=/dev/null',
      '-XX:HeapDumpPath=/dev/null',
    ]) {
      requireText(source, flag, '$dockerfile is missing $flag');
    }
    forbidText(
      source,
      'sh", "-c',
      '$dockerfile entrypoint must not use a shell',
    );
    forbidText(source, 'COPY .', '$dockerfile must not copy the source tree');
  }

  final build = read('server_hardened/deploy/build_privacy_images.sh');
  requireText(
    build,
    r'@sha256:[a-f0-9]{64}',
    'image build must reject mutable base tags',
  );
  requireText(
    build,
    '--offline --no-daemon',
    'server build must resolve offline',
  );

  final deploy = read('server_hardened/deploy/deploy_privacy_stack.sh');
  for (final image in ['REDIS_IMAGE', 'SIGNALING_IMAGE', 'BOT_API_IMAGE']) {
    requireText(
      deploy,
      'require_digest $image',
      '$image must be digest-validated before compose is evaluated',
    );
  }
  requireText(
    deploy,
    'sslmode=verify-full',
    'PostgreSQL transport must authenticate the remote certificate',
  );
  requireText(
    deploy,
    'numeric_mode & 077',
    'host secret files must reject group/world permissions',
  );
  requireText(
    deploy,
    'secret_fingerprints',
    'deployment must reject cross-purpose secret reuse before startup',
  );
  requireText(
    deploy,
    'DATABASE_URL must not embed a database password',
    'database credentials must stay in the read-only secret file boundary',
  );
  requireText(
    deploy,
    r'mode="${1:---check-only}"',
    'deployment preflight must be non-mutating by default',
  );
  requireText(
    deploy,
    'SECURECHAT_DEPLOY_CONFIRMATION',
    'container mutation must require an explicit confirmation',
  );
  forbidText(
    deploy,
    'infra/docker-compose.yml',
    'hardened deploy gate must never invoke the legacy compose target',
  );

  final compose = read('server_hardened/deploy/compose.privacy.yml');
  for (final value in [
    'PRIVACY_PRODUCTION_MODE: "true"',
    'read_only: true',
    'cap_drop: [ALL]',
    'no-new-privileges:true',
    'soft: 0',
    'hard: 0',
    'driver: none',
    'internal: true',
    '--appendonly no',
    "--save ''",
    'ALLOW_LEGACY_PLAINTEXT_QUEUE: "false"',
    'DIRECTORY_OPRF_KEY_BACKEND: PKCS11',
  ]) {
    requireText(compose, value, 'compose privacy invariant missing: $value');
  }

  final signalingApplication = read(
    'server_hardened/signaling-server/src/main/kotlin/'
    'com/securechat/signaling/Application.kt',
  );
  final botApplication = read(
    'server_hardened/bot-api/src/main/kotlin/'
    'com/securechat/botapi/Application.kt',
  );
  requireText(
    signalingApplication,
    'ProductionDeploymentPolicy.validate()',
    'signaling binary must enforce the production deployment boundary',
  );
  requireText(
    botApplication,
    'ProductionDeploymentPolicy.validate()',
    'bot binary must enforce the production deployment boundary',
  );
  for (final image in ['REDIS_IMAGE', 'SIGNALING_IMAGE', 'BOT_API_IMAGE']) {
    requireText(
      compose,
      r'${' + image + ':?',
      '$image must be mandatory and supplied by the release environment',
    );
  }
  for (final secret in [
    'DATABASE_PASSWORD',
    'REDIS_PASSWORD',
    'TURN_SECRET',
    'JWT_SECRET',
    'PRIVACY_INDEX_KEY',
    'OFFLINE_QUEUE_ENCRYPTION_KEY',
    'FCM_TOKEN_ENCRYPTION_KEY',
    'METRICS_BEARER_TOKEN',
    'BOT_MASTER_KEY',
    'BOT_QUEUE_ENCRYPTION_KEY',
    'BOT_ADMIN_TOKEN',
    'BOT_METRICS_BEARER_TOKEN',
    'BOT_SERVICE_PRIVATE_KEY',
    'BOT_SERVICE_PUBLIC_KEY',
  ]) {
    forbidText(
      compose,
      RegExp.escape('$secret:'),
      '$secret must not be copied into container environment',
    );
    requireText(
      compose,
      '${secret}_FILE:',
      '$secret must use a read-only secret file',
    );
  }
  // Bot ihlali butun kullanicilarin taklit edilmesine donusmemeli: bot,
  // signaling'in kullanici token'larini imzalayan secret'i asla gormemeli.
  final botServiceBlock = _serviceBlock(compose, 'bot-api');
  if (botServiceBlock == null) {
    failures.add('bot-api service block not found in the hardened compose file');
  } else {
    forbidText(
      botServiceBlock,
      'jwt_secret',
      'bot-api must not be granted the signaling user-token signing secret',
    );
    forbidText(
      botServiceBlock,
      'JWT_SECRET',
      'bot-api must not receive JWT_SECRET in its environment',
    );
    requireText(
      botServiceBlock,
      'BOT_SERVICE_PRIVATE_KEY_FILE',
      'bot-api must authenticate with its own scoped service key',
    );
    // Public/admin yuzu ag uzerinden yayinlanmaz; erisim yalniz socket.
    forbidText(
      botServiceBlock,
      'ports:',
      'bot-api must not publish its public or admin surface on the network',
    );
    requireText(
      botServiceBlock,
      'target: /run/bot',
      'bot-api must expose its surface through a mounted unix socket directory',
    );
  }

  // Redis kisa TTL'li ciphertext tutar; disari cikan bir yolu olmamalidir.
  final redisBlock = _serviceBlock(compose, 'redis-ephemeral');
  if (redisBlock == null) {
    failures.add('redis-ephemeral service block not found in the hardened compose file');
  } else {
    forbidText(
      redisBlock,
      'securechat-egress',
      'the ephemeral Redis must not be attached to the egress network',
    );
  }

  // Host proxy'si kendi logunu tutar; container log driver'i onu korumaz.
  final proxy = read('server_hardened/deploy/reverse-proxy.conf');
  requireText(
    proxy,
    'access_log off;',
    'the reverse proxy must not write an access log',
  );
  requireText(
    proxy,
    r'proxy_set_header Authorization $http_authorization;',
    'the reverse proxy must preserve the bearer credential across upgrade',
  );
  requireText(
    proxy,
    r'if ($arg_token)',
    'the reverse proxy must reject a credential carried in the query string',
  );

  forbidText(compose, 'redis_data', 'ephemeral Redis must not have a volume');
  forbidText(
    compose,
    'backend_logs',
    'application logs must not have a volume',
  );
  forbidText(
    compose,
    'LOG_DIR:',
    'application must not receive a log directory',
  );
  forbidText(
    compose,
    'LOG_LEVEL:',
    'production log level must not be overridden',
  );

  return failures;
}

void main() {
  final failures = auditServerDeploymentPrivacy();
  if (failures.isEmpty) {
    stdout.writeln('Server deployment privacy audit: PASS');
    return;
  }
  for (final failure in failures) {
    stderr.writeln('FAIL: $failure');
  }
  exitCode = 1;
}


/// Compose dosyasindan tek bir servis blogunu ayirir.
///
/// Statik kapi, bir secret'in yanlislikla baska bir servise verilmedigini
/// dosyanin tamamina degil ilgili blogun icerigine bakarak dogrulamalidir.
String? _serviceBlock(String compose, String serviceName) {
  final lines = compose.split('\n');
  final startIndex = lines.indexWhere(
    (line) => line.trimRight() == '  $serviceName:',
  );
  if (startIndex < 0) return null;
  final block = <String>[];
  for (final line in lines.skip(startIndex + 1)) {
    final isNextServiceOrTopLevel =
        line.trim().isNotEmpty &&
        !line.startsWith('    ') &&
        !line.startsWith('\t');
    if (isNextServiceOrTopLevel) break;
    // Yorumlar konfigurasyon degildir; aciklama metni bir secret bagi gibi
    // okunmamali.
    if (line.trimLeft().startsWith('#')) continue;
    block.add(line);
  }
  return block.join('\n');
}
