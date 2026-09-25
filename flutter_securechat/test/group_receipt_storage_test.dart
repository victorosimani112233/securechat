import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final operation in ['startup', 'restore', 'import']) {
    for (final status in [
      StorageMessageStatus.delivered,
      StorageMessageStatus.read,
    ]) {
      test(
        '$operation normalizes unsupported legacy group $status without losing evidence',
        () async {
          final f = await _Fixture.open();
          addTearDown(f.close);
          for (final (id, group, frozen, outgoing) in [
            ('legacy-group', true, false, true),
            ('legacy-direct', false, false, true),
            ('snapshot-group', true, true, true),
            ('incoming-group', true, false, false),
          ]) {
            await f.database.conversations.insert(
              ConversationEntity(
                id: id,
                peerId: group ? id : 'alice',
                peerName: id,
                peerPhone: '',
                isGroup: group,
                groupMembers: group ? 'me,alice,bob' : null,
                lastMessage: 'Message',
                lastMessageTimestamp: 1000,
                lastMessageOutgoing: outgoing,
                lastMessageStatus: status.name,
              ),
            );
            await f.database.messages.insert(
              _message(
                id: id,
                conversationId: id,
                isOutgoing: outgoing,
                senderId: outgoing ? 'me' : 'alice',
                status: status,
                recipients: frozen ? ['alice', 'bob'] : null,
                deliveredTo: frozen ? ['alice', 'bob'] : ['alice'],
                readBy: frozen && status == StorageMessageStatus.read
                    ? ['alice', 'bob']
                    : ['alice'],
              ),
            );
          }
          if (operation == 'startup') {
            await f.reopen();
          } else {
            final backup = await f.database.exportPortableJson();
            if (operation == 'restore') {
              await f.database.replaceFromPortableJson(backup);
            } else {
              await f.database.clearAll();
              await f.database.importLegacyRoomPortableJson(backup);
            }
          }
          for (final id in [
            'legacy-group',
            'legacy-direct',
            'snapshot-group',
            'incoming-group',
          ]) {
            final conversation = (await f.database.conversations.getById(id))!;
            expect(
              conversation.lastMessageStatus,
              id == 'legacy-group'
                  ? StorageMessageStatus.sent.name
                  : status.name,
            );
            final message = (await f.database.messages.getById(id))!;
            expect(
              message.status,
              id == 'legacy-group' ? StorageMessageStatus.sent : status,
            );
            expect(
              message.deliveredTo,
              id == 'snapshot-group' ? ['alice', 'bob'] : ['alice'],
            );
            expect(
              message.readBy,
              id == 'snapshot-group' && status == StorageMessageStatus.read
                  ? ['alice', 'bob']
                  : ['alice'],
            );
            expect(
              message.receiptRecipients,
              id == 'snapshot-group' ? ['alice', 'bob'] : null,
            );
          }
        },
      );
    }
  }

  for (final operation in ['startup', 'restore']) {
    test(
      '$operation normalization prevents expiry from reviving legacy group read ticks',
      () async {
        final f = await _Fixture.open();
        addTearDown(f.close);
        await f.database.messages.insert(
          _message(
            recipients: null,
            status: StorageMessageStatus.read,
            deliveredTo: ['alice'],
            readBy: ['alice'],
          ),
        );
        await f.database.messages.insert(
          _message(id: 'newer', timestamp: 2000).copyWith(expiresAt: 2500),
        );
        await f.database.conversations.updateLastMessageById(
          'group',
          'Newer message',
          2000,
          outgoing: true,
          status: StorageMessageStatus.sent,
        );
        if (operation == 'startup') {
          await f.reopen();
        } else {
          await f.database.replaceFromPortableJson(
            await f.database.exportPortableJson(),
          );
        }
        final older = (await f.database.messages.getById('message'))!;
        expect(older.status, StorageMessageStatus.sent);
        expect(older.receiptRecipients, isNull);
        expect(older.deliveredTo, ['alice']);
        expect(older.readBy, ['alice']);
        expect(await f.database.messages.deleteExpiredMessages(3000), 1);
        expect(
          (await f.database.messages.getLatestMessage('group'))!.id,
          'message',
        );
        final conversation = (await f.database.conversations.getById('group'))!;
        expect(conversation.lastMessageTimestamp, 1000);
        expect(conversation.lastMessageStatus, StorageMessageStatus.sent.name);
        await f.reopen();
        expect(
          (await f.database.messages.getById('message'))!.status,
          StorageMessageStatus.sent,
        );
        expect(
          (await f.database.conversations.getById('group'))!.lastMessageStatus,
          StorageMessageStatus.sent.name,
        );
      },
    );
  }

  test(
    'receipt fields preserve null, empty and populated snapshots in JSON and copyWith',
    () {
      for (final recipients in <List<String>?>[
        null,
        [],
        ['alice', 'bob'],
      ]) {
        final original = _message(
          recipients: recipients,
          deliveredTo: ['alice', 'bob'],
          readBy: ['alice'],
        );
        final decoded = MessageEntity.fromJson(
          Map<String, Object?>.from(
            jsonDecode(jsonEncode(original.toJson())) as Map,
          ),
        );
        expect(decoded.toJson(), original.toJson());
        final edited = decoded.copyWith(content: 'edited');
        expect(edited.receiptRecipients, recipients);
        expect(edited.deliveredTo, ['alice', 'bob']);
        expect(edited.readBy, ['alice']);
        final cleared = edited.copyWith(
          receiptRecipients: null,
          deliveredTo: [],
          readBy: [],
        );
        expect(cleared.receiptRecipients, isNull);
        expect(cleared.deliveredTo, isEmpty);
        expect(cleared.readBy, isEmpty);
        expect(cleared.copyWith(receiptRecipients: ['bob']).receiptRecipients, [
          'bob',
        ]);
      }
      final legacy = _message().toJson()
        ..remove('receiptRecipients')
        ..remove('deliveredTo')
        ..remove('readBy');
      final restored = MessageEntity.fromJson(legacy);
      expect(restored.receiptRecipients, isNull);
      expect(restored.deliveredTo, isEmpty);
      expect(restored.readBy, isEmpty);
    },
  );

  test(
    'three-member group requires every recipient, including reverse and duplicate receipts',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      await f.database.messages.insert(_message());
      expect(await f.receipt('alice', StorageMessageStatus.read), isTrue);
      await f.expectState(
        StorageMessageStatus.sent,
        delivered: ['alice'],
        read: ['alice'],
      );
      expect(await f.receipt('alice', StorageMessageStatus.delivered), isTrue);
      expect(await f.receipt('alice', StorageMessageStatus.read), isTrue);
      await f.expectState(
        StorageMessageStatus.sent,
        delivered: ['alice'],
        read: ['alice'],
      );
      expect(await f.receipt('bob', StorageMessageStatus.delivered), isTrue);
      await f.expectState(
        StorageMessageStatus.delivered,
        delivered: ['alice', 'bob'],
        read: ['alice'],
      );
      expect(await f.receipt('bob', StorageMessageStatus.read), isTrue);
      await f.expectState(
        StorageMessageStatus.read,
        delivered: ['alice', 'bob'],
        read: ['alice', 'bob'],
      );
      for (final recipient in ['alice', 'bob']) {
        expect(
          await f.receipt(recipient, StorageMessageStatus.delivered),
          isTrue,
        );
        expect(await f.receipt(recipient, StorageMessageStatus.read), isTrue);
      }
      await f.expectState(
        StorageMessageStatus.read,
        delivered: ['alice', 'bob'],
        read: ['alice', 'bob'],
      );
    },
  );

  test(
    'frozen recipients survive member removal and reject new members',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      await f.database.messages.insert(_message());
      await f.database.conversations.updateGroupMembers(
        'group',
        'me,bob,charlie',
      );
      expect(await f.receipt('charlie', StorageMessageStatus.read), isFalse);
      expect(await f.receipt('alice', StorageMessageStatus.read), isTrue);
      await f.database.conversations.updateGroupMembers('group', 'charlie');
      expect(await f.receipt('bob', StorageMessageStatus.read), isTrue);
      await f.expectState(
        StorageMessageStatus.read,
        delivered: ['alice', 'bob'],
        read: ['alice', 'bob'],
      );
      expect(
        (await f.database.messages.getById('message'))!.receiptRecipients,
        ['alice', 'bob'],
      );
    },
  );

  for (final previous in [
    StorageMessageStatus.delivered,
    StorageMessageStatus.read,
  ]) {
    test(
      'legacy group $previous remains unknown and never infers all recipients',
      () async {
        final f = await _Fixture.open();
        addTearDown(f.close);
        await f.database.messages.insert(
          _message(recipients: null, status: previous),
        );
        expect(
          (await f.database.messages.getById('message'))!.receiptRecipients,
          isNull,
        );
        expect(await f.receipt('outsider', StorageMessageStatus.read), isFalse);
        expect(await f.receipt('alice', StorageMessageStatus.read), isTrue);
        await f.expectState(
          StorageMessageStatus.sent,
          delivered: ['alice'],
          read: ['alice'],
        );
        expect(await f.receipt('bob', StorageMessageStatus.read), isTrue);
        await f.expectState(
          StorageMessageStatus.sent,
          delivered: ['alice', 'bob'],
          read: ['alice', 'bob'],
        );
        expect(
          (await f.database.messages.getById('message'))!.receiptRecipients,
          isNull,
        );
        await f.database.conversations.updateGroupMembers('group', 'me,bob');
        expect(await f.receipt('alice', StorageMessageStatus.read), isFalse);
        await f.database.conversations.updateGroupMembers('group', 'bob');
        expect(await f.receipt('bob', StorageMessageStatus.read), isFalse);
      },
    );
  }

  for (final previous in StorageMessageStatus.values) {
    test(
      'legacy direct $previous authenticates peer and preserves known receipts',
      () async {
        final f = await _Fixture.open();
        addTearDown(f.close);
        await f.database.messages.insert(
          _message(
            conversationId: 'direct',
            recipients: null,
            status: previous,
          ),
        );
        expect(await f.receipt('bob', StorageMessageStatus.read), isFalse);
        expect(
          await f.receipt('alice', StorageMessageStatus.delivered),
          isTrue,
        );
        await f.expectState(
          previous == StorageMessageStatus.read
              ? StorageMessageStatus.read
              : StorageMessageStatus.delivered,
          delivered: ['alice'],
          read: previous == StorageMessageStatus.read ? ['alice'] : [],
          conversationId: 'direct',
        );
        expect(await f.receipt('alice', StorageMessageStatus.read), isTrue);
        expect(
          await f.receipt('alice', StorageMessageStatus.delivered),
          isTrue,
        );
        await f.expectState(
          StorageMessageStatus.read,
          delivered: ['alice'],
          read: ['alice'],
          conversationId: 'direct',
        );
        expect(
          (await f.database.messages.getById('message'))!.receiptRecipients,
          isNull,
        );
      },
    );
  }

  test('frozen direct receipts promote only the expected peer', () async {
    final f = await _Fixture.open();
    addTearDown(f.close);
    await f.database.messages.insert(
      _message(conversationId: 'direct', recipients: ['alice']),
    );
    expect(await f.receipt('bob', StorageMessageStatus.read), isFalse);
    expect(await f.receipt('alice', StorageMessageStatus.read), isTrue);
    await f.expectState(
      StorageMessageStatus.read,
      delivered: ['alice'],
      read: ['alice'],
      conversationId: 'direct',
    );
  });

  for (final group in [false, true]) {
    test(
      'snapshot ignores empty and self recipients for aggregation: group $group',
      () async {
        final f = await _Fixture.open();
        addTearDown(f.close);
        final recipients = [
          '',
          ' ',
          'me',
          ' me ',
          'alice',
          'alice',
          if (group) 'bob',
        ];
        final conversationId = group ? 'group' : 'direct';
        await f.database.messages.insert(
          _message(conversationId: conversationId, recipients: recipients),
        );
        expect(await f.receipt('me', StorageMessageStatus.read), isFalse);
        expect(await f.receipt('', StorageMessageStatus.read), isFalse);
        expect(await f.receipt('alice', StorageMessageStatus.read), isTrue);
        if (group) {
          await f.expectState(
            StorageMessageStatus.sent,
            delivered: ['alice'],
            read: ['alice'],
          );
          expect(await f.receipt('bob', StorageMessageStatus.read), isTrue);
        }
        await f.expectState(
          StorageMessageStatus.read,
          delivered: ['alice', if (group) 'bob'],
          read: ['alice', if (group) 'bob'],
          conversationId: conversationId,
        );
        expect(
          (await f.database.messages.getById('message'))!.receiptRecipients,
          recipients,
        );
        await f.database.messages.insert(
          _message(conversationId: conversationId, recipients: ['', ' ', 'me']),
        );
        expect(await f.receipt('alice', StorageMessageStatus.read), isFalse);
      },
    );
  }

  test('corrupt direct snapshot cannot authorize a stranger', () async {
    final f = await _Fixture.open();
    addTearDown(f.close);
    for (final recipients in [
      ['bob'],
      ['alice', 'bob'],
    ]) {
      final original = _message(
        conversationId: 'direct',
        recipients: recipients,
      );
      await f.database.messages.insert(original);
      expect(await f.receipt('bob', StorageMessageStatus.read), isFalse);
      expect(
        (await f.database.messages.getById('message'))!.toJson(),
        original.toJson(),
      );
      expect(
        (await f.database.conversations.getById('direct'))!.lastMessageStatus,
        StorageMessageStatus.sent.name,
      );
    }
  });

  test(
    'unsupported, self, unknown and wrong-owner receipts do not mutate storage',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      final original = _message();
      await f.database.messages.insert(original);
      final conversation = (await f.database.conversations.getById(
        'group',
      ))!.toJson();
      for (final recipient in ['', 'me', 'outsider']) {
        expect(await f.receipt(recipient, StorageMessageStatus.read), isFalse);
      }
      for (final status in [
        StorageMessageStatus.sending,
        StorageMessageStatus.sent,
        StorageMessageStatus.failed,
      ]) {
        expect(await f.receipt('alice', status), isFalse);
      }
      for (final local in ['', 'someone-else']) {
        expect(
          await f.database.messages.recordDeliveryReceipt(
            'message',
            recipientId: 'alice',
            status: StorageMessageStatus.read,
            localUserId: local,
          ),
          isFalse,
        );
      }
      expect(
        await f.receipt(
          'alice',
          StorageMessageStatus.read,
          messageId: 'missing',
        ),
        isFalse,
      );
      expect(
        (await f.database.messages.getById('message'))!.toJson(),
        original.toJson(),
      );
      expect(
        (await f.database.conversations.getById('group'))!.toJson(),
        conversation,
      );
      for (final invalid in [
        _message(isOutgoing: false),
        _message(senderId: 'someone-else'),
        _message(conversationId: 'missing-conversation'),
        _message(recipients: []),
      ]) {
        await f.database.messages.insert(invalid);
        expect(await f.receipt('alice', StorageMessageStatus.read), isFalse);
        expect(
          (await f.database.messages.getById('message'))!.toJson(),
          invalid.toJson(),
        );
      }
    },
  );

  test(
    'older message receipt leaves the latest conversation status untouched',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      await f.database.messages.insert(_message(timestamp: 999));
      await f.receipt('alice', StorageMessageStatus.read);
      await f.receipt('bob', StorageMessageStatus.read);
      expect(
        (await f.database.messages.getById('message'))!.status,
        StorageMessageStatus.read,
      );
      expect(
        (await f.database.conversations.getById('group'))!.lastMessageStatus,
        StorageMessageStatus.sent.name,
      );
    },
  );

  test(
    'generic insertion and reopening never fabricate a legacy snapshot',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      await f.database.messages.insert(_message(recipients: null));
      await f.reopen();
      final legacy = (await f.database.messages.getById('message'))!;
      expect(legacy.receiptRecipients, isNull);
      expect(legacy.deliveredTo, isEmpty);
      expect(legacy.readBy, isEmpty);
      await f.database.messages.update(legacy.copyWith(isStarred: true));
      expect(
        (await f.database.messages.getById('message'))!.receiptRecipients,
        isNull,
      );
    },
  );

  test(
    'concurrent receipts from separate database handles merge and persist',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      await f.database.messages.insert(_message());
      final other = await SecureChatDatabase.open(
        file: f.file,
        crypto: f.crypto,
      );
      try {
        expect(
          await Future.wait([
            f.receipt('alice', StorageMessageStatus.read),
            other.messages.recordDeliveryReceipt(
              'message',
              recipientId: 'bob',
              status: StorageMessageStatus.delivered,
              localUserId: 'me',
            ),
          ]),
          [true, true],
        );
        await f.expectState(
          StorageMessageStatus.delivered,
          delivered: ['alice', 'bob'],
          read: ['alice'],
        );
        expect(
          await Future.wait([
            f.receipt('alice', StorageMessageStatus.delivered),
            other.messages.recordDeliveryReceipt(
              'message',
              recipientId: 'bob',
              status: StorageMessageStatus.read,
              localUserId: 'me',
            ),
          ]),
          [true, true],
        );
      } finally {
        await other.close();
      }
      await f.reopen();
      await f.expectState(
        StorageMessageStatus.read,
        delivered: ['alice', 'bob'],
        read: ['alice', 'bob'],
      );
      expect(
        (await f.database.messages.getById('message'))!.receiptRecipients,
        ['alice', 'bob'],
      );
      expect(
        (await f.database.conversations.getById('group'))!.isMuted,
        isTrue,
      );
    },
  );
}

