import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/incoming/incoming_message_handler.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';

/// Uye ayrilinca ya da cikarilinca grup anahtari yenilenir ve cikarilan uye
/// eski uye listesiyle gruba geri sokulamaz.
void main() {
  late Directory root;
  late SecureChatDatabase database;
  late InMemorySignalingService signaling;
  late _CountingGroupCrypto crypto;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('group_rekey_');
    crypto = _CountingGroupCrypto();
    database = await SecureChatDatabase.open(
      file: File('${root.path}/db'),
      crypto: crypto,
    );
    signaling = InMemorySignalingService();
    await signaling.connect(userId: 'me', url: 'wss://t', accessToken: 't');
    await database.conversations.insert(
      const ConversationEntity(
        id: 'g',
        peerId: 'g',
        peerName: 'Ekip',
        peerPhone: '',
        isGroup: true,
        groupMembers: 'admin,me,bob,eve',
        groupAdmins: 'admin',
      ),
    );
  });

  tearDown(() async {
    await database.close();
    await signaling.dispose();
    await root.delete(recursive: true);
  });

  Future<void> deliver(List<GroupNotificationSignal> signals) async {
    final handler = IncomingMessageHandler(
      signaling: signaling,
      crypto: crypto,
      database: database,
      session: SessionStore(userId: 'me', accessToken: 't'),
    )..start();
    for (final signal in signals) {
      signaling.addIncoming(signal);
    }
    await handler.waitForIdle();
    await handler.close();
  }

  GroupNotificationSignal control(
    String sender,
    String action,
    List<String> members, {
    String? target,
  }) => GroupNotificationSignal(
    senderId: sender,
    recipientId: 'me',
    timestamp: DateTime.now(),
    groupId: 'g',
    groupName: 'Ekip',
    action: action,
    groupMembers: members,
    targetMemberId: target,
  );

  Future<List<String>> members() async =>
      (await database.conversations.getById('g'))!.groupMembers!.split(',');

  test('removal and leave rotate our own group key', () async {
    await deliver([
      control('admin', 'REMOVE_MEMBER', ['admin', 'me', 'bob'], target: 'eve'),
    ]);
    expect(crypto.resets, ['g:me']);
    await deliver([
      control('bob', 'LEAVE_GROUP', ['admin', 'me']),
    ]);
    expect(crypto.resets, ['g:me', 'g:me']);
    expect(await members(), ['admin', 'me']);
  });

  test('a stale member list cannot bring a removed member back', () async {
    await deliver([
      control('admin', 'REMOVE_MEMBER', ['admin', 'me', 'bob'], target: 'eve'),
      // Cikarmayi henuz islememis yoneticinin her mesajla gelen CREATE'i.
      control('admin', 'CREATE', ['admin', 'me', 'bob', 'eve']),
    ]);
    expect(await members(), isNot(contains('eve')));

    // Acik bir ekleme ise geri alir.
    await deliver([
      control('admin', 'ADD_MEMBER', [
        'admin',
        'me',
        'bob',
        'eve',
      ], target: 'eve'),
    ]);
    expect(await members(), contains('eve'));
    await deliver([
      control('admin', 'CREATE', ['admin', 'me', 'bob', 'eve', 'new']),
    ]);
    expect(await members(), containsAll(['eve', 'new']));
  });
}

class _CountingGroupCrypto extends LocalAeadCryptoService
    implements GroupCryptoService {
  _CountingGroupCrypto() : super(SecretKey(List<int>.filled(32, 4)));

  final resets = <String>[];

  @override
  Future<void> resetLocalSenderKey(String groupId, String senderId) async =>
      resets.add('$groupId:$senderId');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
