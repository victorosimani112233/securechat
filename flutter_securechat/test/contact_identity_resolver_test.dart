import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/contacts/contact_service.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';

/// Kisi kimligi cozumleme. Eskiden libsignal prekey sozlesme testleriyle
/// ayni dosyadaydi (`server_contract_parity_test`); prekey yolu kaldirilinca
/// yalniz bu testler kaldi.
void main() {
  test(
    'unknown identity remains opaque and never creates phone data',
    () async {
      final fixture = await _Fixture.open();
      addTearDown(fixture.close);
      final resolver = ContactIdentityResolver(database: fixture.database);

      final identity = await resolver.resolve('alice-id');

      expect(identity.displayName, 'alice-id');
      expect(identity.phoneNumber, isEmpty);
      expect(await fixture.database.contacts.getById('alice-id'), isNull);
    },
  );

  test('phone resolver preserves contact name and fails closed', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.close);
    await fixture.database.contacts.insert(
      const ContactEntity(
        id: 'known',
        phoneNumber: '+90 555 000 0000',
        phoneHash: 'hash',
        displayName: 'Alice',
        isRegistered: true,
      ),
    );
    final resolver = ContactIdentityResolver(database: fixture.database);

    expect(await resolver.resolveDisplayName('known'), 'Alice');
    expect(await resolver.resolvePhoneNumber('unknown'), '');
  });

  // QA 2026-10-14: numarayla eklenen kisi grupta "~Ad" yerine numara
  // olarak gorunuyordu.
  test('a contact added only by number uses the shared chat title', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.close);
    await fixture.database.contacts.insert(
      const ContactEntity(
        id: 'dialed',
        phoneNumber: '+905321000417',
        phoneHash: 'h',
        displayName: '+905321000417',
        isRegistered: true,
        addedManually: true,
      ),
    );
    await fixture.database.conversations.insert(
      const ConversationEntity(
        id: 'dialed',
        peerId: 'dialed',
        peerName: '~B Telefonu',
        peerPhone: '+905321000417',
      ),
    );
    await fixture.database.contacts.insert(
      const ContactEntity(
        id: 'named',
        phoneNumber: '+905321000418',
        phoneHash: 'h2',
        displayName: 'Rehber Adi',
        isRegistered: true,
        addedManually: true,
      ),
    );
    await fixture.database.conversations.insert(
      const ConversationEntity(
        id: 'named',
        peerId: 'named',
        peerName: '~Sahte',
        peerPhone: '+905321000418',
      ),
    );
    final resolver = ContactIdentityResolver(database: fixture.database);

    final identities = await resolver.resolveMany(['dialed', 'named']);
    expect(identities['dialed']!.displayName, '~B Telefonu');
    expect(identities['dialed']!.phoneNumber, '+905321000417');
    // Kullanicinin yazdigi rehber adi her zaman onde.
    expect(identities['named']!.displayName, 'Rehber Adi');
    expect(await resolver.resolveDisplayName('dialed'), '~B Telefonu');
  });

  // QA 2026-10-14: numarasini paylasmayan kisi grupta "Bilinmeyen uye"
  // gorunuyordu; birebir sohbetin basligi biliniyordu.
  test('a peer without a shared number uses the direct chat title', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.close);
    await fixture.database.conversations.insert(
      const ConversationEntity(
        id: 'hidden',
        peerId: 'hidden',
        peerName: '~A Telefonu',
        peerPhone: '',
      ),
    );
    await fixture.database.conversations.insert(
      const ConversationEntity(
        id: 'untitled',
        peerId: 'untitled',
        peerName: 'untitled',
        peerPhone: '',
      ),
    );
    final resolver = ContactIdentityResolver(database: fixture.database);

    final identities = await resolver.resolveMany(['hidden', 'untitled']);
    expect(identities['hidden']!.displayName, '~A Telefonu');
    expect(identities['hidden']!.phoneNumber, isEmpty);
    // Baslik kimligin kendisiyse yeni bir ad uydurulmaz.
    expect(identities['untitled']!.displayName, 'untitled');
  });
}

class _Fixture {
  const _Fixture(this.directory, this.database);

  final Directory directory;
  final SecureChatDatabase database;

  static Future<_Fixture> open() async {
    final directory = await Directory.systemTemp.createTemp(
      'securechat_contact_identity_',
    );
    final database = await SecureChatDatabase.open(
      file: File('${directory.path}/storage.securejson'),
      crypto: LocalAeadCryptoService(
        SecretKey(List<int>.generate(32, (index) => index + 1)),
      ),
    );
    return _Fixture(directory, database);
  }

  Future<void> close() async {
    await database.close();
    await directory.delete(recursive: true);
  }
}
