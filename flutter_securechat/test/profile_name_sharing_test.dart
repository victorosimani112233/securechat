import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/contacts/profile_name_sharing_service.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/domain/send_message_use_case.dart';
import 'package:flutter_securechat/src/incoming/incoming_message_handler.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/private_chat_control_support.dart';

/// QA 2026-10-12 Bulgu 3, madde 2: rehberde olmayan biri ilk mesajda UUID
/// yerine gonderenin sectigi adi "~Ad" olarak gorur.
void main() {
  group('sanitize', () {
    test('strips control and direction characters and bounds length', () {
      expect(ProfileNameSharingService.sanitize(' Qa\u202EAlfa\n '), 'QaAlfa');
      expect(ProfileNameSharingService.sanitize('~~Qa  Alfa'), 'Qa Alfa');
      expect(
        ProfileNameSharingService.sanitize('x' * 60)!.length,
        ProfileNameSharingService.maxNameLength,
      );
    });

    test('rejects empty and id-shaped names', () {
      expect(ProfileNameSharingService.sanitize('   '), isNull);
      expect(ProfileNameSharingService.sanitize('~'), isNull);
      expect(
        ProfileNameSharingService.sanitize(
          '3b3663e9-3046-4ba9-acd6-dfdaf3fa510c',
        ),
        isNull,
      );
    });
  });

  group('sending', () {
    test('shares once per name and again after a rename', () async {
      final f = await _Fixture.open();
      addTearDown(f.close);

      expect(await f.names.shareWith('peer'), isTrue);
      expect(await f.names.shareWith('peer'), isFalse);
      f.session.displayName = 'QaAlfa Yeni';
      expect(await f.names.shareWith('peer'), isTrue);

      final controls = await f.sentControls();
      expect(
        controls.whereType<SharedProfileNameSignal>().map((c) => c.displayName),
        ['QaAlfa', 'QaAlfa Yeni'],
      );
    });

    test('a lost introduction is repeated after a week', () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      expect(await f.names.shareWith('peer'), isTrue);
      f.now = f.now.add(ProfileNameSharingService.resendAfter);
      expect(await f.names.shareWith('peer'), isTrue);
    });

    // QA 2026-10-13 T12: yeniden kurulan/kurtarilan karsi taraf adi 7 gun
    // boyunca hic gormuyordu.
    test('a peer with a new identity is introduced again at once', () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      Future<void> pin(int byte) => f.db.identities.insert(
        IdentityEntity(
          addressName: 'peer',
          identityKey: List.filled(64, byte),
          trustLevel: TrustLevel.trustedUnverified,
        ),
      );
      await pin(1);
      expect(await f.names.shareWith('peer'), isTrue);
      expect(await f.names.shareWith('peer'), isFalse);
      await f.db.identities.delete('peer');
      await pin(2);
      expect(await f.names.shareWith('peer'), isTrue);
    });

    test('a session reset from the peer forgets the introduction', () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      expect(await f.names.shareWith('peer'), isTrue);
      await f.names.forgetSentTo('peer');
      expect(await f.names.shareWith('peer'), isTrue);
    });

    test('nothing is shared when disabled or in a group', () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      await f.db.conversations.insert(
        const ConversationEntity(
          id: 'group',
          peerId: 'group',
          peerName: 'Team',
          peerPhone: '',
          isGroup: true,
        ),
      );
      expect(await f.names.shareWith('group'), isFalse);
      f.session.shareProfileName = false;
      expect(await f.names.shareWith('peer'), isFalse);
      expect(f.socket.sentMessages, isEmpty);
    });

    test('a direct text send introduces the sender first', () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      await f.db.conversations.insert(
        const ConversationEntity(
          id: 'peer',
          peerId: 'peer',
          peerName: 'Peer',
          peerPhone: '',
        ),
      );
      final sender = SendMessageUseCase(
        database: f.db,
        signaling: f.socket,
        session: f.session,
        crypto: f.crypto,
        profileNames: f.names,
        maxRetryCount: 0,
        retryDelay: Duration.zero,
      );

      await sender(
        const SendMessageRequest(conversationId: 'peer', content: 'merhaba'),
      );

      final controls = await f.sentControls();
      expect(controls.whereType<SharedProfileNameSignal>(), hasLength(1));
    });
  });

  group('receiving', () {
    test(
      'a stranger chat created after the introduction shows ~Name',
      () async {
        final f = await _Fixture.open();
        addTearDown(f.close);

        f.socket.addIncoming(
          await encryptTestPrivateChatControl(
            crypto: f.crypto,
            control: SharedProfileNameSignal(
              senderId: 'stranger',
              recipientId: 'me',
              timestamp: DateTime.now(),
              displayName: 'QaAlfa',
            ),
          ),
        );
        f.socket.addIncoming(
          EncryptedSignalMessage(
            senderId: 'stranger',
            recipientId: 'me',
            timestamp: DateTime.now(),
            envelope: await f.crypto.encryptDirect(
              recipientId: 'me',
              plaintext: 'MSGID:m1:merhaba',
            ),
          ),
        );
        await f.handler.waitForIdle();

        expect(
          (await f.db.conversations.getById('stranger'))?.peerName,
          '~QaAlfa',
        );
      },
    );

    test('an existing unnamed chat is relabelled', () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      await f.db.conversations.insert(
        const ConversationEntity(
          id: 'stranger',
          peerId: 'stranger',
          peerName: '',
          peerPhone: '',
        ),
      );

      expect(await f.names.accept(_signal('QaAlfa')), isTrue);

      expect(
        (await f.db.conversations.getById('stranger'))?.peerName,
        '~QaAlfa',
      );
    });

    test('a phonebook name always wins', () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      await f.db.contacts.insert(
        const ContactEntity(
          id: 'stranger',
          phoneNumber: '+905321000412',
          phoneHash: 'h',
          displayName: 'Alfa (rehber)',
          isRegistered: true,
        ),
      );
      await f.db.conversations.insert(
        const ConversationEntity(
          id: 'stranger',
          peerId: 'stranger',
          peerName: 'Alfa (rehber)',
          peerPhone: '+905321000412',
        ),
      );

      await f.names.accept(_signal('Sahte Ad'));

      expect(
        (await f.db.conversations.getById('stranger'))?.peerName,
        'Alfa (rehber)',
      );
    });

    // QA 2026-10-13 T2: tus takimindan numarayla acilan kisinin adi numara
    // oluyor ve paylasilan ad hic gorunmuyordu.
    test('a contact added only by number shows the shared name', () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      await f.db.contacts.insert(
        const ContactEntity(
          id: 'stranger',
          phoneNumber: '+905321000412',
          phoneHash: 'h',
          displayName: '+905321000412',
          isRegistered: true,
          addedManually: true,
        ),
      );
      await f.db.conversations.insert(
        const ConversationEntity(
          id: 'stranger',
          peerId: 'stranger',
          peerName: '+905321000412',
          peerPhone: '+905321000412',
        ),
      );

      await f.names.accept(_signal('Beta'));

      expect((await f.db.conversations.getById('stranger'))?.peerName, '~Beta');
    });
  });
}

