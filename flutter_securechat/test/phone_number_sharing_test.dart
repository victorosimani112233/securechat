import 'dart:async';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/auth/phone_privacy.dart';
import 'package:flutter_securechat/src/contacts/contact_service.dart';
import 'package:flutter_securechat/src/contacts/phone_number_sharing_service.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/domain/send_message_use_case.dart';
import 'package:flutter_securechat/src/incoming/incoming_message_handler.dart';
import 'package:flutter_securechat/src/media/file_transfer_manager.dart';
import 'package:flutter_securechat/src/media/media_attachment.dart';
import 'package:flutter_securechat/src/media/media_message_service.dart';
import 'package:flutter_securechat/src/media/voice_note_service.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/private_chat_control_support.dart';
import 'support/storage_at_rest.dart';

const _phone = '+905551234567';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final voice in [false, true]) {
    for (final mode in ['disabled', 'direct', 'group']) {
      test(
        '${voice ? 'voice' : 'file'} send respects $mode phone consent',
        () async {
          final f = await _Fixture.open();
          addTearDown(f.close);
          f.session.sharePhoneNumber = mode != 'disabled';
          final transfers = FileTransferManager(
            signaling: f.socket,
            crypto: f.crypto,
            filesDirectory: Directory('${f.root.path}/media'),
          );
          addTearDown(transfers.dispose);
          final media = MediaMessageService(
            database: f.db,
            transfers: transfers,
            session: f.session,
            localMediaDirectory: Directory('${f.root.path}/media'),
            phoneSharing: f.sharing,
          );
          addTearDown(media.close);
          final source = File('${f.root.path}/sample.${voice ? 'm4a' : 'pdf'}');
          await source.writeAsBytes([1, 2, 3, 4]);
          final result = await media.send(
            conversationId: mode == 'group' ? 'group' : 'peer',
            recipientId: mode == 'group' ? 'group' : 'peer',
            attachments: [await MediaAttachment.fromPath(source.path)],
            isGroup: mode == 'group',
            groupMembers: const ['me', 'peer'],
            voiceNote: voice
                ? const VoiceNoteMetadata(
                    duration: Duration(seconds: 2),
                    waveform: [0.1, 0.3],
                  )
                : null,
          );
          expect(result.single.result, isA<FileTransferSuccess>());
          final controls = f.socket.sentMessages
              .whereType<EncryptedSignalMessage>();
          expect(controls, hasLength(mode == 'direct' ? 1 : 0));
          if (mode == 'direct') {
            expect(
              await decryptTestPrivateChatControl(
                crypto: f.crypto,
                wire: controls.single,
              ),
              isA<SharedPhoneSignal>(),
            );
          }
          for (final wire in f.socket.sentMessages) {
            expect(wire.encode(), isNot(contains(_phone)));
          }
        },
      );
    }
  }

  test(
    'disabled sharing never creates a phone control; opt-out stops new sends',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      expect(await f.sharing.shareWith('peer'), isFalse);
      expect(f.socket.sentMessages, isEmpty);
      f.session.sharePhoneNumber = true;
      expect(await f.sharing.shareWith('peer'), isTrue);
      f.session.sharePhoneNumber = false;
      expect(await f.sharing.shareWith('peer'), isFalse);
      expect(f.socket.sentMessages, hasLength(1));
      expect(f.directory.calls, isEmpty);
    },
  );

  test('phone is only inside recipient-encrypted padded control', () async {
    final f = await _Fixture.open();
    addTearDown(f.close);
    f.session.sharePhoneNumber = true;
    await f.sharing.shareWith('peer');
    final wire = f.socket.sentMessages.single as EncryptedSignalMessage;
    expect(wire.recipientId, 'peer');
    expect(wire.type, 'encrypted_message');
    expect(wire.encode(), isNot(contains(_phone)));
    expect(wire.encode(), isNot(contains('shared_phone')));
    expect(wire.encode(), isNot(contains('phoneNumber')));
    final decoded =
        await decryptTestPrivateChatControl(crypto: f.crypto, wire: wire)
            as SharedPhoneSignal;
    expect(decoded.phoneNumber, _phone);
    expect(decoded.senderId, 'me');
    expect(decoded.recipientId, 'peer');
    await expectLater(
      f.crypto.decryptDirect(
        senderId: 'other-recipient',
        envelope: wire.envelope,
      ),
      throwsA(anything),
    );
  });

  test('disabled preference wins when changed during encryption', () async {
    final f = await _Fixture.open();
    addTearDown(f.close);
    final crypto = _PausedCrypto(_key);
    final sharing = f.service(crypto: crypto);
    f.session.sharePhoneNumber = true;
    final sending = sharing.shareWith('peer');
    await crypto.entered.future;
    f.session.sharePhoneNumber = false;
    crypto.release.complete();
    expect(await sending, isFalse);
    expect(f.socket.sentMessages, isEmpty);
  });

  test('account switch during encryption cancels the old disclosure', () async {
    final f = await _Fixture.open();
    addTearDown(f.close);
    final crypto = _PausedCrypto(_key);
    f.session.sharePhoneNumber = true;
    final sending = f.service(crypto: crypto).shareWith('peer');
    await crypto.entered.future;
    f.session.userId = 'other-account';
    crypto.release.complete();
    expect(await sending, isFalse);
    expect(f.socket.sentMessages, isEmpty);
  });

  test(
    'direct messages introduce opted-in phone without changing message body',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      f.session.sharePhoneNumber = true;
      final sender = SendMessageUseCase(
        database: f.db,
        signaling: f.socket,
        session: f.session,
        crypto: f.crypto,
        phoneSharing: f.sharing,
      );
      expect(
        await sender(
          const SendMessageRequest(conversationId: 'peer', content: 'hello'),
        ),
        SendMessageOutcome.sent,
      );
      final wires = f.socket.sentMessages
          .whereType<EncryptedSignalMessage>()
          .toList();
      expect(wires, hasLength(2));
      expect(
        await decryptTestPrivateChatControl(
          crypto: f.crypto,
          wire: wires.first,
        ),
        isA<SharedPhoneSignal>(),
      );
      final content = await f.crypto.decryptDirect(
        senderId: 'peer',
        envelope: wires.last.envelope,
      );
      expect(content, startsWith('MSGID:'));
      expect(content, endsWith(':hello'));
      expect(content, isNot(contains(_phone)));
      expect(
        (await f.db.messages.getMessagesImmediate('peer')).single.content,
        'hello',
      );
    },
  );

  test('groups and self never receive phone introductions', () async {
    final f = await _Fixture.open();
    addTearDown(f.close);
    f.session.sharePhoneNumber = true;
    await f.db.conversations.insert(
      const ConversationEntity(
        id: 'group',
        peerId: 'group',
        peerName: 'Team',
        peerPhone: '',
        isGroup: true,
        groupMembers: 'me,peer',
        groupAdmins: 'me',
      ),
    );
    expect(await f.sharing.shareWith('group'), isFalse);
    expect(await f.sharing.shareWith('me'), isFalse);
    final sender = SendMessageUseCase(
      database: f.db,
      signaling: f.socket,
      session: f.session,
      crypto: f.crypto,
      phoneSharing: f.sharing,
    );
    expect(
      await sender(
        const SendMessageRequest(
          conversationId: 'group',
          content: 'group message',
        ),
      ),
      SendMessageOutcome.sent,
    );
    for (final wire
        in f.socket.sentMessages.whereType<EncryptedSignalMessage>()) {
      final payload = await f.crypto.decryptDirect(
        senderId: wire.recipientId,
        envelope: wire.envelope,
      );
      expect(payload, isNot(contains('CHATCTRL:v2:')));
      expect(payload, isNot(contains(_phone)));
    }
  });

  test(
    'authenticated introduction verifies directory and updates UUID without phantom messages',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      await f.seedPeer(locked: true);
      expect(await f.sharing.accept(_claim()), isTrue);
      final conversation = (await f.db.conversations.getById('peer'))!;
      expect(conversation.peerName, _phone);
      expect(conversation.peerPhone, _phone);
      expect(conversation.isLocked, isTrue);
      expect(conversation.lastMessage, 'existing');
      expect(conversation.unreadCount, 3);
      expect(await f.db.contacts.getById('peer'), isNull);
      expect(await f.db.messages.getMessageCount('peer'), 0);
      final atRest = await storageAtRest(File('${f.root.path}/db'));
      expect(atRest, isNotEmpty);
      expect(atRest, isNot(contains(_phone)));
      final reopened = await SecureChatDatabase.open(
        file: File('${f.root.path}/db'),
        crypto: f.crypto,
      );
      expect((await reopened.conversations.getById('peer'))!.peerPhone, _phone);
      await reopened.close();
      expect(f.directory.calls.single, [await hashPhoneNumber(_phone)]);
      expect(f.socket.sentMessages, isEmpty);
      expect(
        (await ContactIdentityResolver(
          database: f.db,
        ).resolve('peer')).displayName,
        _phone,
      );
      await f.sharing.accept(_claim());
      expect(
        f.directory.calls,
        hasLength(1),
        reason: 'Verified local association avoids repeated lookup',
      );
    },
  );

  test(
    'saved contact name has priority over shared phone and other claims',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      await f.seedPeer();
      await f.db.contacts.insert(
        ContactEntity(
          id: 'peer',
          phoneNumber: _phone,
          phoneHash: await hashPhoneNumber(_phone),
          displayName: 'Local name',
          isRegistered: true,
        ),
      );
      expect(await f.sharing.accept(_claim()), isTrue);
      expect(
        (await f.db.conversations.getById('peer'))!.peerName,
        'Local name',
      );
      expect(f.directory.calls, isEmpty);
      f.directory.owner = 'someone-else';
      expect(await f.sharing.accept(_claim(phone: '+905550009999')), isFalse);
      expect(
        (await f.db.conversations.getById('peer'))!.peerName,
        'Local name',
      );
      expect((await f.db.conversations.getById('peer'))!.peerPhone, _phone);
    },
  );

  test('wrong account or hash cannot claim a phone number', () async {
    final f = await _Fixture.open();
    addTearDown(f.close);
    f.directory.owner = 'victim';
    expect(await f.sharing.accept(_claim()), isFalse);
    expect(await f.db.conversations.getById('peer'), isNull);
    f.now = f.now.add(const Duration(minutes: 2));
    f.directory.owner = 'peer';
    f.directory.wrongHash = true;
    expect(await f.sharing.accept(_claim()), isFalse);
    expect(await f.db.conversations.getById('peer'), isNull);
  });

  test(
    'malformed and misaddressed claims are rejected before network access',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      for (final phone in [
        '',
        'me@example.test',
        '+90555<script>',
        '+123',
        '+000000000',
        '+1234567890123456',
        '+905551234567\n',
      ]) {
        expect(
          await f.sharing.accept(_claim(phone: phone)),
          isFalse,
          reason: phone,
        );
      }
      expect(await f.sharing.accept(_claim(recipient: 'other')), isFalse);
      expect(await f.sharing.accept(_claim(sender: 'me')), isFalse);
      expect(f.directory.calls, isEmpty);
    },
  );

  test(
    'plain signaling cannot introduce a phone and encrypted controls remain silent',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      f.socket.addIncoming(_claim());
      await f.handler.waitForIdle();
      expect(f.directory.calls, isEmpty);
      expect(await f.db.conversations.getById('peer'), isNull);
      final events = <IncomingMessageEvent>[];
      final sub = f.handler.acceptedMessages.listen(events.add);
      addTearDown(sub.cancel);
      f.socket.addIncoming(
        await encryptTestPrivateChatControl(
          crypto: f.crypto,
          control: _claim(),
        ),
      );
      await f.handler.waitForIdle();
      expect((await f.db.conversations.getById('peer'))!.peerPhone, _phone);
      expect(events, isEmpty);
      expect(
        f.socket.sentMessages,
        isEmpty,
        reason: 'Receiving a number never discloses ours',
      );
      f.socket.addIncoming(
        EncryptedSignalMessage(
          senderId: 'peer',
          recipientId: 'me',
          timestamp: DateTime.now(),
          envelope: await f.crypto.encryptDirect(
            recipientId: 'me',
            plaintext: 'MSGID:one:hello',
          ),
        ),
      );
      await f.handler.waitForIdle();
      expect(events.single.title, _phone);
    },
  );

  test(
    'directory outage fails closed without blocking the following message',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      f.directory.failure = StateError('sensitive $_phone');
      f.socket.addIncoming(
        await encryptTestPrivateChatControl(
          crypto: f.crypto,
          control: _claim(),
        ),
      );
      f.socket.addIncoming(
        EncryptedSignalMessage(
          senderId: 'peer',
          recipientId: 'me',
          timestamp: DateTime.now(),
          envelope: await f.crypto.encryptDirect(
            recipientId: 'me',
            plaintext: 'MSGID:two:still delivered',
          ),
        ),
      );
      await f.handler.waitForIdle();
      expect((await f.db.messages.getById('two'))!.content, 'still delivered');
      expect((await f.db.conversations.getById('peer'))!.peerPhone, isEmpty);
      expect(f.failures.single, isNot(contains(_phone)));
    },
  );

  test(
    'untrusted claims have bounded per-peer and total lookup budgets',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      f.directory.owner = 'nobody';
      for (var i = 0; i < 40; i++) {
        await f.sharing.accept(_claim(sender: 'peer-$i'));
      }
      expect(f.directory.calls, hasLength(20));
      await f.sharing.accept(_claim(sender: 'peer-0', phone: '+905550009999'));
      expect(f.directory.calls, hasLength(20));
      f.now = f.now.add(const Duration(minutes: 2));
      await f.sharing.accept(_claim(sender: 'peer-0'));
      expect(f.directory.calls, hasLength(21));
    },
  );
}

