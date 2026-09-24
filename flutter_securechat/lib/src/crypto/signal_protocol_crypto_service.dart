import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart' as signal;

import '../services/crypto_service.dart';
import 'libsignal_protocol_store.dart';
import '../services/peer_identity_review_service.dart';

abstract interface class PreKeyBundleProvider {
  Future<signal.PreKeyBundle?> fetch(String recipientId);
}

class _AsyncKeyedMutex {
  final Map<String, Future<void>> _tails = {};

  Future<T> protect<T>(String key, Future<T> Function() operation) {
    final previous = _tails[key] ?? Future<void>.value();
    final ready = previous.then<void>((_) {}, onError: (_, _) {});
    final result = ready.then<T>((_) => operation());
    final tail = result.then<void>((_) {}, onError: (_, _) {});
    _tails[key] = tail;
    tail.whenComplete(() {
      if (identical(_tails[key], tail)) _tails.remove(key);
    });
    return result;
  }
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
class SignalProtocolCryptoService
    implements CryptoService, PeerSessionRecovery, PeerIdentityReviewService {
  SignalProtocolCryptoService({
    required PersistentSignalProtocolStore store,
    required PreKeyBundleProvider preKeyBundles,
    PeerIdentityRotationHandler? onPeerIdentityRotated,
  }) : _store = store,
       _preKeyBundles = preKeyBundles,
       _onPeerIdentityRotated = onPeerIdentityRotated;

  static const deviceId = 1;
  final PersistentSignalProtocolStore _store;
  final PreKeyBundleProvider _preKeyBundles;
  final PeerIdentityRotationHandler? _onPeerIdentityRotated;
  final _operations = _AsyncKeyedMutex();
  final _issuedReviews = Expando<bool>();

  @override
  Future<PeerIdentityReview> reviewPeerIdentity(String peerId) =>
      _operations.protect('direct:$peerId', () async {
        final bundle = await _fetchReviewBundle(peerId);
        final previous = await _store.getIdentity(
          signal.SignalProtocolAddress(peerId, deviceId),
        );
        final local = await _store.getIdentityKeyPair();
        final review = PeerIdentityReview(
          peerId: peerId,
          previousIdentity: previous?.serialize(),
          currentIdentity: bundle.getIdentityKey().serialize(),
          localIdentity: local.getPublicKey().serialize(),
        );
        _issuedReviews[review] = true;
        return review;
      });

  @override
  Future<void> approvePeerIdentity(PeerIdentityReview review) =>
      _operations.protect('direct:${review.peerId}', () async {
        // Only snapshots issued by this instance can authorize a change.
        if (_issuedReviews[review] != true) {
          throw const PeerIdentityReviewStaleException();
        }
        _issuedReviews[review] = null;
        final bundle = await _fetchReviewBundle(review.peerId);
        final local = await _store.getIdentityKeyPair();
        final previous = await _store.getIdentity(
          signal.SignalProtocolAddress(review.peerId, deviceId),
        );
        if (!identityBytesEqual(
              bundle.getIdentityKey().serialize(),
              review.currentIdentity,
            ) ||
            !identityBytesEqual(
              previous?.serialize(),
              review.previousIdentity,
            ) ||
            !identityBytesEqual(
              local.getPublicKey().serialize(),
              review.localIdentity,
            )) {
          throw const PeerIdentityReviewStaleException();
        }
        await _store.approveIdentity(
          peerId: review.peerId,
          expectedIdentity: review.previousIdentity,
          approvedIdentity: review.currentIdentity,
          expectedLocalIdentityRecord: local.serialize(),
        );
      });

  Future<signal.PreKeyBundle> _fetchReviewBundle(String peerId) async {
    final bundle = await _preKeyBundles.fetch(peerId);
    if (bundle == null) throw StateError('Peer prekeys are unavailable');
    final signed = bundle.getSignedPreKey();
    final signature = bundle.getSignedPreKeySignature();
    if (bundle.getDeviceId() != deviceId ||
        signed == null ||
        signature == null ||
        !signal.Curve.verifySignature(
          bundle.getIdentityKey().publicKey,
          signed.serialize(),
          // libsignal 0.8.2 clears the sign bit in its signature argument.
          Uint8List.fromList(signature),
        )) {
      throw signal.InvalidKeyException('Invalid signed prekey for review');
    }
    return bundle;
  }

  /// [force] verilirse mevcut oturum kaydi gecerli sayilmaz: once silinir,
  /// sonra taze bir prekey bundle ile X3DH bastan kurulur. Bozuk oturumdan
  /// kurtulmanin tek yolu budur; aksi halde `containsSession` true dondugu
  /// icin olu oturum sonsuza kadar kullanilmaya devam eder.
  Future<bool> ensureSession(String recipientId, {bool force = false}) =>
      _operations.protect(
        'direct:$recipientId',
        () => _ensureSessionUnlocked(recipientId, force: force),
      );

  Future<bool> _ensureSessionUnlocked(
    String recipientId, {
    bool force = false,
  }) async {
    final address = signal.SignalProtocolAddress(recipientId, deviceId);
    if (force) {
      await _store.deleteSession(address);
    } else if (await _store.containsSession(address)) {
      return true;
    }
    final bundle = await _preKeyBundles.fetch(recipientId);
    if (bundle == null) return false;
    final builder = signal.SessionBuilder.fromSignalStore(_store, address);
    try {
      await builder.processPreKeyBundle(bundle);
    } on signal.UntrustedIdentityException {
      // Kimlik degisimi bir liveness olayi degil, guven karari. Sunucudan
      // gelen yeni bundle eski TOFU pinini otomatik silemez; once kullanici
      // onayi veya key-transparency kaniti gerekir.
      await _onPeerIdentityRotated?.call(recipientId);
      rethrow;
    }
    return _store.containsSession(address);
  }

  @override
  Future<void> resetPeerSession(String peerId) => _operations.protect(
    'direct:$peerId',
    () => _resetPeerSessionUnlocked(peerId),
  );

  Future<void> _resetPeerSessionUnlocked(String peerId) async {
    await _store.deleteSession(signal.SignalProtocolAddress(peerId, deviceId));
    await _store.deleteAllSessions(peerId);
  }

  @override
  Future<bool> rebuildPeerSession(String peerId) =>
      _operations.protect('direct:$peerId', () async {
        await _resetPeerSessionUnlocked(peerId);
        return _ensureSessionUnlocked(peerId, force: true);
      });

  /// Hatanin oturumun kullanilamaz oldugunu mu gosterdigini siniflandirir.
  ///
  /// `DuplicateMessageException` kasitli olarak DISARIDA: tekrar teslim edilen
  /// bir cerceve saglikli bir oturumda da olagan, oturumu sifirlamak yanlis
  /// olur. `InvalidMessageException` ve `InvalidMacException` paket
  /// barrel'indan export edilmedigi icin tip adiyla eslenir.
  static bool indicatesUnusableSession(Object error) {
    if (error is signal.DuplicateMessageException) return false;
    if (error is signal.NoSessionException) return true;
    if (error is signal.UntrustedIdentityException) return true;
    final name = error.runtimeType.toString();
    return name == 'InvalidMessageException' || name == 'InvalidMacException';
  }

  @override
  Future<String> encryptDirect({
    required String recipientId,
    required String plaintext,
  }) => _operations.protect('direct:$recipientId', () async {
    if (!await _ensureSessionUnlocked(recipientId)) {
      throw StateError('Signal session could not be established: $recipientId');
    }
    final address = signal.SignalProtocolAddress(recipientId, deviceId);
    final signal.CiphertextMessage message;
    try {
      message = await signal.SessionCipher.fromStore(
        _store,
        address,
      ).encrypt(Uint8List.fromList(utf8.encode(plaintext)));
    } on signal.UntrustedIdentityException {
      await _onPeerIdentityRotated?.call(recipientId);
      rethrow;
    }
    final type = message.getType() == signal.CiphertextMessage.prekeyType
        ? 'PREKEY'
        : 'SIGNAL';
    final registrationId = await _store.getLocalRegistrationId();
    return 'E2EE:v1:$type:$registrationId:${base64Encode(message.serialize())}';
  });

  @override
  Future<String> decryptDirect({
    required String senderId,
    required String envelope,
  }) => _operations.protect('direct:$senderId', () async {
    final parts = envelope.split(':');
    if (parts.length != 5 || parts[0] != 'E2EE' || parts[1] != 'v1') {
      throw FormatException('Unsupported Signal envelope', envelope);
    }
    final bytes = _decodeBase64(parts[4]);
    final cipher = signal.SessionCipher.fromStore(
      _store,
      signal.SignalProtocolAddress(senderId, deviceId),
    );
    final List<int> plaintext;
    try {
      plaintext = switch (parts[2]) {
        'PREKEY' => await cipher.decrypt(signal.PreKeySignalMessage(bytes)),
        'SIGNAL' => await cipher.decryptFromSignal(
          signal.SignalMessage.fromSerialized(bytes),
        ),
        _ => throw FormatException('Unknown Signal envelope type', parts[2]),
      };
    } on FormatException {
      rethrow;
    } catch (error) {
      if (!indicatesUnusableSession(error)) rethrow;
      // Oturum olu: bir daha kullanilmasin diye hemen silinir, boylece
      // sonraki gonderim taze bir prekey bundle ile X3DH'i bastan kurar.
      await _resetPeerSessionUnlocked(senderId);
      if (error is signal.UntrustedIdentityException) {
        await _onPeerIdentityRotated?.call(senderId);
      }
      throw SignalSessionUnusableException(peerId: senderId, cause: error);
    }
    return utf8.decode(plaintext);
  });

  Future<String> createSenderKeyDistribution({
    required String groupId,
    required String senderId,
  }) => _operations.protect('group:$groupId:$senderId', () async {
    final name = _senderKeyName(groupId, senderId);
    final message = await signal.GroupSessionBuilder(_store).create(name);
    return 'SKDM:$groupId:${base64Encode(message.serialize())}';
  });

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
    await _operations.protect('group:$groupId:$senderId', () async {
      await signal.GroupSessionBuilder(
        _store,
      ).process(_senderKeyName(groupId, senderId), message);
    });
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
  }) => _operations.protect('group:$groupId:$senderId', () async {
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
  });

  @override
  Future<String> decryptGroup({
    required String senderId,
    required String groupId,
    required String envelope,
  }) => _operations.protect('group:$groupId:$senderId', () async {
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
  });

  Future<void> resetLocalSenderKey(String groupId, String senderId) =>
      _operations.protect(
        'group:$groupId:$senderId',
        () => _store.resetSenderKey(groupId, senderId),
      );

  signal.SenderKeyName _senderKeyName(String groupId, String senderId) =>
      signal.SenderKeyName(
        groupId,
        signal.SignalProtocolAddress(senderId, deviceId),
      );
}

Uint8List _decodeBase64(String value) =>
    Uint8List.fromList(base64Decode(base64.normalize(value)));
