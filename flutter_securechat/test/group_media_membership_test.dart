import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/media/file_transfer_manager.dart';
import 'package:flutter_securechat/src/media/media_attachment.dart';
import 'package:flutter_securechat/src/media/media_message_service.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';

void main() {
  for (final left in [true, false]) {
    test(
      'media uses persisted membership, not stale picker members (left=$left)',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'group_media_members_',
        );
        addTearDown(() => root.delete(recursive: true));
        final crypto = LocalAeadCryptoService(SecretKey(List.filled(32, 17)));
        final database = await SecureChatDatabase.open(
          file: File('${root.path}/db'),
          crypto: crypto,
        );
        addTearDown(database.close);
        await database.conversations.insert(
          ConversationEntity(
            id: 'group',
            peerId: 'group',
            peerName: 'Group',
            peerPhone: '',
            isGroup: true,
            groupMembers: left ? 'peer' : 'me,peer',
          ),
        );
        final signaling = InMemorySignalingService()..setConnected(true);
        addTearDown(signaling.dispose);
        final transfers = FileTransferManager(
          signaling: signaling,
          crypto: crypto,
          filesDirectory: Directory('${root.path}/media'),
        );
        addTearDown(transfers.dispose);
        final media = MediaMessageService(
          database: database,
          transfers: transfers,
          session: SessionStore(userId: 'me'),
          localMediaDirectory: Directory('${root.path}/media'),
        );
        addTearDown(media.close);
        final source = File('${root.path}/photo.jpg')
          ..writeAsBytesSync([1, 2, 3]);
        final attachment = await MediaAttachment.fromPath(source.path);
        final result = media.send(
          conversationId: 'group',
          recipientId: 'group',
          attachments: [attachment],
          isGroup: true,
          groupMembers: ['me', 'peer', 'departed-peer'],
        );
        if (left) {
          await expectLater(result, throwsStateError);
          expect(signaling.sentMessages, isEmpty);
          expect(await database.messages.getAllMessages(), isEmpty);
          expect(await source.exists(), isTrue);
        } else {
          expect((await result).single.result, isA<FileTransferSuccess>());
          final recipients = signaling.sentMessages
              .whereType<FileTransferSignal>()
              .map((signal) => signal.recipientId)
              .toSet();
          expect(recipients, {'peer'});
        }
      },
    );
  }
}
