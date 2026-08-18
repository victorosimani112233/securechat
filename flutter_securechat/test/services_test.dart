import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart'
    as storage;

void main() {
  test(
    'local AEAD crypto round trips direct, group, and storage envelopes',
    () async {
      final crypto = LocalAeadCryptoService(
        SecretKey(List<int>.generate(32, (index) => index + 7)),
      );

      final direct = await crypto.encryptDirect(
        recipientId: 'peer-ayse',
        plaintext: 'merhaba',
      );
      expect(
        await crypto.decryptDirect(senderId: 'peer-ayse', envelope: direct),
        'merhaba',
      );

      final group = await crypto.encryptGroup(
        senderId: 'me',
        groupId: 'group-ops',
        plaintext: 'ekip',
      );
      expect(
        await crypto.decryptGroup(
          senderId: 'me',
          groupId: 'group-ops',
          envelope: group,
        ),
        'ekip',
      );

      final storage = await crypto.encryptStorageJson('{"ok":true}');
      expect(await crypto.decryptStorageJson(storage), '{"ok":true}');
    },
  );

  test(
    'signaling codec covers media, prekey, server and group call messages',
    () {
      final now = DateTime.fromMillisecondsSinceEpoch(1234);
      final messages = <SignalMessage>[
        PreKeyBundleSignal(
          senderId: 'me',
          recipientId: 'peer',
          timestamp: now,
          bundle: 'bundle-json',
        ),
        AudioDataSignal(
          senderId: 'me',
          recipientId: 'peer',
          timestamp: now,
          data: 'base64pcm',
        ),
        VideoDataSignal(
          senderId: 'me',
          recipientId: 'peer',
          timestamp: now,
          data: 'base64jpg',
          width: 320,
          height: 240,
        ),
        AdminEncryptedLogSignal(
          senderId: 'me',
          timestamp: now,
          groupId: 'group',
          eventType: 'PRIVATE_EVENT',
          adminPayloads: {'admin': 'cipher'},
        ),
        SfuRoomCreatedSignal(
          timestamp: now,
          groupId: 'group',
          roomId: 42,
          janusWsUrl: 'wss://janus',
        ),
        GroupCallInviteSignal(
          senderId: 'me',
          recipientId: 'peer',
          timestamp: now,
          groupId: 'group',
          callType: 'VIDEO',
          callId: 'call-1',
          participants: ['me', 'peer'],
        ),
        GroupCallStatusResponseSignal(
          recipientId: 'me',
          timestamp: now,
          groupId: 'group',
          isActive: true,
          callId: 'call-1',
          coordinatorId: 'me',
          callType: 'VIDEO',
          participants: ['me', 'peer'],
          mode: 'SFU',
          sfuRoomId: 42,
          janusWsUrl: 'wss://janus',
        ),
      ];

      for (final message in messages) {
        final decoded = SignalMessage.decode(message.encode());
        expect(decoded.runtimeType, message.runtimeType);
        expect(decoded.toJson(), message.toJson());
      }
    },
  );

  test('secure storage database covers DAO-style module contracts', () async {
    final dir = await Directory.systemTemp.createTemp('securechat_db_test_');
    addTearDown(() => dir.delete(recursive: true));
    final crypto = LocalAeadCryptoService(
      SecretKey(List<int>.generate(32, (index) => index + 21)),
    );
    final file = File('${dir.path}/securechat_storage.securejson');
    final db = await SecureChatDatabase.open(file: file, crypto: crypto);
    addTearDown(db.close);

    await db.conversations.insert(
      const storage.ConversationEntity(
        id: 'peer-1',
        peerId: 'peer-1',
        peerName: 'Peer One',
        peerPhone: '+1',
      ),
    );
    await db.messages.insert(
      const storage.MessageEntity(
        id: 'm1',
        conversationId: 'peer-1',
        senderId: 'me',
        content: 'secret text',
        contentType: storage.StorageMessageContentType.text,
        timestamp: 100,
        status: storage.StorageMessageStatus.sending,
        isOutgoing: true,
      ),
    );
    await db.messages.updateStatus('m1', storage.StorageMessageStatus.sent);
    await db.contacts.insert(
      const storage.ContactEntity(
        id: 'c1',
        phoneNumber: '+1',
        phoneHash: 'hash-1',
        displayName: 'Peer One',
        isRegistered: true,
      ),
    );
    await db.scheduledMessages.insert(
      storage.ScheduledMessageEntity(
        id: 's1',
        messageContent: 'later',
        repeatType: 'ONCE',
        hour: 10,
        minute: 0,
        recipientIds: 'peer-1',
        recipientNames: 'Peer One',
        nextTriggerTime: 50,
      ),
    );
    await db.preKeys.insert(const storage.PreKeyEntity(id: 1, record: [1, 2]));
    await db.sessions.insert(
      const storage.SessionEntity(id: 'peer-1:1', record: [3, 4]),
    );
    await db.senderKeys.put(
      const storage.SenderKeyEntity(
        groupId: 'group',
        senderId: 'me',
        deviceId: 1,
        record: [5, 6],
        updatedAt: 100,
      ),
    );

    expect(
      (await db.messages.getById('m1'))?.status,
      storage.StorageMessageStatus.sent,
    );
    expect(await db.contacts.getRegisteredCount(), 1);
    expect(await db.scheduledMessages.getDueMessages(100), hasLength(1));
    expect(await db.preKeys.exists(1), isTrue);
    expect(await db.sessions.exists('peer-1:1'), isTrue);
    expect(await db.senderKeys.exists('group', 'me', 1), isTrue);
    expect(await file.readAsString(), isNot(contains('secret text')));

    final reopened = await SecureChatDatabase.open(file: file, crypto: crypto);
    addTearDown(reopened.close);
    expect((await reopened.messages.getById('m1'))?.content, 'secret text');
    expect(
      (await reopened.conversations.getById('peer-1'))?.peerName,
      'Peer One',
    );
  });

  test('session writes serialize and close flushes the final state', () async {
    final dir = await Directory.systemTemp.createTemp(
      'securechat_session_queue_test_',
    );
    addTearDown(() => dir.delete(recursive: true));
    final crypto = LocalAeadCryptoService(
      SecretKey(List<int>.generate(32, (index) => index + 41)),
    );
    final file = File('${dir.path}/session.securejson');
    final session = await PersistentSessionStore.open(
      file: file,
      crypto: crypto,
    );

    session.login(
      userId: 'first',
      displayName: 'First',
      phoneNumber: '+1',
      accessToken: 'access-1',
      refreshToken: 'refresh-1',
    );
    session.login(
      userId: 'second',
      displayName: 'Second',
      phoneNumber: '+2',
      accessToken: 'access-2',
      refreshToken: 'refresh-2',
    );
    session.clear();
    await session.close();
    await session.close();

    final reopened = await PersistentSessionStore.open(
      file: file,
      crypto: crypto,
    );
    expect(reopened.isLoggedIn, isFalse);
    expect(reopened.userId, isNull);
    expect(reopened.accessToken, isNull);
    await reopened.close();
    expect(session.persist, throwsStateError);
  });
}
