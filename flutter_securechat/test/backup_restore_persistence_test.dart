import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/backup/backup_service.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late File databaseFile;
  late LocalAeadCryptoService crypto;
  late SecureChatDatabase database;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('backup_restart_');
    databaseFile = File('${root.path}/data');
    crypto = LocalAeadCryptoService(SecretKey(List.filled(32, 28)));
    database = await SecureChatDatabase.open(
      file: databaseFile,
      crypto: crypto,
    );
  });
  tearDown(() async {
    await database.close();
    await root.delete(recursive: true);
  });

  Future<void> seed(String id) async {
    await database.conversations.insert(
      ConversationEntity(
        id: id,
        peerId: id,
        peerName: 'Name $id',
        peerPhone: '',
      ),
    );
    await database.messages.insert(
      MessageEntity(
        id: 'message-$id',
        conversationId: id,
        senderId: 'me',
        content: 'private restored content $id',
        contentType: StorageMessageContentType.text,
        timestamp: 1,
        status: StorageMessageStatus.read,
        isOutgoing: false,
      ),
    );
  }

  test(
    'successful encrypted restore survives closing and reopening the database',
    () async {
      await seed('restored');
      await database.contacts.insert(
        const ContactEntity(
          id: 'restored',
          phoneNumber: '+905550000001',
          phoneHash: 'hash',
          displayName: 'Restored Contact',
          isRegistered: true,
        ),
      );
      await database.cryptoState.put(
        'local_identity_key_pair_v1',
        'not-clonable',
      );
      final service = BackupService(
        database: database,
        session: SessionStore(userId: 'me', phoneNumber: '+905550000000'),
        backupDirectory: Directory('${root.path}/backups'),
      );
      final backup = await service.createBackup('correct-password');
      final originalBackup = await backup.readAsBytes();
      await database.clearAll();
      await seed('stale');
      await database.cryptoState.put('local_identity_key_pair_v1', 'old-key');

      expect(
        await service.restoreBackup(backup, 'correct-password'),
        isA<BackupRestoreSuccess>(),
      );
      expect(await database.messages.getById('message-restored'), isNotNull);
      final expected = jsonDecode(await database.exportPortableJson());
      await database.close();
      database = await SecureChatDatabase.open(
        file: databaseFile,
        crypto: crypto,
      );

      expect(await database.conversations.getById('restored'), isNotNull);
      expect(await database.messages.getById('message-restored'), isNotNull);
      expect(
        (await database.contacts.getById('restored'))?.displayName,
        'Restored Contact',
      );
      expect(await database.conversations.getById('stale'), isNull);
      expect(
        await database.cryptoState.get('local_identity_key_pair_v1'),
        isNull,
      );
      expect(jsonDecode(await database.exportPortableJson()), expected);
      expect(await backup.readAsBytes(), originalBackup);
      expect(
        String.fromCharCodes(
          await SecureChatDatabase.storeFileFor(databaseFile).readAsBytes(),
        ),
        isNot(contains('private restored content')),
      );
    },
  );

  test(
    'failed replacement keeps old memory and disk state and permits a later write',
    () async {
      await seed('replacement');
      final replacement = await database.exportPortableJson();
      await database.clearAll();
      await seed('original');
      final original = jsonDecode(await database.exportPortableJson());
      database.store.failMidTransaction = true;
      await expectLater(
        database.replaceFromPortableJson(replacement),
        throwsStateError,
      );
      expect(jsonDecode(await database.exportPortableJson()), original);
      await database.cryptoState.put('after-failure', 'valid');
      await database.close();
      database = await SecureChatDatabase.open(
        file: databaseFile,
        crypto: crypto,
      );
      expect(await database.conversations.getById('original'), isNotNull);
      expect(await database.conversations.getById('replacement'), isNull);
      expect(await database.cryptoState.get('after-failure'), 'valid');
      await database.replaceFromPortableJson(replacement);
      await database.close();
      database = await SecureChatDatabase.open(
        file: databaseFile,
        crypto: crypto,
      );
      expect(await database.conversations.getById('replacement'), isNotNull);
      expect(await database.conversations.getById('original'), isNull);
    },
  );
}