SharedPhoneSignal _claim({
  String sender = 'peer',
  String recipient = 'me',
  String phone = _phone,
}) => SharedPhoneSignal(
  senderId: sender,
  recipientId: recipient,
  timestamp: DateTime.now(),
  phoneNumber: phone,
);

final _key = SecretKey(List<int>.generate(32, (index) => index + 1));

class _Directory implements ContactDiscoveryApi {
  String owner = 'peer';
  bool wrongHash = false;
  Object? failure;
  final calls = <List<String>>[];

  @override
  Future<List<RegisteredUserMatch>> checkUsers(
    List<String> hashes,
    String token, {
    String? ownPhoneHash,
    String? ownUserId,
  }) async {
    calls.add(hashes);
    if (failure != null) throw failure!;
    return [
      RegisteredUserMatch(
        userId: owner,
        phoneHash: wrongHash ? 'wrong' : hashes.single,
      ),
    ];
  }
}

class _PausedCrypto extends LocalAeadCryptoService {
  _PausedCrypto(super.key);
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<String> encryptDirect({
    required String recipientId,
    required String plaintext,
  }) async {
    entered.complete();
    await release.future;
    return super.encryptDirect(recipientId: recipientId, plaintext: plaintext);
  }
}

class _Fixture {
  _Fixture(this.root, this.db);
  final Directory root;
  final SecureChatDatabase db;
  final crypto = LocalAeadCryptoService(_key);
  final socket = InMemorySignalingService();
  final session = SessionStore(
    userId: 'me',
    phoneNumber: _phone,
    accessToken: 'token',
  );
  final directory = _Directory();
  final failures = <String>[];
  DateTime now = DateTime.now();
  late final PhoneNumberSharingService sharing;
  late final IncomingMessageHandler handler;

