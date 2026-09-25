import 'dart:async';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/chat/message_interaction_service.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/incoming/incoming_message_handler.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/private_chat_control_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'another message cannot replace a pin until explicitly unpinned',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      expect(await f.service.setPinned('m1', true), isTrue);
      expect(await f.service.setPinned('m2', true), isFalse);
      expect(await f.pinned(), ['m1']);
      expect(f.signaling.sentMessages, hasLength(1));

      expect(await f.service.setPinned('m1', false), isTrue);
      expect((await f.database.messages.getById('m1'))!.pinnedAt, isNull);
      expect(await f.service.setPinned('m2', true), isTrue);
      expect(await f.pinned(), ['m2']);

      await f.database.conversations.insert(
        const ConversationEntity(
          id: 'other',
          peerId: 'other',
          peerName: 'Other',
          peerPhone: '',
        ),
      );
      await f.database.messages.insert(_message('other-message', 'other'));
      expect(await f.service.setPinned('other-message', true), isTrue);
      expect(await f.pinned(), ['m2']);
      expect(await f.pinned('other'), ['other-message']);
    },
  );

  test('concurrent local pins send only the winning message', () async {
    final f = await _Fixture.open();
    addTearDown(f.close);
    final results = await Future.wait([
      f.service.setPinned('m1', true),
      f.service.setPinned('m2', true),
    ]);
    expect(results.where((accepted) => accepted), hasLength(1));
    expect(await f.pinned(), hasLength(1));
    expect(f.signaling.sentMessages, hasLength(1));
  });

  test('two SQLite runtimes cannot claim different pins', () async {
    final f = await _Fixture.open();
    addTearDown(f.close);
    final second = await SecureChatDatabase.open(
      file: f.file,
      crypto: f.crypto,
    );
    try {
      final results = await Future.wait([
        f.service.setPinned('m1', true),
        f.serviceFor(second).setPinned('m2', true),
      ]);
      expect(results.where((accepted) => accepted), hasLength(1));
      expect(await f.pinned(), hasLength(1));
      expect(
        await second.messages.getPinnedMessages('peer').first,
        hasLength(1),
      );
      expect(f.signaling.sentMessages, hasLength(1));
    } finally {
      await second.close();
    }
  });

  test('incoming pin rejects replacement and accepts explicit unpin', () async {
    final f = await _Fixture.open();
    addTearDown(f.close);
    await f.receive('m1', true);
    await f.receive('m2', true);
    expect(await f.pinned(), ['m1']);
    expect(await f.service.setPinned('m2', true), isFalse);
    expect(f.signaling.sentMessages, isEmpty);
    await f.receive('m2', false);
    expect(await f.pinned(), ['m1']);
    await f.receive('m1', false);
    await f.receive('m2', true);
    expect(await f.pinned(), ['m2']);
  });

  test(
    'incoming pin cannot win a slot already claimed by an in-flight send',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      final sending = Completer<void>();
      final release = Completer<void>();
      f.signaling.beforeSend = (_) async {
        if (!sending.isCompleted) sending.complete();
        await release.future;
      };
      final operation = f.service.setPinned('m1', true);
      try {
        await sending.future;
        await f.receive('m2', true);
        expect(await f.pinned(), ['m1']);
      } finally {
        release.complete();
      }
      expect(await operation, isTrue);
      expect(await f.pinned(), ['m1']);
    },
  );

  test(
    'local pin and unpin fanout stay ordered within a conversation',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      final sending = Completer<void>();
      final release = Completer<void>();
      f.signaling.beforeSend = (_) async {
        if (!sending.isCompleted) {
          sending.complete();
          await release.future;
        }
      };
      final pin = f.service.setPinned('m1', true);
      await sending.future;
      final unpin = f.service.setPinned('m1', false);
      release.complete();
      expect(await pin, isTrue);
      expect(await unpin, isTrue);
      expect(await f.pinned(), isEmpty);
      final controls = await f.sentPins();
      expect(controls.map((pin) => pin.isPinned), [true, false]);
    },
  );

  test('group pin and unpin retain admin and membership checks', () async {
    final f = await _Fixture.open(group: true);
    addTearDown(f.close);
    await f.database.conversations.updateGroupAdmins('group', 'peer');
    expect(await f.service.setPinned('m1', true), isFalse);
    await f.receive('m1', true, sender: 'other');
    await f.receive('m1', true, sender: 'outsider');
    await f.receive('m1', true, groupId: 'wrong-group');
    expect(await f.pinned(), isEmpty);
    await f.receive('m1', true);
    expect(await f.pinned(), ['m1']);
    expect(await f.service.setPinned('m1', false), isFalse);
    await f.receive('m1', false, sender: 'other');
    expect(await f.pinned(), ['m1']);
    await f.receive('m1', false);
    await f.database.conversations.updateGroupAdmins('group', 'me,peer');
    expect(await f.service.setPinned('m2', true), isTrue);
    expect(await f.service.setPinned('m2', false), isTrue);
    await f.database.conversations.updateGroupMembers('group', 'peer,other');
    expect(await f.service.setPinned('m1', true), isFalse);
  });

  for (final deleted in [false, true]) {
    test(
      '${deleted ? 'deleted' : 'expired'} pins neither display nor block a new pin',
      () async {
        final f = await _Fixture.open();
        addTearDown(f.close);
        await f.database.messages.insert(
          _message(
            'm1',
            'peer',
            pinned: true,
            deleted: deleted,
            expiresAt: deleted
                ? null
                : DateTime.now().millisecondsSinceEpoch - 1,
          ),
        );
        expect(await f.pinned(), isEmpty);
        expect(
          await f.database.messages.observeLatestPinned('peer').first,
          isNull,
        );
        expect(await f.service.setPinned('m1', true), isFalse);
        await f.receive('m1', true);
        expect(await f.pinned(), isEmpty);
        expect(f.signaling.sentMessages, isEmpty);
        expect(await f.service.setPinned('m2', true), isTrue);
        expect(await f.pinned(), ['m2']);
        expect(
          (await f.database.messages.observeLatestPinned('peer').first)!.id,
          'm2',
        );
      },
    );
  }

  test('all failed sends roll back a new claim, not an existing pin', () async {
    final f = await _Fixture.open();
    addTearDown(f.close);
    f.signaling.failRecipients.add('peer');
    expect(await f.service.setPinned('m1', true), isFalse);
    expect(await f.pinned(), isEmpty);
    f.signaling.failRecipients.clear();
    expect(await f.service.setPinned('m1', true), isTrue);
    f.signaling.failRecipients.add('peer');
    expect(await f.service.setPinned('m1', true), isFalse);
    expect(await f.service.setPinned('m1', false), isFalse);
    expect(await f.pinned(), ['m1']);
    expect(await f.service.setPinned('m2', true), isFalse);
  });

  test('partial group fanout retains the pin and retry can converge', () async {
    final f = await _Fixture.open(group: true);
    addTearDown(f.close);
    f.signaling.failRecipients.add('other');
    expect(await f.service.setPinned('m1', true), isFalse);
    expect(await f.pinned(), ['m1']);
    expect(f.signaling.sentMessages, hasLength(1));
    expect(await f.service.setPinned('m2', true), isFalse);
    f.signaling.failRecipients.clear();
    expect(await f.service.setPinned('m1', true), isTrue);
    f.signaling.failRecipients.add('other');
    expect(await f.service.setPinned('m1', false), isFalse);
    expect(await f.pinned(), ['m1']);
    expect(await f.service.setPinned('m2', true), isFalse);
    f.signaling.failRecipients.clear();
    expect(await f.service.setPinned('m1', false), isTrue);
    expect(await f.service.setPinned('m2', true), isTrue);
    expect(await f.pinned(), ['m2']);
  });

  test('ambiguous send exceptions keep the slot occupied', () async {
    final f = await _Fixture.open();
    addTearDown(f.close);
    f.signaling.beforeSend = (_) async => throw StateError('uncertain send');
    expect(await f.service.setPinned('m1', true), isFalse);
    expect(await f.pinned(), ['m1']);
    expect(await f.service.setPinned('m2', true), isFalse);
  });

  test('failed claim rollback does not erase a newer incoming pin', () async {
    final f = await _Fixture.open();
    addTearDown(f.close);
    final sending = Completer<void>();
    final release = Completer<void>();
    f.signaling.failRecipients.add('peer');
    f.signaling.beforeSend = (_) async {
      if (!sending.isCompleted) sending.complete();
      await release.future;
    };
    final operation = f.service.setPinned('m1', true);
    try {
      await sending.future;
      final claimedAt = (await f.database.messages.getById('m1'))!.pinnedAt!;
      await f.receive('m1', true, pinnedAt: claimedAt + 1000);
    } finally {
      release.complete();
    }
    expect(await operation, isFalse);
    expect(await f.pinned(), ['m1']);
  });

  test('pin conflict still holds after reopening SQLite', () async {
    final f = await _Fixture.open();
    addTearDown(f.close);
    expect(await f.service.setPinned('m1', true), isTrue);
    final reopened = await SecureChatDatabase.open(
      file: f.file,
      crypto: f.crypto,
    );
    try {
      expect(await f.serviceFor(reopened).setPinned('m2', true), isFalse);
      expect(
        await reopened.messages.getPinnedMessages('peer').first,
        contains(isA<MessageEntity>().having((m) => m.id, 'id', 'm1')),
      );
    } finally {
      await reopened.close();
    }
  });
}

