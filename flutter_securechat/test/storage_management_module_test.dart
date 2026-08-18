import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_securechat/src/storage/storage_management_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'auto download matrix and encrypted policy persistence match Kotlin',
    () async {
      final f = await _fixture();
      addTearDown(f.close);
      final policy = const AutoDownloadPolicy().copyWith(
        videosOnCellular: true,
        maxAutoDownloadBytes: 10,
      );
      await f.service.savePolicy(policy);
      expect((await f.service.loadPolicy()).videosOnCellular, isTrue);
      expect(
        f.service.shouldDownload(
          policy: policy,
          category: MediaCategory.video,
          fileSize: 10,
          network: NetworkKind.cellular,
        ),
        isTrue,
      );
      expect(
        f.service.shouldDownload(
          policy: policy,
          category: MediaCategory.photo,
          fileSize: 11,
          network: NetworkKind.cellular,
        ),
        isFalse,
      );
      expect(
        await f.dbFile.readAsString(),
        isNot(contains('videosOnCellular')),
      );
    },
  );

  test(
    'storage analysis uses disk size and clean preserves text messages',
    () async {
      final f = await _fixture();
      addTearDown(f.close);
      final media = File('${f.root.path}/media.bin');
      await media.writeAsBytes(List.filled(100, 7));
      await f.database.conversations.insert(
        const ConversationEntity(
          id: 'c1',
          peerId: 'c1',
          peerName: 'Sohbet',
          peerPhone: '',
        ),
      );
      await f.database.messages.insert(
        const MessageEntity(
          id: 'text',
          conversationId: 'c1',
          senderId: 'me',
          content: 'kalmalı',
          contentType: StorageMessageContentType.text,
          timestamp: 1,
          status: StorageMessageStatus.sent,
          isOutgoing: true,
        ),
      );
      await f.database.messages.insert(
        MessageEntity(
          id: 'file',
          conversationId: 'c1',
          senderId: 'me',
          content: 'media.bin|application/octet-stream|5|${media.path}',
          contentType: StorageMessageContentType.file,
          timestamp: 2,
          status: StorageMessageStatus.sent,
          isOutgoing: true,
        ),
      );
      final item = (await f.service.analyzeAll()).single;
      expect(item.fileBytes, 100);
      expect(item.totalBytes, 100 + 2 * 256);

      expect(await f.service.cleanFiles('c1'), 100);
      expect(await media.exists(), isFalse);
      expect(await f.database.messages.getById('file'), isNull);
      expect((await f.database.messages.getById('text'))?.content, 'kalmalı');
    },
  );
}

class _Fixture {
  const _Fixture({
    required this.root,
    required this.dbFile,
    required this.database,
    required this.service,
  });
  final Directory root;
  final File dbFile;
  final SecureChatDatabase database;
  final StorageManagementService service;
  Future<void> close() async {
    await database.close();
    await root.delete(recursive: true);
  }
}

Future<_Fixture> _fixture() async {
  final root = await Directory.systemTemp.createTemp('securechat_storage_mgr_');
  final dbFile = File('${root.path}/db.securejson');
  final database = await SecureChatDatabase.open(
    file: dbFile,
    crypto: LocalAeadCryptoService(
      SecretKey(List<int>.generate(32, (index) => index + 1)),
    ),
  );
  return _Fixture(
    root: root,
    dbFile: dbFile,
    database: database,
    service: StorageManagementService(database),
  );
}
