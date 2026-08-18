import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/export/export_audit_service.dart';
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
    'conversation export preserves formatting and sends admin-only audit',
    () async {
      final fixture = await _fixture();
      addTearDown(fixture.close);
      await fixture.seedGroup(exportEnabled: true);
      await fixture.database.messages.insert(
        const MessageEntity(
          id: 'm1',
          conversationId: 'g1',
          senderId: 'me',
          content: 'gizli içerik',
          contentType: StorageMessageContentType.text,
          timestamp: 1000,
          status: StorageMessageStatus.sent,
          isOutgoing: true,
        ),
      );

      final exported = await fixture.audit.exportConversation('g1');
      expect(exported.text, contains('Ben: gizli içerik'));
      expect(exported.text, contains('Mesaj sayısı: 1'));
      final auditSignal = fixture.signaling.sentMessages
          .whereType<AdminEncryptedLogSignal>()
          .single;
      expect(auditSignal.adminPayloads.keys, ['admin-2']);
      expect(auditSignal.groupId, isNot('g1'));
      expect(auditSignal.groupId, isNot(await groupRoutingToken('g1')));
      expect(auditSignal.eventType, 'PRIVATE_EVENT');
      expect(auditSignal.toJson().toString(), isNot(contains('gizli içerik')));
      expect(auditSignal.toJson().toString(), isNot(contains('EXPORT')));
    },
  );

  test('group export policy is admin-only and fans out', () async {
    final fixture = await _fixture();
    addTearDown(fixture.close);
    await fixture.seedGroup(exportEnabled: false);
    await fixture.audit.toggleGroupExport('g1', true);
    expect(
      (await fixture.database.conversations.getById('g1'))?.isExportEnabled,
      isTrue,
    );
    final controls = await _outboundControls(
      fixture,
      action: 'UPDATE_EXPORT_POLICY',
    );
    expect(controls, hasLength(2));
    expect(controls.every((signal) => signal.groupId == 'g1'), isTrue);

    fixture.session.userId = 'member';
    expect(
      () => fixture.audit.toggleGroupExport('g1', false),
      throwsA(isA<ExportNotAllowed>()),
    );
  });

  test(
    'incoming audit is silently filtered and decrypted only for admin',
    () async {
      final fixture = await _fixture();
      addTearDown(fixture.close);
      await fixture.seedGroup(exportEnabled: true);
      final handler = IncomingMessageHandler(
        signaling: fixture.signaling,
        crypto: fixture.crypto,
        database: fixture.database,
        session: fixture.session,
      )..start();
      addTearDown(handler.close);
      final routingToken = await groupRoutingToken('g1');
      final routeNonce = newOpaqueRoutingNonce();
      final envelope = await fixture.crypto.encryptDirect(
        recipientId: 'me',
        plaintext:
            '{"actorUserId":"actor","actorDisplayName":"Aktaran",'
            '"groupId":"g1","groupToken":"$routingToken",'
            '"routeNonce":"$routeNonce",'
            '"eventType":"EXPORT","timestamp":5,"messageCount":3}',
      );
      fixture.signaling.addIncoming(
        AdminEncryptedLogSignal(
          senderId: 'actor',
          timestamp: DateTime.fromMillisecondsSinceEpoch(5),
          groupId: routeNonce,
          eventType: 'PRIVATE_EVENT',
          adminPayloads: {'someone-else': envelope},
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(await fixture.database.exportLogs.countForGroup('g1'), 0);

      fixture.signaling.addIncoming(
        AdminEncryptedLogSignal(
          senderId: 'actor',
          timestamp: DateTime.fromMillisecondsSinceEpoch(5),
          groupId: routeNonce,
          eventType: 'PRIVATE_EVENT',
          adminPayloads: {'me': envelope},
        ),
      );
      await _eventually(
        () => fixture.database.exportLogs.countForGroup('g1'),
        1,
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
    required this.audit,
  });
  final Directory root;
  final SecureChatDatabase database;
  final SessionStore session;
  final InMemorySignalingService signaling;
  final LocalAeadCryptoService crypto;
  final ExportAuditService audit;

  Future<void> seedGroup({required bool exportEnabled}) =>
      database.conversations.insert(
        ConversationEntity(
          id: 'g1',
          peerId: 'g1',
          peerName: 'Ekip',
          peerPhone: '',
          isGroup: true,
          groupMembers: 'me,admin-2,member',
          groupAdmins: 'me,admin-2',
          isExportEnabled: exportEnabled,
        ),
      );

  Future<void> close() async {
    await database.close();
    await root.delete(recursive: true);
  }
}

Future<_Fixture> _fixture() async {
  final root = await Directory.systemTemp.createTemp('securechat_export_');
  final crypto = LocalAeadCryptoService(
    SecretKey(List<int>.generate(32, (index) => 100 + index)),
  );
  final database = await SecureChatDatabase.open(
    file: File('${root.path}/db.securejson'),
    crypto: crypto,
  );
  final session = SessionStore(
    userId: 'me',
    displayName: 'Ben',
    phoneNumber: '+90',
  );
  final signaling = InMemorySignalingService();
  await signaling.connect(userId: 'me', url: 'ws://test', accessToken: 'x');
  final audit = ExportAuditService(
    database: database,
    session: session,
    crypto: crypto,
    signaling: signaling,
  );
  return _Fixture(
    root: root,
    database: database,
    session: session,
    signaling: signaling,
    crypto: crypto,
    audit: audit,
  );
}

Future<List<GroupNotificationSignal>> _outboundControls(
  _Fixture fixture, {
  required String action,
}) async {
  final result = <GroupNotificationSignal>[];
  for (final signal
      in fixture.signaling.sentMessages.whereType<EncryptedSignalMessage>()) {
    final plaintext = await fixture.crypto.decryptDirect(
      senderId: signal.recipientId,
      envelope: signal.envelope,
    );
    final control = await decodePrivateGroupControl(
      plaintext: plaintext,
      authenticatedSenderId: signal.senderId,
      localRecipientId: signal.recipientId,
    );
    if (control.action == action) result.add(control);
  }
  return result;
}

Future<void> _eventually(Future<int> Function() read, int expected) async {
  for (var i = 0; i < 50; i++) {
    if (await read() == expected) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(await read(), expected);
}
