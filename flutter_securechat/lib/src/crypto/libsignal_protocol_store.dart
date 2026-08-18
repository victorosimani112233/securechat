import 'dart:typed_data';

import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart' as signal;

import 'crypto_protocol_store.dart';

/// Persistent adapter between libsignal's typed store contracts and the
/// encrypted application database. Record bytes remain in libsignal's own
/// protobuf format so Kotlin/Java and Flutter can exchange and restore them.
class PersistentSignalProtocolStore extends signal.SignalProtocolStore
    implements signal.SenderKeyStore {
  PersistentSignalProtocolStore(this._store);

  final DatabaseCryptoProtocolStore _store;

  @override
  Future<signal.IdentityKeyPair> getIdentityKeyPair() async {
    final bytes = await _store.getIdentityKeyPair();
    if (bytes == null) throw StateError('Signal identity is not initialized');
    return signal.IdentityKeyPair.fromSerialized(Uint8List.fromList(bytes));
  }

  @override
  Future<int> getLocalRegistrationId() => _store.getLocalRegistrationId();

  @override
  Future<signal.IdentityKey?> getIdentity(
    signal.SignalProtocolAddress address,
  ) async {
    final bytes = await _store.loadIdentity(address.getName());
    return bytes == null
        ? null
        : signal.IdentityKey.fromBytes(Uint8List.fromList(bytes), 0);
  }

  @override
  Future<bool> isTrustedIdentity(
    signal.SignalProtocolAddress address,
    signal.IdentityKey? identityKey,
    signal.Direction direction,
  ) async {
    if (identityKey == null) return false;
    return _store.isTrustedIdentity(address.getName(), identityKey.serialize());
  }

  @override
  Future<bool> saveIdentity(
    signal.SignalProtocolAddress address,
    signal.IdentityKey? identityKey,
  ) async {
    if (identityKey == null) return false;
    return _store.storeIdentity(address.getName(), identityKey.serialize());
  }

  @override
  Future<signal.PreKeyRecord> loadPreKey(int preKeyId) async {
    final bytes = await _store.loadPreKey(preKeyId);
    if (bytes == null) {
      throw signal.InvalidKeyIdException('PreKey not found: $preKeyId');
    }
    return signal.PreKeyRecord.fromBuffer(Uint8List.fromList(bytes));
  }

  @override
  Future<void> storePreKey(int preKeyId, signal.PreKeyRecord record) =>
      _store.storePreKey(preKeyId, record.serialize());

  @override
  Future<bool> containsPreKey(int preKeyId) => _store.containsPreKey(preKeyId);

  @override
  Future<void> removePreKey(int preKeyId) => _store.removePreKey(preKeyId);

  @override
  Future<signal.SignedPreKeyRecord> loadSignedPreKey(int signedPreKeyId) async {
    final bytes = await _store.loadSignedPreKey(signedPreKeyId);
    if (bytes == null) {
      throw signal.InvalidKeyIdException(
        'SignedPreKey not found: $signedPreKeyId',
      );
    }
    return signal.SignedPreKeyRecord.fromSerialized(Uint8List.fromList(bytes));
  }

  @override
  Future<List<signal.SignedPreKeyRecord>> loadSignedPreKeys() async =>
      (await _store.loadAllSignedPreKeys())
          .map(
            (bytes) => signal.SignedPreKeyRecord.fromSerialized(
              Uint8List.fromList(bytes),
            ),
          )
          .toList(growable: false);

  @override
  Future<void> storeSignedPreKey(
    int signedPreKeyId,
    signal.SignedPreKeyRecord record,
  ) => _store.storeSignedPreKey(signedPreKeyId, record.serialize());

  @override
  Future<bool> containsSignedPreKey(int signedPreKeyId) =>
      _store.containsSignedPreKey(signedPreKeyId);

  @override
  Future<void> removeSignedPreKey(int signedPreKeyId) =>
      _store.removeSignedPreKey(signedPreKeyId);

  @override
  Future<signal.SessionRecord> loadSession(
    signal.SignalProtocolAddress address,
  ) async {
    final bytes = await _store.loadSession(
      address.getName(),
      address.getDeviceId(),
    );
    return bytes == null
        ? signal.SessionRecord()
        : signal.SessionRecord.fromSerialized(Uint8List.fromList(bytes));
  }

  @override
  Future<void> storeSession(
    signal.SignalProtocolAddress address,
    signal.SessionRecord record,
  ) => _store.storeSession(
    address.getName(),
    address.getDeviceId(),
    record.serialize(),
  );

  @override
  Future<bool> containsSession(signal.SignalProtocolAddress address) =>
      _store.containsSession(address.getName(), address.getDeviceId());

  @override
  Future<void> deleteSession(signal.SignalProtocolAddress address) =>
      _store.deleteSession(address.getName(), address.getDeviceId());

  @override
  Future<void> deleteAllSessions(String name) => _store.deleteAllSessions(name);

  @override
  Future<List<int>> getSubDeviceSessions(String name) =>
      _store.getSubDeviceSessions(name);

  @override
  Future<signal.SenderKeyRecord> loadSenderKey(
    signal.SenderKeyName senderKeyName,
  ) async {
    final address = senderKeyName.sender;
    final bytes = await _store.loadSenderKey(
      senderKeyName.groupId,
      address.getName(),
      address.getDeviceId(),
    );
    return bytes == null
        ? signal.SenderKeyRecord()
        : signal.SenderKeyRecord.fromSerialized(Uint8List.fromList(bytes));
  }

  @override
  Future<void> storeSenderKey(
    signal.SenderKeyName senderKeyName,
    signal.SenderKeyRecord record,
  ) {
    final address = senderKeyName.sender;
    return _store.storeSenderKey(
      senderKeyName.groupId,
      address.getName(),
      address.getDeviceId(),
      record.serialize(),
    );
  }

  Future<void> resetSenderKey(String groupId, String senderId) =>
      _store.deleteSenderKey(groupId, senderId, 1);
}
