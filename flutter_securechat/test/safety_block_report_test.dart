import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/incoming/incoming_message_handler.dart';
import 'package:flutter_securechat/src/safety/abuse_report.dart';
import 'package:flutter_securechat/src/safety/block_list.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late SecureChatDatabase database;
  late LocalAeadCryptoService crypto;
  late BlockList blockList;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('safety_');
    crypto = LocalAeadCryptoService(SecretKey(List.filled(32, 9)));
    database = await SecureChatDatabase.open(
      file: File('${directory.path}/db.securejson'),
      crypto: crypto,
    );
    blockList = BlockList(database.cryptoState);
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  group('BlockList', () {
    test('block, unblock and list round-trip', () async {
      expect(await blockList.isBlocked('peer'), isFalse);
      await blockList.block('peer');
      await blockList.block('other');
      expect(await blockList.isBlocked('peer'), isTrue);
      expect(await blockList.all(), containsAll(['peer', 'other']));

      await blockList.unblock('peer');
      expect(await blockList.isBlocked('peer'), isFalse);
      expect(await blockList.all(), ['other']);
    });

    test('empty id is never blocked', () async {
      expect(await blockList.isBlocked(''), isFalse);
    });
  });

  group('incoming messages', () {
    late InMemorySignalingService signaling;
    late IncomingMessageHandler handler;

    setUp(() async {
      signaling = InMemorySignalingService();
      await signaling.connect(
        userId: 'me',
        url: 'ws://local',
        accessToken: 'token',
      );
      handler = IncomingMessageHandler(
        signaling: signaling,
        crypto: crypto,
        database: database,
        session: SessionStore(userId: 'me', accessToken: 'token'),
      )..start();
    });

    tearDown(() => handler.close());

    Future<void> deliver(String senderId, String text) async {
      final envelope = await crypto.encryptDirect(
        recipientId: 'me',
        plaintext: 'MSGID:$senderId-$text:$text',
      );
      signaling.addIncoming(
        EncryptedSignalMessage(
          senderId: senderId,
          recipientId: 'me',
          timestamp: DateTime.now(),
          envelope: envelope,
        ),
      );
      await handler.waitForIdle();
    }

    test('blocked sender content is dropped without a receipt', () async {
      await blockList.block('spammer');
      signaling.sentMessages.clear();

      await deliver('spammer', 'hello');

      expect(await database.messages.getMessagesImmediate('spammer'), isEmpty);
      expect(await database.conversations.getById('spammer'), isNull);
      expect(
        signaling.sentMessages.whereType<DeliveryReceiptSignal>(),
        isEmpty,
      );
    });

    test('other senders and unblocked senders still arrive', () async {
      await blockList.block('spammer');
      await deliver('friend', 'hi');
      expect(
        await database.messages.getMessagesImmediate('friend'),
        hasLength(1),
      );

      await blockList.unblock('spammer');
      await deliver('spammer', 'again');
      expect(
        await database.messages.getMessagesImmediate('spammer'),
        hasLength(1),
      );
    });
  });

  group('AbuseReportService', () {
    late List<Map<String, Object?>> submitted;
    late AbuseReportService service;

    setUp(() {
      submitted = [];
      service = AbuseReportService(
        submit: (report) async => submitted.add(report),
        blockList: blockList,
        localUserId: () => 'me',
      );
    });

    test('user report carries no content and can also block', () async {
      await service.reportUser(
        'peer',
        reason: ReportReason.harassment,
        note: '  rude  ',
        alsoBlock: true,
      );

      expect(submitted.single, {
        'kind': 'user',
        'targetUserIds': ['peer'],
        'reason': 'harassment',
        'note': 'rude',
      });
      expect(await blockList.isBlocked('peer'), isTrue);
    });

    test('note is capped and omitted when blank', () async {
      await service.reportUser('peer', reason: ReportReason.spam, note: '   ');
      await service.reportUser(
        'peer',
        reason: ReportReason.spam,
        note: 'x' * 900,
      );

      expect(submitted.first.containsKey('note'), isFalse);
      expect(
        (submitted.last['note'] as String).length,
        AbuseReportService.maxNoteLength,
      );
    });

    test('group report targets admins, else members, never the reporter', () {
      expect(
        groupReportTargets(
          admins: ['me', 'admin'],
          members: ['me', 'admin', 'a', 'b'],
          localUserId: 'me',
        ),
        ['admin'],
      );
      expect(
        groupReportTargets(
          admins: ['me'],
          members: ['me', 'a', 'b', 'a'],
          localUserId: 'me',
        ),
        ['a', 'b'],
      );
    });

    test('group report with nobody else fails instead of sending', () async {
      await expectLater(
        service.reportGroup(
          admins: const ['me'],
          members: const ['me'],
          reason: ReportReason.spam,
        ),
        throwsStateError,
      );
      expect(submitted, isEmpty);
    });
  });
}
