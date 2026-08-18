import 'package:flutter_securechat/src/chat/private_chat_control.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';

/// Opens an outbound control produced with the deterministic local AEAD test
/// backend. Production Signal sessions derive their key from the remote
/// identity; LocalAeadCryptoService derives it from the target label instead.
Future<SignalMessage> decryptTestPrivateChatControl({
  required CryptoService crypto,
  required EncryptedSignalMessage wire,
}) async {
  final plaintext = await crypto.decryptDirect(
    senderId: wire.recipientId,
    envelope: wire.envelope,
  );
  return decodePrivateChatControl(
    plaintext: plaintext,
    authenticatedSenderId: wire.senderId,
    localRecipientId: wire.recipientId,
  );
}

Future<EncryptedSignalMessage> encryptTestPrivateChatControl({
  required CryptoService crypto,
  required SignalMessage control,
}) async => EncryptedSignalMessage(
  senderId: control.senderId,
  recipientId: control.recipientId,
  timestamp: control.timestamp,
  envelope: await crypto.encryptDirect(
    recipientId: control.recipientId,
    plaintext: encodePrivateChatControl(control),
  ),
);