MessageEntity _message({
  String id = 'message',
  String conversationId = 'group',
  String senderId = 'me',
  bool isOutgoing = true,
  int timestamp = 1000,
  StorageMessageStatus status = StorageMessageStatus.sent,
  List<String>? recipients = const ['alice', 'bob'],
  List<String> deliveredTo = const [],
  List<String> readBy = const [],
}) => MessageEntity(
  id: id,
  conversationId: conversationId,
  senderId: senderId,
  content: 'Message',
  contentType: StorageMessageContentType.text,
  timestamp: timestamp,
  status: status,
  isOutgoing: isOutgoing,
  receiptRecipients: recipients,
  deliveredTo: deliveredTo,
  readBy: readBy,
);

class _Fixture {
  _Fixture(this.directory, this.file, this.crypto, this.database);
  final Directory directory;
  final File file;
  final LocalAeadCryptoService crypto;
  SecureChatDatabase database;

  static Future<_Fixture> open() async {
    final directory = await Directory.systemTemp.createTemp('group-receipts-');
    final file = File('${directory.path}/storage.securejson');
    final crypto = LocalAeadCryptoService(
      SecretKey(List<int>.generate(32, (index) => index + 1)),
    );
    final database = await SecureChatDatabase.open(file: file, crypto: crypto);
    for (final group in [false, true]) {
      await database.conversations.insert(
        ConversationEntity(
          id: group ? 'group' : 'direct',
          peerId: group ? 'group-peer' : 'alice',
          peerName: group ? 'Group' : 'Alice',
          peerPhone: '',
          isGroup: group,
          groupMembers: group ? 'me, alice, bob' : null,
          isMuted: true,
          lastMessage: 'Message',
          lastMessageTimestamp: 1000,
          lastMessageOutgoing: true,
          lastMessageStatus: StorageMessageStatus.sent.name,
        ),
      );
    }
    return _Fixture(directory, file, crypto, database);
  }

  Future<bool> receipt(
    String recipientId,
    StorageMessageStatus status, {
    String messageId = 'message',
  }) => database.messages.recordDeliveryReceipt(
    messageId,
    recipientId: recipientId,
    status: status,
    localUserId: 'me',
  );

  Future<void> expectState(
    StorageMessageStatus status, {
    required List<String> delivered,
    required List<String> read,
    String conversationId = 'group',
  }) async {
    final message = (await database.messages.getById('message'))!;
    expect(message.status, status);
    expect(message.deliveredTo, delivered);
    expect(message.readBy, read);
    expect(
      (await database.conversations.getById(conversationId))!.lastMessageStatus,
      status.name,
    );
  }

  Future<void> reopen() async {
    await database.close();
    database = await SecureChatDatabase.open(file: file, crypto: crypto);
  }

  Future<void> close() async {
    await database.close();
    await directory.delete(recursive: true);
  }
}
