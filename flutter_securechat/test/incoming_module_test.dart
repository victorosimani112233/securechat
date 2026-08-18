import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/chat/poll_service.dart';
import 'package:flutter_securechat/src/chat/message_interaction_service.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/incoming/incoming_message_handler.dart';
import 'package:flutter_securechat/src/incoming/message_envelope_parser.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/private_chat_control_support.dart';

void main() {
  test('message envelope parser preserves all ordered metadata', () {
    final parsed = parseMessageEnvelope(
      'MSGID:m1:REPLY:r1:EXP:9000:VIEWONCE:MENTION:me,bob:POLL:{"q":"?"}',
    );
    expect(parsed.messageId, 'm1');
    expect(parsed.replyToId, 'r1');
    expect(parsed.absoluteExpiresAt, 9000);
    expect(parsed.isViewOnce, isTrue);
    expect(parsed.mentionedUserIds, ['me', 'bob']);
    expect(parsed.contentType, StorageMessageContentType.poll);
    expect(parsed.content, '{"q":"?"}');
  });

  test('incoming direct message decrypts, deduplicates and receipts', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.close);
    final envelope = await fixture.crypto.encryptDirect(
      recipientId: 'me',
      plaintext: 'MSGID:m1:hello',
    );
    final signal = EncryptedSignalMessage(
      senderId: 'alice',
      recipientId: 'me',
      timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
      envelope: envelope,
    );
    final notification = fixture.handler.acceptedMessages.first;

    fixture.signaling.addIncoming(signal);
    fixture.signaling.addIncoming(signal);
    await fixture.handler.waitForIdle();

    expect((await fixture.database.messages.getById('m1'))?.content, 'hello');
    expect(await fixture.database.messages.getMessageCount('alice'), 1);
    final receiptWire = fixture.signaling.sentMessages
        .whereType<EncryptedSignalMessage>()
        .single;
    final receipt = await decryptTestPrivateChatControl(
      crypto: fixture.crypto,
      wire: receiptWire,
    );
    expect(receipt, isA<DeliveryReceiptSignal>());
    expect(receiptWire.toJson(), isNot(containsPair('messageId', anything)));
    expect(receiptWire.toJson()['type'], 'encrypted_message');
    final event = await notification;
    expect(event.conversationId, 'alice');
    expect(event.title, 'alice');
    expect(event.preview, 'hello');
  });

  test(
    'incoming group message carries opaque group id and stores in group',
    () async {
      final fixture = await _Fixture.open();
      addTearDown(fixture.close);
      await fixture.database.conversations.insert(
        const ConversationEntity(
          id: 'group-secret',
          peerId: 'group-secret',
          peerName: 'Hidden Name',
          peerPhone: '',
          isGroup: true,
        ),
      );
      final envelope = await fixture.crypto.encryptGroup(
        senderId: 'alice',
        groupId: 'group-secret',
        plaintext: 'MSGID:g1:team secret',
      );
      expect(envelope, isNot(contains('group-secret')));
      expect(envelope, isNot(contains('Hidden Name')));

      fixture.signaling.addIncoming(
        EncryptedSignalMessage(
          senderId: 'alice',
          recipientId: 'me',
          timestamp: DateTime.fromMillisecondsSinceEpoch(2000),
          envelope: envelope,
        ),
      );
      await _eventually(
        () async => await fixture.database.messages.getById('g1') != null,
      );
      expect(
        (await fixture.database.messages.getById('g1'))?.conversationId,
        'group-secret',
      );
    },
  );

  test(
    'plaintext controls are rejected, private receipts are monotonic and tamper is dropped',
    () async {
      final fixture = await _Fixture.open();
      addTearDown(fixture.close);
      await fixture.database.conversations.insert(
        const ConversationEntity(
          id: 'alice',
          peerId: 'alice',
          peerName: 'Alice',
          peerPhone: '',
        ),
      );
      await fixture.database.messages.insert(
        const MessageEntity(
          id: 'out',
          conversationId: 'alice',
          senderId: 'me',
          content: 'outgoing',
          contentType: StorageMessageContentType.text,
          timestamp: 1,
          status: StorageMessageStatus.sent,
          isOutgoing: true,
        ),
      );
      fixture.signaling.addIncoming(
        DeliveryReceiptSignal(
          senderId: 'alice',
          recipientId: 'me',
          timestamp: DateTime.now(),
          messageId: 'out',
          status: 'DELIVERED',
        ),
      );
      fixture.signaling.addIncoming(
        EncryptedSignalMessage(
          senderId: 'alice',
          recipientId: 'me',
          timestamp: DateTime.now(),
          envelope: 'E2EE:v1:LOCAL_AES_GCM:bad:bad:bad',
        ),
      );
      await fixture.handler.waitForIdle();
      expect(
        (await fixture.database.messages.getById('out'))?.status,
        StorageMessageStatus.sent,
      );
      expect(await fixture.database.messages.getMessageCount('alice'), 1);

      fixture.signaling.addIncoming(
        await encryptTestPrivateChatControl(
          crypto: fixture.crypto,
          control: DeliveryReceiptSignal(
            senderId: 'alice',
            recipientId: 'me',
            timestamp: DateTime.now(),
            messageId: 'out',
            status: 'READ',
          ),
        ),
      );
      await fixture.handler.waitForIdle();
      expect(
        (await fixture.database.messages.getById('out'))?.status,
        StorageMessageStatus.read,
      );
    },
  );

  test('incoming encrypted poll vote updates option voter lists', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.close);
    await fixture.database.conversations.insert(
      const ConversationEntity(
        id: 'alice',
        peerId: 'alice',
        peerName: 'Alice',
        peerPhone: '',
      ),
    );
    await fixture.database.messages.insert(
      MessageEntity(
        id: 'poll-1',
        conversationId: 'alice',
        senderId: 'me',
        content: PollData(
          question: 'Devam?',
          options: const ['Evet', 'Hayır'],
          singleChoice: true,
        ).encode(),
        contentType: StorageMessageContentType.poll,
        timestamp: 1,
        status: StorageMessageStatus.sent,
        isOutgoing: true,
      ),
    );
    final envelope = await fixture.crypto.encryptDirect(
      recipientId: 'me',
      plaintext: 'MSGID:vote-1:POLLVOTE:poll-1:0',
    );
    fixture.signaling.addIncoming(
      EncryptedSignalMessage(
        senderId: 'alice',
        recipientId: 'me',
        timestamp: DateTime.now(),
        envelope: envelope,
      ),
    );
    await fixture.handler.waitForIdle();
    final updated = await fixture.database.messages.getById('poll-1');
    expect(PollData.parse(updated!.content).votes[0], ['alice']);
  });

  test('incoming reaction preserves emoji to voter-list schema', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.close);
    await fixture.database.conversations.insert(
      const ConversationEntity(
        id: 'alice',
        peerId: 'alice',
        peerName: 'Alice',
        peerPhone: '',
      ),
    );
    await fixture.database.messages.insert(
      const MessageEntity(
        id: 'reaction-1',
        conversationId: 'alice',
        senderId: 'me',
        content: 'hello',
        contentType: StorageMessageContentType.text,
        timestamp: 1,
        status: StorageMessageStatus.sent,
        isOutgoing: true,
      ),
    );
    fixture.signaling.addIncoming(
      await encryptTestPrivateChatControl(
        crypto: fixture.crypto,
        control: MessageReactionSignal(
          senderId: 'alice',
          recipientId: 'me',
          timestamp: DateTime.now(),
          messageId: 'reaction-1',
          emoji: '👍',
        ),
      ),
    );
    await _eventually(() async {
      final message = await fixture.database.messages.getById('reaction-1');
      return parseReactions(message!.reactions)['👍']?.contains('alice') ??
          false;
    });
    fixture.signaling.addIncoming(
      await encryptTestPrivateChatControl(
        crypto: fixture.crypto,
        control: MessageReactionSignal(
          senderId: 'alice',
          recipientId: 'me',
          timestamp: DateTime.now(),
          messageId: 'reaction-1',
          emoji: '👍',
          remove: true,
        ),
      ),
    );
    await _eventually(() async {
      final message = await fixture.database.messages.getById('reaction-1');
      return parseReactions(message!.reactions).isEmpty;
    });
  });

  test('authenticated author may edit only their own message', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.close);
    await fixture.database.conversations.insert(
      const ConversationEntity(
        id: 'alice',
        peerId: 'alice',
        peerName: 'Alice',
        peerPhone: '',
      ),
    );
    for (final message in const [
      MessageEntity(
        id: 'remote',
        conversationId: 'alice',
        senderId: 'alice',
        content: 'remote old',
        contentType: StorageMessageContentType.text,
        timestamp: 1,
        status: StorageMessageStatus.delivered,
        isOutgoing: false,
      ),
      MessageEntity(
        id: 'local',
        conversationId: 'alice',
        senderId: 'me',
        content: 'local old',
        contentType: StorageMessageContentType.text,
        timestamp: 2,
        status: StorageMessageStatus.sent,
        isOutgoing: true,
      ),
    ]) {
      await fixture.database.messages.insert(message);
    }
    for (final id in ['remote', 'local']) {
      fixture.signaling.addIncoming(
        await encryptTestPrivateChatControl(
          crypto: fixture.crypto,
          control: MessageEditSignal(
            senderId: 'alice',
            recipientId: 'me',
            timestamp: DateTime.now(),
            messageId: id,
            newContent: 'changed',
          ),
        ),
      );
    }
    await fixture.handler.waitForIdle();
    expect(
      (await fixture.database.messages.getById('remote'))?.content,
      'changed',
    );
    expect(
      (await fixture.database.messages.getById('local'))?.content,
      'local old',
    );
  });
}

