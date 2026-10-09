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
