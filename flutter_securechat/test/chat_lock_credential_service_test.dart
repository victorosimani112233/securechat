import 'dart:math';

import 'package:flutter_securechat/src/security/chat_lock_credential_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chat password is salted, verified and removable', () async {
    final store = _MemoryCredentialStore();
    final service = ChatLockCredentialService(store: store, random: Random(17));

    await service.setPassword('private-chat-id', 'correct horse');

    expect(await service.hasCredential('private-chat-id'), isTrue);
    expect(
      store.values.keys.single,
      isNot(contains('private-chat-id')),
      reason: 'conversation identity must not be exposed by the state key',
    );
    expect(store.values.values.single, isNot(contains('correct horse')));
    expect(
      await service.verifyPassword('private-chat-id', 'correct horse'),
      isTrue,
    );
    expect(
      await service.verifyPassword('private-chat-id', 'wrong password'),
      isFalse,
    );

    await service.clear('private-chat-id');
    expect(await service.hasCredential('private-chat-id'), isFalse);
  });

  test('short passwords are rejected before persistence', () async {
    final store = _MemoryCredentialStore();
    final service = ChatLockCredentialService(store: store);

    await expectLater(
      service.setPassword('chat', 'short'),
      throwsArgumentError,
    );
    expect(store.values, isEmpty);
  });
}

class _MemoryCredentialStore implements ChatLockCredentialStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