class _Fixture {
  _Fixture(
    this.directory,
    this.database,
    this.crypto,
    this.signaling,
    this.handler,
  );
  final Directory directory;
  final SecureChatDatabase database;
  final LocalAeadCryptoService crypto;
  final InMemorySignalingService signaling;
  final IncomingMessageHandler handler;

  static Future<_Fixture> open() async {
    final directory = await Directory.systemTemp.createTemp('incoming_test_');
    final crypto = LocalAeadCryptoService(
      SecretKey(List.generate(32, (index) => index + 3)),
    );
    final database = await SecureChatDatabase.open(
      file: File('${directory.path}/db.securejson'),
      crypto: crypto,
    );
    final signaling = InMemorySignalingService();
    await signaling.connect(
      userId: 'me',
      url: 'ws://local',
      accessToken: 'token',
    );
    final handler = IncomingMessageHandler(
      signaling: signaling,
      crypto: crypto,
      database: database,
      session: SessionStore(userId: 'me', accessToken: 'token'),
    )..start();
    return _Fixture(directory, database, crypto, signaling, handler);
  }

  Future<void> close() async {
    await handler.close();
    await database.close();
    await directory.delete(recursive: true);
  }
}

Future<void> _eventually(Future<bool> Function() predicate) async {
  for (var attempt = 0; attempt < 30; attempt++) {
    if (await predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Condition was not satisfied before timeout');
}
