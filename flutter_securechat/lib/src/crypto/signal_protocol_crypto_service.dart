import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart' as signal;

import '../services/crypto_service.dart';
import 'libsignal_protocol_store.dart';

abstract interface class PreKeyBundleProvider {
  Future<signal.PreKeyBundle?> fetch(String recipientId);
}

class HttpPreKeyBundleProvider implements PreKeyBundleProvider {
  HttpPreKeyBundleProvider({
    required Uri apiBaseUrl,
    required HttpClient httpClient,
    required Future<String?> Function() accessTokenProvider,
  }) : _apiBaseUrl = apiBaseUrl,
       _httpClient = httpClient,
       _accessTokenProvider = accessTokenProvider;

  final Uri _apiBaseUrl;
  final HttpClient _httpClient;
  final Future<String?> Function() _accessTokenProvider;

  @override
  Future<signal.PreKeyBundle?> fetch(String recipientId) async {
    final uri = _apiBaseUrl.resolve(
      '/api/v1/users/${Uri.encodeComponent(recipientId)}/prekeys',
    );
    final request = await _httpClient
        .getUrl(uri)
        .timeout(const Duration(seconds: 15));
    final token = await _accessTokenProvider();
    if (token != null && token.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    final response = await request.close().timeout(const Duration(seconds: 20));
    if (response.statusCode == HttpStatus.notFound) return null;
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'PreKey fetch failed: HTTP ${response.statusCode}',
        uri: uri,
      );
    }
    final json = (jsonDecode(body) as Map).cast<String, Object?>();
    final oneTime = json['oneTimePreKey'];
    final oneTimeMap = oneTime is Map ? oneTime.cast<String, Object?>() : null;
    final identity = signal.IdentityKey.fromBytes(
      _decodeBase64(json['identityPublicKey'] as String),
      0,
    );
    return signal.PreKeyBundle(
      (json['registrationId'] as num).toInt(),
      1,
      (oneTimeMap?['keyId'] as num?)?.toInt(),
      oneTimeMap == null
          ? null
          : signal.Curve.decodePoint(
              _decodeBase64(oneTimeMap['publicKey'] as String),
              0,
            ),
      (json['signedPreKeyId'] as num).toInt(),
      signal.Curve.decodePoint(
        _decodeBase64(json['signedPreKey'] as String),
        0,
      ),
      _decodeBase64(json['signedPreKeySignature'] as String),
      identity,
    );
  }
}

/// Production message crypto. Local database/session wrapping deliberately
/// remains in [LocalAeadCryptoService]; this class is only for peer/group wire
/// messages and implements Signal Protocol V3 Double Ratchet + SenderKey.
class SignalProtocolCryptoService implements CryptoService {
  SignalProtocolCryptoService({
    required PersistentSignalProtocolStore store,
    required PreKeyBundleProvider preKeyBundles,
  }) : _store = store,
       _preKeyBundles = preKeyBundles;

  static const deviceId = 1;
  final PersistentSignalProtocolStore _store;
  final PreKeyBundleProvider _preKeyBundles;
  final Map<String, Future<bool>> _sessionAttempts = {};

  Future<bool> ensureSession(String recipientId) {
    return _sessionAttempts
        .putIfAbsent(recipientId, () async {
          final address = signal.SignalProtocolAddress(recipientId, deviceId);
          if (await _store.containsSession(address)) return true;
          final bundle = await _preKeyBundles.fetch(recipientId);
          if (bundle == null) return false;
          await signal.SessionBuilder.fromSignalStore(
            _store,
            address,
          ).processPreKeyBundle(bundle);
          return _store.containsSession(address);
        })
        .whenComplete(() => _sessionAttempts.remove(recipientId));
  }

  @override
  Future<String> encryptDirect({
    required String recipientId,
    required String plaintext,
  }) async {
    if (!await ensureSession(recipientId)) {
      throw StateError('Signal session could not be established: $recipientId');
    }
    final address = signal.SignalProtocolAddress(recipientId, deviceId);
    final message = await signal.SessionCipher.fromStore(
      _store,
      address,
    ).encrypt(Uint8List.fromList(utf8.encode(plaintext)));
    final type = message.getType() == signal.CiphertextMessage.prekeyType
        ? 'PREKEY'
        : 'SIGNAL';
    final registrationId = await _store.getLocalRegistrationId();
    return 'E2EE:v1:$type:$registrationId:${base64Encode(message.serialize())}';
  }

