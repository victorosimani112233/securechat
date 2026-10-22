import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/bulk/broadcast_lists.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/storage_at_rest.dart';

void main() {
  late Directory root;
  late File file;
  late SecureChatDatabase database;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('broadcast_lists_');
    file = File('${root.path}/db.securejson');
    database = await SecureChatDatabase.open(
      file: file,
      crypto: LocalAeadCryptoService(
        SecretKey(List<int>.generate(32, (i) => i + 9)),
      ),
    );
  });

  tearDown(() async {
    await database.close();
    await root.delete(recursive: true);
  });

  test('lists are stored encrypted, sorted, and replaced by name', () async {
    final store = StorageBroadcastListStore(database);
    final updates = <List<BroadcastList>>[];
    final subscription = store.watch().listen(updates.add);
    addTearDown(subscription.cancel);

    final family = await store.save('  Aile   grubu ', ['a', 'b', 'a', '']);
    await store.save('Bisiklet', ['c']);
    expect(family.name, 'Aile grubu');
    expect(family.memberIds, ['a', 'b']);

    // Ayni ad (harf buyuklugu farkli) yeni liste acmaz, uyeleri gunceller.
    final updated = await store.save('AİLE GRUBU', ['b', 'c']);
    final lists = await store.watch().first;
    expect(lists.map((list) => list.name), ['AİLE GRUBU', 'Bisiklet']);
    expect(lists.length, 2);
    expect(updated.id, family.id);

    await store.delete(lists.last.id);
    expect((await store.watch().first).single.memberIds, ['b', 'c']);
    expect(updates, isNotEmpty);
    expect(await storageAtRest(file), isNot(contains('Bisiklet')));
  });

  test('a list needs a name and members and stays within limits', () async {
    final store = StorageBroadcastListStore(database);
    Future<BroadcastListError?> failure(
      String name,
      List<String> members,
    ) async {
      try {
        await store.save(name, members);
        return null;
      } on BroadcastListException catch (error) {
        return error.reason;
      }
    }

    expect(await failure('  ', ['a']), BroadcastListError.emptyName);
    final long = await store.save('x' * 200, ['a']);
    expect(long.name.length, maxBroadcastListNameLength);
    await store.delete(long.id);
    expect(await failure('Boş', []), BroadcastListError.noMembers);
    expect(
      await failure('Kalabalık', [
        for (var i = 0; i <= maxBroadcastListMembers; i++) 'u$i',
      ]),
      BroadcastListError.tooManyMembers,
    );
    for (var i = 0; i < maxBroadcastLists; i++) {
      await store.save('Liste $i', ['a']);
    }
    expect(await failure('Bir fazla', ['a']), BroadcastListError.tooManyLists);
    // Var olan listeyi guncellemek sinira takilmaz.
    expect(await failure('liste 0', ['b']), isNull);
  });

  test('a corrupted record is skipped instead of breaking the list', () async {
    await database.cryptoState.put('broadcast-list:bad', '{not json');
    await database.cryptoState.put(
      'broadcast-list:ok',
      const BroadcastList(id: 'ok', name: 'Tamam', memberIds: ['a']).encode(),
    );
    final lists = await StorageBroadcastListStore(database).watch().first;
    expect(lists.single.name, 'Tamam');
  });
}