SharedProfileNameSignal _signal(String name) => SharedProfileNameSignal(
  senderId: 'stranger',
  recipientId: 'me',
  timestamp: DateTime.now(),
  displayName: name,
);

final _key = SecretKey(List<int>.generate(32, (index) => index + 9));

class _Fixture {
  _Fixture(this.root, this.db);
  final Directory root;
  final SecureChatDatabase db;
  final crypto = LocalAeadCryptoService(_key);
  final socket = InMemorySignalingService();
  final session = SessionStore(
    userId: 'me',
    displayName: 'QaAlfa',
    accessToken: 'token',
  );
  DateTime now = DateTime(2026, 10, 12, 12);
  late final ProfileNameSharingService names;
  late final IncomingMessageHandler handler;

  static Future<_Fixture> open() async {
    final root = await Directory.systemTemp.createTemp('profile_name_test_');
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
    f.names = ProfileNameSharingService(
      session: f.session,
      crypto: f.crypto,
      signaling: f.socket,
      database: db,
      now: () => f.now,
    );
    f.handler = IncomingMessageHandler(
      signaling: f.socket,
      crypto: f.crypto,
      database: db,
      session: f.session,
      profileNames: f.names,
    )..start();
    return f;
  }

  Future<List<SignalMessage>> sentControls() async {
    final controls = <SignalMessage>[];
    for (final wire
        in socket.sentMessages.whereType<EncryptedSignalMessage>()) {
      try {
        controls.add(
          await decryptTestPrivateChatControl(crypto: crypto, wire: wire),
        );
      } on FormatException {
        // Mesajin kendisi, kontrol degil.
      }
    }
    return controls;
  }

  Future<void> close() async {
    await handler.close();
    await socket.disconnect();
    await db.close();
    await root.delete(recursive: true);
  }
}