  PhoneNumberSharingService service({CryptoService? crypto}) =>
      PhoneNumberSharingService(
        session: session,
        crypto: crypto ?? this.crypto,
        signaling: socket,
        database: db,
        discovery: directory,
        now: () => now,
        onAsyncFailure: (op, error, stack) async => failures.add('$op: $error'),
      );

  static Future<_Fixture> open() async {
    final root = await Directory.systemTemp.createTemp('phone_sharing_test_');
    final db = await SecureChatDatabase.open(
      file: File('${root.path}/db'),
      crypto: LocalAeadCryptoService(_key),
    );
    final f = _Fixture(root, db);
    await f.socket.connect(
      userId: 'me',
      url: 'wss://test.invalid',
      accessToken: 'token',
    );
    f.sharing = f.service();
    f.handler = IncomingMessageHandler(
      signaling: f.socket,
      crypto: f.crypto,
      database: db,
      session: f.session,
      identityResolver: ContactIdentityResolver(database: db),
      phoneSharing: f.sharing,
    )..start();
    return f;
  }

  Future<void> seedPeer({bool locked = false}) => db.conversations.insert(
    ConversationEntity(
      id: 'peer',
      peerId: 'peer',
      peerName: 'peer',
      peerPhone: '',
      isLocked: locked,
      unreadCount: 3,
      lastMessage: 'existing',
    ),
  );

  Future<void> close() async {
    await handler.close();
    await socket.disconnect();
    await db.close();
    await root.delete(recursive: true);
  }
}
