import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_securechat/src/storage/storage_management_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/storage_at_rest.dart';

void main() {
  Future<void> insertMedia(
    _Fixture f,
    String id,
    String conversation,
    File file, {
    String mime = 'application/octet-stream',
    StorageMessageContentType type = StorageMessageContentType.file,
  }) => f.database.messages.insert(
    MessageEntity(
      id: id,
      conversationId: conversation,
      senderId: 'me',
      content: '$id|$mime|500|${file.path}',
      contentType: type,
      timestamp: 2,
      status: StorageMessageStatus.sent,
      isOutgoing: true,
    ),
  );

  test(
    'selected cleanup preserves shared files until the last reference',
    () async {
      final f = await _fixture();
      addTearDown(f.close);
      final shared = await File(
        '${f.root.path}/shared.bin',
      ).writeAsBytes(List.filled(10, 1));
      final kept = await File(
        '${f.root.path}/kept.bin',
      ).writeAsBytes(List.filled(20, 2));
      await insertMedia(f, 'selected', 'c1', shared);
      await insertMedia(f, 'other-chat', 'c2', shared);
      await insertMedia(f, 'unselected', 'c1', kept);

      final first = await f.service.cleanSelectedFiles('c1', [
        'selected',
        'selected',
        'other-chat',
      ]);
      expect(first.deletedCount, 1);
      expect(first.freedBytes, 0);
      expect(first.failedIds, isEmpty);
      expect(await shared.exists(), isTrue);
      expect(await kept.exists(), isTrue);
      expect(await f.database.messages.getById('unselected'), isNotNull);
      expect(await f.database.messages.getById('other-chat'), isNotNull);

      final last = await f.service.cleanSelectedFiles('c2', ['other-chat']);
      expect(last.deletedCount, 1);
      expect(last.freedBytes, 10);
      expect(await shared.exists(), isFalse);
    },
  );

  test(
    'iOS container relocation resolves previews and shared cleanup without rewriting history',
    () async {
      final f = await _fixture();
      addTearDown(f.close);
      final directory = await Directory(
        '${f.root.path}/received_files',
      ).create();
      final current = await File(
        '${directory.path}/photo with spaces.png',
      ).writeAsBytes([1, 2, 3]);
      const old =
          '/var/mobile/Containers/Data/Application/11111111-2222-3333-4444-555555555555/Library/Application Support/media/received_files/photo with spaces.png';
      await insertMedia(f, 'old', 'c1', File(old), mime: 'image/png');
      await insertMedia(f, 'current', 'c2', current, mime: 'image/png');
      final resolved = (await f.service.filesForChat('c1')).single;
      expect(resolved.available, isTrue);
      expect(resolved.diskBytes, 3);
      expect(resolved.path, await current.resolveSymbolicLinks());
      expect(resolved.message.filePath, old);
      expect(
        (await f.service.fileForOpening('c1', 'old'))!.path,
        resolved.path,
      );
      expect(
        (await f.database.messages.getById('old'))!.content,
        endsWith(old),
      );
      final first = await f.service.cleanSelectedFiles('c1', ['old']);
      expect(first.deletedCount, 1);
      expect(first.freedBytes, 0);
      expect(await current.exists(), isTrue);
      final last = await f.service.cleanSelectedFiles('c2', ['current']);
      expect(last.freedBytes, 3);
      expect(await current.exists(), isFalse);
    },
  );

  test(
    'local file URI resolves encoded filename for preview and cleanup',
    () async {
      final f = await _fixture();
      addTearDown(f.close);
      final current = await File(
        '${f.root.path}/photo #1.png',
      ).writeAsBytes([1, 2]);
      await insertMedia(
        f,
        'uri',
        'c1',
        File(current.uri.toString()),
        mime: 'image/png',
      );
      final item = (await f.service.filesForChat('c1')).single;
      expect(item.available, isTrue);
      expect(item.path, await current.resolveSymbolicLinks());
      expect((await f.service.fileForOpening('c1', 'uri'))!.path, item.path);
      expect((await f.service.cleanSelectedFiles('c1', ['uri'])).freedBytes, 2);
      expect(await current.exists(), isFalse);
    },
  );

  test(
    'relocation never guesses basenames or escapes the managed root',
    () async {
      final f = await _fixture();
      addTearDown(f.close);
      final outside = await Directory.systemTemp.createTemp('storage-outside-');
      addTearDown(() => outside.delete(recursive: true));
      final secret = await File(
        '${outside.path}/secret',
      ).writeAsString('secret');
      await Link('${f.root.path}/escape').create(secret.path);
      await File('${f.root.path}/secret').writeAsString('not a match');
      const old =
          '/var/mobile/Containers/Data/Application/11111111-2222-3333-4444-555555555555/Library/Application Support/media';
      for (final (id, path) in [
        ('external', secret.path),
        ('traversal', '$old/../secret'),
        ('symlink', '$old/escape'),
        ('arbitrary', '/unknown/container/secret'),
        ('remote', 'https://example.invalid/secret'),
      ]) {
        await insertMedia(f, id, 'c1', File(path), mime: 'image/png');
        expect(await f.service.fileForOpening('c1', id), isNull);
      }
      expect(
        (await f.service.filesForChat('c1')).every((file) => !file.available),
        isTrue,
      );
      expect(await secret.readAsString(), 'secret');
    },
  );

  test('opening rechecks message ownership and privacy flags', () async {
    final f = await _fixture();
    addTearDown(f.close);
    final image = await File('${f.root.path}/image.png').writeAsBytes([1]);
    await insertMedia(f, 'image', 'c1', image, mime: 'image/png');
    expect(await f.service.fileForOpening('another-chat', 'image'), isNull);
    final original = (await f.database.messages.getById('image'))!;
    for (final flags in [
      {'isViewOnce': true},
      {'isMediaPreviewDeferred': true},
      {'expiresAt': 1},
      {'contentType': 'deleted'},
    ]) {
      await f.database.messages.update(
        MessageEntity.fromJson({...original.toJson(), ...flags}),
      );
      expect(await f.service.fileForOpening('c1', 'image'), isNull);
    }
    await f.database.messages.update(original);
    expect(await f.service.fileForOpening('c1', 'image'), isNotNull);
    await f.database.messages.delete('image');
    expect(await f.service.fileForOpening('c1', 'image'), isNull);
  });

  test(
    'cleanup refuses external files and symlink escapes without deleting records',
    () async {
      final f = await _fixture();
      addTearDown(f.close);
      final externalRoot = await Directory.systemTemp.createTemp(
        'external_storage_',
      );
      addTearDown(() => externalRoot.delete(recursive: true));
      final external = await File(
        '${externalRoot.path}/private',
      ).writeAsString('keep');
      final link = await Link('${f.root.path}/escape').create(external.path);
      await insertMedia(f, 'external', 'c1', external);
      await insertMedia(f, 'link', 'c1', File(link.path));
      final result = await f.service.cleanSelectedFiles('c1', [
        'external',
        'link',
      ]);
      expect(result.deletedCount, 0);
      expect(result.failedIds, ['external', 'link']);
      expect(await external.readAsString(), 'keep');
      expect(await f.database.messages.getById('external'), isNotNull);
      expect(await f.database.messages.getById('link'), isNotNull);
    },
  );

  test(
    'missing files use zero disk bytes and empty files remain available',
    () async {
      final f = await _fixture();
      addTearDown(f.close);
      final empty = await File('${f.root.path}/empty').create();
      await insertMedia(f, 'empty', 'c1', empty, mime: 'image/png');
      await insertMedia(
        f,
        'missing',
        'c1',
        File('${f.root.path}/missing'),
        mime: 'video/mp4',
      );
      await insertMedia(
        f,
        'voice',
        'c1',
        File('${f.root.path}/voice'),
        type: StorageMessageContentType.voiceNote,
      );
      final files = {
        for (final file in await f.service.filesForChat('c1'))
          file.message.id: file,
      };
      expect(files['empty']!.available, isTrue);
      expect(files['empty']!.diskBytes, 0);
      expect(files['empty']!.category, StorageFileCategory.photo);
      expect(files['missing']!.available, isFalse);
      expect(files['missing']!.diskBytes, 0);
      expect(files['missing']!.category, StorageFileCategory.video);
      expect(files['voice']!.category, StorageFileCategory.audio);
      final result = await f.service.cleanSelectedFiles('c1', ['missing']);
      expect(result.deletedCount, 1);
      expect(result.freedBytes, 0);
    },
  );

  test('managed root is required before removing any existing file', () async {
    final f = await _fixture();
    addTearDown(f.close);
    final file = await File('${f.root.path}/kept').writeAsString('keep');
    await insertMedia(f, 'kept', 'c1', file);
    final result = await StorageManagementService(
      f.database,
    ).cleanSelectedFiles('c1', ['kept']);
    expect(result.failedIds, ['kept']);
    expect(await file.exists(), isTrue);
    expect(await f.database.messages.getById('kept'), isNotNull);
  });

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
        await storageAtRest(f.dbFile),
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
      expect(
        (await f.database.conversations.getById('c1'))?.lastMessage,
        'kalmalı',
      );
      expect(
        (await f.database.conversations.getById('c1'))?.lastMessageTimestamp,
        1,
      );
      expect(
        (await f.service.cleanSelectedFiles('c1', ['text'])).deletedCount,
        0,
      );
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
    service: StorageManagementService(database, mediaDirectory: root),
  );
}
