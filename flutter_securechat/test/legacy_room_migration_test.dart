import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/storage/legacy_room_importer.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Room v22 fixture imports every table and binary Signal state',
    () async {
      final fixture = await _openDatabase();
      addTearDown(fixture.close);
      final gateway = _FakeGateway(_exportFixture());

      final result = await LegacyRoomImporter(
        database: fixture.database,
        gateway: gateway,
      ).run();

      expect(result, LegacyRoomImportResult.imported);
      expect(gateway.archiveCalls, 1);
      expect(
        await fixture.database.conversations.getById('conversation-1'),
        isNotNull,
      );
      expect(await fixture.database.messages.getById('message-1'), isNotNull);
      expect(await fixture.database.contacts.getAllOnce(), hasLength(1));
      expect(
        await fixture.database.callLogs.getByPeerId('alice').first,
        hasLength(1),
      );
      expect(
        await fixture.database.scheduledMessages.getById('scheduled-1'),
        isNotNull,
      );
      expect(await fixture.database.exportLogs.countForGroup('group-1'), 1);
      expect(await fixture.database.pendingTimerUpdates.getAll(), hasLength(1));
      expect((await fixture.database.identities.get('alice'))!.identityKey, [
        1,
        2,
        3,
      ]);
      expect((await fixture.database.preKeys.get(7))!.record, [4, 5, 6]);
      expect((await fixture.database.signedPreKeys.get(8))!.record, [7, 8, 9]);
      expect((await fixture.database.sessions.get('alice:1'))!.record, [
        10,
        11,
      ]);
      expect(
        (await fixture.database.senderKeys.get('group-1', 'alice', 1))!.record,
        [12, 13],
      );
      expect(
        await fixture.database.cryptoState.get('local_registration_id'),
        '1234',
      );
      expect(
        base64Decode(
          (await fixture.database.cryptoState.get(
            'local_identity_key_pair_v1',
          ))!,
        ),
        [21, 22, 23],
      );
      expect(await fixture.database.isLegacyRoomImportComplete(), isTrue);

      final encrypted = await fixture.file.readAsString();
      expect(encrypted, isNot(contains('legacy plaintext message')));
      expect(encrypted, isNot(contains(base64Encode([21, 22, 23]))));
    },
  );

  test(
    'committed import is idempotent and only retries native archive',
    () async {
      final fixture = await _openDatabase();
      addTearDown(fixture.close);
      final gateway = _FakeGateway(_exportFixture());
      final importer = LegacyRoomImporter(
        database: fixture.database,
        gateway: gateway,
      );

      expect(await importer.run(), LegacyRoomImportResult.imported);
      gateway.exportValue = null;
      expect(await importer.run(), LegacyRoomImportResult.alreadyCompleted);
      expect(gateway.exportCalls, 1);
      expect(gateway.archiveCalls, 2);
      expect(await fixture.database.messages.getById('message-1'), isNotNull);
    },
  );

  test(
    'malformed export leaves active database unchanged and is not archived',
    () async {
      final fixture = await _openDatabase();
      addTearDown(fixture.close);
      await fixture.database.conversations.insert(
        const ConversationEntity(
          id: 'existing',
          peerId: 'existing-peer',
          peerName: 'Existing',
          peerPhone: '',
        ),
      );
      final before = await fixture.database.exportPortableJson();
      final gateway = _FakeGateway(
        const LegacyRoomExport(json: '{"sourceSchema":22}', sourceSchema: 22),
      );

      await expectLater(
        LegacyRoomImporter(database: fixture.database, gateway: gateway).run(),
        throwsFormatException,
      );

      expect(await fixture.database.exportPortableJson(), before);
      expect(gateway.archiveCalls, 0);
    },
  );

  test(
    'valid legacy data cannot overwrite an active Flutter database',
    () async {
      final fixture = await _openDatabase();
      addTearDown(fixture.close);
      await fixture.database.conversations.insert(
        const ConversationEntity(
          id: 'existing',
          peerId: 'existing-peer',
          peerName: 'Existing',
          peerPhone: '',
        ),
      );
      final gateway = _FakeGateway(_exportFixture());

      await expectLater(
        LegacyRoomImporter(database: fixture.database, gateway: gateway).run(),
        throwsStateError,
      );

      expect(
        await fixture.database.conversations.getById('existing'),
        isNotNull,
      );
      expect(
        await fixture.database.conversations.getById('conversation-1'),
        isNull,
      );
      expect(gateway.archiveCalls, 0);
    },
  );

  test('new install without Android Room source is a no-op', () async {
    final fixture = await _openDatabase();
    addTearDown(fixture.close);
    final gateway = _FakeGateway(null);

    expect(
      await LegacyRoomImporter(
        database: fixture.database,
        gateway: gateway,
      ).run(),
      LegacyRoomImportResult.absent,
    );
    expect(gateway.archiveCalls, 0);
    expect(await fixture.database.conversations.getAllImmediate(), isEmpty);
  });

  test('v1 Room rows receive every later schema default without data loss', () {
    final raw = jsonEncode({
      'sourceSchema': 1,
      'tables': {
        'conversations': [
          {
            'id': 'v1-chat',
            'peer_id': 'peer',
            'peer_name': 'Peer',
            'peer_phone': '',
            'last_message': null,
            'last_message_timestamp': null,
            'unread_count': 0,
            'is_muted': 0,
            'is_pinned': 0,
          },
        ],
        'messages': [
          {
            'id': 'v1-message',
            'conversation_id': 'v1-chat',
            'sender_id': 'peer',
            'content': '',
            'content_type': 'TEXT',
            'timestamp': 1,
            'status': 'SENT',
            'reply_to_id': null,
            'is_outgoing': 0,
          },
        ],
      },
      'rowCounts': {'conversations': 1, 'messages': 1},
    });

    final converted =
        jsonDecode(LegacyRoomSnapshotConverter.convert(raw, expectedSchema: 1))
            as Map<String, dynamic>;
    final conversation = (converted['conversations'] as List).single as Map;
    final message = (converted['messages'] as List).single as Map;
    expect(conversation['isGroup'], isFalse);
    expect(conversation['isArchived'], isFalse);
    expect(conversation['isExportEnabled'], isFalse);
    expect(conversation['manuallyUnread'], isFalse);
    expect(conversation['isReadOnly'], isFalse);
    expect(message['isStarred'], isFalse);
    expect(message['isViewOnce'], isFalse);
    expect(message['isPinned'], isFalse);
    expect(message['content'], '');
  });
}

