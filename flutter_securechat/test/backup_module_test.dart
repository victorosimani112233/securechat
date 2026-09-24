import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/backup/backup_crypto.dart';
import 'package:flutter_securechat/src/backup/backup_service.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('backup crypto authenticates Kotlin-compatible binary layout', () async {
    final crypto = BackupCrypto(random: Random(42));
    final encrypted = await crypto.encrypt(
      utf8.encode('gizli yedek'),
      'çok-güçlü-parola',
    );

    expect(encrypted.length, greaterThan(32 + 12 + 16));
    expect(
      utf8.decode((await crypto.decrypt(encrypted, 'çok-güçlü-parola'))!),
      'gizli yedek',
    );
    expect(await crypto.decrypt(encrypted, 'yanlış-parola'), isNull);
    encrypted[45] ^= 1;
    expect(await crypto.decrypt(encrypted, 'çok-güçlü-parola'), isNull);
  });

  test(
    'version 3 backup restores app data without cloning Signal state',
    () async {
      final fixture = await _fixture();
      addTearDown(() => fixture.root.delete(recursive: true));
      await fixture.database.conversations.insert(
        const ConversationEntity(
          id: 'group-1',
          peerId: 'group-1',
          peerName: 'Özel Grup',
          peerPhone: '',
          isGroup: true,
          groupMembers: 'me,admin',
        ),
      );
      await fixture.database.messages.insert(
        const MessageEntity(
          id: 'm1',
          conversationId: 'group-1',
          senderId: 'me',
          content: 'yalnızca yedekte',
          contentType: StorageMessageContentType.text,
          timestamp: 100,
          status: StorageMessageStatus.sent,
          isOutgoing: true,
        ),
      );
      await fixture.database.preKeys.insert(
        const PreKeyEntity(id: 7, record: [1, 2, 3]),
      );
      await fixture.database.cryptoState.put(
        'local_identity_key_pair_v1',
        base64Encode([4, 5, 6]),
      );
      final file = await fixture.service.createBackup('correct-password');
      expect(
        utf8.decode(await file.readAsBytes(), allowMalformed: true),
        isNot(contains('yalnızca yedekte')),
      );

      await fixture.database.messages.delete('m1');
      final result = await fixture.service.restoreBackup(
        file,
        'correct-password',
      );
      expect(result, isA<BackupRestoreSuccess>());
      expect(
        (await fixture.database.messages.getById('m1'))?.content,
        'yalnızca yedekte',
      );
      expect(await fixture.database.preKeys.exists(7), isTrue);
      expect(
        await fixture.database.cryptoState.get('local_identity_key_pair_v1'),
        base64Encode([4, 5, 6]),
      );
      expect(fixture.session.displayName, 'Mevcut Kullanıcı');
    },
  );

  test(
    'wrong account is rejected and fifth bad password deletes file',
    () async {
      final source = await _fixture(phone: '+905001112233');
      addTearDown(() => source.root.delete(recursive: true));
      final backup = await source.service.createBackup('correct-password');

      source.session.userId = '22222222-2222-4222-8222-222222222222';
      expect(
        await source.service.restoreBackup(backup, 'correct-password'),
        isA<BackupRestoreFailure>(),
      );
      source.session.userId = '11111111-1111-4111-8111-111111111111';
      for (
        var attempt = 1;
        attempt < BackupService.maximumAttempts;
        attempt++
      ) {
        final result = await source.service.restoreBackup(
          backup,
          'bad-password',
        );
        expect(result, isA<BackupWrongPassword>());
      }
      final exhausted = await source.service.restoreBackup(
        backup,
        'bad-password',
      );
      expect(exhausted, isA<BackupAttemptsExhausted>());
      expect(await backup.exists(), isFalse);
    },
  );

  test(
    'legacy version 2 backups cannot restore Signal private state',
    () async {
      final fixture = await _fixture();
      addTearDown(() => fixture.root.delete(recursive: true));
      final database =
          (jsonDecode(await fixture.database.exportPortableJson()) as Map)
              .cast<String, Object?>();
      for (final key in const [
        'identities',
        'preKeys',
        'signedPreKeys',
        'sessions',
        'senderKeys',
        'pendingSignals',
      ]) {
        database[key] = <Object?>[
          <String, Object?>{'attackerControlledPrivateState': key},
        ];
      }
      database['cryptoState'] = <String, Object?>{
        'local_registration_id': '31337',
        'local_identity_key_pair_v1': base64Encode([1, 2, 3]),
        'pending_sender_key_rotation:group-1': 'private-state',
        'non_signal_setting': 'preserved',
      };
      final root = <String, Object?>{
        'version': 2,
        'createdAt': 1,
        'profile': <String, Object?>{
          'userId': fixture.session.userId,
          'displayName': 'Mevcut Kullanıcı',
          'phoneNumber': fixture.session.phoneNumber,
          'profilePhotoUri': '',
        },
        'database': database,
      };
      final encrypted = await BackupCrypto(
        random: Random(123),
      ).encrypt(gzip.encode(utf8.encode(jsonEncode(root))), 'correct-password');
      final legacy = File('${fixture.root.path}/legacy-v2.elbk');
      await legacy.writeAsBytes(encrypted);

      expect(
        await fixture.service.restoreBackup(legacy, 'correct-password'),
        isA<BackupRestoreSuccess>(),
      );
      final restored =
          (jsonDecode(await fixture.database.exportPortableJson()) as Map)
              .cast<String, Object?>();
      for (final key in const [
        'identities',
        'preKeys',
        'signedPreKeys',
        'sessions',
        'senderKeys',
        'pendingSignals',
      ]) {
        expect(restored[key], isEmpty, reason: key);
      }
      final restoredState = (restored['cryptoState'] as Map)
          .cast<String, Object?>();
      expect(restoredState['local_registration_id'], isNull);
      expect(restoredState['local_identity_key_pair_v1'], isNull);
      expect(
        restoredState.keys,
        everyElement(isNot(startsWith('pending_sender_key_rotation:'))),
      );
      expect(restoredState['non_signal_setting'], isNull);
    },
  );
}

class _BackupFixture {
  const _BackupFixture({
    required this.root,
    required this.database,
    required this.session,
    required this.service,
  });
  final Directory root;
  final SecureChatDatabase database;
  final SessionStore session;
  final BackupService service;
}

Future<_BackupFixture> _fixture({String phone = '+905001112233'}) async {
  final root = await Directory.systemTemp.createTemp('securechat_backup_');
  final localCrypto = LocalAeadCryptoService(
    SecretKey(List<int>.generate(32, (index) => index + 10)),
  );
  final database = await SecureChatDatabase.open(
    file: File('${root.path}/db.securejson'),
    crypto: localCrypto,
  );
  addTearDown(database.close);
  final session = SessionStore(
    userId: '11111111-1111-4111-8111-111111111111',
    displayName: 'Mevcut Kullanıcı',
    phoneNumber: phone,
    accessToken: 'not-backed-up',
    refreshToken: 'not-backed-up-either',
  );
  return _BackupFixture(
    root: root,
    database: database,
    session: session,
    service: BackupService(
      database: database,
      session: session,
      backupDirectory: Directory('${root.path}/backups'),
      crypto: BackupCrypto(random: Random(99)),
    ),
  );
}
