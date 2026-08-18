import 'dart:convert';

import '../services/crypto_service.dart';

const _privateGroupRoutePrefix = 'GROUPROUTE:v3:';

/// Recipient-specific routing data that lives inside a direct Signal session.
/// The server sees an ordinary encrypted_message and cannot correlate messages
/// by a stable group identifier or inspect the SenderKey envelope.
class PrivateGroupRoute {
  const PrivateGroupRoute({required this.groupId, required this.groupEnvelope});

  final String groupId;
  final String groupEnvelope;
}

String encodePrivateGroupRoute({
  required String groupId,
  required String groupEnvelope,
}) {
  if (groupId.isEmpty || groupId.length > 256) {
    throw const FormatException('Invalid private group route identifier');
  }
  if (groupEnvelope.isEmpty || groupEnvelope.length > 2 * 1024 * 1024) {
    throw const FormatException('Invalid private group route envelope');
  }
  final body = base64UrlEncode(
    utf8.encode(
      jsonEncode(<String, Object?>{
        'v': 3,
        'groupId': groupId,
        'envelope': groupEnvelope,
      }),
    ),
  ).replaceAll('=', '');
  return '$_privateGroupRoutePrefix$body';
}

bool isPrivateGroupRoute(String plaintext) =>
    plaintext.startsWith(_privateGroupRoutePrefix);

Future<PrivateGroupRoute> decodePrivateGroupRoute(String plaintext) async {
  if (!isPrivateGroupRoute(plaintext)) {
    throw const FormatException('Not a private group route');
  }
  final encoded = plaintext.substring(_privateGroupRoutePrefix.length);
  final decoded = jsonDecode(
    utf8.decode(base64Url.decode(base64Url.normalize(encoded))),
  );
  if (decoded is! Map) {
    throw const FormatException('Invalid private group route JSON');
  }
  final data = decoded.cast<String, Object?>();
  final groupId = data['groupId'];
  final envelope = data['envelope'];
  if ((data['v'] as num?)?.toInt() != 3 ||
      groupId is! String ||
      groupId.isEmpty ||
      groupId.length > 256 ||
      envelope is! String ||
      envelope.isEmpty ||
      envelope.length > 2 * 1024 * 1024) {
    throw const FormatException('Invalid private group route fields');
  }
  // SenderKey v2 authenticates the same token after direct-route decryption.
  // Checking here rejects a maliciously mixed local id/envelope before crypto.
  final embeddedToken = groupRoutingTokenFromEnvelope(envelope);
  if (embeddedToken == null ||
      embeddedToken != await groupRoutingToken(groupId)) {
    throw const FormatException('Private group route binding mismatch');
  }
  return PrivateGroupRoute(groupId: groupId, groupEnvelope: envelope);
}
