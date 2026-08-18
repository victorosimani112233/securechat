import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/chat/chat_activity_service.dart';
import 'package:flutter_securechat/src/chat/private_chat_control.dart';
import 'package:flutter_securechat/src/core/models.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'typing state is deduplicated and sent only as encrypted controls',
    () async {
      final crypto = LocalAeadCryptoService(
        SecretKey(List<int>.generate(32, (index) => index + 31)),
      );
      final signaling = InMemorySignalingService();
      await signaling.connect(
        userId: 'alice',
        url: 'wss://test.invalid',
        accessToken: 'token',
      );
      final activity = ChatActivityService(
        session: _session('alice'),
        signaling: signaling,
        crypto: crypto,
      );
      addTearDown(activity.dispose);
      addTearDown(signaling.dispose);
      const conversation = Conversation(
        id: 'bob',
        peerId: 'bob',
        peerName: 'Bob',
        peerPhone: '',
      );

      await activity.updateTyping(conversation, true);
      await activity.updateTyping(conversation, true);
      expect(signaling.sentMessages, hasLength(1));
      await activity.stopTyping();
      expect(signaling.sentMessages, hasLength(2));

      final states = <bool>[];
      for (final message in signaling.sentMessages) {
        expect(message, isA<EncryptedSignalMessage>());
        expect(message.encode(), isNot(contains('typing_indicator')));
        final wire = message as EncryptedSignalMessage;
        final plaintext = await crypto.decryptDirect(
          senderId: 'bob',
          envelope: wire.envelope,
        );
        final control =
            decodePrivateChatControl(
                  plaintext: plaintext,
                  authenticatedSenderId: 'alice',
                  localRecipientId: 'bob',
                )
                as TypingIndicatorSignal;
        states.add(control.isTyping);
      }
      expect(states, [true, false]);
    },
  );

  test(
    'group typing fans out direct encrypted controls without group metadata',
    () async {
      final crypto = LocalAeadCryptoService(
        SecretKey(List<int>.generate(32, (index) => 255 - index)),
      );
      final signaling = InMemorySignalingService();
      await signaling.connect(
        userId: 'me',
        url: 'wss://test.invalid',
        accessToken: 'token',
      );
      final activity = ChatActivityService(
        session: _session('me'),
        signaling: signaling,
        crypto: crypto,
      );
      addTearDown(activity.dispose);
      addTearDown(signaling.dispose);
      const conversation = Conversation(
        id: 'secret-group-id',
        peerId: 'secret-group-id',
        peerName: 'Secret Group Name',
        peerPhone: '',
        isGroup: true,
        groupMembers: ['me', 'bob', 'charlie'],
        groupAdmins: ['me'],
      );

      await activity.updateTyping(conversation, true);
      expect(signaling.sentMessages, hasLength(2));
      for (final message in signaling.sentMessages) {
        final encoded = message.encode();
        expect(encoded, isNot(contains('secret-group-id')));
        expect(encoded, isNot(contains('Secret Group Name')));
        expect(message, isA<EncryptedSignalMessage>());
      }
    },
  );
}

SessionStore _session(String userId) => SessionStore(
  userId: userId,
  displayName: 'Test',
  phoneNumber: '+900000000000',
  accessToken: 'access',
  refreshToken: 'refresh',
);
