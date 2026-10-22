import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';

LocalAeadCryptoService _crypto() =>
    LocalAeadCryptoService(SecretKey(List.filled(32, 41)));

MessageEntity _message(
  String id,
  String conversation,
  int timestamp, {
  String? content,
}) => MessageEntity(
  id: id,
  conversationId: conversation,
  senderId: conversation,
  content: content ?? 'mesaj $id',
  contentType: StorageMessageContentType.text,
  timestamp: timestamp,
  status: StorageMessageStatus.delivered,
  isOutgoing: false,
);

/// Mesajlar acilista bellege yuklenmez; sohbet sayfa sayfa okunur.
void main() {
  late Directory root;
  late File file;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('message_paging_');
    file = File('${root.path}/db.securejson');
  });
  tearDown(() => root.delete(recursive: true));

  Future<SecureChatDatabase> open() =>
      SecureChatDatabase.open(file: file, crypto: _crypto());

  Future<void> seed(SecureChatDatabase db, {int perConversation = 300}) async {
    for (final conversation in ['alice', 'bob']) {
      await db.conversations.insert(
        ConversationEntity(
          id: conversation,
          peerId: conversation,
          peerName: conversation,
          peerPhone: '',
          lastMessageTimestamp: perConversation,
        ),
      );
    }
    for (var i = 1; i <= perConversation; i++) {
      await db.messages.insert(_message('a$i', 'alice', i));
      await db.messages.insert(_message('b$i', 'bob', i));
    }
  }

  test('history is not decoded into memory when the database opens', () async {
    final writer = await open();
    await seed(writer);
    await writer.close();

    final db = await open();
    addTearDown(db.close);
    // Acilista yalniz her sohbetin son mesaji (onizleme onarimi) okunur.
    expect(db.debugLoadedMessageCount, lessThanOrEqualTo(2));
    expect(await db.messages.getMessageCount('alice'), 300);
    expect(db.debugLoadedMessageCount, lessThanOrEqualTo(2));
  });

  test('the latest page is the newest messages in order', () async {
    final writer = await open();
    await seed(writer, perConversation: 120);
    await writer.close();
    final db = await open();
    addTearDown(db.close);

    final page = await db.messages.getLatestPage('alice', 50).first;
    expect(page.map((m) => m.id), [for (var i = 71; i <= 120; i++) 'a$i']);
    final older = await db.messages.getOlderMessages('alice', 71, 20);
    expect(older.first.id, 'a70');
    expect(older.last.id, 'a51');
    // Sayfa sohbetin tamamini okumaz.
    expect(db.debugLoadedMessageCount, lessThan(120));
  });

  test('a conversation query uses the timeline index', () async {
    final db = await open();
    addTearDown(db.close);
    final plan = db.store.query(
      'EXPLAIN QUERY PLAN SELECT id, data FROM records '
      "WHERE collection = 'messages' "
      "AND json_extract(data, '\$.conversationId') = ? "
      "ORDER BY json_extract(data, '\$.timestamp') DESC LIMIT 50;",
      ['alice'],
    );
    expect(
      plan.map((row) => row['detail']).join(' '),
      contains('records_message_timeline'),
    );
  });

  test('a write from another connection replaces the cached message', () async {
    final first = await open();
    addTearDown(first.close);
    await first.conversations.insert(
      const ConversationEntity(
        id: 'alice',
        peerId: 'alice',
        peerName: 'alice',
        peerPhone: '',
      ),
    );
    await first.messages.insert(_message('m1', 'alice', 1, content: 'eski'));
    expect((await first.messages.getById('m1'))!.content, 'eski');

    final second = await open();
    await second.messages.updateContent(
      'm1',
      'yeni',
      StorageMessageContentType.text,
    );
    await second.close();

    expect((await first.messages.getById('m1'))!.content, 'yeni');
    expect(
      (await first.messages.getLatestPage('alice', 10).first).single.content,
      'yeni',
    );
  });

  test('clearing account content removes every message on disk', () async {
    final db = await open();
    await seed(db, perConversation: 30);
    await db.clearAccountContent();
    expect(await db.messages.getMessageCount('alice'), 0);
    await db.close();

    final reopened = await open();
    addTearDown(reopened.close);
    expect(await reopened.messages.getAllMessages(), isEmpty);
    expect(await reopened.hasAccountContent(), isFalse);
  });

  test('changes inside one write are visible to its later reads', () async {
    final db = await open();
    addTearDown(db.close);
    await seed(db, perConversation: 5);
    // Suresi dolan en yeni mesaj silinince onizleme kalan en yeniye gecer.
    await db.messages.insert(_message('a6', 'alice', 6).copyWith(expiresAt: 1));
    expect(await db.messages.deleteExpiredMessages(2), 1);
    final alice = await db.conversations.getById('alice');
    expect(alice!.lastMessageTimestamp, 5);
    expect(alice.lastMessage, 'mesaj a5');
  });
}
