import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/settings/local_data_owner_guard.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';

/// Bulgu 1 (QA 2026-10-12): cikis yapilan cihazda yeni hesap, onceki hesabin
/// sohbetlerini gormemeli.
void main() {
  late Directory root;
  late Directory media;
  late SecureChatDatabase database;
  late LocalDataOwnerGuard guard;
  late int forgottenDiagnostics;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('owner_guard_');
    media = Directory('${root.path}/media');
    database = await SecureChatDatabase.open(
      file: File('${root.path}/database'),
      crypto: LocalAeadCryptoService(SecretKey(List.filled(32, 41))),
    );
    forgottenDiagnostics = 0;
    guard = LocalDataOwnerGuard(
      database: database,
      managedDirectories: [media],
      forgetDiagnostics: () async => forgottenDiagnostics++,
    );
  });

  tearDown(() async {
    await database.close();
    await root.delete(recursive: true);
  });

  Future<void> seedPreviousAccount() async {
    await database.conversations.insert(
      const ConversationEntity(
        id: 'old-peer',
        peerId: 'old-peer',
        peerName: 'Old peer',
        peerPhone: '+901646767346',
      ),
    );
    await database.contacts.insert(
      const ContactEntity(
        id: 'old-peer',
        phoneNumber: '+901646767346',
        phoneHash: 'hash',
        displayName: 'Old peer',
        isRegistered: true,
      ),
    );
    await database.callLogs.insert(
      CallLogEntity(
        id: 'call-1',
        peerId: 'old-peer',
        peerName: 'Old peer',
        callType: 'AUDIO',
        direction: 'OUTGOING',
        status: 'COMPLETED',
        timestamp: DateTime(2026, 10, 7).millisecondsSinceEpoch,
      ),
    );
    await media.create(recursive: true);
    await File('${media.path}/photo.jpg').writeAsString('old');
    // Yeni hesabin kayit oncesi uretilmis Olm durumu yerine gecer.
    await database.cryptoState.put('local_identity_marker', 'new-account');
  }

  test('different owner: content and media are wiped, crypto kept', () async {
    await seedPreviousAccount();
    await database.cryptoState.put(LocalDataOwnerGuard.ownerKey, 'old-user');

    await guard.claim('new-user');

    expect(await database.hasAccountContent(), isFalse);
    expect(await database.conversations.getById('old-peer'), isNull);
    expect(await database.contacts.getAllOnce(), isEmpty);
    expect(await media.exists(), isFalse);
    // QA 2026-10-12 R2: onceki hesabin cokme kayitlari da gider.
    expect(forgottenDiagnostics, 1);
    expect(
      await database.cryptoState.get('local_identity_marker'),
      'new-account',
    );
    expect(
      await database.cryptoState.get(LocalDataOwnerGuard.ownerKey),
      'new-user',
    );
  });

  test('unknown owner with leftover content (older app) is wiped', () async {
    await seedPreviousAccount();

    await guard.claim('new-user');

    expect(await database.hasAccountContent(), isFalse);
    expect(await media.exists(), isFalse);
    expect(
      await database.cryptoState.get(LocalDataOwnerGuard.ownerKey),
      'new-user',
    );
  });

  test('same owner keeps everything', () async {
    await seedPreviousAccount();
    await database.cryptoState.put(LocalDataOwnerGuard.ownerKey, 'me');

    await guard.claim('me');

    expect(await database.conversations.getById('old-peer'), isNotNull);
    expect(await File('${media.path}/photo.jpg').exists(), isTrue);
    expect(forgottenDiagnostics, 0);
  });

  test('fresh device only records the owner', () async {
    await media.create(recursive: true);

    await guard.claim('me');

    expect(await media.exists(), isTrue);
    expect(await database.cryptoState.get(LocalDataOwnerGuard.ownerKey), 'me');
  });

  test('full local wipe forgets the owner', () async {
    await guard.claim('me');
    await database.clearAll();
    expect(
      await database.cryptoState.get(LocalDataOwnerGuard.ownerKey),
      isNull,
    );
  });
}
