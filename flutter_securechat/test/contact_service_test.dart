import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/auth/phone_privacy.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/groups/private_group_control.dart';
import 'package:flutter_securechat/src/network/network_resilience.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/contacts/contact_service.dart';
import 'package:flutter_securechat/src/contacts/private_contact_discovery.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('local contact boundary persists private-directory matches', () async {
    final fixture = await _openFixture();
    addTearDown(fixture.close);
    final aliceHash = await hashPhoneNumber('05551234567');
    final api = _FakeDiscoveryApi([
      RegisteredUserMatch(userId: 'alice-id', phoneHash: aliceHash),
    ]);
    final service = ContactService(
      deviceContacts: _FakeGateway(const [
        DeviceContact(displayName: 'Alice', phoneNumber: '0555 123 45 67'),
        DeviceContact(displayName: 'Bob', phoneNumber: '0532 000 00 00'),
      ]),
      api: api,
      database: fixture.database,
      session: SessionStore(userId: 'me', accessToken: 'access'),
    );

    final result = await service.importAndDiscover();

    expect(result.single.id, 'alice-id');
    expect(api.receivedHashes, hasLength(2));
    expect(api.receivedHashes.join(), isNot(contains('05551234567')));
    expect(await fixture.database.contacts.getRegisteredCount(), 1);
  });

  // QA 2026-10-13 O5: kurtarmadan sonra girilen numara yalniz okunur;
  // checkUsers ownPhoneHash almadigi icin dizin kaydi degismez.
  test('own phone status reads the directory without claiming it', () async {
    final fixture = await _openFixture();
    addTearDown(fixture.close);
    final mine = await hashPhoneNumber('+905551234567');
    final theirs = await hashPhoneNumber('+905320000000');
    final api = _FakeDiscoveryApi([
      RegisteredUserMatch(userId: 'me', phoneHash: mine),
      RegisteredUserMatch(userId: 'other', phoneHash: theirs),
    ]);
    final service = ContactService(
      deviceContacts: _FakeGateway(const []),
      api: api,
      database: fixture.database,
      session: SessionStore(userId: 'me', accessToken: 'access'),
    );

    expect(
      await service.ownPhoneStatus('+905551234567'),
      OwnPhoneStatus.matches,
    );
    expect(api.receivedHashes, [mine]);
    expect(api.receivedOwnHash, isNull);
    expect(
      await service.ownPhoneStatus('+905320000000'),
      OwnPhoneStatus.otherAccount,
    );
    expect(
      await service.ownPhoneStatus('+905449999999'),
      OwnPhoneStatus.notRegistered,
    );
  });

  test('contact sync removes entries no longer present on device', () async {
    final fixture = await _openFixture();
    addTearDown(fixture.close);
    await fixture.database.contacts.insert(
      const ContactEntity(
        id: 'stale',
        phoneNumber: '+90111',
        phoneHash: 'stale-hash',
        displayName: 'Stale',
        isRegistered: true,
      ),
    );
    final service = ContactService(
      deviceContacts: _FakeGateway(const []),
      api: _FakeDiscoveryApi(const []),
      database: fixture.database,
      session: SessionStore(userId: 'me', accessToken: 'access'),
    );

    await service.importAndDiscover();
    expect(await fixture.database.contacts.getById('stale'), isNull);
  });

  group('QA 2026-10-12 Bulgu 6', () {
    test('a contact added by number survives the phonebook sync', () async {
      final fixture = await _openFixture();
      addTearDown(fixture.close);
      final betaHash = await hashPhoneNumber('905321000413');
      final service = ContactService(
        deviceContacts: _FakeGateway(const []),
        api: _FakeDiscoveryApi([
          RegisteredUserMatch(userId: 'beta-id', phoneHash: betaHash),
        ]),
        database: fixture.database,
        session: SessionStore(userId: 'me', accessToken: 'access'),
      );

      final manual = await service.resolvePhone('+90 532 100 04 13');
      expect(manual!.addedManually, isTrue);
      await service.importAndDiscover();

      expect(await fixture.database.contacts.getById('beta-id'), isNotNull);
    });

    test(
      'a phonebook contact with an open chat is kept as manual on removal',
      () async {
        final fixture = await _openFixture();
        addTearDown(fixture.close);
        await fixture.database.contacts.insert(
          const ContactEntity(
            id: 'friend',
            phoneNumber: '+90222',
            phoneHash: 'friend-hash',
            displayName: 'Friend',
            isRegistered: true,
          ),
        );
        await fixture.database.conversations.insert(
          const ConversationEntity(
            id: 'friend',
            peerId: 'friend',
            peerName: 'Friend',
            peerPhone: '+90222',
          ),
        );
        final service = ContactService(
          deviceContacts: _FakeGateway(const []),
          api: _FakeDiscoveryApi(const []),
          database: fixture.database,
          session: SessionStore(userId: 'me', accessToken: 'access'),
        );

        await service.importAndDiscover();

        final kept = await fixture.database.contacts.getById('friend');
        expect(kept?.displayName, 'Friend');
        expect(kept?.addedManually, isTrue);
      },
    );

    test('adding a known phonebook contact by number keeps its name', () async {
      final fixture = await _openFixture();
      addTearDown(fixture.close);
      final hash = await hashPhoneNumber('905321000413');
      await fixture.database.contacts.insert(
        ContactEntity(
          id: 'beta-id',
          phoneNumber: '+90 532 100 04 13',
          phoneHash: hash,
          displayName: 'QaBeta',
          isRegistered: true,
        ),
      );
      final service = ContactService(
        deviceContacts: _FakeGateway(const []),
        api: _FakeDiscoveryApi([
          RegisteredUserMatch(userId: 'beta-id', phoneHash: hash),
        ]),
        database: fixture.database,
        session: SessionStore(userId: 'me', accessToken: 'access'),
      );

      final contact = await service.resolvePhone('5321000413');

      expect(contact?.displayName, 'QaBeta');
      expect(
        (await fixture.database.contacts.getById('beta-id'))?.displayName,
        'QaBeta',
      );
    });

    test(
      'group candidates include direct chat peers outside the phonebook',
      () async {
        final fixture = await _openFixture();
        addTearDown(fixture.close);
        await fixture.database.contacts.insert(
          const ContactEntity(
            id: 'alice',
            phoneNumber: '+901',
            phoneHash: 'a',
            displayName: 'Alice',
            isRegistered: true,
          ),
        );
        for (final conversation in const [
          ConversationEntity(
            id: 'alice',
            peerId: 'alice',
            peerName: 'Alice (chat)',
            peerPhone: '+901',
          ),
          ConversationEntity(
            id: 'beta',
            peerId: 'beta',
            peerName: 'QaBeta',
            peerPhone: '+905321000413',
          ),
          ConversationEntity(
            id: 'group',
            peerId: 'group',
            peerName: 'Group',
            peerPhone: '',
            isGroup: true,
          ),
        ]) {
          await fixture.database.conversations.insert(conversation);
        }
        final service = ContactService(
          deviceContacts: _FakeGateway(const []),
          api: _FakeDiscoveryApi(const []),
          database: fixture.database,
          session: SessionStore(userId: 'me', accessToken: 'access'),
        );

        final candidates = await service.watchGroupCandidates().first;

        expect(candidates.map((c) => (c.id, c.displayName)), [
          ('alice', 'Alice'),
          ('beta', 'QaBeta'),
        ]);
      },
    );
  });

  // Kullanici istegi 2026-10-14: rehberde olmayan kisi rehbere eklenebilir.
  test(
    'add to device contacts offers the shared name without the tilde',
    () async {
      final fixture = await _openFixture();
      addTearDown(fixture.close);
      final gateway = _FakeGateway(const []);
      final service = ContactService(
        deviceContacts: gateway,
        api: _FakeDiscoveryApi(const []),
        database: fixture.database,
        session: SessionStore(userId: 'me', accessToken: 'access'),
      );

      expect(
        await service.openAddToDeviceContacts(
          phone: ' +905551112233 ',
          sharedName: '~Ayse',
        ),
        isTrue,
      );
      expect(
        await service.openAddToDeviceContacts(
          phone: '+905551112244',
          sharedName: '+905551112244',
        ),
        isTrue,
      );
      // Numara yoksa eklenecek bir sey yok; sistem ekrani acilmaz.
      expect(await service.openAddToDeviceContacts(phone: ' '), isFalse);
      expect(gateway.added, [('+905551112233', 'Ayse'), ('+905551112244', '')]);
    },
  );

  test('permission denial stops discovery before API call', () async {
    final fixture = await _openFixture();
    addTearDown(fixture.close);
    final api = _FakeDiscoveryApi(const []);
    final service = ContactService(
      deviceContacts: _FakeGateway(const [], permitted: false),
      api: api,
      database: fixture.database,
      session: SessionStore(userId: 'me', accessToken: 'access'),
    );

    expect(service.importAndDiscover, throwsStateError);
    expect(api.receivedHashes, isEmpty);
  });

  test(
    'private-directory outage preserves cached device-only matches',
    () async {
      final fixture = await _openFixture();
      addTearDown(fixture.close);
      await fixture.database.contacts.insert(
        const ContactEntity(
          id: 'cached-user',
          phoneNumber: '+905551234567',
          phoneHash: 'cached-hash',
          displayName: 'Cached contact',
          isRegistered: true,
        ),
      );
      final service = ContactService(
        deviceContacts: _FakeGateway(const [
          DeviceContact(
            displayName: 'Cached contact',
            phoneNumber: '+905551234567',
          ),
        ]),
        api: const _UnavailableDiscoveryApi(),
        database: fixture.database,
        session: SessionStore(userId: 'me', accessToken: 'access'),
      );

      await expectLater(
        service.importAndDiscover(),
        throwsA(isA<DirectoryServiceUnavailableException>()),
      );
      expect(await fixture.database.contacts.getById('cached-user'), isNotNull);
      expect(await fixture.database.contacts.getRegisteredCount(), 1);
    },
  );

  test('group creation persists membership and local admin', () async {
    final fixture = await _openFixture();
    addTearDown(fixture.close);
    final signaling = InMemorySignalingService()..setConnected(true);
    final crypto = LocalAeadCryptoService(SecretKey(List.filled(32, 7)));
    final queue = OfflineMessageQueue(
      database: fixture.database,
      signaling: signaling,
    );
    addTearDown(() async {
      await queue.close();
      await signaling.dispose();
    });
    final service = ContactService(
      deviceContacts: _FakeGateway(const []),
      api: _FakeDiscoveryApi(const []),
      database: fixture.database,
      session: SessionStore(userId: 'me', accessToken: 'access'),
      groupControls: PrivateGroupControlSender(
        crypto: crypto,
        signaling: signaling,
      ),
      offlineQueue: queue,
    );
    const contact = ContactEntity(
      id: 'alice',
      phoneNumber: '+90',
      phoneHash: 'hash',
      displayName: 'Alice',
      isRegistered: true,
    );

    final group = await service.createGroup('Team', [contact]);

    expect(group.isGroup, isTrue);
    expect(group.groupMembers, 'me,alice');
    expect(group.groupAdmins, 'me');
    expect(await fixture.database.conversations.getById(group.id), isNotNull);
    final invite = signaling.sentMessages
        .whereType<EncryptedSignalMessage>()
        .single;
    final decoded = await decodePrivateGroupControl(
      plaintext: await crypto.decryptDirect(
        senderId: 'alice',
        envelope: invite.envelope,
      ),
      authenticatedSenderId: 'me',
      localRecipientId: 'alice',
    );
    expect(decoded.action, 'CREATE');
    expect(decoded.groupId, group.id);
    expect(decoded.groupMembers, ['me', 'alice']);
    expect(invite.encode(), isNot(contains('Team')));
    expect(await queue.getPendingCount(), 0);

    signaling.setConnected(false);
    final offline = await service.createGroup('Offline', [contact]);
    expect(await fixture.database.conversations.getById(offline.id), isNotNull);
    expect(await queue.getPendingCount(), 1);
    signaling.setConnected(true);
    await queue.flushEnqueuedSignals();
    expect(await queue.getPendingCount(), 0);
    expect(
      signaling.sentMessages.whereType<EncryptedSignalMessage>(),
      hasLength(2),
    );
  });

  test(
    'group creation skips members without keys and keeps the rest',
    () async {
      final fixture = await _openFixture();
      addTearDown(fixture.close);
      final signaling = InMemorySignalingService()..setConnected(true);
      final local = LocalAeadCryptoService(SecretKey(List.filled(32, 7)));
      final crypto = _UnreachableCrypto(local, {'stale'});
      final queue = OfflineMessageQueue(
        database: fixture.database,
        signaling: signaling,
      );
      addTearDown(() async {
        await queue.close();
        await signaling.dispose();
      });
      final service = ContactService(
        deviceContacts: _FakeGateway(const []),
        api: _FakeDiscoveryApi(const []),
        database: fixture.database,
        session: SessionStore(userId: 'me', accessToken: 'access'),
        groupControls: PrivateGroupControlSender(
          crypto: crypto,
          signaling: signaling,
        ),
        offlineQueue: queue,
      );
      const alice = ContactEntity(
        id: 'alice',
        phoneNumber: '+90',
        phoneHash: 'hash',
        displayName: 'Alice',
        isRegistered: true,
      );
      const stale = ContactEntity(
        id: 'stale',
        phoneNumber: '+91',
        phoneHash: 'hash-2',
        displayName: 'Eski',
        isRegistered: true,
      );

      List<ContactEntity>? skipped;
      final group = await service.createGroup('Team', [
        alice,
        stale,
      ], onUnreachable: (members) => skipped = members);

      expect(skipped?.map((member) => member.id), ['stale']);
      expect(group.groupMembers, 'me,alice');
      final invite = signaling.sentMessages
          .whereType<EncryptedSignalMessage>()
          .single;
      expect(invite.recipientId, 'alice');
      final decoded = await decodePrivateGroupControl(
        plaintext: await local.decryptDirect(
          senderId: 'alice',
          envelope: invite.envelope,
        ),
        authenticatedSenderId: 'me',
        localRecipientId: 'alice',
      );
      // Davet edilen uye, atlanan kisiyi uye listesinde gormemeli.
      expect(decoded.groupMembers, ['me', 'alice']);

      await expectLater(
        service.createGroup('Solo', [stale]),
        throwsA(isA<GroupMembersUnreachableException>()),
      );
      expect(
        (await fixture.database.conversations.getAllImmediate()).where(
          (conversation) => conversation.peerName == 'Solo',
        ),
        isEmpty,
      );
    },
  );

  test('opening a contact preserves the existing chat lock', () async {
    final fixture = await _openFixture();
    addTearDown(fixture.close);
    await fixture.database.conversations.insert(
      const ConversationEntity(
        id: 'alice',
        peerId: 'alice',
        peerName: 'Alice',
        peerPhone: '+90',
        isLocked: true,
      ),
    );
    final service = ContactService(
      deviceContacts: _FakeGateway(const []),
      api: _FakeDiscoveryApi(const []),
      database: fixture.database,
      session: SessionStore(userId: 'me', accessToken: 'access'),
    );

    final conversation = await service.ensureConversation(
      const ContactEntity(
        id: 'alice',
        phoneNumber: '+90',
        phoneHash: 'hash',
        displayName: 'Alice',
        isRegistered: true,
      ),
    );

    expect(conversation.isLocked, isTrue);
  });
}

