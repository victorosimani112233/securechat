import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

abstract interface class CryptoService {
  Future<String> encryptDirect({
    required String recipientId,
    required String plaintext,
  });

  Future<String> decryptDirect({
    required String senderId,
    required String envelope,
  });

  Future<String> encryptGroup({
    required String senderId,
    required String groupId,
    required String plaintext,
  });

  Future<String> decryptGroup({
    required String senderId,
    required String groupId,
    required String envelope,
  });
}

/// Produces the opaque, stable group routing token used by wire envelopes.
///
/// Group identifiers are expected to be cryptographically random UUIDs. The
/// token prevents the identifier and the human-readable group name from being
/// exposed in queued per-recipient envelopes. It is deliberately centralized
/// so production Signal and local test crypto cannot drift.
Future<String> groupRoutingToken(String groupId) async =>
    base64UrlEncode((await Sha256().hash(utf8.encode(groupId))).bytes);

/// Creates an unlinkable, high-entropy routing nonce for one live operation.
String newOpaqueRoutingNonce() {
  final random = Random.secure();
  return base64UrlEncode(
    List<int>.generate(32, (_) => random.nextInt(256)),
  ).replaceAll('=', '');
}

/// Resolves the remote key label used only by the deterministic local AEAD
/// backend. Production Signal sessions always authenticate by sender.
String directDecryptionPeer({
  required String envelope,
  required String authenticatedSenderId,
  required String localRecipientId,
}) => envelope.startsWith('E2EE:v1:LOCAL_AES_GCM:')
    ? localRecipientId
    : authenticatedSenderId;

/// Reads an opaque group token without exposing or guessing the underlying
/// group identifier. Both formats are accepted because local integration
/// tests use GROUPMETA while production uses Signal SenderKey GROUPSK.
String? groupRoutingTokenFromEnvelope(String envelope) {
  final prefix = envelope.startsWith('GROUPSK:v2:')
      ? 'GROUPSK:v2:'
      : envelope.startsWith('GROUPMETA:v1:')
      ? 'GROUPMETA:v1:'
      : null;
  if (prefix == null) return null;
  final rest = envelope.substring(prefix.length);
  final separator = rest.indexOf(':');
  if (separator < 1) return null;
  return rest.substring(0, separator);
}

class LocalAeadCryptoService implements CryptoService {
  LocalAeadCryptoService(this._masterKey);

  final SecretKey _masterKey;
  final AesGcm _aead = AesGcm.with256bits();
  final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  static List<int> newMasterKeyBytes() {
    final random = Random.secure();
    return List<int>.generate(32, (_) => random.nextInt(256));
  }

  @override
  Future<String> encryptDirect({
    required String recipientId,
    required String plaintext,
  }) async {
    return _encryptWire(
      prefix: 'E2EE:v1:LOCAL_AES_GCM',
      context: 'direct:$recipientId',
      plaintext: plaintext,
    );
  }

  @override
  Future<String> decryptDirect({
    required String senderId,
    required String envelope,
  }) async {
    return _decryptWire(
      expectedPrefix: 'E2EE:v1:LOCAL_AES_GCM',
      context: 'direct:$senderId',
      envelope: envelope,
    );
  }

  @override
  Future<String> encryptGroup({
    required String senderId,
    required String groupId,
    required String plaintext,
  }) async {
    final encrypted = await _encryptWire(
      prefix: 'GROUPSK:v1:LOCAL_AES_GCM',
      context: 'group:$groupId:$senderId',
      plaintext: plaintext,
    );
    final routingToken = await groupRoutingToken(groupId);
    return 'GROUPMETA:v1:$routingToken:$encrypted';
  }

  @override
  Future<String> decryptGroup({
    required String senderId,
    required String groupId,
    required String envelope,
  }) async {
    var encrypted = envelope;
    if (envelope.startsWith('GROUPMETA:v1:')) {
      final rest = envelope.substring('GROUPMETA:v1:'.length);
      final separator = rest.indexOf(':');
      if (separator < 1) throw const FormatException('Missing group metadata');
      final routingToken = rest.substring(0, separator);
      final expectedToken = await groupRoutingToken(groupId);
      if (routingToken != expectedToken) {
        throw const FormatException('Encrypted group metadata does not match');
      }
      encrypted = rest.substring(separator + 1);
    }
    return _decryptWire(
      expectedPrefix: 'GROUPSK:v1:LOCAL_AES_GCM',
      context: 'group:$groupId:$senderId',
      envelope: encrypted,
    );
  }

  Future<String> encryptStorageJson(String plaintext) {
    return _encryptWire(
      prefix: 'STORE:v1:LOCAL_AES_GCM',
      context: 'local-store',
      plaintext: plaintext,
    );
  }

  Future<String> decryptStorageJson(String envelope) {
    return _decryptWire(
      expectedPrefix: 'STORE:v1:LOCAL_AES_GCM',
      context: 'local-store',
      envelope: envelope,
    );
  }

  Future<String> _encryptWire({
    required String prefix,
    required String context,
    required String plaintext,
  }) async {
    final key = await _deriveKey(context);
    final nonce = _randomBytes(12);
    final secretBox = await _aead.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      nonce: nonce,
    );
    return [
      prefix,
      base64Encode(secretBox.nonce),
      base64Encode(secretBox.mac.bytes),
      base64Encode(secretBox.cipherText),
    ].join(':');
  }

  Future<String> _decryptWire({
    required String expectedPrefix,
    required String context,
    required String envelope,
  }) async {
    final parts = envelope.split(':');
    if (parts.length != 6 || parts.take(3).join(':') != expectedPrefix) {
      throw FormatException('Unsupported encrypted envelope format', envelope);
    }
    final key = await _deriveKey(context);
    final box = SecretBox(
      base64Decode(parts[5]),
      nonce: base64Decode(parts[3]),
      mac: Mac(base64Decode(parts[4])),
    );
    final bytes = await _aead.decrypt(box, secretKey: key);
    return utf8.decode(bytes);
  }

  Future<SecretKey> _deriveKey(String context) {
    return _hkdf.deriveKey(
      secretKey: _masterKey,
      nonce: utf8.encode(context),
      info: utf8.encode('securechat.flutter.local-aead.v1'),
    );
  }

  List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }
}
