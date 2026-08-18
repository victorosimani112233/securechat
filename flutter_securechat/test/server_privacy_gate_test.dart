import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String source(String relativePath) =>
      File('${Directory.current.path}/$relativePath').readAsStringSync();

  Iterable<File> kotlinSources(String relativeRoot) =>
      Directory('${Directory.current.path}/$relativeRoot')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.kt'));

  test('hardened server fails closed on identity and retention secrets', () {
    final privacy = source(
      'server_hardened/signaling-server/src/main/kotlin/'
      'com/securechat/signaling/ServerPrivacy.kt',
    );
    expect(privacy, contains('PRIVACY_INDEX_KEY'));
    expect(privacy, contains('OFFLINE_QUEUE_ENCRYPTION_KEY'));
    expect(privacy, isNot(contains('GROUP_DIRECTORY_ENCRYPTION_KEY')));
    expect(privacy, contains('60L..3_600L'));
    expect(privacy, contains('60L..900L'));
    expect(privacy, contains('300L..3_600L'));
    expect(
      privacy,
      contains(
        '"OFFLINE_QUEUE_TTL_SECONDS",\n                    defaultValue = 900',
      ),
    );
    expect(
      privacy,
      contains(
        '"OFFLINE_FILE_TTL_SECONDS",\n                    defaultValue = 300',
      ),
    );
    expect(privacy, isNot(contains('AUDIT_RETENTION_DAYS')));
    expect(
      privacy,
      contains(
        '"PUSH_TOKEN_RETENTION_DAYS",\n                    defaultValue = 30',
      ),
    );
    expect(
      privacy,
      contains(
        '"API_CLIENT_RETENTION_DAYS",\n                    defaultValue = 30',
      ),
    );
    expect(privacy, contains('Legacy plaintext offline queue entry rejected'));
    expect(privacy, contains('AES/GCM/NoPadding'));
    expect(privacy, contains('HmacSHA256'));
  });

  test('OTP has no universal code and never keys Redis by email', () {
    final otp = source(
      'server_hardened/signaling-server/src/main/kotlin/'
      'com/securechat/signaling/OtpService.kt',
    );
    expect(otp, isNot(contains('BACKDOOR')));
    expect(otp, isNot(contains('111111')));
    expect(otp, contains('otp_v2:'));
    expect(otp, contains('ServerPrivacy.blindIndex'));
    expect(otp, isNot(contains(r'otp:${email.lowercase()}')));

    final routes = source(
      'server_hardened/signaling-server/src/main/kotlin/'
      'com/securechat/signaling/HttpRoutes.kt',
    );
    expect(routes, contains('AuthService.registrationGrantClaim(regToken)'));
    expect(
      routes,
      contains(
        'RegistrationGrants.claimAccount(grant, candidate, userRegistry)',
      ),
    );
    expect(
      routes,
      isNot(contains('val requireOtp = EmailService.isConfigured')),
    );
    expect(routes, isNot(contains('Geriye uyumluluk: SMTP')));

    final registrationGrants = source(
      'server_hardened/signaling-server/src/main/kotlin/'
      'com/securechat/signaling/RegistrationGrants.kt',
    );
    expect(registrationGrants, contains('connection.autoCommit = false'));
    expect(
      registrationGrants,
      contains('ON CONFLICT (grant_index) DO NOTHING'),
    );
    expect(
      registrationGrants,
      contains('ServerPrivacy.registrationTokenUseKey(claim.grantId)'),
    );
    expect(
      registrationGrants,
      contains('userRegistry.insertRegistration(connection, candidate)'),
    );
    expect(registrationGrants, contains('connection.rollback()'));
    expect(registrationGrants, contains('connection.commit()'));

    final application = source(
      'server_hardened/signaling-server/src/main/kotlin/'
      'com/securechat/signaling/Application.kt',
    );
    expect(application, contains('EmailService.initialize()'));
    expect(application, contains('MetricsAccess.initialize()'));
    expect(application, contains('RedisManager.requireMemoryOnly()'));
    expect(
      application,
      contains('throw IllegalStateException("PostgreSQL ve Redis'),
    );
  });

  test(
    'contact discovery uses fixed blind OPRF and no address-book hashes',
    () {
      final routes = source(
        'server_hardened/signaling-server/src/main/kotlin/'
        'com/securechat/signaling/HttpRoutes.kt',
      );
      expect(routes, isNot(contains('encryptedPhone')));
      expect(routes, isNot(contains('/api/v1/users/{userId}/phone')));
      expect(routes, isNot(contains('/api/v1/users/online')));
      expect(routes, isNot(contains('/api/v1/users/check')));
      expect(routes, contains('/api/v1/directory/evaluate'));
      expect(routes, contains('/api/v1/directory/snapshot'));
      expect(routes, contains('evaluateBatch(request.blinded)'));
      expect(routes, contains('DIRECTORY_EVALUATE_BODY_LIMIT'));
      expect(routes, contains('receivePrivateDirectoryJson'));
      expect(routes, contains('HttpStatusCode.PayloadTooLarge'));
      expect(routes, contains('DirectoryIdentityAlreadyRegisteredException'));
      expect(routes, contains('directory_identity_already_registered'));

      final registry = source(
        'server_hardened/signaling-server/src/main/kotlin/'
        'com/securechat/signaling/UserRegistry.kt',
      );
      expect(registry, contains('directory.tokenForPhoneHash(phoneHash)'));
      expect(registry, contains('directory_key_id'));
      expect(
        registry,
        contains('throw DirectoryIdentityAlreadyRegisteredException()'),
      );
      expect(registry, isNot(contains('encrypted_phone')));

      final oprf = source(
        'server_hardened/signaling-server/src/main/kotlin/'
        'com/securechat/signaling/PrivateDirectoryOprf.kt',
      );
      expect(oprf, contains('AUTHENTICATED_BATCH_SIZE = 256'));
      expect(oprf, contains('DIRECTORY_OPRF_PRIVATE_KEY'));
      expect(oprf, contains('DIRECTORY_OPRF_KEY_BACKEND'));
      expect(oprf, contains('DIRECTORY_OPRF_PKCS11_PROVIDER'));
      expect(oprf, contains('KeyStore.getInstance("PKCS11", provider)'));
      expect(oprf, contains('AES/GCM/NoPadding'));
      expect(oprf, contains('RSA/ECB/NoPadding'));

      final privateClient = source(
        'lib/src/contacts/private_contact_discovery.dart',
      );
      expect(privateClient, contains('_authenticatedBatchSize = 256'));
      expect(privateClient, contains('_fullDomainPoint'));
      expect(privateClient, contains('_resolveSnapshot'));
      expect(privateClient, isNot(contains('/api/v1/users/check')));

      final directoryMigration = source(
        'server_hardened/signaling-server/src/main/resources/db/migration/'
        'V13__private_contact_directory.sql',
      );
      expect(directoryMigration, contains('RENAME COLUMN phone_hash'));
      expect(directoryMigration, contains('directory_key_id'));

      final migration = source(
        'server_hardened/signaling-server/src/main/resources/db/migration/'
        'V6__remove_shared_phone_envelope.sql',
      );
      expect(migration, contains('DROP COLUMN IF EXISTS encrypted_phone'));

      final flutterPhone = source('lib/src/auth/phone_privacy.dart');
      expect(flutterPhone, isNot(contains('class PhoneEncryptor')));
      expect(flutterPhone, isNot(contains('_keyBytes')));
      final authApi = source('lib/src/auth/auth_api.dart');
      expect(authApi, isNot(contains("'encryptedPhone'")));
    },
  );

  test('offline server queues are opaque, bounded and ack-after-send', () {
    final connection = source(
      'server_hardened/signaling-server/src/main/kotlin/'
      'com/securechat/signaling/ConnectionManager.kt',
    );
    expect(connection, contains('ServerPrivacy.sealQueue'));
    expect(connection, contains('ServerPrivacy.openQueue'));
    expect(connection, contains('ServerPrivacy.queueKey("message"'));
    expect(connection, contains('ServerPrivacy.queueKey("file"'));
    expect(connection, contains('offlineQueueTtlSeconds'));
    expect(connection, contains('offlineFileTtlSeconds'));
    expect(connection, isNot(contains('30 * 24 * 3600')));
    expect(connection, isNot(contains('expire(key, 24 * 3600')));
    expect(connection, contains('ServerPrivacy.activeCallKey'));
    expect(connection, contains('ServerPrivacy.activeCallIndexKey'));
    expect(connection, isNot(contains('jedis.keys("active_call:')));
    expect(connection, isNot(contains('setex(key, 300, "\$callerId>')));
    final delivery = connection.substring(
      connection.indexOf('private suspend fun deliverOfflineMessages'),
    );
    final sendIndex = delivery.indexOf('session.send(Frame.Text(message))');
    final ackCommentIndex = delivery.indexOf('// Remove only after send');
    final acknowledgedRemoveIndex = delivery.indexOf(
      'jedis.zrem(key, stored)',
      ackCommentIndex,
    );
    expect(sendIndex, greaterThanOrEqualTo(0));
    expect(sendIndex, lessThan(ackCommentIndex));
    expect(ackCommentIndex, lessThan(acknowledgedRemoveIndex));

    final redisPolicy = source(
      'server_hardened/signaling-server/src/main/kotlin/'
      'com/securechat/signaling/db/RedisEphemeralPolicy.kt',
    );
    expect(redisPolicy, contains('appendonly'));
    expect(redisPolicy, contains('snapshotSchedule.isEmpty()'));
  });

  test('credential revocation is durable and survives a cache loss', () {
    // Revocation kaydi persistence'siz ve `allkeys-lru` calisan Redis'te
    // tutulamaz: restart veya eviction iptal edilmis bir token'i yeniden
    // gecerli hale getirirdi.
    final credentialState = source(
      'server_hardened/signaling-server/src/main/kotlin/'
      'com/securechat/signaling/CredentialState.kt',
    );
    expect(credentialState, contains('UPDATE users'));
    expect(credentialState, contains('credential_epoch'));
    expect(credentialState, contains('refresh_generation'));
    // Rotasyon compare-and-set olmali; reuse tespiti buna dayanir.
    expect(
      credentialState,
      contains('WHERE user_id = ?::uuid AND refresh_generation = ?'),
    );
    expect(credentialState, isNot(contains('RedisManager')));

    final auth = source(
      'server_hardened/signaling-server/src/main/kotlin/'
      'com/securechat/signaling/AuthService.kt',
    );
    expect(auth, contains('CredentialState.cachedSnapshot'));
    expect(auth, contains('fail-closed'));
    // Per-JTI blacklist yalniz Redis'te yasiyordu; geri gelmemeli.
    expect(auth, isNot(contains('JwtBlacklist')));

    final routes = source(
      'server_hardened/signaling-server/src/main/kotlin/'
      'com/securechat/signaling/HttpRoutes.kt',
    );
    expect(routes, contains('AuthService.revokeAllTokens'));
    expect(routes, contains('CredentialState.rotateRefreshGeneration'));
    expect(routes, contains('AUTH_REFRESH_REUSE'));
  });

  test('account deletion covers caches, queues, audit and token families', () {
    final routes = source(
      'server_hardened/signaling-server/src/main/kotlin/'
      'com/securechat/signaling/HttpRoutes.kt',
    );
    expect(routes, isNot(contains('audit_log')));
    expect(routes, isNot(contains('recipient_user_id')));
    expect(routes, isNot(contains('fcm_tokens WHERE user_index = ? OR')));
    expect(routes, isNot(contains('group_members')));
    expect(routes, contains('AccountDeletion.execute'));

    final deletion = source(
      'server_hardened/signaling-server/src/main/kotlin/'
      'com/securechat/signaling/AccountDeletion.kt',
    );
    // Kalici kopyalarin tamami tek transaction'da gitmeli.
    expect(deletion, contains('DELETE FROM fcm_tokens'));
    expect(deletion, contains('DELETE FROM bot_signal_session'));
    expect(deletion, contains('DELETE FROM users'));
    expect(deletion, contains('ServerPrivacy.blindIndex("bot-signal-peer"'));
    expect(deletion, contains('connection.commit()'));
    expect(deletion, contains('connection.rollback()'));
    // Gecici kopyalarin her adimi yalitilmis olmali: bir adimin hatasi
    // kendinden sonrakileri atlamamali.
    expect(deletion, contains('runCatching { step.action() }'));
    expect(deletion, contains('userRegistry.removeUser'));
    expect(deletion, contains('AuthService.forgetAccount'));
    expect(deletion, contains('connectionManager.closeUserSocket'));
    expect(deletion, contains('connectionManager.purgeQueuedEnvelopes'));
    // Silinen hesabin UUID'sini kalici bir tombstone satirinda tutmak,
    // silinmesi istenen iliskiyi geride birakirdi.
    expect(deletion, isNot(contains('INSERT INTO')));

    final retention = source(
      'server_hardened/signaling-server/src/main/kotlin/'
      'com/securechat/signaling/PrivacyRetentionWorker.kt',
    );
    expect(retention, isNot(contains('audit_log')));
    expect(retention, isNot(contains('DELETE FROM one_time_prekeys')));
    expect(retention, contains('DELETE FROM bot_one_time_prekey'));
    expect(retention, contains('DELETE FROM fcm_tokens'));
    expect(retention, contains('DELETE FROM api_client'));
    expect(retention, contains('config.apiClientRetentionDays'));
    expect(retention, contains('fun isHealthy(): Boolean'));
    expect(retention, contains('throw IllegalStateException'));
    expect(retention, contains('FAILURE_RETRY_MILLIS'));

    final application = source(
      'server_hardened/signaling-server/src/main/kotlin/'
      'com/securechat/signaling/Application.kt',
    );
    expect(application, contains('connectionManager.closeAllConnections()'));

    final privacyRoutes = source(
      'server_hardened/signaling-server/src/main/kotlin/'
      'com/securechat/signaling/HttpRoutes.kt',
    );
    expect(privacyRoutes, contains('privacy_retention_unavailable'));
    expect(privacyRoutes, contains('PrivacyRetentionWorker.isHealthy()'));

    final webSocket = source(
      'server_hardened/signaling-server/src/main/kotlin/'
      'com/securechat/signaling/WebSocketRoutes.kt',
    );
    expect(webSocket, contains('Privacy retention unavailable'));
    expect(webSocket, contains('PrivacyRetentionWorker.isHealthy()'));

    final audit = source(
      'server_hardened/signaling-server/src/main/kotlin/'
      'com/securechat/signaling/AuditLog.kt',
    );
    expect(audit, contains('ConcurrentHashMap<String, LongAdder>'));
    expect(audit, isNot(contains('Database.getConnection')));
    expect(audit, isNot(contains('userId?.')));

    final auditMigration = source(
      'server_hardened/signaling-server/src/main/resources/db/migration/'
      'V10__remove_behavioral_audit_log.sql',
    );
    expect(auditMigration, contains('DROP TABLE IF EXISTS audit_log'));

    final rateLimiter = source(
      'server_hardened/signaling-server/src/main/kotlin/'
      'com/securechat/signaling/RateLimiter.kt',
    );
    expect(rateLimiter, contains('ServerPrivacy.rateLimitKey'));
    expect(rateLimiter, isNot(contains('"ratelimit:\$endpoint:\$identifier"')));

    final groupMigration = source(
      'server_hardened/signaling-server/src/main/resources/db/migration/'
      'V9__remove_persistent_group_graph.sql',
    );
    expect(groupMigration, contains('DROP TABLE IF EXISTS group_members'));

    final preKeyStore = source(
      'server_hardened/signaling-server/src/main/kotlin/'
      'com/securechat/signaling/PreKeyStore.kt',
    );
    expect(preKeyStore, contains('DELETE FROM one_time_prekeys'));
    expect(preKeyStore, contains('RETURNING one_time_prekeys.key_id'));
    expect(preKeyStore, isNot(contains('SET consumed_at = NOW()')));
    final preKeyMigration = source(
      'server_hardened/signaling-server/src/main/resources/db/migration/'
      'V11__remove_user_prekey_timeline.sql',
    );
    expect(preKeyMigration, contains('DROP COLUMN IF EXISTS consumed_at'));
    expect(preKeyMigration, contains('DROP COLUMN IF EXISTS created_at'));
    expect(
      File(
        '${Directory.current.path}/server_hardened/signaling-server/src/main/'
        'kotlin/com/securechat/signaling/GroupMemberStore.kt',
      ).existsSync(),
      isFalse,
    );

    final botSend = source(
      'server_hardened/bot-api/src/main/kotlin/'
      'com/securechat/botapi/send/SendPipeline.kt',
    );
    expect(botSend, contains('recipientUserIds'));
    expect(botSend, contains('opaque-routing-token'));
    expect(botSend, isNot(contains('group_members')));
    expect(botSend, isNot(contains('BotGroupDirectoryPrivacy')));

    final turn = source(
      'server_hardened/signaling-server/src/main/kotlin/'
      'com/securechat/signaling/TurnCredentialService.kt',
    );
    expect(turn, contains('ServerPrivacy.blindIndex("turn-user"'));
    expect(turn, isNot(contains(r'"$expiry:$userId"')));
  });

  test('push provider receives a generic wake signal only', () {
    final fcm = source(
      'server_hardened/signaling-server/src/main/kotlin/'
      'com/securechat/signaling/FcmPushSender.kt',
    );
    expect(fcm, contains('.putData("type", "securechat_wake_v2")'));
    expect(fcm, isNot(contains('.putData("senderId"')));
    expect(fcm, isNot(contains('.putData("messageType"')));
    expect(fcm, isNot(contains('.putData("sentAt"')));
  });

  test('push tokens use opaque account indexes and user-bound v4 AEAD', () {
    final cipher = source(
      'server_hardened/signaling-server/src/main/kotlin/'
      'com/securechat/signaling/FcmTokenCipher.kt',
    );
    expect(cipher, contains('securechat-fcm-token-v4'));
    expect(cipher, contains('AES/GCM/NoPadding'));
    expect(cipher, contains('cipher.updateAAD(aad)'));
    expect(cipher, contains('FCM_TOKEN_ENCRYPTION_KEY'));

    final store = source(
      'server_hardened/signaling-server/src/main/kotlin/'
      'com/securechat/signaling/FcmTokenStore.kt',
    );
    expect(store, contains('ServerPrivacy.blindIndex("push-user"'));
    expect(store, contains('VALUES (?, ?, CURRENT_DATE)'));
    expect(store, contains('registered_on = CURRENT_DATE'));
    expect(store, isNot(contains('updated_at')));
    expect(store, contains('requireValidToken(token)'));
    expect(store, contains('cipher.seal(userIndex, token)'));
    expect(store, contains('cipher.openV4(row.userIndex, row.token)'));
    expect(store, isNot(contains('tokens[userId]')));
    expect(store, isNot(contains('fcm_tokens (user_id')));
    expect(store, isNot(contains('openLegacyV')));

    final migration = source(
      'server_hardened/signaling-server/src/main/resources/db/migration/'
      'V5__push_token_privacy.sql',
    );
    expect(migration, contains('ADD COLUMN user_index'));
    expect(migration, contains('ALTER COLUMN user_id DROP NOT NULL'));
    expect(migration, contains('idx_fcm_private_user'));

    final timeMigration = source(
      'server_hardened/signaling-server/src/main/resources/db/migration/'
      'V12__coarsen_push_token_time.sql',
    );
    expect(timeMigration, contains('registered_on DATE'));
    expect(timeMigration, contains('DROP COLUMN IF EXISTS updated_at'));

    final finalSchema = source(
      'server_hardened/signaling-server/src/main/resources/db/migration/'
      'V14__drop_legacy_identity_links.sql',
    );
    expect(finalSchema, contains('ALTER TABLE fcm_tokens DROP COLUMN user_id'));
    expect(
      finalSchema,
      contains('ALTER TABLE bot_signal_session DROP COLUMN recipient_user_id'),
    );
    expect(finalSchema, contains('V14 refused: migrate every push token'));
    expect(finalSchema, contains('V14 refused: migrate every bot session'));

    final retention = source(
      'server_hardened/signaling-server/src/main/kotlin/'
      'com/securechat/signaling/PrivacyRetentionWorker.kt',
    );
    expect(retention, contains('tokenStore?.purgeExpiredMemory'));
  });

  test('bot queue and all log sinks enforce the same privacy boundary', () {
    final botQueue = source(
      'server_hardened/bot-api/src/main/kotlin/'
      'com/securechat/botapi/delivery/OutboundQueue.kt',
    );
    expect(botQueue, contains('BotQueuePrivacy.seal'));
    expect(botQueue, contains('outboundQueueTtlSeconds'));
    expect(botQueue, contains('MAX_MESSAGES'));

    final idempotency = source(
      'server_hardened/bot-api/src/main/kotlin/'
      'com/securechat/botapi/send/IdempotencyStore.kt',
    );
    expect(idempotency, contains('BotQueuePrivacy.sealPrivate'));
    expect(idempotency, contains('BotQueuePrivacy.openPrivate'));
    expect(idempotency, contains('BotApiConfig.idempotencyTtlSeconds'));
    expect(idempotency, isNot(contains('86400L')));
    expect(idempotency, isNot(contains('"bot_idem:\$clientId:\$idemKey"')));

    final botConfig = source(
      'server_hardened/bot-api/src/main/kotlin/'
      'com/securechat/botapi/BotApiConfig.kt',
    );
    expect(botConfig, contains('BOT_OUTBOUND_TTL_SECONDS", "900"'));
    expect(botConfig, contains('BOT_IDEMPOTENCY_TTL_SECONDS", "900"'));

    final nonce = source(
      'server_hardened/bot-api/src/main/kotlin/'
      'com/securechat/botapi/auth/NonceStore.kt',
    );
    expect(nonce, contains('BotQueuePrivacy.blindIndex'));

    final botSessions = source(
      'server_hardened/bot-api/src/main/kotlin/'
      'com/securechat/botapi/signal/PgSignalProtocolStore.kt',
    );
    expect(botSessions, contains('BotSessionRecordCipher.seal'));
    expect(botSessions, contains('BotSessionRecordCipher.open'));
    expect(botSessions, contains('recipient_index'));
    expect(botSessions, isNot(contains('recipient_user_id')));

    final botStartup = source(
      'server_hardened/bot-api/src/main/kotlin/'
      'com/securechat/botapi/Application.kt',
    );
    expect(
      botStartup,
      contains('BotSessionPrivacyMigration.migrateAndVerify()'),
    );
    expect(
      botStartup,
      contains('ApiClientPrivacyMigration.migrateAndVerify()'),
    );
    expect(botStartup, contains('BotRedisManager.requireMemoryOnly()'));

    final apiClients = source(
      'server_hardened/bot-api/src/main/kotlin/'
      'com/securechat/botapi/db/ApiClientRepository.kt',
    );
    expect(apiClients, contains('ApiClientPrivateFields.sealName'));
    expect(apiClients, contains('ApiClientPrivateFields.sealAllowList'));
    expect(apiClients, contains('ApiClientPrivateFields.openAllowList'));

    final credentialResolver = source(
      'server_hardened/bot-api/src/main/kotlin/'
      'com/securechat/botapi/auth/ClientKeyCache.kt',
    );
    expect(
      credentialResolver,
      contains('ApiClientRepository.findActiveByKid(kid)'),
    );
    expect(credentialResolver, isNot(contains('ConcurrentHashMap')));
    expect(credentialResolver, isNot(contains('cache[kid]')));

    final signalingLogback = source(
      'server_hardened/signaling-server/src/main/resources/logback.xml',
    );
    final botLogback = source(
      'server_hardened/bot-api/src/main/resources/logback.xml',
    );
    expect(signalingLogback, contains('%privacyMessage'));
    expect(signalingLogback, isNot(contains(' - %msg%n')));
    expect(botLogback, contains('%privacyMessage'));
    expect(botLogback, isNot(contains(' - %msg%n')));

    final botHealth = source(
      'server_hardened/bot-api/src/main/kotlin/'
      'com/securechat/botapi/health/HealthListener.kt',
    );
    expect(botHealth, contains('metricsAuthorized'));
    expect(botHealth, contains('MessageDigest.isEqual'));

    final botAudit = source(
      'server_hardened/bot-api/src/main/kotlin/'
      'com/securechat/botapi/audit/BotAuditLog.kt',
    );
    expect(botAudit, contains('ConcurrentHashMap<String, LongAdder>'));
    expect(botAudit, isNot(contains('BotDatabase')));
    expect(botAudit, isNot(contains('audit_log')));
  });

  test('server production logs cannot emit request exception or identity data', () {
    final files = <File>[
      ...kotlinSources('server_hardened/signaling-server/src/main/kotlin'),
      ...kotlinSources('server_hardened/bot-api/src/main/kotlin'),
    ];
    final unsafeIdentity = RegExp(
      r'\$(?:[A-Za-z]*(?:userId|senderId|recipientId|groupId|callerId|memberId|sessionId|handleId|jti|email)[A-Za-z]*)\b',
      caseSensitive: false,
    );
    final unsafeFormatArgument = RegExp(
      r',\s*(?:[A-Za-z]*(?:userId|senderId|recipientId|groupId|callerId|memberId|sessionId|handleId|jti|email)[A-Za-z]*)\s*\)?\s*$',
      caseSensitive: false,
    );
    for (final file in files) {
      final contents = file.readAsStringSync();
      expect(contents, isNot(contains('e.message')), reason: file.path);
      for (final line in contents.split('\n')) {
        if (!line.contains(
          RegExp(r'\b(?:log|logger)\.(?:trace|debug|info|warn|error)'),
        )) {
          continue;
        }
        expect(line, isNot(matches(unsafeIdentity)), reason: file.path);
        expect(line, isNot(matches(unsafeFormatArgument)), reason: file.path);
      }
    }
  });

  test('Flutter group file and push senders default to private v3 wire', () {
    final groupCrypto = source(
      'lib/src/crypto/signal_protocol_crypto_service.dart',
    );
    expect(groupCrypto, contains("return 'GROUPSK:v2:"));
    expect(groupCrypto, isNot(contains("return 'GROUPSK:v1:")));

    final files = source('lib/src/media/file_transfer_manager.dart');
    expect(files, contains("fileName: 'attachment.bin'"));
    expect(files, contains("mimeType: 'application/octet-stream'"));
    expect(files, contains("'flutter-file-v3-group'"));
    expect(files, contains('_PrivateFileManifest'));
    expect(files, contains('fileSize: totalChunks * chunkSize'));
    expect(files, contains("'size': fileSize"));
    expect(files, contains('metadata.secure'));
    expect(files, isNot(contains('groupName: isGroup')));

    final sender = source('lib/src/domain/send_message_use_case.dart');
    expect(sender, contains('encodePrivateGroupRoute'));
    expect(sender, isNot(contains('GroupMessageFanoutSignal(')));
    final route = source('lib/src/groups/private_group_route.dart');
    expect(
      route,
      contains("const _privateGroupRoutePrefix = 'GROUPROUTE:v3:'"),
    );
    expect(route, contains('Private group route binding mismatch'));

    final hardenedWs = source(
      'server_hardened/signaling-server/src/main/kotlin/'
      'com/securechat/signaling/WebSocketRoutes.kt',
    );
    expect(hardenedWs, contains('Linkable group_message_fanout reddedildi'));
    final hardenedConnections = source(
      'server_hardened/signaling-server/src/main/kotlin/'
      'com/securechat/signaling/ConnectionManager.kt',
    );
    expect(hardenedConnections, isNot(contains('handleGroupMessageFanout')));

    final calls = source('lib/src/media/call_manager.dart');
    expect(calls, contains('participants: const []'));
    final app = source('lib/src/services/app_container.dart');
    expect(app, contains('newOpaqueRoutingNonce()'));
    expect(app, contains('privateGroupCallPreparationAction'));

    final push = source('lib/src/push/push_service.dart');
    expect(push, contains("type == 'securechat_wake_v2'"));
    expect(push, isNot(contains('final String senderId;')));
    expect(push, isNot(contains('final String messageType;')));
  });

  test(
    'behavioral chat controls use padded E2EE and plaintext is rejected',
    () {
      final control = source('lib/src/chat/private_chat_control.dart');
      expect(control, contains("'CHATCTRL:v2:'"));
      expect(control, contains('_privateControlPacketBytes = 16 * 1024'));
      expect(control, contains('Random.secure()'));
      expect(control, contains('EncryptedSignalMessage('));

      for (final path in [
        'lib/src/chat/message_interaction_service.dart',
        'lib/src/chat/read_receipt_service.dart',
        'lib/src/chat/chat_info_service.dart',
        'lib/src/background/background_tasks.dart',
      ]) {
        expect(source(path), contains('sendPrivateChatControl('), reason: path);
      }
      final incoming = source('lib/src/incoming/incoming_message_handler.dart');
      expect(incoming, contains('decodePrivateChatControl('));
      expect(incoming, contains('privateChatControl: true'));
      expect(incoming, contains('when privateChatControl'));

      final hardenedWs = source(
        'server_hardened/signaling-server/src/main/kotlin/'
        'com/securechat/signaling/WebSocketRoutes.kt',
      );
      for (final type in [
        'delivery_receipt',
        'message_delete',
        'message_edit',
        'message_reaction',
        'message_pin',
        'typing_indicator',
        'disappearing_timer',
      ]) {
        expect(hardenedWs, contains('"$type"'));
      }
      expect(hardenedWs, contains('Plaintext legacy chat control reddedildi'));

      final audit = source('lib/src/export/export_audit_service.dart');
      expect(audit, contains("eventType: 'PRIVATE_EVENT'"));
      expect(hardenedWs, contains('eventType != "PRIVATE_EVENT"'));
    },
  );
}
