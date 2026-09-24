import '../core/signal_message.dart';
import '../services/crypto_service.dart';
import 'signal_protocol_crypto_service.dart';

/// Text and attachments must distribute the same current SenderKey before
/// encrypting group payloads, including the first message after a key reset.
Future<void> distributeGroupSenderKey({
  required CryptoService crypto,
  required String senderId,
  required String groupId,
  required Iterable<String> members,
  required DateTime timestamp,
  required Future<bool> Function(EncryptedSignalMessage signal) send,
}) async {
  if (crypto is! SignalProtocolCryptoService) return;
  final distribution = await crypto.createSenderKeyDistribution(
    groupId: groupId,
    senderId: senderId,
  );
  for (final member in members.toSet().where((id) => id != senderId)) {
    final encrypted = await crypto.encryptDirect(
      recipientId: member,
      plaintext: distribution,
    );
    if (!await send(
      EncryptedSignalMessage(
        senderId: senderId,
        recipientId: member,
        timestamp: timestamp,
        envelope: encrypted,
      ),
    ))
      throw StateError('Group key distribution failed');
  }
}