  @override
  Future<String> decryptDirect({
    required String senderId,
    required String envelope,
  }) async {
    final parts = envelope.split(':');
    if (parts.length != 5 || parts[0] != 'E2EE' || parts[1] != 'v1') {
      throw FormatException('Unsupported Signal envelope', envelope);
    }
    final bytes = _decodeBase64(parts[4]);
    final cipher = signal.SessionCipher.fromStore(
      _store,
      signal.SignalProtocolAddress(senderId, deviceId),
    );
    final plaintext = switch (parts[2]) {
      'PREKEY' => await cipher.decrypt(signal.PreKeySignalMessage(bytes)),
      'SIGNAL' => await cipher.decryptFromSignal(
        signal.SignalMessage.fromSerialized(bytes),
      ),
      _ => throw FormatException('Unknown Signal envelope type', parts[2]),
    };
    return utf8.decode(plaintext);
  }

  Future<String> createSenderKeyDistribution({
    required String groupId,
    required String senderId,
  }) async {
    final name = _senderKeyName(groupId, senderId);
    final message = await signal.GroupSessionBuilder(_store).create(name);
    return 'SKDM:$groupId:${base64Encode(message.serialize())}';
  }

  Future<void> processSenderKeyDistribution({
    required String senderId,
    required String plaintext,
  }) async {
    final first = plaintext.indexOf(':');
    final second = plaintext.indexOf(':', first + 1);
    if (first < 0 || second < 0 || plaintext.substring(0, first) != 'SKDM') {
      throw const FormatException('Invalid sender-key distribution envelope');
    }
    final groupId = plaintext.substring(first + 1, second);
    final message = signal.SenderKeyDistributionMessageWrapper.fromSerialized(
      _decodeBase64(plaintext.substring(second + 1)),
    );
    await signal.GroupSessionBuilder(
      _store,
    ).process(_senderKeyName(groupId, senderId), message);
  }

  @override
  Future<String> encryptGroup({
    required String senderId,
    required String groupId,
    required String plaintext,
  }) => encryptGroupWire(
    senderId: senderId,
    groupId: groupId,
    plaintext: plaintext,
  );

  Future<String> encryptGroupWire({
    required String senderId,
    required String groupId,
    required String plaintext,
  }) async {
    final name = _senderKeyName(groupId, senderId);
    final record = await _store.loadSenderKey(name);
    if (record.isEmpty) {
      throw StateError('SenderKey is not distributed for group $groupId');
    }
    final ciphertext = await signal.GroupCipher(
      _store,
      name,
    ).encrypt(Uint8List.fromList(utf8.encode(plaintext)));
    final routingToken = await groupRoutingToken(groupId);
    return 'GROUPSK:v2:$routingToken:${base64Encode(ciphertext)}';
  }

  @override
  Future<String> decryptGroup({
    required String senderId,
    required String groupId,
    required String envelope,
  }) async {
    final parts = envelope.split(':');
    final isLegacyV1 =
        parts.length == 5 &&
        parts[0] == 'GROUPSK' &&
        parts[1] == 'v1' &&
        parts[2] == groupId;
    final isPrivateV2 =
        parts.length == 4 &&
        parts[0] == 'GROUPSK' &&
        parts[1] == 'v2' &&
        parts[2] == await groupRoutingToken(groupId);
    if (!isLegacyV1 && !isPrivateV2) {
      throw FormatException('Unsupported SenderKey envelope', envelope);
    }
    final ciphertext = isLegacyV1 ? parts[4] : parts[3];
    final plaintext = await signal.GroupCipher(
      _store,
      _senderKeyName(groupId, senderId),
    ).decrypt(_decodeBase64(ciphertext));
    return utf8.decode(plaintext);
  }

  Future<void> resetLocalSenderKey(String groupId, String senderId) =>
      _store.resetSenderKey(groupId, senderId);

  signal.SenderKeyName _senderKeyName(String groupId, String senderId) =>
      signal.SenderKeyName(
        groupId,
        signal.SignalProtocolAddress(senderId, deviceId),
      );
}

Uint8List _decodeBase64(String value) =>
    Uint8List.fromList(base64Decode(base64.normalize(value)));