class _UnreachableCrypto implements CryptoService {
  _UnreachableCrypto(this._inner, this._unreachable);

  final CryptoService _inner;
  final Set<String> _unreachable;

  @override
  Future<String> encryptDirect({
    required String recipientId,
    required String plaintext,
  }) {
    if (_unreachable.contains(recipientId)) {
      throw StateError('prekey bundle unavailable');
    }
    return _inner.encryptDirect(recipientId: recipientId, plaintext: plaintext);
  }

  @override
  Future<String> decryptDirect({
    required String senderId,
    required String envelope,
  }) => _inner.decryptDirect(senderId: senderId, envelope: envelope);

  @override
  Future<String> encryptGroup({
    required String senderId,
    required String groupId,
    required String plaintext,
  }) => _inner.encryptGroup(
    senderId: senderId,
    groupId: groupId,
    plaintext: plaintext,
  );

  @override
  Future<String> decryptGroup({
    required String senderId,
    required String groupId,
    required String envelope,
  }) => _inner.decryptGroup(
    senderId: senderId,
    groupId: groupId,
    envelope: envelope,
  );
}

class _FakeGateway implements DeviceContactsGateway {
  _FakeGateway(this.contacts, {this.permitted = true});

  final List<DeviceContact> contacts;
  final bool permitted;
  final added = <(String, String)>[];