LegacyRoomExport _exportFixture() {
  Map<String, Object?> blob(List<int> bytes) => {'base64': base64Encode(bytes)};
  final tables = <String, Object?>{
    'conversations': [
      {
        'id': 'conversation-1',
        'peer_id': 'alice',
        'peer_name': 'Alice',
        'peer_phone': '+90500',
        'last_message': 'legacy plaintext message',
        'last_message_timestamp': 100,
        'unread_count': 2,
        'is_muted': 0,
        'is_pinned': 1,
        'is_group': 0,
        'group_members': null,
        'contact_note': 'note',
        'custom_notification_uri': null,
        'is_archived': 0,
        'disappearing_duration': 0,
        'group_admins': null,
        'is_favorite': 1,
        'is_locked': 0,
        'is_export_enabled': 0,
        'manually_unread': 1,
        'is_read_only': 0,
      },
    ],
    'messages': [
      {
        'id': 'message-1',
        'conversation_id': 'conversation-1',
        'sender_id': 'alice',
        'content': 'legacy plaintext message',
        'content_type': 'TEXT',
        'timestamp': 100,
        'status': 'READ',
        'reply_to_id': null,
        'is_outgoing': 0,
        'is_starred': 1,
        'expires_at': null,
        'edited_at': null,
        'edit_history': null,
        'reactions': null,
        'caption': null,
        'is_view_once': 0,
        'is_viewed': 0,
        'is_pinned': 1,
        'pinned_at': 101,
      },
    ],
    'contacts': [
      {
        'id': 'contact-1',
        'phone_number': '+90500',
        'phone_hash': 'hash',
        'display_name': 'Alice',
        'is_registered': 1,
        'avatar_uri': null,
        'last_seen': 99,
      },
    ],
    'call_log': [
      {
        'id': 'call-1',
        'peer_id': 'alice',
        'peer_name': 'Alice',
        'call_type': 'VOICE',
        'direction': 'INCOMING',
        'status': 'ANSWERED',
        'timestamp': 90,
        'duration': 500,
      },
    ],
    'scheduled_messages': [
      {
        'id': 'scheduled-1',
        'message_content': 'later',
        'repeat_type': 'ONCE',
        'repeat_days': null,
        'hour': 10,
        'minute': 30,
        'recipient_ids': 'alice',
        'recipient_names': 'Alice',
        'is_enabled': 1,
        'next_trigger_time': 1000,
        'created_at': 50,
      },
    ],
    'export_log': [
      {
        'id': 'export-1',
        'group_id': 'group-1',
        'actor_user_id': 'me',
        'actor_display_name': 'Me',
        'event_type': 'EXPORT',
        'timestamp': 80,
        'message_count': 1,
        'first_msg_ts': 10,
        'last_msg_ts': 20,
      },
    ],
    'pending_timer_updates': [
      {
        'id': 'timer-1',
        'conversation_id': 'conversation-1',
        'target_user_id': 'alice',
        'duration': 60000,
        'created_at': 70,
      },
    ],
    'identities': [
      {
        'addressName': 'alice',
        'identity_key': blob([1, 2, 3]),
        'trust_level': 'TRUSTED_VERIFIED',
      },
    ],
    'prekeys': [
      {
        'id': 7,
        'record': blob([4, 5, 6]),
      },
    ],
    'signed_prekeys': [
      {
        'id': 8,
        'record': blob([7, 8, 9]),
        'created_at': 60,
      },
    ],
    'sessions': [
      {
        'id': 'alice:1',
        'record': blob([10, 11]),
      },
    ],
    'sender_keys': [
      {
        'group_id': 'group-1',
        'sender_id': 'alice',
        'device_id': 1,
        'record': blob([12, 13]),
        'updated_at': 65,
      },
    ],
  };
  final root = {
    'sourceSchema': 22,
    'tables': tables,
    'rowCounts': tables.map(
      (key, value) => MapEntry(key, (value as List).length),
    ),
    'cryptoState': {
      'local_registration_id': '1234',
      'local_identity_key_pair_v1': base64Encode([21, 22, 23]),
    },
  };
  return LegacyRoomExport(json: jsonEncode(root), sourceSchema: 22);
}

Future<_DatabaseFixture> _openDatabase() async {
  final directory = await Directory.systemTemp.createTemp('legacy_room_test_');
  final file = File('${directory.path}/storage.securejson');
  final database = await SecureChatDatabase.open(
    file: file,
    crypto: LocalAeadCryptoService(
      SecretKey(List<int>.generate(32, (index) => index + 1)),
    ),
  );
  return _DatabaseFixture(directory, file, database);
}

class _DatabaseFixture {
  const _DatabaseFixture(this.directory, this.file, this.database);
  final Directory directory;
  final File file;
  final SecureChatDatabase database;

  Future<void> close() async {
    await database.close();
    await directory.delete(recursive: true);
  }
}

class _FakeGateway implements LegacyRoomGateway {
  _FakeGateway(this.exportValue);
  LegacyRoomExport? exportValue;
  int exportCalls = 0;
  int archiveCalls = 0;

  @override
  Future<LegacyRoomExport?> exportIfPresent() async {
    exportCalls += 1;
    return exportValue;
  }

  @override
  Future<void> archiveAfterImport() async {
    archiveCalls += 1;
  }
}
