import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/chat/read_receipt_service.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/private_chat_control_support.dart';

void main() {
  test(
    'opening a chat marks incoming messages read and sends one receipt',
    () async {
      final fixture = await _Fixture.open();
      addTearDown(fixture.close);
      await fixture.insertIncoming('m1', senderId: 'alice');
      await fixture.insertOutgoing('mine');

      final results = await Future.wait([
        fixture.service.markConversationRead('alice'),
        fixture.service.markConversationRead('alice'),
      ]);

      expect(results, [1, 1]);
      expect(
        (await fixture.database.messages.getById('m1'))?.status,
        StorageMessageStatus.read,
      );
      expect(
        (await fixture.database.messages.getById('mine'))?.status,
        StorageMessageStatus.sent,
      );
      final receipts = (await fixture.sentControls())
          .whereType<DeliveryReceiptSignal>()
          .toList(growable: false);
      expect(receipts, hasLength(1));
      expect(receipts.single.messageId, 'm1');
      expect(receipts.single.recipientId, 'alice');
      expect(receipts.single.status, 'READ');
    },
  );

  test(
    'a new message arriving in the open conversation gets its own receipt',
    () async {
      final fixture = await _Fixture.open();
      addTearDown(fixture.close);
      await fixture.insertIncoming('m1', senderId: 'alice');
      expect(await fixture.service.markConversationRead('alice'), 1);
      await fixture.insertIncoming('m2', senderId: 'alice');

      expect(await fixture.service.markConversationRead('alice'), 1);
      expect(
        (await fixture.sentControls()).whereType<DeliveryReceiptSignal>().map(
          (receipt) => receipt.messageId,
        ),
        ['m1', 'm2'],
      );
    },
  );
}

class _Fixture {
  _Fixture({
    required this.directory,
    required this.database,
    required this.crypto,
    required this.signaling,
    required this.service,
  });

  final Directory directory;
  final SecureChatDatabase database;
  final LocalAeadCryptoService crypto;
  final InMemorySignalingService signaling;
  final ReadReceiptService service;

  static Future<_Fixture> open() async {
    final directory = await Directory.systemTemp.createTemp('read_receipt_');
    final crypto = LocalAeadCryptoService(
      SecretKey(List<int>.generate(32, (index) => index + 51)),
    );
    final database = await SecureChatDatabase.open(
      file: File('${directory.path}/database.securejson'),
      crypto: crypto,
    );
    await database.conversations.insert(
      const ConversationEntity(
        id: 'alice',
        peerId: 'alice',
        peerName: 'Alice',
        peerPhone: '+1',
        unreadCount: 2,
      ),
    );
    final signaling = InMemorySignalingService();
    await signaling.connect(
      userId: 'me',
      url: 'wss://test.invalid',
      accessToken: 'token',
    );
    return _Fixture(
      directory: directory,
      database: database,
      crypto: crypto,
      signaling: signaling,
      service: ReadReceiptService(
        database: database,
        session: SessionStore(userId: 'me', accessToken: 'token'),
        signaling: signaling,
        crypto: crypto,
        deliveredVisibilityDelay: Duration.zero,
      ),
    );
  }

  Future<void> insertIncoming(String id, {required String senderId}) =>
      database.messages.insert(
        MessageEntity(
          id: id,
          conversationId: 'alice',
          senderId: senderId,
          content: 'message',
          contentType: StorageMessageContentType.text,
          timestamp: DateTime.now().microsecondsSinceEpoch,
          status: StorageMessageStatus.delivered,
          isOutgoing: false,
        ),
      );

  Future<void> insertOutgoing(String id) => database.messages.insert(
    MessageEntity(
      id: id,
      conversationId: 'alice',
      senderId: 'me',
      content: 'outgoing',
      contentType: StorageMessageContentType.text,
      timestamp: DateTime.now().microsecondsSinceEpoch,
      status: StorageMessageStatus.sent,
      isOutgoing: true,
    ),
  );

  Future<List<SignalMessage>> sentControls() => Future.wait(
    signaling.sentMessages.whereType<EncryptedSignalMessage>().map(
      (wire) => decryptTestPrivateChatControl(crypto: crypto, wire: wire),
    ),
  );

  Future<void> close() async {
    await signaling.disconnect();
    await database.close();
    await directory.delete(recursive: true);
  }
}
