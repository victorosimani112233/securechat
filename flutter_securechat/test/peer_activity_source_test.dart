import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/incoming/incoming_message_handler.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/peer_activity_source.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'peer activity subscribes, refreshes after reconnect and unsubscribes',
    () async {
      final directory = await Directory.systemTemp.createTemp('presence_test_');
      final crypto = LocalAeadCryptoService(
        SecretKey(List<int>.generate(32, (index) => index + 11)),
      );
      final database = await SecureChatDatabase.open(
        file: File('${directory.path}/db.securejson'),
        crypto: crypto,
      );
      final session = SessionStore(userId: 'me', accessToken: 'token');
      final signaling = InMemorySignalingService();
      await signaling.connect(
        userId: 'me',
        url: 'ws://local',
        accessToken: 'token',
      );
      final incoming = IncomingMessageHandler(
        signaling: signaling,
        crypto: crypto,
        database: database,
        session: session,
      )..start();
      addTearDown(() async {
        await incoming.close();
        await signaling.dispose();
        await database.close();
        await directory.delete(recursive: true);
      });
      final source = IncomingPeerActivitySource(
        incoming,
        signaling: signaling,
        session: session,
      );
      final states = <AppPeerActivity>[];
      final subscription = source.watch('alice').listen(states.add);

      await _eventually(
        () =>
            signaling.sentMessages
                .whereType<PresenceSubscribeSignal>()
                .length ==
            1,
      );
      final seenAt = DateTime.fromMillisecondsSinceEpoch(123456);
      signaling.addIncoming(
        PresenceUpdateSignal(
          senderId: 'alice',
          recipientId: 'me',
          timestamp: seenAt,
          isOnline: false,
          lastSeen: seenAt,
        ),
      );
      await incoming.waitForIdle();
      await _eventually(() => states.any((state) => state.lastSeen == seenAt));

      signaling.setConnected(false);
      signaling.setConnected(true);
      await _eventually(
        () =>
            signaling.sentMessages
                .whereType<PresenceSubscribeSignal>()
                .length ==
            2,
      );

      await subscription.cancel();
      expect(
        signaling.sentMessages.whereType<PresenceUnsubscribeSignal>(),
        hasLength(1),
      );
    },
  );
}

Future<void> _eventually(bool Function() predicate) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Condition was not satisfied before timeout');
}
