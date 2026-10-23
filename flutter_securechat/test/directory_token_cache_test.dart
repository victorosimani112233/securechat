import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/contacts/directory_token_cache.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/storage_at_rest.dart';

void main() {
  late Directory root;
  late File file;
  late SecureChatDatabase database;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('directory_tokens_');
    file = File('${root.path}/db.securejson');
    database = await SecureChatDatabase.open(
      file: file,
      crypto: LocalAeadCryptoService(
        SecretKey(List<int>.generate(32, (i) => i + 5)),
      ),
    );
  });

  tearDown(() async {
    await database.close();
    await root.delete(recursive: true);
  });

  test('tokens are stored encrypted and bound to the directory key', () async {
    final cache = StoredDirectoryTokenCache(database.cryptoState);
    final hash = 'a' * 64;
    final token = 'T' * 43;
    expect(await cache.load('key-1'), isEmpty);

    await cache.save('key-1', {hash: token, 'not-a-hash': token});
    expect(await cache.load('key-1'), {hash: token});
    expect(await cache.load('key-2'), isEmpty);
    expect(await storageAtRest(file), isNot(contains(token)));

    await database.cryptoState.put('directory-tokens:v1', '{broken');
    expect(await cache.load('key-1'), isEmpty);
  });
}
