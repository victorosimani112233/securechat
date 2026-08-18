import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/groups/group_management_service.dart';
import 'package:flutter_securechat/src/groups/private_group_control.dart';
import 'package:flutter_securechat/src/incoming/incoming_message_handler.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'admin manages members, name and announcement policy with fanout',
    () async {
      final f = await _fixture();
      addTearDown(f.close);

      await f.groups.addMembers('g1', ['new-member']);
      expect(
        (await f.database.conversations.getById('g1'))!.groupMembers,
        'me,member,new-member',
      );
      final additions = await _outboundControls(f, action: 'ADD_MEMBER');
      expect(additions, hasLength(1));
      expect(additions.every((signal) => signal.groupName == 'Ekip'), isTrue);
      final bootstrap = await _outboundControls(f, action: 'CREATE');
      expect(bootstrap.single.recipientId, 'new-member');
      expect(bootstrap.single.groupMembers, ['me', 'member', 'new-member']);
      for (final wire
          in f.signaling.sentMessages.whereType<EncryptedSignalMessage>()) {
        expect(wire.toJson(), isNot(containsPair('groupId', anything)));
        expect(wire.toJson(), isNot(containsPair('groupName', anything)));
      }

      await f.groups.promoteToAdmin('g1', 'member');
      await f.groups.updateName('g1', 'Yeni Ekip');
      await f.groups.setReadOnly('g1', true);
      final group = (await f.database.conversations.getById('g1'))!;
      expect(group.groupAdmins, 'me,member');
      expect(group.peerName, 'Yeni Ekip');
      expect(group.isReadOnly, isTrue);

      await f.groups.removeMember('g1', 'member');
      expect((await f.database.conversations.getById('g1'))!.groupAdmins, 'me');
    },
  );

  test('non-admin mutation is rejected without local changes', () async {
    final f = await _fixture(userId: 'member');
    addTearDown(f.close);
    expect(
      () => f.groups.addMembers('g1', ['attacker-choice']),
      throwsA(isA<GroupManagementException>()),
    );
    expect(
      (await f.database.conversations.getById('g1'))!.groupMembers,
      'me,member',
    );
  });

  test(
    'incoming group changes validate admin and persist system events',
    () async {
      final f = await _fixture(userId: 'member');
      final handler = IncomingMessageHandler(
        signaling: f.signaling,
        crypto: f.crypto,
        database: f.database,
        session: f.session,
      )..start();
      addTearDown(() async {
        await handler.close();
        await f.close();
      });

      f.signaling.addIncoming(
        GroupNotificationSignal(
          senderId: 'attacker',
          recipientId: 'member',
          timestamp: DateTime.fromMillisecondsSinceEpoch(1),
          groupId: 'g1',
          groupName: 'Ele Geçirildi',
          action: 'UPDATE_NAME',
          groupMembers: const ['me', 'member'],
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect((await f.database.conversations.getById('g1'))!.peerName, 'Ekip');

      f.signaling.addIncoming(
        GroupNotificationSignal(
          senderId: 'me',
          recipientId: 'member',
          timestamp: DateTime.fromMillisecondsSinceEpoch(2),
          groupId: 'g1',
          groupName: 'Gerçek İsim',
          action: 'UPDATE_NAME',
          groupMembers: const ['me', 'member'],
        ),
      );
      await _eventually(
        () async =>
            (await f.database.conversations.getById('g1'))?.peerName ==
            'Gerçek İsim',
      );
      await _eventually(
        () async => await f.database.messages.getMessageCount('g1') == 1,
      );
    },
  );

  test('leave archives local group and notifies remaining members', () async {
    final f = await _fixture();
    addTearDown(f.close);
    await f.groups.leaveGroup('g1');
    final group = (await f.database.conversations.getById('g1'))!;
    expect(group.groupMembers, 'member');
    expect(group.isArchived, isTrue);
    expect(
      (await _outboundControls(f, action: 'LEAVE_GROUP')).single.action,
      'LEAVE_GROUP',
    );
  });

  test(
    'private call preparation stores only an encrypted local route',
    () async {
      final f = await _fixture(userId: 'member');
      final handler = IncomingMessageHandler(
        signaling: f.signaling,
        crypto: f.crypto,
        database: f.database,
        session: f.session,
      )..start();
      addTearDown(() async {
        await handler.close();
        await f.close();
      });
      final token = newOpaqueRoutingNonce();
      await PrivateGroupControlSender(
        crypto: f.crypto,
        signaling: f.signaling,
      ).send(
        senderId: 'me',
        groupId: 'g1',
        groupName: 'Ekip',
        memberIds: const ['me', 'member'],
        recipients: const ['member'],
        action: privateGroupCallPreparationAction,
        targetMemberId: token,
      );
      final wire = f.signaling.sentMessages
          .whereType<EncryptedSignalMessage>()
          .single;
      expect(wire.toJson(), isNot(containsPair('groupId', anything)));
      f.signaling.addIncoming(wire);
      await _eventually(
        () async =>
            await f.database.cryptoState.get(
              privateGroupCallRouteStateKey(token),
            ) !=
            null,
      );
      final stored =
          jsonDecode(
                (await f.database.cryptoState.get(
                  privateGroupCallRouteStateKey(token),
                ))!,
              )
              as Map<String, Object?>;
      expect(stored['groupId'], 'g1');
      expect(
        (stored['expiresAt'] as int),
        greaterThan(DateTime.now().millisecondsSinceEpoch),
      );
    },
  );
}

class _Fixture {
  const _Fixture({
    required this.root,
    required this.database,
    required this.session,
    required this.signaling,
    required this.crypto,
    required this.groups,
  });
  final Directory root;
  final SecureChatDatabase database;
  final SessionStore session;
  final InMemorySignalingService signaling;
  final LocalAeadCryptoService crypto;
  final GroupManagementService groups;

  Future<void> close() async {
    await database.close();
    await root.delete(recursive: true);
  }
}

Future<_Fixture> _fixture({String userId = 'me'}) async {
  final root = await Directory.systemTemp.createTemp('securechat_group_');
  final crypto = LocalAeadCryptoService(
    SecretKey(List<int>.generate(32, (index) => index + 4)),
  );
  final database = await SecureChatDatabase.open(
    file: File('${root.path}/db.securejson'),
    crypto: crypto,
  );
  await database.conversations.insert(
    const ConversationEntity(
      id: 'g1',
      peerId: 'g1',
      peerName: 'Ekip',
      peerPhone: '',
      isGroup: true,
      groupMembers: 'me,member',
      groupAdmins: 'me',
    ),
  );
  final session = SessionStore(userId: userId, displayName: userId);
  final signaling = InMemorySignalingService();
  await signaling.connect(userId: userId, url: 'ws://test', accessToken: 'x');
  return _Fixture(
    root: root,
    database: database,
    session: session,
    signaling: signaling,
    crypto: crypto,
    groups: GroupManagementService(
      database: database,
      session: session,
      signaling: signaling,
      crypto: crypto,
    ),
  );
}

Future<List<GroupNotificationSignal>> _outboundControls(
  _Fixture fixture, {
  required String action,
}) async {
  final decoded = <GroupNotificationSignal>[];
  for (final signal
      in fixture.signaling.sentMessages.whereType<EncryptedSignalMessage>()) {
    final plaintext = await fixture.crypto.decryptDirect(
      // LocalAeadCryptoService derives its loopback test key from the outbound
      // recipient. Production Signal sessions authenticate the real sender.
      senderId: signal.recipientId,
      envelope: signal.envelope,
    );
    final control = await decodePrivateGroupControl(
      plaintext: plaintext,
      authenticatedSenderId: signal.senderId,
      localRecipientId: signal.recipientId,
    );
    if (control.action == action) decoded.add(control);
  }
  return decoded;
}

Future<void> _eventually(Future<bool> Function() condition) async {
  for (var i = 0; i < 50; i++) {
    if (await condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(await condition(), isTrue);
}
