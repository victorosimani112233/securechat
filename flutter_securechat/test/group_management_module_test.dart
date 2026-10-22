import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

  test('admin sets description and photo; new members receive both', () async {
    final f = await _fixture();
    addTearDown(f.close);
    final photo = _jpeg(2048);

    await f.groups.updateDescription('g1', '  Haftalık plan burada  ');
    await f.groups.updatePhoto('g1', photo);
    var group = (await f.database.conversations.getById('g1'))!;
    expect(group.groupDescription, 'Haftalık plan burada');
    expect(group.groupPhoto, base64.encode(photo));
    final described = await _outboundControls(f, action: 'UPDATE_DESCRIPTION');
    expect(described.single.recipientId, 'member');
    expect(described.single.description, 'Haftalık plan burada');
    final pictured = await _outboundControls(f, action: 'UPDATE_PHOTO');
    expect(pictured.single.photo, base64.encode(photo));

    // Yeni uye grup kaydini CREATE ile alir; bilgiyi de orada gormeli.
    await f.groups.addMembers('g1', ['new-member']);
    final bootstrap = await _outboundControls(f, action: 'CREATE');
    expect(bootstrap.single.description, 'Haftalık plan burada');
    expect(bootstrap.single.photo, base64.encode(photo));

    await f.groups.updateDescription('g1', '');
    await f.groups.updatePhoto('g1', null);
    group = (await f.database.conversations.getById('g1'))!;
    expect(group.groupDescription, isNull);
    expect(group.groupPhoto, isNull);
    expect(
      (await _outboundControls(f, action: 'UPDATE_PHOTO')).last.photo,
      isEmpty,
    );
  });

  test('description and photo limits are enforced before sending', () async {
    final f = await _fixture();
    addTearDown(f.close);
    final sentBefore = f.signaling.sentMessages.length;

    await expectLater(
      f.groups.updateDescription('g1', 'a' * (maxGroupDescriptionLength + 1)),
      throwsA(isA<GroupManagementException>()),
    );
    await expectLater(
      f.groups.updatePhoto('g1', _jpeg(maxGroupPhotoBytes + 1)),
      throwsA(isA<GroupManagementException>()),
    );
    await expectLater(
      f.groups.updatePhoto('g1', Uint8List.fromList(utf8.encode('not image'))),
      throwsA(isA<GroupManagementException>()),
    );
    expect(f.signaling.sentMessages.length, sentBefore);
    final member = await _fixture(userId: 'member');
    addTearDown(member.close);
    await expectLater(
      member.groups.updateDescription('g1', 'yetkisiz'),
      throwsA(isA<GroupManagementException>()),
    );
  });

  test(
    'incoming description and photo require an admin and a real image',
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
      GroupNotificationSignal control(
        String sender,
        String action, {
        String? description,
        String? photo,
        int at = 1,
      }) => GroupNotificationSignal(
        senderId: sender,
        recipientId: 'member',
        timestamp: DateTime.fromMillisecondsSinceEpoch(at),
        groupId: 'g1',
        groupName: 'Ekip',
        action: action,
        groupMembers: const ['me', 'member'],
        description: description,
        photo: photo,
      );

      f.signaling.addIncoming(
        control('member', 'UPDATE_DESCRIPTION', description: 'yetkisiz'),
      );
      f.signaling.addIncoming(
        control(
          'me',
          'UPDATE_PHOTO',
          photo: base64.encode(utf8.encode('x')),
          at: 2,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      var group = (await f.database.conversations.getById('g1'))!;
      expect(group.groupDescription, isNull);
      expect(group.groupPhoto, isNull);

      final photo = base64.encode(_jpeg(512));
      f.signaling.addIncoming(
        control('me', 'UPDATE_DESCRIPTION', description: 'Kurallar', at: 3),
      );
      f.signaling.addIncoming(
        control('me', 'UPDATE_PHOTO', photo: photo, at: 4),
      );
      await _eventually(() async {
        final current = (await f.database.conversations.getById('g1'))!;
        return current.groupDescription == 'Kurallar' &&
            current.groupPhoto == photo;
      });
      await _eventually(
        () async => await f.database.messages.getMessageCount('g1') == 2,
      );

      f.signaling.addIncoming(control('me', 'UPDATE_PHOTO', photo: '', at: 5));
      await _eventually(
        () async =>
            (await f.database.conversations.getById('g1'))!.groupPhoto == null,
      );
      group = (await f.database.conversations.getById('g1'))!;
      expect(group.groupDescription, 'Kurallar');
    },
  );

  test('a new member bootstraps the group description and photo', () async {
    final f = await _fixture(userId: 'fresh');
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
    final photo = base64.encode(_jpeg(256));
    f.signaling.addIncoming(
      GroupNotificationSignal(
        senderId: 'owner',
        recipientId: 'fresh',
        timestamp: DateTime.fromMillisecondsSinceEpoch(1),
        groupId: 'g2',
        groupName: 'Aile',
        action: 'CREATE',
        groupMembers: const ['owner', 'fresh'],
        description: 'Sadece aile',
        photo: photo,
      ),
    );
    await _eventually(
      () async => await f.database.conversations.getById('g2') != null,
    );
    final group = (await f.database.conversations.getById('g2'))!;
    expect(group.groupDescription, 'Sadece aile');
    expect(group.groupPhoto, photo);
  });

  test('group control payload rejects oversized description and photo', () {
    expect(isAcceptedGroupPhoto(_jpeg(maxGroupPhotoBytes)), isTrue);
    expect(isAcceptedGroupPhoto(_jpeg(maxGroupPhotoBytes + 1)), isFalse);
    expect(
      isAcceptedGroupPhoto([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0]),
      isTrue,
    );
    expect(isAcceptedGroupPhoto(const []), isFalse);
    expect(acceptedGroupPhotoBase64('%%%'), isNull);
    expect(acceptedGroupPhotoBase64(''), isNull);
  });

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
    expect(group.groupAdmins, isEmpty);
    expect(f.groups.isLocalMember(group), isFalse);
    expect(f.groups.isLocalAdmin(group), isFalse);
    await f.groups.leaveGroup('g1');
    await expectLater(
      f.groups.updateName('g1', 'stale admin'),
      throwsA(isA<GroupManagementException>()),
    );
    expect(
      (await _outboundControls(f, action: 'LEAVE_GROUP')).single.action,
      'LEAVE_GROUP',
    );
  });

  test(
    'concurrent leave sends one control and stale admin is not privileged',
    () async {
      final f = await _fixture();
      addTearDown(f.close);
      final first = f.groups.leaveGroup('g1');
      final second = f.groups.leaveGroup('g1');
      expect(identical(first, second), isTrue);
      await Future.wait([first, second]);
      expect(await _outboundControls(f, action: 'LEAVE_GROUP'), hasLength(1));
      final left = (await f.database.conversations.getById('g1'))!;
      await f.database.conversations.update(left.copyWith(groupAdmins: 'me'));
      expect(f.groups.isLocalAdmin(left.copyWith(groupAdmins: 'me')), isFalse);
      await expectLater(
        f.groups.updateName('g1', 'not permitted'),
        throwsA(isA<GroupManagementException>()),
      );
    },
  );

  test('offline leave preserves membership and can be retried', () async {
    final f = await _fixture();
    addTearDown(f.close);
    f.signaling.setConnected(false);
    await expectLater(
      f.groups.leaveGroup('g1'),
      throwsA(isA<GroupLeaveDeliveryException>()),
    );
    final unchanged = (await f.database.conversations.getById('g1'))!;
    expect(unchanged.groupMembers, 'me,member');
    expect(unchanged.groupAdmins, 'me');
    expect(unchanged.isArchived, isFalse);
    expect(f.signaling.sentMessages, isEmpty);
    f.signaling.setConnected(true);
    await f.groups.leaveGroup('g1');
    expect(
      (await f.database.conversations.getById('g1'))!.groupMembers,
      'member',
    );
  });

  test(
    'leave reconnects first and retries the same envelope after socket failure',
    () async {
      final signaling = _ReconnectingSignaling();
      final f = await _fixture(signalingOverride: signaling);
      addTearDown(f.close);
      signaling.setConnected(false);
      await f.groups.leaveGroup('g1');
      expect(signaling.connections, 2);
      expect(signaling.attempts, hasLength(2));
      expect(identical(signaling.attempts[0], signaling.attempts[1]), isTrue);
      expect(
        (await f.database.conversations.getById('g1'))!.isArchived,
        isTrue,
      );
    },
  );

  test('last member can leave without a network connection', () async {
    final f = await _fixture();
    addTearDown(f.close);
    await f.database.conversations.updateGroupMembers('g1', 'me');
    f.signaling.setConnected(false);
    await f.groups.leaveGroup('g1');
    final left = (await f.database.conversations.getById('g1'))!;
    expect(left.groupMembers, isEmpty);
    expect(left.groupAdmins, isEmpty);
    expect(left.isArchived, isTrue);
    expect(f.signaling.sentMessages, isEmpty);
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
    await signaling.dispose();
    await database.close();
    await root.delete(recursive: true);
  }
}

Future<_Fixture> _fixture({
  String userId = 'me',
  InMemorySignalingService? signalingOverride,
}) async {
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
  final signaling = signalingOverride ?? InMemorySignalingService();
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

class _ReconnectingSignaling extends InMemorySignalingService {
  int connections = 0;
  final attempts = <SignalMessage>[];

  @override
  Future<bool> ensureConnected({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    connections++;
    setConnected(true);
    return true;
  }

  @override
  Future<bool> send(SignalMessage message) async {
    attempts.add(message);
    if (attempts.length == 1) {
      setConnected(false);
      return false;
    }
    return super.send(message);
  }
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

/// JPEG imzasiyla baslayan, istenen boyutta sahte fotograf.
Uint8List _jpeg(int length) {
  final bytes = Uint8List(length);
  bytes.setAll(0, const [0xFF, 0xD8, 0xFF, 0xE0]);
  return bytes;
}