MessageEntity _message(
  String id,
  String conversation, {
  bool pinned = false,
  bool deleted = false,
  int? expiresAt,
}) => MessageEntity(
  id: id,
  conversationId: conversation,
  senderId: 'me',
  content: id,
  contentType: deleted
      ? StorageMessageContentType.deleted
      : StorageMessageContentType.text,
  timestamp: 1,
  status: StorageMessageStatus.sent,
  isOutgoing: true,
  isPinned: pinned,
  pinnedAt: pinned ? 1 : null,
  expiresAt: expiresAt,
);

class _Signaling extends InMemorySignalingService {
  final failRecipients = <String>{};
  Future<void> Function(SignalMessage)? beforeSend;

  @override
  Future<bool> send(SignalMessage message) async {
    await beforeSend?.call(message);
    if (failRecipients.contains(message.recipientId)) return false;
    return super.send(message);
  }
}

class _Fixture {
  _Fixture(
    this.directory,
    this.file,
    this.database,
    this.crypto,
    this.signaling,
    this.session,
    this.handler,
    this.conversationId,
  );

  final Directory directory;
  final File file;
  final SecureChatDatabase database;
  final LocalAeadCryptoService crypto;
  final _Signaling signaling;
  final SessionStore session;
  final IncomingMessageHandler handler;
  final String conversationId;
  late final service = serviceFor(database);

