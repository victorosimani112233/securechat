import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';

LocalAeadCryptoService _crypto() =>
    LocalAeadCryptoService(SecretKey(List.filled(32, 73)));

ConversationEntity _conversation(String id) =>
    ConversationEntity(id: id, peerId: id, peerName: id, peerPhone: '');

MessageEntity _message(String id, String conversation) => MessageEntity(
  id: id,
  conversationId: conversation,
  senderId: conversation,
  content: 'background $id',
  contentType: StorageMessageContentType.text,
  timestamp: 10,
  status: StorageMessageStatus.delivered,
  isOutgoing: false,
);

const _pin = IdentityEntity(
  addressName: 'peer',
  identityKey: [9, 8],
  trustLevel: TrustLevel.trustedVerified,
);

Future<void> _incrementWorker((String, SendPort) args) async {
  final database = await SecureChatDatabase.open(
    file: File(args.$1),
    crypto: _crypto(),
  );
  final start = ReceivePort();
  args.$2.send(start.sendPort);
  await start.first;
  var result = 'done';
  try {
    for (var i = 0; i < 30; i++) {
      await database.conversations.incrementUnreadCount('peer');
    }
  } catch (error) {
    result = 'error: $error';
  } finally {
    await database.close();
  }
  args.$2.send(result);
}

