import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/backup/backup_crypto.dart';
import 'package:flutter_securechat/src/backup/backup_service.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';

const _account = '11111111-1111-4111-8111-111111111111';
const _otherAccount = '22222222-2222-4222-8222-222222222222';
const _password = 'correct-password';
const _securityCollections = [
  'identities',
  'preKeys',
  'signedPreKeys',
  'sessions',
  'senderKeys',
  'pendingSignals',
  'cryptoState',
];

void main() {
  late Directory root;
  late File databaseFile;
  late File sessionFile;
  late LocalAeadCryptoService localCrypto;
  late SecureChatDatabase database;
  late PersistentSessionStore session;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('backup_recovery_');
    databaseFile = File('${root.path}/database');
    sessionFile = File('${root.path}/session');
    localCrypto = LocalAeadCryptoService(SecretKey(List.filled(32, 67)));
    database = await SecureChatDatabase.open(
      file: databaseFile,
      crypto: localCrypto,
    );
    session = await PersistentSessionStore.open(
      file: sessionFile,
      crypto: localCrypto,
    );
  });

  tearDown(() async {
    await database.close();
    await session.close();
    await root.delete(recursive: true);
  });

  BackupService service() => BackupService(
    database: database,
    session: session,
    backupDirectory: Directory('${root.path}/backups'),
  );

  Future<Map<String, Object?>> snapshot() async =>
      (jsonDecode(await database.exportPortableJson()) as Map)
          .cast<String, Object?>();

  Future<void> login({String userId = _account}) => session.loginAndPersist(
    userId: userId,
    displayName: 'Recovered profile',
    phoneNumber: '+905550000000',
    accessToken: 'recovered-access',
    refreshToken: 'recovered-refresh',
  );

  Future<void> seedHistory(String id) async {
    await database.conversations.insert(
      ConversationEntity(
        id: id,
        peerId: 'peer',
        peerName: 'Peer',
        peerPhone: '',
      ),
    );
    await database.messages.insert(
      MessageEntity(
        id: id,
        conversationId: id,
        senderId: _account,
        content: 'History $id',
        contentType: StorageMessageContentType.text,
        timestamp: 1,
        status: StorageMessageStatus.read,
        isOutgoing: true,
      ),
    );
  }

  Future<void> seedSecurity(int generation) async {
    await database.identities.insert(
      IdentityEntity(
        addressName: 'peer',
        identityKey: [generation, 1],
        trustLevel: TrustLevel.trustedVerified,
      ),
    );
    await database.preKeys.insert(
      PreKeyEntity(id: generation, record: [generation, 2]),
    );
    await database.signedPreKeys.insert(
      SignedPreKeyEntity(
        id: generation,
        record: [generation, 3],
        createdAt: generation,
      ),
    );
    await database.sessions.insert(
      SessionEntity(id: 'peer:1', record: [generation, 4]),
    );
    await database.senderKeys.put(
      SenderKeyEntity(
        groupId: 'group',
        senderId: _account,
        deviceId: 1,
        record: [generation, 5],
        updatedAt: generation,
      ),
    );
    await database.pendingSignals.put(
      PendingSignalEntity(
        id: 'pending',
        encodedSignal: 'active-ciphertext-$generation',
        createdAt: generation,
        attempts: 2,
      ),
    );
    for (final key in [
      'local_identity_key_pair_v1',
      'local_registration_id',
      'pending_sender_key_rotation:group:$_account',
      'processed-delivery:receipt',
      'chat_lock_credential_v1',
      'future_private_secret',
      'account_recovery_pending_v1',
      'backup_attempt:other-backup',
    ]) {
      await database.cryptoState.put(key, 'local-$generation-$key');
    }
  }

  Future<File> encryptedBackup({
    Object? profile = const {
      'userId': _account,
      'displayName': 'Old profile',
      'phoneNumber': '+905550000000',
    },
    Object? version = 3,
    Map<String, Object?>? data,
  }) async {
    final history = data ?? await snapshot();
    final payload = <String, Object?>{
      if (version != null) 'version': version,
      'profile': profile,
      if (version == 1 || version == null) ...history else 'database': history,
    };
    final file = File('${root.path}/import.elbk');
    await file.writeAsBytes(
      await BackupCrypto().encrypt(
        gzip.encode(utf8.encode(jsonEncode(payload))),
        _password,
      ),
    );
    return file;
  }

  Future<void> reopen() async {
    await database.close();
    await session.close();
    database = await SecureChatDatabase.open(
      file: databaseFile,
      crypto: localCrypto,
    );
    session = await PersistentSessionStore.open(
      file: sessionFile,
      crypto: localCrypto,
    );
  }

  Future<void> expectRejectedWithoutWrites(File backup) async {
    final before = await snapshot();
    final profileBefore = session.toJson();
    final dbBytes = await SecureChatDatabase.storeFileFor(
      databaseFile,
    ).readAsBytes();
    final sessionBytes = await sessionFile.readAsBytes();
    expect(
      await service().restoreBackup(backup, _password),
      isA<BackupRestoreFailure>(),
    );
    expect(await snapshot(), before);
    expect(session.toJson(), profileBefore);
    expect(
      await SecureChatDatabase.storeFileFor(databaseFile).readAsBytes(),
      dbBytes,
    );
    expect(await sessionFile.readAsBytes(), sessionBytes);
    await reopen();
    expect(await snapshot(), before);
    expect(session.toJson(), profileBefore);
  }

  test(
    'same-account recovered profile, credentials and security survive restore and reopen',
    () async {
      await login();
      await seedHistory('archived');
      await seedSecurity(1);
      final backup = await service().createBackup(_password);
      await database.clearAll();
      await seedHistory('current');
      await seedSecurity(2);
      session.displayName = 'New recovered name';
      session.phoneNumber = '+905559999999';
      session.profilePhotoUri = 'new-local-photo';
      session.pushToken = 'active-push';
      session.sharePhoneNumber = true;
      await session.persist();
      final activeProfile = session.toJson();
      final activeSecurity = _security(await snapshot());

      expect(
        await service().restoreBackup(backup, _password),
        isA<BackupRestoreSuccess>(),
      );
      expect(session.toJson(), activeProfile);
      expect(_security(await snapshot()), activeSecurity);
      expect(await database.messages.getById('archived'), isNotNull);
      expect(await database.messages.getById('current'), isNull);
      await reopen();
      expect(session.toJson(), activeProfile);
      expect(_security(await snapshot()), activeSecurity);
      expect(await database.messages.getById('archived'), isNotNull);
      expect(await database.messages.getById('current'), isNull);
    },
  );

  test(
    'exported JSON contains history but no tokens or generic crypto state',
    () async {
      await login();
      await seedHistory('archived');
      await seedSecurity(1);
      final backup = await service().createBackup(_password);
      final clear = (await BackupCrypto().decrypt(
        await backup.readAsBytes(),
        _password,
      ))!;
      final json = utf8.decode(gzip.decode(clear));
      final payload = jsonDecode(json) as Map;
      expect(payload['profile'], {
        'userId': _account,
        'displayName': 'Recovered profile',
        'phoneNumber': '+905550000000',
        'profilePhotoUri': '',
      });
      expect(json, contains('History archived'));
      expect(json, isNot(contains('recovered-access')));
      expect(json, isNot(contains('recovered-refresh')));
      for (final key in _securityCollections) {
        expect((payload['database'] as Map)[key], isEmpty, reason: key);
      }
    },
  );

  test(
    'different UUID with the same phone is rejected before any write',
    () async {
      await login();
      await seedHistory('active');
      await seedSecurity(2);
      final backup = await encryptedBackup(
        profile: {
          'userId': _otherAccount,
          'displayName': 'Other account',
          'phoneNumber': session.phoneNumber,
        },
      );
      await expectRejectedWithoutWrites(backup);
    },
  );

  final malformedProfiles = <String, Object?>{
    'missing profile': null,
    'list profile': [],
    'missing UUID': {'phoneNumber': '+905550000000'},
    'empty UUID': {'userId': ''},
    'non-string UUID': {'userId': 123},
    'invalid UUID': {'userId': 'not-an-account'},
    'padded UUID': {'userId': ' $_account'},
    'malformed display name': {'userId': _account, 'displayName': []},
    'malformed phone': {'userId': _account, 'phoneNumber': 123},
    'malformed photo': {'userId': _account, 'profilePhotoUri': {}},
  };
  for (final entry in malformedProfiles.entries) {
    test(
      '${entry.key} fails before writes even with a valid password',
      () async {
        await login();
        await seedHistory('active');
        await seedSecurity(2);
        final backup = await encryptedBackup(profile: entry.value);
        await expectRejectedWithoutWrites(backup);
      },
    );
  }

  for (final version in <int?>[null, 1, 2, 3]) {
    test(
      'offline legacy/version $version restore installs only a profile and history',
      () async {
        await seedHistory('archived');
        await seedSecurity(1);
        final backup = await encryptedBackup(version: version);
        await database.clearAll();
        expect(
          await service().restoreBackup(backup, _password),
          isA<BackupRestoreSuccess>(),
        );
        await reopen();
        expect(session.userId, _account);
        expect(session.displayName, 'Old profile');
        expect(session.accessToken, isNull);
        expect(session.refreshToken, isNull);
        expect(session.isLoggedIn, isFalse);
        expect(await database.messages.getById('archived'), isNotNull);
        for (final value in _security(await snapshot()).values) {
          expect(value, isEmpty);
        }
      },
    );
  }

  test(
    'legacy backup private state and injected tokens cannot replace active state',
    () async {
      await seedHistory('archived');
      await seedSecurity(1);
      final backup = await encryptedBackup(
        version: 2,
        profile: {
          'userId': _account,
          'accessToken': 'imported-access',
          'refreshToken': 'imported-refresh',
        },
      );
      await database.clearAll();
      await login();
      await seedSecurity(2);
      final current = _security(await snapshot());
      final profile = session.toJson();
      expect(
        await service().restoreBackup(backup, _password),
        isA<BackupRestoreSuccess>(),
      );
      await reopen();
      expect(_security(await snapshot()), current);
      expect(session.toJson(), profile);
      expect(await database.messages.getById('archived'), isNotNull);
    },
  );

  test('offline import ignores injected credentials', () async {
    final backup = await encryptedBackup(
      profile: {
        'userId': _account,
        'accessToken': 'imported-access',
        'refreshToken': 'imported-refresh',
        'pushToken': 'imported-push',
      },
    );
    expect(
      await service().restoreBackup(backup, _password),
      isA<BackupRestoreSuccess>(),
    );
    await reopen();
    expect(session.userId, _account);
    expect(session.accessToken, isNull);
    expect(session.refreshToken, isNull);
    expect(session.pushToken, isNull);
    expect(session.isLoggedIn, isFalse);
  });

  test('legacy phone-only profile is not proof of account ownership', () async {
    await login();
    await seedHistory('active');
    await expectRejectedWithoutWrites(
      await encryptedBackup(
        version: 1,
        profile: {'phoneNumber': session.phoneNumber},
      ),
    );
  });

  for (final version in <Object>[0, 4, 2.5, '3']) {
    test('invalid version $version is rejected before writes', () async {
      await login();
      await expectRejectedWithoutWrites(
        await encryptedBackup(version: version),
      );
    });
  }

  test('malformed history row is fully parsed before writes', () async {
    await login();
    await seedHistory('active');
    final data = await snapshot();
    (data['messages'] as List).first['timestamp'] = 'invalid-number';
    await expectRejectedWithoutWrites(await encryptedBackup(data: data));
  });

  test('backup creation refuses a missing account UUID', () async {
    await expectLater(service().createBackup(_password), throwsFormatException);
    expect(await Directory('${root.path}/backups').exists(), isFalse);
  });

  test('offline profile cannot be rebound to a different UUID', () async {
    session.userId = _otherAccount;
    await session.persist();
    await seedSecurity(2);
    await expectRejectedWithoutWrites(await encryptedBackup());
  });

  test(
    'orphan credentials cannot be attached to an offline backup profile',
    () async {
      session.refreshToken = 'orphan-refresh';
      await session.persist();
      await expectRejectedWithoutWrites(await encryptedBackup());
    },
  );

  test(
    'malformed history collection is rejected instead of silently erased',
    () async {
      await login();
      await seedHistory('active');
      final data = await snapshot();
      data['messages'] = 'not-a-list';
      await expectRejectedWithoutWrites(await encryptedBackup(data: data));
    },
  );

  test(
    'transaction failure preserves active history, credentials and security on disk',
    () async {
      await login();
      await seedHistory('archived');
      final backup = await service().createBackup(_password);
      await database.clearAll();
      await seedHistory('active');
      await seedSecurity(2);
      database.store.failMidTransaction = true;
      await expectRejectedWithoutWrites(backup);
    },
  );

  test(
    'security preservation sees writes queued before and after replacement',
    () async {
      await seedHistory('archived');
      final replacement = await database.exportPortableJson();
      await database.clearAll();
      final first = database.preKeys.insert(
        const PreKeyEntity(id: 8, record: [8]),
      );
      final restore = database.replaceFromPortableJson(
        replacement,
        preserveLocalSecurityState: true,
      );
      final last = database.preKeys.insert(
        const PreKeyEntity(id: 9, record: [9]),
      );
      await first;
      await restore;
      await last;
      await reopen();
      expect(await database.preKeys.exists(8), isTrue);
      expect(await database.preKeys.exists(9), isTrue);
      expect(await database.messages.getById('archived'), isNotNull);
    },
  );

  test(
    'commit guard rejects an account switch while replacement is queued',
    () async {
      await login();
      await seedHistory('active');
      await seedSecurity(2);
      final original = await snapshot();
      final restore = database.replaceFromPortableJson(
        jsonEncode({...original, 'messages': []}),
        preserveLocalSecurityState: true,
        validateBeforeCommit: () {
          if (session.userId != _account) throw StateError('Account changed');
        },
      );
      session.userId = _otherAccount;
      await expectLater(restore, throwsStateError);
      expect(await snapshot(), original);
      await reopen();
      expect(await snapshot(), original);
    },
  );
}

Map<String, Object?> _security(Map<String, Object?> snapshot) => {
  for (final key in _securityCollections) key: snapshot[key],
};
