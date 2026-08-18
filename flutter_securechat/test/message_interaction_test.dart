import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_securechat/src/chat/message_interaction_service.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';

import 'support/private_chat_control_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('edit reaction star pin and delete update DAO and fan out', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.close);
    await fixture.database.conversations.insert(
      const ConversationEntity(
        id: 'peer',
        peerId: 'peer',
        peerName: 'Peer',
        peerPhone: '',
      ),
    );
    await fixture.database.messages.insert(
      MessageEntity(
        id: 'm1',
        conversationId: 'peer',
        senderId: 'me',
        content: 'ilk',
        contentType: StorageMessageContentType.text,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        status: StorageMessageStatus.sent,
        isOutgoing: true,
      ),
    );

    expect(await fixture.service.edit('m1', 'düzenlendi'), isTrue);
    var controls = await fixture.sentControls();
    expect(controls.whereType<MessageEditSignal>(), hasLength(1));
    expect(
      fixture.signaling.sentMessages.single.encode(),
      isNot(contains('düzenlendi')),
    );
    expect(
      (await fixture.database.messages.getById('m1'))?.content,
      'düzenlendi',
    );

    expect(await fixture.service.toggleReaction('m1', '👍'), isTrue);
    var message = await fixture.database.messages.getById('m1');
    expect(parseReactions(message!.reactions), {
      '👍': {'me'},
    });
    expect(await fixture.service.toggleReaction('m1', '👍'), isTrue);
    message = await fixture.database.messages.getById('m1');
    expect(parseReactions(message!.reactions), isEmpty);

    await fixture.service.setStarred('m1', true);
    expect((await fixture.database.messages.getById('m1'))?.isStarred, isTrue);
    expect(await fixture.service.setPinned('m1', true), isTrue);
    expect((await fixture.database.messages.getById('m1'))?.isPinned, isTrue);

    expect(await fixture.service.deleteForEveryone('m1'), isTrue);
    message = await fixture.database.messages.getById('m1');
    expect(message!.contentType, StorageMessageContentType.deleted);
    controls = await fixture.sentControls();
    expect(
      controls.whereType<MessageDeleteSignal>().where(
        (signal) =>
            signal is! MessageEditSignal &&
            signal is! MessageReactionSignal &&
            signal is! MessagePinSignal,
      ),
      hasLength(1),
    );
  });

  test('group pin rejects non-admin without changing local state', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.close);
    await fixture.database.conversations.insert(
      const ConversationEntity(
        id: 'group',
        peerId: 'group',
        peerName: 'Group',
        peerPhone: '',
        isGroup: true,
        groupMembers: 'me,peer',
        groupAdmins: 'peer',
      ),
    );
    await fixture.database.messages.insert(
      MessageEntity(
        id: 'g1',
        conversationId: 'group',
        senderId: 'peer',
        content: 'group message',
        contentType: StorageMessageContentType.text,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        status: StorageMessageStatus.delivered,
        isOutgoing: false,
      ),
    );

    expect(await fixture.service.setPinned('g1', true), isFalse);
    expect((await fixture.database.messages.getById('g1'))?.isPinned, isFalse);
    expect(fixture.signaling.sentMessages, isEmpty);
  });
}

class _Fixture {
  _Fixture(
    this.directory,
    this.database,
    this.crypto,
    this.signaling,
    this.service,
  );

  final Directory directory;
  final SecureChatDatabase database;
  final LocalAeadCryptoService crypto;
  final InMemorySignalingService signaling;
  final MessageInteractionService service;

  static Future<_Fixture> open() async {
    final directory = await Directory.systemTemp.createTemp('interactions_');
    final crypto = LocalAeadCryptoService(
      SecretKey(List<int>.generate(32, (index) => index + 1)),
    );
    final database = await SecureChatDatabase.open(
      file: File('${directory.path}/db.securejson'),
      crypto: crypto,
    );
    final signaling = InMemorySignalingService();
    await signaling.connect(
      userId: 'me',
      url: 'wss://test.invalid',
      accessToken: 'token',
    );
    final service = MessageInteractionService(
      database: database,
      signaling: signaling,
      session: SessionStore(userId: 'me', accessToken: 'token'),
      crypto: crypto,
    );
    return _Fixture(directory, database, crypto, signaling, service);
  }

  Future<List<SignalMessage>> sentControls() => Future.wait(
    signaling.sentMessages.whereType<EncryptedSignalMessage>().map(
      (wire) => decryptTestPrivateChatControl(crypto: crypto, wire: wire),
    ),
  );

  Future<void> close() async {
    await database.close();
    await directory.delete(recursive: true);
  }
}
