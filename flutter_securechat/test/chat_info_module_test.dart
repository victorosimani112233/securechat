import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/chat/chat_info_service.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/private_chat_control_support.dart';

void main() {
  test('chat info filters, preferences and timer propagation work', () async {
    final root = await Directory.systemTemp.createTemp('chat_info_test_');
    final crypto = LocalAeadCryptoService(
      SecretKey(List<int>.generate(32, (index) => index + 9)),
    );
    final database = await SecureChatDatabase.open(
      file: File('${root.path}/db'),
      crypto: crypto,
    );
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });
    await database.conversations.insert(
      const ConversationEntity(
        id: 'peer',
        peerId: 'peer',
        peerName: 'Kişi',
        peerPhone: '+90',
      ),
    );
    await database.messages.insert(
      const MessageEntity(
        id: 'star',
        conversationId: 'peer',
        senderId: 'peer',
        content: 'aranan içerik',
        contentType: StorageMessageContentType.text,
        timestamp: 1,
        status: StorageMessageStatus.read,
        isOutgoing: false,
        isStarred: true,
      ),
    );
    final signaling = InMemorySignalingService();
    await signaling.connect(userId: 'me', url: 'ws://test', accessToken: 'x');
    final service = ChatInfoService(
      database: database,
      session: SessionStore(userId: 'me'),
      signaling: signaling,
      crypto: crypto,
    );
    expect(await service.search('peer', 'aranan').first, hasLength(1));
    expect(await service.watchStarred('peer').first, hasLength(1));
    await service.updateNote('peer', '  önemli  ');
    await service.setMuted('peer', true);
    await service.setLocked('peer', true);
    final conversation = (await database.conversations.getById('peer'))!;
    await service.setDisappearingTimer(conversation, const Duration(days: 1));
    final updated = (await database.conversations.getById('peer'))!;
    expect(updated.contactNote, 'önemli');
    expect(updated.isMuted, isTrue);
    expect(updated.isLocked, isTrue);
    expect(
      updated.disappearingDuration,
      const Duration(days: 1).inMilliseconds,
    );
    final wire = signaling.sentMessages.single as EncryptedSignalMessage;
    final control = await decryptTestPrivateChatControl(
      crypto: crypto,
      wire: wire,
    );
    expect(
      (control as DisappearingTimerSignal).durationMs,
      const Duration(days: 1).inMilliseconds,
    );
    expect(wire.encode(), isNot(contains('conversationId')));
  });
}
