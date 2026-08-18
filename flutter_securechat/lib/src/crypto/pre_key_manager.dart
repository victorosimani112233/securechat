import 'dart:convert';
import 'dart:typed_data';

import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart' as signal;

import 'crypto_protocol_store.dart';

class SerializedOneTimePreKey {
  const SerializedOneTimePreKey({required this.keyId, required this.publicKey});

  final int keyId;
  final List<int> publicKey;

  Map<String, Object?> toJson() => {
    'keyId': keyId,
    'publicKey': base64Encode(publicKey),
  };
}

class SerializedPreKeyBundle {
  const SerializedPreKeyBundle({
    required this.identityPublicKey,
    required this.registrationId,
    required this.signedPreKeyId,
    required this.signedPreKey,
    required this.signedPreKeySignature,
    required this.oneTimePreKeys,
  });

  final List<int> identityPublicKey;
  final int registrationId;
  final int signedPreKeyId;
  final List<int> signedPreKey;
  final List<int> signedPreKeySignature;
  final List<SerializedOneTimePreKey> oneTimePreKeys;

  Map<String, Object?> toJson() => {
    'identityPublicKey': base64Encode(identityPublicKey),
    'registrationId': registrationId,
    'signedPreKeyId': signedPreKeyId,
    'signedPreKey': base64Encode(signedPreKey),
    'signedPreKeySignature': base64Encode(signedPreKeySignature),
    'oneTimePreKeys': oneTimePreKeys.map((key) => key.toJson()).toList(),
  };
}

/// Generates legacy Signal Protocol V3 identity/prekey records. These are the
/// same serialized record and public-key formats consumed by the Kotlin
/// client's signal-protocol-android 2.8.1 implementation.
class PreKeyManager {
  PreKeyManager(
    this._store, {
    this.batchSize = preKeyBatchSize,
    this.refreshThreshold = preKeyRefreshThreshold,
  });

  static const preKeyBatchSize = 100;
  static const preKeyRefreshThreshold = 20;
  static const signedPreKeyRotationDays = 7;

  final DatabaseCryptoProtocolStore _store;
  final int batchSize;
  final int refreshThreshold;

  Future<SerializedPreKeyBundle> generateAndSerializeInitialBundle() async {
    var existing = await _store.getIdentityKeyPair();
    if (existing != null && !_isSignalIdentityRecord(existing)) {
      await _store.clearProtocolState();
      existing = null;
    }
    if (existing != null) {
      if (await _store.getLocalRegistrationId() < 1) {
        await _store.storeLocalRegistrationId(
          signal.generateRegistrationId(false),
        );
      }
      if (await _store.getAvailablePreKeyCount() == 0) {
        await _generatePreKeys(await _store.getNextPreKeyId(), batchSize);
      }
      return _buildExistingBundle(existing);
    }

    final identity = signal.generateIdentityKeyPair();
    await _store.storeIdentityKeyPair(identity.serialize());
    await _store.storeLocalRegistrationId(signal.generateRegistrationId(false));
    await _generatePreKeys(0, batchSize);
    await _storeSignedPreKey(signal.generateSignedPreKey(identity, 0));
    return _buildExistingBundle(identity.serialize());
  }

  Future<List<SerializedOneTimePreKey>?> buildSerializedReplenishBatch() async {
    if (await availablePreKeyCount() >= refreshThreshold) return null;
    return _generatePreKeys(await _store.getNextPreKeyId(), batchSize);
  }

  Future<int> availablePreKeyCount() => _store.getAvailablePreKeyCount();

  /// Removes a batch that was generated locally but rejected by the server.
  /// Without this rollback the local threshold would suppress every later
  /// refresh attempt even though the server never received the keys.
  Future<void> discardOneTimePreKeys(Iterable<int> keyIds) async {
    for (final keyId in keyIds) {
      await _store.removePreKey(keyId);
    }
  }

  Future<void> rotateSignedPreKey() async {
    final identityBytes = await _store.getIdentityKeyPair();
    if (identityBytes == null) {
      throw StateError('Signal identity is not initialized');
    }
    final existing = await _store.loadAllSignedPreKeys();
    final nextId = existing.isEmpty
        ? 0
        : existing
                  .map(
                    (bytes) => signal.SignedPreKeyRecord.fromSerialized(
                      Uint8List.fromList(bytes),
                    ).id,
                  )
                  .reduce((a, b) => a > b ? a : b) +
              1;
    final identity = signal.IdentityKeyPair.fromSerialized(
      Uint8List.fromList(identityBytes),
    );
    await _storeSignedPreKey(signal.generateSignedPreKey(identity, nextId));
  }

  Future<bool> verifySignedPreKey(SerializedPreKeyBundle bundle) async {
    final identity = signal.IdentityKey.fromBytes(
      Uint8List.fromList(bundle.identityPublicKey),
      0,
    );
    return signal.Curve.verifySignature(
      identity.publicKey,
      Uint8List.fromList(bundle.signedPreKey),
      Uint8List.fromList(bundle.signedPreKeySignature),
    );
  }

  Future<SerializedPreKeyBundle> _buildExistingBundle(
    List<int> identityBytes,
  ) async {
    final identity = signal.IdentityKeyPair.fromSerialized(
      Uint8List.fromList(identityBytes),
    );
    var signed = await _store.loadAllSignedPreKeys();
    if (signed.isEmpty) {
      await _storeSignedPreKey(signal.generateSignedPreKey(identity, 0));
      signed = await _store.loadAllSignedPreKeys();
    }
    final signedRecords = signed
        .map(
          (bytes) => signal.SignedPreKeyRecord.fromSerialized(
            Uint8List.fromList(bytes),
          ),
        )
        .toList();
    final latest = signedRecords.reduce((a, b) => a.id > b.id ? a : b);
    final preKeys = <SerializedOneTimePreKey>[];
    for (var id = 0; id < await _store.getNextPreKeyId(); id++) {
      final bytes = await _store.loadPreKey(id);
      if (bytes == null) continue;
      final record = signal.PreKeyRecord.fromBuffer(Uint8List.fromList(bytes));
      preKeys.add(
        SerializedOneTimePreKey(
          keyId: record.id,
          publicKey: record.getKeyPair().publicKey.serialize(),
        ),
      );
    }
    return SerializedPreKeyBundle(
      identityPublicKey: identity.getPublicKey().serialize(),
      registrationId: await _store.getLocalRegistrationId(),
      signedPreKeyId: latest.id,
      signedPreKey: latest.getKeyPair().publicKey.serialize(),
      signedPreKeySignature: latest.signature,
      oneTimePreKeys: preKeys,
    );
  }

  Future<List<SerializedOneTimePreKey>> _generatePreKeys(
    int start,
    int count,
  ) async {
    final records = signal.generatePreKeys(start, count);
    for (final record in records) {
      await _store.storePreKey(record.id, record.serialize());
    }
    return records
        .map(
          (record) => SerializedOneTimePreKey(
            keyId: record.id,
            publicKey: record.getKeyPair().publicKey.serialize(),
          ),
        )
        .toList(growable: false);
  }

  Future<void> _storeSignedPreKey(signal.SignedPreKeyRecord record) =>
      _store.storeSignedPreKey(record.id, record.serialize());

  bool _isSignalIdentityRecord(List<int> bytes) {
    try {
      final pair = signal.IdentityKeyPair.fromSerialized(
        Uint8List.fromList(bytes),
      );
      return pair.getPublicKey().serialize().isNotEmpty &&
          pair.getPrivateKey().serialize().isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
