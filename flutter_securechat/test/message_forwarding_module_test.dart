import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/chat/message_forwarding_service.dart';
import 'package:flutter_securechat/src/chat/poll_service.dart';
import 'package:flutter_securechat/src/core/models.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/domain/send_message_use_case.dart';
import 'package:flutter_securechat/src/media/file_transfer_manager.dart';
import 'package:flutter_securechat/src/media/media_message_service.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'text forwarding creates new encrypted messages for every target',
    () async {
      final fixture = await _Fixture.open();
      addTearDown(fixture.close);

      final source = LocalMessage(
        id: 'source-id',
        conversationId: 'source',
        senderId: 'alice',
        peerId: 'source',
        content: 'forwarded secret',
        contentType: MessageContentType.text,
        timestamp: DateTime.fromMillisecondsSinceEpoch(1),
        status: MessageStatus.delivered,
        isOutgoing: false,
        replyToId: 'old-reply-id',
      );

      expect(
        await fixture.service.forward(source: source, target: fixture.targetA),
        ForwardMessageOutcome.sent,
      );
      expect(
        await fixture.service.forward(source: source, target: fixture.targetB),
        ForwardMessageOutcome.sent,
      );

      final first =
          (await fixture.database.messages.getMessages('target-a').first)
              .single;
      final second =
          (await fixture.database.messages.getMessages('target-b').first)
              .single;
      expect(first.id, isNot(source.id));
      expect(second.id, isNot(source.id));
      expect(first.id, isNot(second.id));
      expect(first.replyToId, isNull);
      final signals = fixture.signaling.sentMessages
          .whereType<EncryptedSignalMessage>()
          .toList(growable: false);
      expect(signals, hasLength(2));
      expect(signals[0].envelope, isNot(signals[1].envelope));
      expect(
        signals.every((signal) => !signal.envelope.contains(source.content)),
        isTrue,
      );
    },
  );

  test('view-once and system messages cannot be forwarded', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.close);
    final source = LocalMessage(
      id: 'view-once',
      conversationId: 'source',
      senderId: 'alice',
      peerId: 'source',
      content: 'one look',
      contentType: MessageContentType.text,
      timestamp: DateTime.now(),
      status: MessageStatus.delivered,
      isOutgoing: false,
      isViewOnce: true,
    );

    expect(
      await fixture.service.forward(source: source, target: fixture.targetA),
      ForwardMessageOutcome.notAllowed,
    );
    expect(fixture.signaling.sentMessages, isEmpty);
    expect(await fixture.database.messages.getMessageCount('target-a'), 0);
  });

  test(
    'multiple selected messages keep order and their original types',
    () async {
      final fixture = await _Fixture.open();
      addTearDown(fixture.close);
      final sources = [
        LocalMessage(
          id: 'text-source',
          conversationId: 'source',
          senderId: 'alice',
          peerId: 'source',
          content: 'first',
          contentType: MessageContentType.text,
          timestamp: DateTime.fromMillisecondsSinceEpoch(1),
          status: MessageStatus.delivered,
          isOutgoing: false,
        ),
        LocalMessage(
          id: 'poll-source',
          conversationId: 'source',
          senderId: 'alice',
          peerId: 'source',
          content: PollData(
            question: 'Question?',
            options: const ['A', 'B'],
            singleChoice: true,
            votes: const {
              0: ['alice'],
            },
          ).encode(),
          contentType: MessageContentType.poll,
          timestamp: DateTime.fromMillisecondsSinceEpoch(2),
          status: MessageStatus.delivered,
          isOutgoing: false,
        ),
      ];

      expect(
        await fixture.service.forwardAll(
          sources: sources,
          target: fixture.targetA,
        ),
        [ForwardMessageOutcome.sent, ForwardMessageOutcome.sent],
      );
      final stored = await fixture.database.messages.getMessagesImmediate(
        'target-a',
      );
      expect(stored.map((message) => message.contentType), [
        StorageMessageContentType.text,
        StorageMessageContentType.poll,
      ]);
      expect(PollData.parse(stored.last.content).votes, isEmpty);
    },
  );

  test(
    'media forwarding retransfers local bytes instead of copying ciphertext',
    () async {
      final fixture = await _Fixture.open();
      addTearDown(fixture.close);
      final sourceFile = File('${fixture.directory.path}/original.txt');
      await sourceFile.writeAsString('fresh encrypted transfer');
      final source = LocalMessage(
        id: 'old-media-id',
        conversationId: 'source',
        senderId: 'alice',
        peerId: 'source',
        content: LocalMessage.buildFileContent(
          fileName: 'original.txt',
          mimeType: 'text/plain',
          fileSize: await sourceFile.length(),
          filePath: sourceFile.path,
        ),
        contentType: MessageContentType.file,
        timestamp: DateTime.now(),
        status: MessageStatus.delivered,
        isOutgoing: false,
        caption: 'caption',
      );

      expect(
        await fixture.service.forward(source: source, target: fixture.targetA),
        ForwardMessageOutcome.sent,
      );
      final stored =
          (await fixture.database.messages.getMessages('target-a').first)
              .single;
      expect(stored.id, isNot(source.id));
      expect(stored.caption, 'caption');
      expect(stored.contentType, StorageMessageContentType.file);
      expect(
        fixture.signaling.sentMessages.whereType<FileTransferSignal>(),
        isNotEmpty,
      );
    },
  );
}

