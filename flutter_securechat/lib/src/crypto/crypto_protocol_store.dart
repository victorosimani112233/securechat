import 'dart:convert';

import '../storage/secure_chat_database.dart';
import '../storage/storage_entities.dart';

abstract interface class CryptoIdentityStore {
  Future<List<int>?> loadIdentity(String name);
  Future<bool> storeIdentity(String name, List<int> identityKey);
  Future<void> deleteIdentity(String name);
  Future<int> getLocalRegistrationId();
  Future<void> storeLocalRegistrationId(int registrationId);
  Future<List<int>?> getIdentityKeyPair();
  Future<void> storeIdentityKeyPair(List<int> keyPair);
}

abstract interface class CryptoPreKeyStore {
  Future<List<int>?> loadPreKey(int id);
  Future<void> storePreKey(int id, List<int> record);
  Future<bool> containsPreKey(int id);
  Future<void> removePreKey(int id);
  Future<int> getAvailablePreKeyCount();
  Future<int> getNextPreKeyId();
}

abstract interface class CryptoSignedPreKeyStore {
  Future<List<int>?> loadSignedPreKey(int id);
  Future<List<List<int>>> loadAllSignedPreKeys();
  Future<void> storeSignedPreKey(int id, List<int> record);
  Future<bool> containsSignedPreKey(int id);
  Future<void> removeSignedPreKey(int id);
}

abstract interface class CryptoSessionStore {
  Future<List<int>?> loadSession(String name, int deviceId);
  Future<void> storeSession(String name, int deviceId, List<int> record);
  Future<bool> containsSession(String name, int deviceId);
  Future<void> deleteSession(String name, int deviceId);
  Future<void> deleteAllSessions(String name);
  Future<List<int>> getSubDeviceSessions(String name);
}

abstract interface class CryptoSenderKeyStore {
  Future<List<int>?> loadSenderKey(
    String groupId,
    String senderId,
    int deviceId,
  );
  Future<void> storeSenderKey(
    String groupId,
    String senderId,
    int deviceId,
    List<int> record,
  );
  Future<void> deleteSenderKey(String groupId, String senderId, int deviceId);
  Future<void> deleteAllForGroup(String groupId);
  Future<bool> containsSenderKey(String groupId, String senderId, int deviceId);
}

