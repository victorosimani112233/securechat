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

  test('version 2 backup restores profile and complete encrypted DB', () async {
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
    expect(fixture.session.displayName, 'Mevcut Kullanıcı');
  });

  test(
    'wrong account is rejected and fifth bad password deletes file',
    () async {
      final source = await _fixture(phone: '+905001112233');
      addTearDown(() => source.root.delete(recursive: true));
      final backup = await source.service.createBackup('correct-password');

      source.session.phoneNumber = '+905009998877';
      expect(
        await source.service.restoreBackup(backup, 'correct-password'),
        isA<BackupRestoreFailure>(),
      );
      source.session.phoneNumber = '+905001112233';
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
  final session = SessionStore(
    userId: 'me',
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