class _Fixture {
  _Fixture({
    required this.directory,
    required this.database,
    required this.signaling,
    required this.transfers,
    required this.media,
    required this.service,
  });

  final Directory directory;
  final SecureChatDatabase database;
  final InMemorySignalingService signaling;
  final FileTransferManager transfers;
  final MediaMessageService media;
  final MessageForwardingService service;
  final targetA = const Conversation(
    id: 'target-a',
    peerId: 'target-a',
    peerName: 'Target A',
    peerPhone: '+1',
  );
  final targetB = const Conversation(
    id: 'target-b',
    peerId: 'target-b',
    peerName: 'Target B',
    peerPhone: '+2',
  );

  static Future<_Fixture> open() async {
    final directory = await Directory.systemTemp.createTemp('forwarding_');
    final crypto = LocalAeadCryptoService(
      SecretKey(List<int>.generate(32, (index) => index + 31)),
    );
    final database = await SecureChatDatabase.open(
      file: File('${directory.path}/database.securejson'),
      crypto: crypto,
    );
    for (final target in const [
      Conversation(
        id: 'target-a',
        peerId: 'target-a',
        peerName: 'Target A',
        peerPhone: '+1',
      ),
      Conversation(
        id: 'target-b',
        peerId: 'target-b',
        peerName: 'Target B',
        peerPhone: '+2',
      ),
    ]) {
      await database.conversations.insert(
        ConversationEntity(
          id: target.id,
          peerId: target.peerId,
          peerName: target.peerName,
          peerPhone: target.peerPhone,
        ),
      );
    }
    final session = SessionStore(userId: 'me', accessToken: 'token');
    final signaling = InMemorySignalingService();
    await signaling.connect(
      userId: 'me',
      url: 'wss://test.invalid',
      accessToken: 'token',
    );
    final sender = SendMessageUseCase(
      database: database,
      signaling: signaling,
      session: session,
      crypto: crypto,
      maxRetryCount: 0,
      retryDelay: Duration.zero,
    );
    final transfers = FileTransferManager(
      signaling: signaling,
      crypto: crypto,
      filesDirectory: Directory('${directory.path}/incoming'),
      chunkSize: 8,
    );
    final media = MediaMessageService(
      database: database,
      transfers: transfers,
      session: session,
      localMediaDirectory: Directory('${directory.path}/media'),
    );
    final polls = PollService(
      database: database,
      sender: sender,
      signaling: signaling,
      session: session,
      crypto: crypto,
    );
    return _Fixture(
      directory: directory,
      database: database,
      signaling: signaling,
      transfers: transfers,
      media: media,
      service: MessageForwardingService(
        sender: sender,
        polls: polls,
        media: media,
      ),
    );
  }

  Future<void> close() async {
    await media.close();
    await transfers.dispose();
    await signaling.disconnect();
    await database.close();
    await directory.delete(recursive: true);
  }
}
