import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/auth/phone_privacy.dart';
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
      deviceContacts: const _FakeGateway([
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
      deviceContacts: const _FakeGateway([]),
      api: _FakeDiscoveryApi(const []),
      database: fixture.database,
      session: SessionStore(userId: 'me', accessToken: 'access'),
    );

    await service.importAndDiscover();
    expect(await fixture.database.contacts.getById('stale'), isNull);
  });

  test('permission denial stops discovery before API call', () async {
    final fixture = await _openFixture();
    addTearDown(fixture.close);
    final api = _FakeDiscoveryApi(const []);
    final service = ContactService(
      deviceContacts: const _FakeGateway([], permitted: false),
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
        deviceContacts: const _FakeGateway([
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
    final service = ContactService(
      deviceContacts: const _FakeGateway([]),
      api: _FakeDiscoveryApi(const []),
      database: fixture.database,
      session: SessionStore(userId: 'me', accessToken: 'access'),
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
  });
}

class _FakeGateway implements DeviceContactsGateway {
  const _FakeGateway(this.contacts, {this.permitted = true});

  final List<DeviceContact> contacts;
  final bool permitted;

  @override
  Future<List<DeviceContact>> getAllContacts() async => contacts;

  @override
  Future<bool> requestPermission() async => permitted;
}

class _FakeDiscoveryApi implements ContactDiscoveryApi {
  _FakeDiscoveryApi(this.matches);

  final List<RegisteredUserMatch> matches;
  List<String> receivedHashes = const [];

  @override
  Future<List<RegisteredUserMatch>> checkUsers(
    List<String> hashes,
    String accessToken, {
    String? ownPhoneHash,
    String? ownUserId,
  }) async {
    receivedHashes = List.of(hashes);
    return matches;
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