void main() {
  late Directory root;
  late File file;
  late SecureChatDatabase foreground;
  late SecureChatDatabase background;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('cross_runtime_');
    file = File('${root.path}/data');
    foreground = await SecureChatDatabase.open(file: file, crypto: _crypto());
    await foreground.conversations.insert(_conversation('peer'));
    background = await SecureChatDatabase.open(file: file, crypto: _crypto());
  });

  tearDown(() async {
    await foreground.close();
    await background.close();
    await root.delete(recursive: true);
  });

  test(
    'refresh publishes background messages and unread across conversations',
    () async {
      final seen = <List<ConversationEntity>>[];
      final subscription = foreground.conversations.getAll().listen(seen.add);
      addTearDown(subscription.cancel);
      await Future<void>.delayed(Duration.zero);
      await background.conversations.incrementUnreadCount('peer');
      await background.conversations.insert(_conversation('second'));
      await background.messages.insert(_message('m2', 'second'));
      await background.conversations.incrementUnreadCount('second');
      await foreground.refreshFromDisk();
      await Future<void>.delayed(Duration.zero);
      expect(seen.last.fold<int>(0, (sum, c) => sum + c.unreadCount), 2);
      expect(await foreground.messages.getById('m2'), isNotNull);
      expect(await foreground.conversations.unreadCounts(), {
        'peer': 1,
        'second': 1,
      });
      final emissions = seen.length;
      final cached = await foreground.conversations.getById('peer');
      await foreground.refreshFromDisk();
      await foreground.refreshFromDisk();
      await Future<void>.delayed(Duration.zero);
      expect(seen.length, emissions);
      expect(
        identical(await foreground.conversations.getById('peer'), cached),
        isTrue,
      );
    },
  );

  test(
    'active watchers see commits after resume without another DAO read',
    () async {
      await foreground.refreshFromDisk();
      final updated = Completer<void>();
      final subscription = foreground.conversations.observeById('peer').listen((
        c,
      ) {
        if (c?.unreadCount == 1 && !updated.isCompleted) updated.complete();
      });
      addTearDown(subscription.cancel);
      await Future<void>.delayed(Duration.zero);
      await background.conversations.incrementUnreadCount('peer');
      await updated.future.timeout(const Duration(seconds: 4));
    },
  );

  test('one-shot reads check disk without explicit refresh', () async {
    await background.messages.insert(_message('m1', 'peer'));
    await background.cryptoState.put('account_recovery_pending_v1', 'stage');
    expect(await foreground.messages.getById('m1'), isNotNull);
    expect(
      await foreground.cryptoState.get('account_recovery_pending_v1'),
      'stage',
    );
  });

  test(
    'foreground patches preserve background row metadata and other collections',
    () async {
      await background.messages.insert(_message('m1', 'peer'));
      await background.conversations.updateLastMessage(
        'peer',
        'new preview',
        10,
      );
      await background.conversations.updateMuted('peer', true);
      await background.conversations.incrementUnreadCount('peer');
      await background.identities.insert(_pin);
      await background.cryptoState.put('account_recovery_pending_v1', 'stage');
      await foreground.conversations.updatePinned('peer', true);
      final c = (await background.conversations.getById('peer'))!;
      expect(c.isPinned, isTrue);
      expect(c.isMuted, isTrue);
      expect(c.lastMessage, 'new preview');
      expect(c.unreadCount, 1);
      expect(await foreground.messages.getById('m1'), isNotNull);
      expect((await foreground.identities.get('peer'))?.identityKey, [9, 8]);
      expect(
        await foreground.cryptoState.get('account_recovery_pending_v1'),
        'stage',
      );
    },
  );

  test(
    'two cached instances do not lose increments and refresh respects write queue',
    () async {
      final first = foreground.conversations.incrementUnreadCount('peer');
      final refresh = foreground.refreshFromDisk();
      final second = background.conversations.incrementUnreadCount('peer');
      await Future.wait([first, refresh, second]);
      expect((await foreground.conversations.getById('peer'))?.unreadCount, 2);
      expect((await background.conversations.getById('peer'))?.unreadCount, 2);
    },
  );

  test(
    'independent isolates serialize read-modify-write under contention',
    () async {
      final receive = ReceivePort();
      final events = StreamIterator<Object?>(receive);
      final isolate = await Isolate.spawn(_incrementWorker, (
        file.path,
        receive.sendPort,
      ));
      addTearDown(() async {
        isolate.kill(priority: Isolate.immediate);
        await events.cancel();
        receive.close();
      });
      expect(
        await events.moveNext().timeout(const Duration(seconds: 10)),
        isTrue,
      );
      (events.current as SendPort).send('start');
      for (var i = 0; i < 30; i++) {
        await foreground.conversations.incrementUnreadCount('peer');
      }
      expect(
        await events.moveNext().timeout(const Duration(seconds: 10)),
        isTrue,
      );
      expect(events.current, 'done');
      expect((await foreground.conversations.getById('peer'))?.unreadCount, 60);
    },
  );

  test(
    'rollback retains refreshed external state and queue remains usable',
    () async {
      await background.messages.insert(_message('m1', 'peer'));
      await background.conversations.incrementUnreadCount('peer');
      foreground.store.failMidTransaction = true;
      await expectLater(
        foreground.conversations.incrementUnreadCount('peer'),
        throwsStateError,
      );
      expect((await foreground.conversations.getById('peer'))?.unreadCount, 1);
      expect((await background.conversations.getById('peer'))?.unreadCount, 1);
      expect(await foreground.messages.getById('m1'), isNotNull);
      await foreground.conversations.incrementUnreadCount('peer');
      expect((await background.conversations.getById('peer'))?.unreadCount, 2);
    },
  );

  test(
    'backup exports refresh and security-preserving restore retains external pins/stage',
    () async {
      final backup = await foreground.exportPortableJson();
      await background.identities.insert(_pin);
      await background.cryptoState.put('account_recovery_pending_v1', 'stage');
      await background.sessions.insert(
        const SessionEntity(id: 'peer:1', record: [1]),
      );
      final exported = jsonDecode(await foreground.exportPortableJson()) as Map;
      expect(exported['cryptoState']['account_recovery_pending_v1'], 'stage');
      await foreground.replaceFromPortableJson(
        backup,
        preserveLocalSecurityState: true,
      );
      expect((await background.identities.get('peer'))?.identityKey, [9, 8]);
      expect(
        await background.cryptoState.get('account_recovery_pending_v1'),
        'stage',
      );
      expect(await background.sessions.get('peer:1'), isNotNull);
    },
  );

  test(
    'backup guard sees external security changes inside the transaction',
    () async {
      final backup = await foreground.exportPortableJson();
      await background.cryptoState.put(
        'account_recovery_pending_v1',
        'changed',
      );
      final expected = await background.exportPortableJson();
      var validated = false;
      await expectLater(
        foreground.replaceFromPortableJson(
          backup,
          validateBeforeCommit: () {
            validated = true;
            throw StateError('account changed');
          },
        ),
        throwsStateError,
      );
      expect(validated, isTrue);
      expect(await foreground.exportPortableJson(), expected);
      foreground.store.failMidTransaction = true;
      await expectLater(
        foreground.replaceFromPortableJson(backup),
        throwsStateError,
      );
      expect(await foreground.exportPortableJson(), expected);
      expect(await background.exportPortableJson(), expected);
      await foreground.cryptoState.put('after-failure', 'ok');
      expect(await background.cryptoState.get('after-failure'), 'ok');
    },
  );

  test(
    'recovery compare-and-set sees new stage and preserves peer pins',
    () async {
      await foreground.cryptoState.put('account_recovery_pending_v1', 'old');
      await background.cryptoState.put('account_recovery_pending_v1', 'new');
      await background.identities.insert(_pin);
      await background.sessions.insert(
        const SessionEntity(id: 'peer:1', record: [1]),
      );
      Future<void> install(String expected) =>
          foreground.installRecoveryIdentity(
            expectedPendingRecord: expected,
            identityKeyPair: [4, 5],
            registrationId: 42,
            preKeys: const [
              PreKeyEntity(id: 1, record: [2]),
            ],
            signedPreKeys: const [
              SignedPreKeyEntity(id: 2, record: [3], createdAt: 1),
            ],
          );
      await expectLater(install('old'), throwsStateError);
      expect(await background.sessions.get('peer:1'), isNotNull);
      await install('new');
      expect((await background.identities.get('peer'))?.identityKey, [9, 8]);
      expect(
        await background.cryptoState.get('account_recovery_pending_v1'),
        'new',
      );
      expect(
        await background.cryptoState.get('local_identity_key_pair_v1'),
        base64Encode([4, 5]),
      );
      expect(await background.sessions.get('peer:1'), isNull);
      expect((await background.preKeys.get(1))?.record, [2]);
    },
  );

  test(
    'identity approval rejects externally changed pins and local identity',
    () async {
      await foreground.cryptoState.put(
        'local_identity_key_pair_v1',
        base64Encode([1]),
      );
      await background.identities.insert(_pin);
      Future<bool> approve(List<int>? expected) =>
          foreground.approvePeerIdentity(
            peerId: 'peer',
            expectedIdentity: expected,
            approvedIdentity: [7],
            expectedLocalIdentityRecord: [1],
          );
      expect(await approve(null), isFalse);
      await background.cryptoState.put(
        'local_identity_key_pair_v1',
        base64Encode([2]),
      );
      expect(await approve([9, 8]), isFalse);
      expect((await background.identities.get('peer'))?.identityKey, [9, 8]);
    },
  );

  test('Room import guard sees externally created user data', () async {
    await foreground.clearAll();
    final empty = await foreground.exportPortableJson();
    await background.conversations.insert(_conversation('external'));
    await expectLater(
      foreground.importLegacyRoomPortableJson(empty),
      throwsStateError,
    );
    expect(await foreground.conversations.getById('external'), isNotNull);
  });
}