  static Future<_Fixture> open({bool group = false}) async {
    final directory = await Directory.systemTemp.createTemp('one_pin_');
    final file = File('${directory.path}/db');
    final crypto = LocalAeadCryptoService(SecretKey(List.filled(32, 37)));
    final database = await SecureChatDatabase.open(file: file, crypto: crypto);
    final signaling = _Signaling();
    await signaling.connect(
      userId: 'me',
      url: 'ws://test.invalid',
      accessToken: 'token',
    );
    final session = SessionStore(userId: 'me', accessToken: 'token');
    final id = group ? 'group' : 'peer';
    await database.conversations.insert(
      ConversationEntity(
        id: id,
        peerId: id,
        peerName: id,
        peerPhone: '',
        isGroup: group,
        groupMembers: group ? 'me,peer,other' : null,
        groupAdmins: group ? 'me,peer' : null,
      ),
    );
    for (final messageId in ['m1', 'm2']) {
      await database.messages.insert(_message(messageId, id));
    }
    final handler = IncomingMessageHandler(
      signaling: signaling,
      crypto: crypto,
      database: database,
      session: session,
    )..start();
    return _Fixture(
      directory,
      file,
      database,
      crypto,
      signaling,
      session,
      handler,
      id,
    );
  }

  MessageInteractionService serviceFor(SecureChatDatabase db) =>
      MessageInteractionService(
        database: db,
        signaling: signaling,
        session: session,
        crypto: crypto,
      );

  Future<List<String>> pinned([String? id]) async =>
      (await database.messages.getPinnedMessages(id ?? conversationId).first)
          .map((m) => m.id)
          .toList();

  Future<void> receive(
    String id,
    bool pinned, {
    String sender = 'peer',
    String? groupId,
    int? pinnedAt,
  }) async {
    signaling.addIncoming(
      await encryptTestPrivateChatControl(
        crypto: crypto,
        control: MessagePinSignal(
          senderId: sender,
          recipientId: 'me',
          timestamp: DateTime.now(),
          messageId: id,
          isPinned: pinned,
          pinnedAt: pinned
              ? DateTime.fromMillisecondsSinceEpoch(
                  pinnedAt ?? DateTime.now().millisecondsSinceEpoch,
                )
              : null,
          groupId:
              groupId ?? (conversationId == 'group' ? conversationId : null),
        ),
      ),
    );
    await handler.waitForIdle();
  }

  Future<List<MessagePinSignal>> sentPins() async => (await Future.wait(
    signaling.sentMessages.whereType<EncryptedSignalMessage>().map(
      (wire) => decryptTestPrivateChatControl(crypto: crypto, wire: wire),
    ),
  )).whereType<MessagePinSignal>().toList();

  Future<void> close() async {
    await handler.close();
    await signaling.dispose();
    await database.close();
    await directory.delete(recursive: true);
  }
}
