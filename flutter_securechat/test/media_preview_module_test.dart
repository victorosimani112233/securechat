import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations.dart';

import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/chat/conversation_preview.dart';
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

  testWidgets('media preview send action has an accessible label', (
    tester,
  ) async {
    const attachment = MediaAttachment(
      path: '/test/document.txt',
      fileName: 'document.txt',
      mimeType: 'text/plain',
      fileSize: 2,
    );
    await tester.pumpWidget(
      const MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaPreviewScreen(attachments: [attachment]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Send'), findsOneWidget);
    expect(
      tester.widget<IconButton>(find.byKey(const Key('media-send'))).onPressed,
      isNotNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final deliveredEarly in [true, false]) {
    test(
      'media keeps ${deliveredEarly ? 'early delivery receipt' : 'failed transfer'} in chat summary',
      () async {
        final root = await Directory.systemTemp.createTemp('media_status_');
        addTearDown(() => root.delete(recursive: true));
        final crypto = LocalAeadCryptoService(SecretKey(List.filled(32, 7)));
        final database = await SecureChatDatabase.open(
          file: File('${root.path}/store'),
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
        final signaling = _TransferSignaling(() async {
          final row = (await database.messages.getAllMessages()).single;
          expect(
            row.status,
            deliveredEarly
                ? isIn([
                    StorageMessageStatus.sending,
                    StorageMessageStatus.delivered,
                  ])
                : StorageMessageStatus.sending,
          );
          if (deliveredEarly) {
            await database.messages.updateStatus(
              row.id,
              StorageMessageStatus.delivered,
            );
          }
          return deliveredEarly;
        });
        await signaling.connect(
          userId: 'me',
          url: 'wss://test.invalid',
          accessToken: 'token',
        );
        final transfers = FileTransferManager(
          signaling: signaling,
          crypto: crypto,
          filesDirectory: Directory('${root.path}/media'),
        );
        addTearDown(transfers.dispose);
        final media = MediaMessageService(
          database: database,
          transfers: transfers,
          session: SessionStore(userId: 'me', accessToken: 'token'),
          localMediaDirectory: Directory('${root.path}/media'),
        );
        addTearDown(media.close);
        final source = File('${root.path}/photo.jpg')
          ..writeAsBytesSync([1, 2, 3]);
        await media.send(
          conversationId: 'peer',
          recipientId: 'peer',
          attachments: [await MediaAttachment.fromPath(source.path)],
          isGroup: false,
          groupMembers: const [],
        );
        final expected = deliveredEarly
            ? StorageMessageStatus.delivered
            : StorageMessageStatus.failed;
        expect(
          (await database.messages.getAllMessages()).single.status,
          expected,
        );
        expect(
          (await database.conversations.getById('peer'))!.lastMessageStatus,
          expected.name,
        );
      },
    );
  }

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
      final preview = (await database.conversations.getById('peer'))!;
      expect(preview.lastMessage, viewOncePreviewLabel);
      expect(preview.lastMessageStatus, 'sent');
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
      expect(incoming.isViewOnce, isTrue);
      expect(
        (await recipientDatabase.conversations.getById('peer'))!.lastMessage,
        viewOncePreviewLabel,
      );
      expect(
        await recipientDatabase.messages
            .searchMessages('peer', 'caption')
            .first,
        isEmpty,
      );
      expect(
        await recipientDatabase.messages.getMediaMessages('peer').first,
        isEmpty,
      );
    },
  );
}

class _TransferSignaling extends InMemorySignalingService {
  _TransferSignaling(this.onChunk);
  final Future<bool> Function() onChunk;

  @override
  Future<bool> send(SignalMessage message) async {
    if (message is FileTransferSignal) return onChunk();
    return super.send(message);
  }
}
