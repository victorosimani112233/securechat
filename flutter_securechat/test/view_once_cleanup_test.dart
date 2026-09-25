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
import 'package:flutter_securechat/src/storage/storage_management_service.dart';
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
    String? storedPath,
  }) async {
    final file = await File(
      path ?? '${media.path}/$id.jpg',
    ).writeAsBytes([1, 2, 3]);
    final entity = MessageEntity(
      id: id,
      conversationId: 'peer',
      senderId: outgoing ? 'me' : 'peer',
      content: LocalMessage.buildFileContent(
        filePath: storedPath ?? file.path,
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

  for (final uri in [false, true]) {
    for (final startup in [false, true]) {
      test(
        'view-once cleanup deletes ${uri ? 'file URI' : 'relocated iOS'} bytes at ${startup ? 'startup' : 'viewer close'}',
        () async {
          final actual = File('${media.path}/normalized.jpg');
          final stored = uri
              ? actual.uri.toString()
              : '/var/mobile/Containers/Data/Application/11111111-2222-3333-4444-555555555555/Library/Application Support/media/normalized.jpg';
          final message = await insert(
            'normalized',
            viewed: startup,
            storedPath: stored,
          );
          final storage = StorageManagementService(
            database,
            mediaDirectory: media,
          );
          expect(
            await storage.resolveMediaPath(stored),
            await actual.resolveSymbolicLinks(),
          );
          if (startup) {
            await service.cleanupViewedOnceMedia();
          } else {
            expect(await service.markViewOnceViewed(message), isTrue);
            await service.cleanupViewedOnceMedia();
            expect(await actual.exists(), isTrue);
            service.finishViewOnce(message.id);
            await service.waitForIdle();
          }
          expect(await actual.exists(), isFalse);
          final tombstone = (await database.messages.getById(message.id))!;
          expect(tombstone.isViewed, isTrue);
          expect(tombstone.content, isEmpty);
          expect(tombstone.caption, isNull);
        },
      );
    }
  }

  test(
    'strict resolver failure retains retry path and caption until deletion succeeds',
    () async {
      await service.close();
      final storage = _FailingResolver(database, media);
      service = MediaMessageService(
        database: database,
        transfers: transfers,
        session: SessionStore(userId: 'me'),
        localMediaDirectory: media,
        storageManagement: storage,
      );
      final message = await insert(
        'retry',
        viewed: true,
        storedPath: File('${media.path}/retry.jpg').uri.toString(),
      );
      await expectLater(
        service.cleanupViewedOnceMedia(),
        throwsA(isA<FileSystemException>()),
      );
      expect(storage.strictRequested, isTrue);
      expect(await File('${media.path}/retry.jpg').exists(), isTrue);
      final retained = (await database.messages.getById(message.id))!;
      expect(retained.content, isNotEmpty);
      expect(retained.caption, 'private caption');
      storage.fail = false;
      await service.cleanupViewedOnceMedia();
      expect(await File('${media.path}/retry.jpg').exists(), isFalse);
      expect((await database.messages.getById(message.id))!.content, isEmpty);
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

class _FailingResolver extends StorageManagementService {
  _FailingResolver(SecureChatDatabase database, Directory media)
    : super(database, mediaDirectory: media);
  bool fail = true;
  bool strictRequested = false;
  @override
  Future<String?> resolveMediaPath(String path, {bool strict = false}) {
    strictRequested = strict;
    if (fail) throw const FileSystemException('Temporary resolver I/O failure');
    return super.resolveMediaPath(path, strict: strict);
  }
}
