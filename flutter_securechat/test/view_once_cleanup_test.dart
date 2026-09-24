import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/core/models.dart';
import 'package:flutter_securechat/src/media/file_transfer_manager.dart';
import 'package:flutter_securechat/src/media/media_message_service.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late Directory media;
  late SecureChatDatabase database;
  late InMemorySignalingService signaling;
  late FileTransferManager transfers;
  late MediaMessageService service;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('view_once_cleanup_');
    media = await Directory('${root.path}/media').create();
    final crypto = LocalAeadCryptoService(SecretKey(List.filled(32, 4)));
    database = await SecureChatDatabase.open(
      file: File('${root.path}/db'),
      crypto: crypto,
    );
    signaling = InMemorySignalingService();
    transfers = FileTransferManager(
      signaling: signaling,
      crypto: crypto,
      filesDirectory: media,
    );
    service = MediaMessageService(
      database: database,
      transfers: transfers,
      session: SessionStore(userId: 'me'),
      localMediaDirectory: media,
    );
  });
  tearDown(() async {
    await service.close();
    await transfers.dispose();
    await signaling.dispose();
    await database.close();
    await root.delete(recursive: true);
  });

  Future<LocalMessage> insert(
    String id, {
    bool once = true,
    bool viewed = false,
    bool outgoing = false,
    String? path,
  }) async {
    final file = await File(
      path ?? '${media.path}/$id.jpg',
    ).writeAsBytes([1, 2, 3]);
    final entity = MessageEntity(
      id: id,
      conversationId: 'peer',
      senderId: outgoing ? 'me' : 'peer',
      content: LocalMessage.buildFileContent(
        filePath: file.path,
        fileName: '$id.jpg',
        mimeType: 'image/jpeg',
        fileSize: 3,
      ),
      contentType: StorageMessageContentType.image,
      timestamp: 1,
      status: StorageMessageStatus.delivered,
      isOutgoing: outgoing,
      isViewOnce: once,
      isViewed: viewed,
      caption: 'private caption',
    );
    await database.messages.insert(entity);
    return LocalMessage.fromJson(entity.toJson());
  }

  test(
    'claim once, retain during viewing, erase file and caption on close',
    () async {
      final message = await insert('once');
      expect(await service.markViewOnceViewed(message), isTrue);
      expect(await service.markViewOnceViewed(message), isFalse);
      await service.cleanupViewedOnceMedia();
      expect(await File(message.filePath!).exists(), isTrue);
      service.finishViewOnce(message.id);
      service.finishViewOnce(message.id);
      await service.waitForIdle();
      expect(await File(message.filePath!).exists(), isFalse);
      final tombstone = (await database.messages.getById(message.id))!;
      expect(tombstone.isViewed, isTrue);
      expect(tombstone.isViewOnce, isTrue);
      expect(tombstone.content, isEmpty);
      expect(tombstone.caption, isNull);
      expect(await service.markViewOnceViewed(message), isFalse);
    },
  );

  test(
    'startup removes old viewed files but preserves unopened and normal media',
    () async {
      final viewed = await insert('viewed', viewed: true);
      final unopened = await insert('unopened');
      final normal = await insert('normal', once: false, viewed: true);
      final sent = await insert('sent', outgoing: true, viewed: true);
      service.start();
      await service.waitForIdle();
      expect(await File(viewed.filePath!).exists(), isFalse);
      for (final message in [unopened, normal, sent]) {
        expect(await File(message.filePath!).exists(), isTrue);
        expect(
          (await database.messages.getById(message.id))!.caption,
          'private caption',
        );
      }
    },
  );

  test('atomic claim cannot grant two viewers for a stale message', () async {
    final message = await insert('race');
    final results = await Future.wait([
      database.messages.markViewOnceAsViewed(message.id),
      database.messages.markViewOnceAsViewed(message.id),
    ]);
    expect(results.where((claimed) => claimed), hasLength(1));
    await service.cleanupViewedOnceMedia();
    expect(await File(message.filePath!).exists(), isFalse);
  });

  test('missing files still lose their stored caption and path', () async {
    final message = await insert('missing', viewed: true);
    await File(message.filePath!).delete();
    await service.cleanupViewedOnceMedia();
    expect((await database.messages.getById(message.id))!.content, isEmpty);
    expect((await database.messages.getById(message.id))!.caption, isNull);
  });

  test('cleanup refuses paths outside app media, including symlinks', () async {
    final message = await insert(
      'outside',
      viewed: true,
      path: '${root.path}/original.jpg',
    );
    final link = await Link('${media.path}/link.jpg').create(message.filePath!);
    final entity = (await database.messages.getById(message.id))!;
    await database.messages.insert(
      entity.copyWith(
        content: LocalMessage.buildFileContent(
          filePath: link.path,
          fileName: 'link.jpg',
          mimeType: 'image/jpeg',
          fileSize: 3,
        ),
      ),
    );
    await expectLater(
      service.cleanupViewedOnceMedia(),
      throwsA(isA<FileSystemException>()),
    );
    expect(await File(message.filePath!).exists(), isTrue);
    expect((await database.messages.getById(message.id))!.content, isNotEmpty);
  });
}