class DatabaseCryptoProtocolStore
    implements
        CryptoIdentityStore,
        CryptoPreKeyStore,
        CryptoSignedPreKeyStore,
        CryptoSessionStore,
        CryptoSenderKeyStore {
  DatabaseCryptoProtocolStore(this._database);

  static const _registrationIdKey = 'local_registration_id';
  static const _identityKeyPairKey = 'local_identity_key_pair_v1';
  final SecureChatDatabase _database;

  Future<void> clearProtocolState() => _database.clearCryptoProtocolState();

  @override
  Future<List<int>?> loadIdentity(String name) async =>
      (await _database.identities.get(name))?.identityKey;

  @override
  Future<bool> storeIdentity(String name, List<int> identityKey) async {
    final existing = await _database.identities.get(name);
    await _database.identities.insert(
      IdentityEntity(
        addressName: name,
        identityKey: List<int>.from(identityKey),
        trustLevel: TrustLevel.trustedUnverified,
      ),
    );
    return existing != null &&
        !_constantTimeEquals(existing.identityKey, identityKey);
  }

  Future<bool> isTrustedIdentity(String name, List<int> identityKey) async {
    final existing = await loadIdentity(name);
    return existing == null || _constantTimeEquals(existing, identityKey);
  }

  @override
  Future<void> deleteIdentity(String name) => _database.identities.delete(name);

  @override
  Future<int> getLocalRegistrationId() async =>
      int.tryParse(await _database.cryptoState.get(_registrationIdKey) ?? '') ??
      -1;

  @override
  Future<void> storeLocalRegistrationId(int registrationId) =>
      _database.cryptoState.put(_registrationIdKey, registrationId.toString());

  @override
  Future<List<int>?> getIdentityKeyPair() async {
    final value = await _database.cryptoState.get(_identityKeyPairKey);
    return value == null ? null : base64Decode(value);
  }

  @override
  Future<void> storeIdentityKeyPair(List<int> keyPair) =>
      _database.cryptoState.put(_identityKeyPairKey, base64Encode(keyPair));

  @override
  Future<List<int>?> loadPreKey(int id) async =>
      (await _database.preKeys.get(id))?.record;

  @override
  Future<void> storePreKey(int id, List<int> record) => _database.preKeys
      .insert(PreKeyEntity(id: id, record: List<int>.from(record)));

  @override
  Future<bool> containsPreKey(int id) => _database.preKeys.exists(id);

  @override
  Future<void> removePreKey(int id) => _database.preKeys.delete(id);

  @override
  Future<int> getAvailablePreKeyCount() => _database.preKeys.count();

  @override
  Future<int> getNextPreKeyId() async =>
      ((await _database.preKeys.maxId()) ?? -1) + 1;

  @override
  Future<List<int>?> loadSignedPreKey(int id) async =>
      (await _database.signedPreKeys.get(id))?.record;

  @override
  Future<List<List<int>>> loadAllSignedPreKeys() async =>
      (await _database.signedPreKeys.getAll())
          .map((entity) => List<int>.from(entity.record))
          .toList(growable: false);

  @override
  Future<void> storeSignedPreKey(int id, List<int> record) =>
      _database.signedPreKeys.insert(
        SignedPreKeyEntity(
          id: id,
          record: List<int>.from(record),
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );

  @override
  Future<bool> containsSignedPreKey(int id) =>
      _database.signedPreKeys.exists(id);

  @override
  Future<void> removeSignedPreKey(int id) => _database.signedPreKeys.delete(id);

  String _sessionId(String name, int deviceId) => '$name:$deviceId';

  @override
  Future<List<int>?> loadSession(String name, int deviceId) async =>
      (await _database.sessions.get(_sessionId(name, deviceId)))?.record;

  @override
  Future<void> storeSession(String name, int deviceId, List<int> record) =>
      _database.sessions.insert(
        SessionEntity(
          id: _sessionId(name, deviceId),
          record: List<int>.from(record),
        ),
      );

  @override
  Future<bool> containsSession(String name, int deviceId) =>
      _database.sessions.exists(_sessionId(name, deviceId));

  @override
  Future<void> deleteSession(String name, int deviceId) =>
      _database.sessions.delete(_sessionId(name, deviceId));

  @override
  Future<void> deleteAllSessions(String name) =>
      _database.sessions.deleteAllForName(name);

  @override
  Future<List<int>> getSubDeviceSessions(String name) async =>
      (await _database.sessions.getSessionIdsForName(name))
          .map((id) => int.tryParse(id.substring(id.lastIndexOf(':') + 1)))
          .whereType<int>()
          .toList(growable: false);

  @override
  Future<List<int>?> loadSenderKey(
    String groupId,
    String senderId,
    int deviceId,
  ) async =>
      (await _database.senderKeys.get(groupId, senderId, deviceId))?.record;

  @override
  Future<void> storeSenderKey(
    String groupId,
    String senderId,
    int deviceId,
    List<int> record,
  ) => _database.senderKeys.put(
    SenderKeyEntity(
      groupId: groupId,
      senderId: senderId,
      deviceId: deviceId,
      record: List<int>.from(record),
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    ),
  );

  @override
  Future<void> deleteSenderKey(String groupId, String senderId, int deviceId) =>
      _database.senderKeys.delete(groupId, senderId, deviceId);

  @override
  Future<void> deleteAllForGroup(String groupId) =>
      _database.senderKeys.deleteAllForGroup(groupId);

  @override
  Future<bool> containsSenderKey(
    String groupId,
    String senderId,
    int deviceId,
  ) => _database.senderKeys.exists(groupId, senderId, deviceId);
}

bool _constantTimeEquals(List<int> a, List<int> b) {
  var difference = a.length ^ b.length;
  final length = a.length > b.length ? a.length : b.length;
  for (var i = 0; i < length; i++) {
    difference |= (i < a.length ? a[i] : 0) ^ (i < b.length ? b[i] : 0);
  }
  return difference == 0;
}
