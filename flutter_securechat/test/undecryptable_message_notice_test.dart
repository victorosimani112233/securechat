import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/chat/private_chat_control.dart';
import 'package:flutter_securechat/src/chat/security_notice_service.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/incoming/incoming_message_handler.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regresyon: cozulemeyen mesaj SESSIZCE dusuyordu.
///
/// Kullanici mesajin var oldugunu hic ogrenemiyordu; gonderen "gonderdim",
/// alan "gelmedi" diyordu. Grup yolunda kalici: sender key kurulamazsa o
/// gondericinin mesajlari cozulemez ve 1:1 oturum kurtarmasi grup anahtarini
/// geri getirmez, yeniden isteme mekanizmasi da yok.
void main() {
  late Directory directory;
  late SecureChatDatabase database;
  late LocalAeadCryptoService crypto;
  late InMemorySignalingService signaling;
  late IncomingMessageHandler handler;
  late List<String> notified;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('undecryptable_');
    crypto = LocalAeadCryptoService(SecretKey(List.filled(32, 11)));
    database = await SecureChatDatabase.open(
      file: File('${directory.path}/db.securejson'),
      crypto: crypto,
    );
    await database.conversations.insert(
      const ConversationEntity(
        id: 'peer',
        peerId: 'peer',
        peerName: 'Peer',
        peerPhone: '',
      ),
    );
    signaling = InMemorySignalingService();
    await signaling.connect(
      userId: 'me',
      url: 'ws://local',
      accessToken: 'token',
    );
    notified = <String>[];
    handler = IncomingMessageHandler(
      signaling: signaling,
      crypto: crypto,
      database: database,
      session: SessionStore(userId: 'me', accessToken: 'token'),
      onUndecryptableMessage: (conversationId) async {
        notified.add(conversationId);
      },
      onAsyncFailure: (_, _, _) {},
    )..start();
  });

  tearDown(() async {
    await handler.close();
    await database.close();
    await directory.delete(recursive: true);
  });

  test('cozulemeyen zarf kullaniciya bildirilir', () async {
    signaling.addIncoming(
      EncryptedSignalMessage(
        senderId: 'peer',
        recipientId: 'me',
        timestamp: DateTime.now(),
        envelope: 'E2EE:v1:SIGNAL:42:bozuk-veri',
      ),
    );
    await handler.waitForIdle();
    expect(notified, ['peer'], reason: 'dusen mesaj sessiz kalmamali');
  });

  // QA 2026-10-13 T16: kalici olarak cozulemeyen mesaj sunucuya
  // onaylanmiyordu; her yeniden baglantida tekrar teslim ediliyor ve alici
  // her seferinde saglam oturumunu siliyordu.
  test('kalici cozulemeyen mesaj onaylanir ve yerel oturum silinmez', () async {
    final failing = _UnusableSessionCrypto();
    final receiving = IncomingMessageHandler(
      signaling: signaling,
      crypto: failing,
      database: database,
      session: SessionStore(userId: 'me', accessToken: 'token'),
      onUndecryptableMessage: (conversationId) async {
        notified.add(conversationId);
      },
      onAsyncFailure: (_, _, _) {},
    )..start();
    addTearDown(receiving.close);
    await handler.close();
    final token = List.filled(43, 'U').join();

    for (var delivery = 0; delivery < 2; delivery++) {
      signaling.addIncoming(
        EncryptedSignalMessage(
          senderId: 'peer',
          recipientId: 'me',
          timestamp: DateTime.now(),
          envelope: 'E2EE:v1:OLM:1:eski-oturum',
          deliveryToken: token,
        ),
      );
      await receiving.waitForIdle();
    }

    final acks = signaling.sentMessages
        .whereType<DeliveryTransportAckSignal>()
        .where((ack) => ack.deliveryToken == token);
    expect(acks, isNotEmpty, reason: 'sunucu mesaji tekrar teslim etmemeli');
    expect(failing.decryptCalls, 1, reason: 'ayni teslim ikinci kez denenmez');
    expect(failing.resets, 0, reason: 'yerel oturumlar korunur');
    expect(failing.freshSessions, 1, reason: 'yeni oturum bir kez acilir');
    expect(
      signaling.sentMessages.whereType<SessionResetRequestSignal>(),
      isEmpty,
      reason: 'duz istek sunucuda reddedilir (T14)',
    );
    final controls = <SignalMessage>[];
    for (final sent
        in signaling.sentMessages.whereType<EncryptedSignalMessage>()) {
      final plaintext = await failing.decryptOwn(
        sent.recipientId,
        sent.envelope,
      );
      if (!isPrivateChatControl(plaintext)) continue;
      controls.add(
        decodePrivateChatControl(
          plaintext: plaintext,
          authenticatedSenderId: 'me',
          localRecipientId: sent.recipientId,
        ),
      );
    }
    expect(
      controls.whereType<SessionResetRequestSignal>(),
      hasLength(1),
      reason: 'karsi taraftan yeni oturum sifreli kanalla istenir',
    );
  });

  test(
    'sistem mesaji sohbette gorunur ve gun basina bir kez yazilir',
    () async {
      final notices = SecurityNoticeService(database: database);
      final day = DateTime(2026, 9, 14, 10);
      await notices.messageUnreadable('peer', at: day);
      await notices.messageUnreadable(
        'peer',
        at: day.add(const Duration(minutes: 30)),
      );

      final messages = await database.messages.getMessagesImmediate('peer');
      expect(messages, hasLength(1), reason: 'sohbet doldurulmamali');
      expect(messages.single.contentType, StorageMessageContentType.system);
      expect(messages.single.senderId, 'SYSTEM');

      final conversation = await database.conversations.getById('peer');
      expect(conversation!.unreadCount, 1, reason: 'dikkat cekmeli');
    },
  );

  test('bozuk sender key dagitimi sessizce yutulmaz', () async {
    final failures = <String>[];
    final reporting = IncomingMessageHandler(
      signaling: signaling,
      crypto: crypto,
      database: database,
      session: SessionStore(userId: 'me', accessToken: 'token'),
      onAsyncFailure: (operation, _, _) => failures.add(operation),
    )..start();
    addTearDown(reporting.close);
    // Anahtar yalniz bilinen grupta, gonderen ve biz uyeyken islenir.
    await database.conversations.insert(
      const ConversationEntity(
        id: 'group-1',
        peerId: 'group-1',
        peerName: 'Grup',
        peerPhone: '',
        isGroup: true,
        groupMembers: 'me,peer',
      ),
    );

    final envelope = await crypto.encryptDirect(
      recipientId: 'me',
      plaintext: 'SKDM:group-1:bu-base64-degil!!',
    );
    signaling.addIncoming(
      EncryptedSignalMessage(
        senderId: 'peer',
        recipientId: 'me',
        timestamp: DateTime.now(),
        envelope: envelope,
      ),
    );
    await reporting.waitForIdle();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
      failures.any((name) => name.contains('sender-key')),
      isTrue,
      reason: 'grup anahtari kurulamadi, teshis izi kalmali: $failures',
    );
  });

  test('grupta olmayan birinin grup anahtari kabul edilmez', () async {
    await database.conversations.insert(
      const ConversationEntity(
        id: 'group-2',
        peerId: 'group-2',
        peerName: 'Grup',
        peerPhone: '',
        isGroup: true,
        groupMembers: 'me,friend',
      ),
    );
    final key = List<int>.generate(32, (i) => i);
    for (final (sender, group) in [
      ('outsider', 'group-2'),
      ('friend', 'unknown-group'),
    ]) {
      signaling.addIncoming(
        EncryptedSignalMessage(
          senderId: sender,
          recipientId: 'me',
          timestamp: DateTime.now(),
          envelope: await crypto.encryptDirect(
            recipientId: 'me',
            plaintext: 'SKDM:$group:${base64Encode(key)}',
          ),
        ),
      );
    }
    signaling.addIncoming(
      EncryptedSignalMessage(
        senderId: 'friend',
        recipientId: 'me',
        timestamp: DateTime.now(),
        envelope: await crypto.encryptDirect(
          recipientId: 'me',
          plaintext: 'SKDM:group-2:${base64Encode(key)}',
        ),
      ),
    );
    await handler.waitForIdle();
    expect(await database.senderKeys.exists('group-2', 'outsider', 1), isFalse);
    expect(
      await database.senderKeys.exists('unknown-group', 'friend', 1),
      isFalse,
    );
    expect(await database.senderKeys.exists('group-2', 'friend', 1), isTrue);
  });
}

/// Her direkt mesajda "oturum kullanilamaz" atar; sifirlama cagrilarini sayar.
class _UnusableSessionCrypto extends LocalAeadCryptoService
    implements PeerSessionRecovery {
  _UnusableSessionCrypto() : super(SecretKey(List.filled(32, 11)));

  int decryptCalls = 0;
  int resets = 0;

  @override
  Future<String> decryptDirect({
    required String senderId,
    required String envelope,
  }) async {
    decryptCalls++;
    throw SignalSessionUnusableException(
      peerId: senderId,
      cause: StateError('eski oturum'),
    );
  }

  int freshSessions = 0;

  /// Bu servisin kendi gonderdigi zarfi acar (yerel AEAD simetrik).
  Future<String> decryptOwn(String recipientId, String envelope) =>
      super.decryptDirect(senderId: recipientId, envelope: envelope);

  @override
  Future<void> resetPeerSession(String peerId) async => resets++;

  @override
  Future<bool> openFreshSession(String peerId) async {
    freshSessions++;
    return true;
  }

  @override
  Future<bool> rebuildPeerSession(String peerId) async {
    resets++;
    return true;
  }
}