  @override
  Future<bool> openAddContact({required String phone, String name = ''}) async {
    added.add((phone, name));
    return true;
  }

  @override
  Future<List<DeviceContact>> getAllContacts() async => contacts;

  @override
  Future<bool> requestPermission() async => permitted;
}

class _FakeDiscoveryApi implements ContactDiscoveryApi {
  _FakeDiscoveryApi(this.matches);

  final List<RegisteredUserMatch> matches;
  List<String> receivedHashes = const [];
  String? receivedOwnHash;

  @override
  Future<List<RegisteredUserMatch>> checkUsers(
    List<String> hashes,
    String accessToken, {
    String? ownPhoneHash,
    String? ownUserId,
  }) async {
    receivedHashes = List.of(hashes);
    receivedOwnHash = ownPhoneHash;
    return matches.where((m) => hashes.contains(m.phoneHash)).toList();
  }
}

class _UnavailableDiscoveryApi implements ContactDiscoveryApi {
  const _UnavailableDiscoveryApi();

  @override
  Future<List<RegisteredUserMatch>> checkUsers(
    List<String> phoneHashes,
    String accessToken, {
    String? ownPhoneHash,
    String? ownUserId,
  }) => throw const DirectoryServiceUnavailableException(statusCode: 404);
}

Future<_Fixture> _openFixture() async {
  final directory = await Directory.systemTemp.createTemp(
    'securechat_contacts_',
  );
  final database = await SecureChatDatabase.open(
    file: File('${directory.path}/storage.securejson'),
    crypto: LocalAeadCryptoService(
      SecretKey(List<int>.generate(32, (index) => index + 1)),
    ),
  );
  return _Fixture(directory, database);
}

class _Fixture {
  const _Fixture(this.directory, this.database);

  final Directory directory;
  final SecureChatDatabase database;

  Future<void> close() async {
    await database.close();
    await directory.delete(recursive: true);
  }
}
