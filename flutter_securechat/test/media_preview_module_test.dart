import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/features/chat/media_preview_screen.dart';
import 'package:flutter_securechat/src/media/file_transfer_manager.dart';
import 'package:flutter_securechat/src/media/media_attachment.dart';
import 'package:flutter_securechat/src/media/media_message_service.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'media metadata is sanitized and typed without trusting picker names',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'media_metadata_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/photo.JPG');
      await file.writeAsBytes([1, 2, 3]);

      final attachment = await MediaAttachment.fromPath(
        file.path,
        fileName: '../../özel|foto.JPG',
      );

      expect(attachment.fileName, '_zel_foto.JPG');
      expect(attachment.mimeType, 'image/jpeg');
      expect(attachment.fileSize, 3);
      expect(mediaMimeType('archive.unknown'), 'application/octet-stream');
    },
  );

  test('preview request preserves caption and view-once decision', () async {
    final directory = await Directory.systemTemp.createTemp('media_preview_');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/report.pdf');
    await file.writeAsBytes([1, 2, 3, 4]);
    final attachment = await MediaAttachment.fromPath(file.path);
    final request = MediaSendRequest(
      attachments: [attachment],
      caption: 'gizli açıklama',
      isViewOnce: true,
    );

    expect(request.caption, 'gizli açıklama');
    expect(request.isViewOnce, isTrue);
    expect(request.attachments.single.fileName, 'report.pdf');
    expect(formatMediaFileSize(4), '4 B');
  });

  test(
    'sent and received encrypted media persist in the conversation',
    () async {
      final root = await Directory.systemTemp.createTemp('media_messages_');
      addTearDown(() => root.delete(recursive: true));
      final crypto = LocalAeadCryptoService(
        SecretKey(List<int>.generate(32, (index) => index + 1)),
      );
      final database = await SecureChatDatabase.open(
        file: File('${root.path}/storage.securejson'),
        crypto: crypto,
      );
      addTearDown(database.close);
      await database.conversations.insert(
        const ConversationEntity(
          id: 'peer',
          peerId: 'peer',
          peerName: 'Peer',
          peerPhone: '',
        ),
      );
      final signaling = InMemorySignalingService();
      await signaling.connect(
        userId: 'me',
        url: 'wss://test.invalid',
        accessToken: 'token',
      );
      final transfers = FileTransferManager(
        signaling: signaling,
        crypto: crypto,
        filesDirectory: Directory('${root.path}/media'),
        chunkSize: 4,
      );
      addTearDown(transfers.dispose);
      final media = MediaMessageService(
        database: database,
        transfers: transfers,
        session: SessionStore(userId: 'me', accessToken: 'token'),
        localMediaDirectory: Directory('${root.path}/media'),
      )..start();
      addTearDown(media.close);
      final source = File('${root.path}/photo.jpg');
      await source.writeAsBytes(List<int>.generate(11, (index) => index));
      final attachment = await MediaAttachment.fromPath(source.path);

      final outcomes = await media.send(
        conversationId: 'peer',
        recipientId: 'peer',
        attachments: [attachment],
        isGroup: false,
        groupMembers: const [],
        caption: 'caption',
        isViewOnce: true,
      );
      expect(outcomes.single.result, isA<FileTransferSuccess>());
      var stored = await database.messages.getAllMessages();
      expect(stored, hasLength(1));
      expect(stored.single.contentType, StorageMessageContentType.image);
      expect(stored.single.caption, 'caption');
      expect(stored.single.isViewOnce, isTrue);
      expect(stored.single.status, StorageMessageStatus.sent);
      expect(File(stored.single.content.split('|').last).existsSync(), isTrue);
      final wireMessageId = stored.single.id;

      // Sender and recipient use separate encrypted databases in production.
      // Keeping that boundary in the test also verifies that the encrypted
      // manifest, rather than clear wire fields, carries the message id.
      await media.close();
      final recipientDatabase = await SecureChatDatabase.open(
        file: File('${root.path}/recipient.securejson'),
        crypto: crypto,
      );
      addTearDown(recipientDatabase.close);
      final recipientMedia = MediaMessageService(
        database: recipientDatabase,
        transfers: transfers,
        session: SessionStore(userId: 'recipient', accessToken: 'token'),
        localMediaDirectory: Directory('${root.path}/recipient_media'),
      )..start();
      addTearDown(recipientMedia.close);

      final chunks = signaling.sentMessages.whereType<FileTransferSignal>();
      for (final chunk in chunks) {
        await transfers.receiveChunk(
          FileTransferSignal.fromJson({
            ...chunk.toJson(),
            'senderId': 'peer',
            'recipientId': 'me',
          }),
        );
      }
      await recipientMedia.waitForIdle();
      stored = await recipientDatabase.messages.getAllMessages();
      expect(stored, hasLength(1));
      final incoming = stored.single;
      expect(incoming.id, wireMessageId);
      expect(incoming.isOutgoing, isFalse);
      expect(incoming.status, StorageMessageStatus.delivered);
      expect(incoming.caption, 'caption');
    },
  );
}
