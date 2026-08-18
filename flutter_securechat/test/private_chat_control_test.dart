import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/chat/private_chat_control.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('private control binds identity and protects edit metadata', () async {
    final crypto = LocalAeadCryptoService(
      SecretKey(List<int>.generate(32, (index) => index + 17)),
    );
    final signaling = InMemorySignalingService();
    await signaling.connect(
      userId: 'alice',
      url: 'wss://test.invalid',
      accessToken: 'token',
    );
    addTearDown(signaling.disconnect);
    final control = MessageEditSignal(
      senderId: 'alice',
      recipientId: 'bob',
      timestamp: DateTime.fromMillisecondsSinceEpoch(1234),
      messageId: 'private-message-id',
      newContent: 'çok gizli yeni içerik',
    );

    expect(
      await sendPrivateChatControl(
        crypto: crypto,
        signaling: signaling,
        control: control,
      ),
      isTrue,
    );
    final wire = signaling.sentMessages.single as EncryptedSignalMessage;
    expect(wire.type, 'encrypted_message');
    expect(wire.encode(), isNot(contains('message_edit')));
    expect(wire.encode(), isNot(contains('private-message-id')));
    expect(wire.encode(), isNot(contains('çok gizli')));

    final plaintext = await crypto.decryptDirect(
      senderId: 'bob',
      envelope: wire.envelope,
    );
    final decoded =
        decodePrivateChatControl(
              plaintext: plaintext,
              authenticatedSenderId: 'authenticated-alice',
              localRecipientId: 'bob',
            )
            as MessageEditSignal;
    expect(decoded.senderId, 'authenticated-alice');
    expect(decoded.recipientId, 'bob');
    expect(decoded.messageId, 'private-message-id');
    expect(decoded.newContent, 'çok gizli yeni içerik');
  });

  test('all private control types have equal padded plaintext size', () {
    final now = DateTime.fromMillisecondsSinceEpoch(1);
    final controls = <SignalMessage>[
      DeliveryReceiptSignal(
        senderId: 'a',
        recipientId: 'b',
        timestamp: now,
        messageId: 'm',
        status: 'READ',
      ),
      MessageEditSignal(
        senderId: 'a',
        recipientId: 'b',
        timestamp: now,
        messageId: 'a-very-long-message-id',
        newContent: 'a substantially longer secret value',
      ),
      TypingIndicatorSignal(
        senderId: 'a',
        recipientId: 'b',
        timestamp: now,
        isTyping: true,
      ),
    ];
    expect(
      controls
          .map(encodePrivateChatControl)
          .map((value) => value.length)
          .toSet(),
      hasLength(1),
    );
  });

  test('malformed and unsupported controls fail closed', () {
    expect(
      () => decodePrivateChatControl(
        plaintext: 'CHATCTRL:v2:not-base64',
        authenticatedSenderId: 'a',
        localRecipientId: 'b',
      ),
      throwsA(anything),
    );
    expect(
      () => encodePrivateChatControl(
        PresenceUpdateSignal(
          senderId: 'a',
          recipientId: 'b',
          timestamp: DateTime.now(),
          isOnline: true,
          lastSeen: DateTime.now(),
        ),
      ),
      throwsArgumentError,
    );
  });
}
