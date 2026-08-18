import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/domain/send_message_use_case.dart';
import 'package:flutter_securechat/src/services/conversation_repository.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('conversation list actions persist through encrypted DAO', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.close);

    await fixture.repository.setPinned('alice', true);
    await fixture.repository.setFavorite('alice', true);
    await fixture.repository.setManuallyUnread('alice', true);
    await fixture.repository.setArchived('alice', true);

    final conversation =
        (await fixture.repository.watchConversations().first).single;
    expect(conversation.isPinned, isTrue);
    expect(conversation.isFavorite, isTrue);
    expect(conversation.manuallyUnread, isTrue);
    expect(conversation.isArchived, isTrue);
    final raw = await fixture.databaseFile.readAsString();
    expect(raw, isNot(contains('Alice')));
  });

  test('deleting a conversation removes its local message rows', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.close);

    await fixture.repository.deleteConversation('alice');

    expect(await fixture.database.conversations.getById('alice'), isNull);
    expect(await fixture.database.messages.getMessageCount('alice'), 0);
  });

  test('global message search is case-insensitive and newest-first', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.close);

    await fixture.database.messages.insert(
      const MessageEntity(
        id: 'm2',
        conversationId: 'alice',
        senderId: 'me',
        content: 'Needle in the recent message',
        contentType: StorageMessageContentType.text,
        timestamp: 30,
        status: StorageMessageStatus.sent,
        isOutgoing: true,
      ),
    );
    await fixture.database.messages.insert(
      const MessageEntity(
        id: 'm3',
        conversationId: 'alice',
        senderId: 'alice',
        content: 'older NEEDLE result',
        contentType: StorageMessageContentType.text,
        timestamp: 20,
        status: StorageMessageStatus.delivered,
        isOutgoing: false,
      ),
    );

    final results = await fixture.repository.searchAllMessages(
      'needle',
      limit: 1,
    );

    expect(results, hasLength(1));
    expect(results.single.id, 'm2');
  });
}

class _Fixture {
  _Fixture(
    this.directory,
    this.databaseFile,
    this.database,
    this.signaling,
    this.repository,
  );

  final Directory directory;
  final File databaseFile;
  final SecureChatDatabase database;
  final InMemorySignalingService signaling;
  final StorageConversationRepository repository;

  static Future<_Fixture> open() async {
    final directory = await Directory.systemTemp.createTemp(
      'conversation_actions_',
    );
    final databaseFile = File('${directory.path}/database.securejson');
    final crypto = LocalAeadCryptoService(
      SecretKey(List<int>.generate(32, (index) => 97 + index)),
    );
    final database = await SecureChatDatabase.open(
      file: databaseFile,
      crypto: crypto,
    );
    await database.conversations.insert(
      const ConversationEntity(
        id: 'alice',
        peerId: 'alice',
        peerName: 'Alice',
        peerPhone: '+1',
      ),
    );
    await database.messages.insert(
      const MessageEntity(
        id: 'm1',
        conversationId: 'alice',
        senderId: 'alice',
        content: 'secret',
        contentType: StorageMessageContentType.text,
        timestamp: 1,
        status: StorageMessageStatus.delivered,
        isOutgoing: false,
      ),
    );
    final signaling = InMemorySignalingService();
    final session = SessionStore(userId: 'me', accessToken: 'token');
    final repository = StorageConversationRepository(
      database,
      sender: SendMessageUseCase(
        database: database,
        signaling: signaling,
        session: session,
        crypto: crypto,
        maxRetryCount: 0,
        retryDelay: Duration.zero,
      ),
    );
    return _Fixture(directory, databaseFile, database, signaling, repository);
  }

  Future<void> close() async {
    await database.close();
    await signaling.disconnect();
    await directory.delete(recursive: true);
  }
}
