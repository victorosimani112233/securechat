import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'expired messages are removed and conversation preview is repaired',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'message_expiry_test_',
      );
      final database = await SecureChatDatabase.open(
        file: File('${root.path}/db'),
        crypto: LocalAeadCryptoService(
          SecretKey(List<int>.generate(32, (index) => index + 1)),
        ),
      );
      addTearDown(() async {
        await database.close();
        await root.delete(recursive: true);
      });
      await database.conversations.insert(
        const ConversationEntity(
          id: 'alice',
          peerId: 'alice',
          peerName: 'Alice',
          peerPhone: '',
          lastMessage: 'expired',
          lastMessageTimestamp: 200,
          lastMessageType: 'text',
          lastMessageOutgoing: true,
          lastMessageStatus: 'sent',
        ),
      );
      await database.messages.insert(
        const MessageEntity(
          id: 'kept',
          conversationId: 'alice',
          senderId: 'alice',
          content: 'kept',
          contentType: StorageMessageContentType.text,
          timestamp: 100,
          status: StorageMessageStatus.delivered,
          isOutgoing: false,
        ),
      );
      await database.messages.insert(
        const MessageEntity(
          id: 'expired',
          conversationId: 'alice',
          senderId: 'me',
          content: 'expired',
          contentType: StorageMessageContentType.text,
          timestamp: 200,
          status: StorageMessageStatus.sent,
          isOutgoing: true,
          expiresAt: 300,
        ),
      );

      expect(await database.messages.deleteExpiredMessages(300), 1);
      final conversation = (await database.conversations.getById('alice'))!;
      expect(conversation.lastMessage, 'kept');
      expect(conversation.lastMessageTimestamp, 100);
      expect(conversation.lastMessageType, 'text');
      expect(conversation.lastMessageOutgoing, isFalse);
      expect(conversation.lastMessageStatus, 'delivered');
    },
  );

  test('preview is cleared when the final message expires', () async {
    final root = await Directory.systemTemp.createTemp('last_expiry_test_');
    final database = await SecureChatDatabase.open(
      file: File('${root.path}/db'),
      crypto: LocalAeadCryptoService(
        SecretKey(List<int>.generate(32, (index) => index + 33)),
      ),
    );
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });
    await database.conversations.insert(
      const ConversationEntity(
        id: 'alice',
        peerId: 'alice',
        peerName: 'Alice',
        peerPhone: '',
        lastMessage: 'last',
        lastMessageTimestamp: 100,
      ),
    );
    await database.messages.insert(
      const MessageEntity(
        id: 'last',
        conversationId: 'alice',
        senderId: 'alice',
        content: 'last',
        contentType: StorageMessageContentType.text,
        timestamp: 100,
        status: StorageMessageStatus.delivered,
        isOutgoing: false,
        expiresAt: 101,
      ),
    );

    expect(await database.messages.deleteExpiredMessages(101), 1);
    final conversation = (await database.conversations.getById('alice'))!;
    expect(conversation.lastMessage, isNull);
    expect(conversation.lastMessageTimestamp, isNull);
    expect(conversation.lastMessageType, isNull);
    expect(conversation.lastMessageStatus, isNull);
  });
}
