import 'dart:async';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/core/models.dart';
import 'package:flutter_securechat/src/domain/send_message_use_case.dart';
import 'package:flutter_securechat/src/media/file_transfer_manager.dart';
import 'package:flutter_securechat/src/media/media_attachment.dart';
import 'package:flutter_securechat/src/media/media_message_service.dart';
import 'package:flutter_securechat/src/media/voice_note_service.dart';
import 'package:flutter_securechat/src/services/conversation_repository.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_securechat/src/storage/storage_management_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late SecureChatDatabase database;
  late StorageManagementService storage;
  late MediaMessageService service;
  late _Transfers transfers;
  final crypto = LocalAeadCryptoService(SecretKey(List.filled(32, 7)));

  Future<void> open() async {
    database = await SecureChatDatabase.open(
      file: File('${root.path}/db'),
      crypto: crypto,
    );
    storage = StorageManagementService(database, mediaDirectory: root);
    service = MediaMessageService(
      database: database,
      transfers: transfers,
      session: SessionStore(userId: 'me'),
      localMediaDirectory: root,
      storageManagement: storage,
      networkKindProvider: _Cellular(),
    )..start();
    await service.waitForIdle();
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('media-preview-deferred-');
    transfers = _Transfers();
    await open();
  });

  tearDown(() async {
    await service.close();
    await transfers.events.close();
    await database.close();
    await root.delete(recursive: true);
  });

  Future<LocalMessage> receive({
    String id = 'received',
    String mime = 'application/pdf',
    String fileName = 'original-report.pdf',
    String? caption,
    bool once = false,
    List<int> bytes = const [1, 2, 3],
  }) async {
    final file = await File('${root.path}/$id').writeAsBytes(bytes);
    // This stream is the authenticated, completed-transfer boundary.
    transfers.events.add(
      ReceivedFile(
        transferId: id,
        originalMessageId: id,
        file: file,
        fileName: fileName,
        mimeType: mime,
        senderId: 'peer',
        fileSize: bytes.length,
        caption: caption,
        isViewOnce: once,
      ),
    );
    await service.waitForIdle();
    return LocalMessage.fromJson(
      (await database.messages.getById(id))!.toJson(),
    );
  }

  test('legacy maps default false and copies preserve or clear deferral', () {
    for (final deferred in [null, false, true]) {
      final json = <String, Object?>{
        if (deferred != null) 'isMediaPreviewDeferred': deferred,
      };
      final entity = MessageEntity.fromJson(json);
      final local = LocalMessage.fromJson(json);
      expect(entity.isMediaPreviewDeferred, deferred ?? false);
      expect(local.isMediaPreviewDeferred, deferred ?? false);
      expect(
        MessageEntity.fromJson(
          entity.copyWith().toJson(),
        ).isMediaPreviewDeferred,
        deferred ?? false,
      );
      expect(
        LocalMessage.fromJson(local.copyWith().toJson()).isMediaPreviewDeferred,
        deferred ?? false,
      );
      expect(
        entity.copyWith(isMediaPreviewDeferred: false).isMediaPreviewDeferred,
        isFalse,
      );
      expect(
        local.copyWith(isMediaPreviewDeferred: false).isMediaPreviewDeferred,
        isFalse,
      );
    }
  });

  test(
    'denied 600KB document retains bytes and activates after restart',
    () async {
      final bytes = List<int>.generate(600 * 1024, (index) => index % 256);
      final received = await receive(bytes: bytes);
      expect(received.isMediaPreviewDeferred, isTrue);
      expect(received.fileName, 'original-report.pdf');
      expect(await File(received.filePath!).readAsBytes(), bytes);
      await service.close();
      await database.close();
      await open();

      final repository = StorageConversationRepository(
        database,
        sender: _Sender(),
      );
      final restored = (await repository.watchMessages('peer').first).single;
      expect(restored.isMediaPreviewDeferred, isTrue);
      expect(restored.filePath, received.filePath);
      expect(restored.fileName, 'original-report.pdf');
      await database.messages.updateStarred(restored.id, true);
      final activated = (await service.activateMediaPreview(restored))!;
      expect(activated.isMediaPreviewDeferred, isFalse);
      expect(activated.isStarred, isTrue);
      expect(activated.peerId, restored.peerId);
      expect(activated.filePath, restored.filePath);
      expect(await File(activated.filePath!).readAsBytes(), bytes);
      expect(
        (await repository.watchMessages('peer').first)
            .single
            .isMediaPreviewDeferred,
        isFalse,
      );

      await service.close();
      await database.close();
      await open();
      expect(
        (await database.messages.getById(restored.id))!.isMediaPreviewDeferred,
        isFalse,
      );
      expect(
        (await service.activateMediaPreview(restored))!.filePath,
        restored.filePath,
      );
    },
  );

  test(
    'send uses original filename, not the private retained basename',
    () async {
      final file = await File('${root.path}/picked').writeAsBytes([4, 5, 6]);
      final results = await service.send(
        conversationId: 'peer',
        recipientId: 'peer',
        attachments: [
          MediaAttachment(
            path: file.path,
            fileName: 'original-report.pdf',
            mimeType: 'application/pdf',
            fileSize: 3,
          ),
        ],
        isGroup: false,
        groupMembers: const [],
      );
      expect(results.single.result, isA<FileTransferSuccess>());
      expect(transfers.sentFileName, 'original-report.pdf');
      expect(
        transfers.sentFile!.uri.pathSegments.last,
        isNot('original-report.pdf'),
      );
      expect(await transfers.sentFile!.readAsBytes(), [4, 5, 6]);
      final sent = LocalMessage.fromJson(
        (await database.messages.getAllMessages()).single.toJson(),
      );
      expect(sent.fileName, 'original-report.pdf');
      expect(sent.isMediaPreviewDeferred, isFalse);
    },
  );

  test(
    'denied photos and videos retain bytes without authorizing previews',
    () async {
      await storage.savePolicy(
        const AutoDownloadPolicy(photosOnCellular: false),
      );
      for (final mime in ['image/png', 'video/mp4']) {
        final message = await receive(id: mime.split('/').first, mime: mime);
        expect(message.isMediaPreviewDeferred, isTrue);
        expect(await File(message.filePath!).readAsBytes(), [1, 2, 3]);
      }
    },
  );

  test('allowed media and voice notes remain immediately available', () async {
    final photo = await receive(id: 'photo', mime: 'image/png');
    final voice = await receive(
      id: 'voice',
      mime: 'audio/mp4',
      caption: const VoiceNoteMetadata(
        duration: Duration(seconds: 2),
        waveform: [0.2, 0.5],
      ).encode(),
    );
    expect(voice.contentType, MessageContentType.voiceNote);
    expect(voice.voiceNoteDuration, const Duration(seconds: 2));
    for (final message in [photo, voice]) {
      expect(message.isMediaPreviewDeferred, isFalse);
      expect(await File(message.filePath!).readAsBytes(), [1, 2, 3]);
      expect(
        (await service.activateMediaPreview(message))!.filePath,
        message.filePath,
      );
    }
    // An ordinary audio attachment is not exempt from document policy.
    expect(
      (await receive(id: 'audio', mime: 'audio/mp4')).isMediaPreviewDeferred,
      isTrue,
    );
  });

  test(
    'activation never resurrects removed, deleted, expired or wrong-chat rows',
    () async {
      final message = await receive();
      final original = (await database.messages.getById(message.id))!;
      for (final invalid in [
        original.copyWith(contentType: StorageMessageContentType.deleted),
        original.copyWith(expiresAt: 1),
        MessageEntity.fromJson({
          ...original.toJson(),
          'conversationId': 'other',
        }),
      ]) {
        await database.messages.update(invalid);
        expect(await service.activateMediaPreview(message), isNull);
        expect(
          (await database.messages.getById(message.id))!.isMediaPreviewDeferred,
          isTrue,
        );
      }
      await database.messages.delete(message.id);
      expect(await service.activateMediaPreview(message), isNull);
      expect(await database.messages.getById(message.id), isNull);
    },
  );

  test(
    'deferred view-once activation preserves atomic claim and consumption',
    () async {
      final message = await receive(once: true);
      final activated = (await service.activateMediaPreview(message))!;
      expect(activated.isMediaPreviewDeferred, isFalse);
      expect(activated.isViewed, isFalse);
      expect(activated.isViewOnce, isTrue);
      final claims = await Future.wait([
        service.markViewOnceViewed(activated),
        service.markViewOnceViewed(activated),
      ]);
      expect(claims.where((claimed) => claimed), hasLength(1));
      expect(await service.activateMediaPreview(message), isNull);
      await service.cleanupViewedOnceMedia();
      expect(await File(message.filePath!).exists(), isTrue);
      service.finishViewOnce(message.id);
      await service.waitForIdle();
      expect(await File(message.filePath!).exists(), isFalse);
      final consumed = (await database.messages.getById(message.id))!;
      expect(consumed.isViewed, isTrue);
      expect(consumed.content, isEmpty);
      expect(await service.activateMediaPreview(message), isNull);
    },
  );

  test(
    'legacy file paths still open and outgoing view-once remains blocked',
    () async {
      final message = await receive();
      final json = (await database.messages.getById(message.id))!.toJson()
        ..remove('isMediaPreviewDeferred');
      await database.messages.update(MessageEntity.fromJson(json));
      expect(
        (await service.activateMediaPreview(message))!.filePath,
        message.filePath,
      );
      await database.messages.update(
        MessageEntity.fromJson({
          ...json,
          'isViewOnce': true,
          'isOutgoing': true,
          'isMediaPreviewDeferred': true,
        }),
      );
      expect(await service.activateMediaPreview(message), isNull);
      expect(await File(message.filePath!).exists(), isTrue);
    },
  );
}

class _Transfers implements FileTransferManager {
  final events = StreamController<ReceivedFile>.broadcast(sync: true);
  String? sentFileName;
  File? sentFile;
  @override
  Stream<ReceivedFile> get receivedFiles => events.stream;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #sendFile) {
      sentFileName = invocation.namedArguments[#fileName] as String?;
      sentFile = invocation.namedArguments[#file] as File;
      return Future<FileTransferResult>.value(
        FileTransferSuccess(
          transferId: 'sent',
          fileName: sentFileName ?? '',
          mimeType: 'application/pdf',
          fileSize: 3,
        ),
      );
    }
    return super.noSuchMethod(invocation);
  }
}

class _Cellular implements NetworkKindProvider {
  @override
  NetworkKind get currentNetworkKind => NetworkKind.cellular;
}

class _Sender implements SendMessageUseCase {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
