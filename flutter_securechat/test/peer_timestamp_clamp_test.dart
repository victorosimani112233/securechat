import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/incoming/incoming_message_handler.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regresyon: mesaj siralamasi karsi tarafin gonderdigi zaman damgasina
/// dayaniyor. Kirpilmazsa kotu niyetli bir peer cok ileri tarihli bir damga
/// gonderip mesajini sohbetin ve sohbet listesinin tepesine KALICI olarak
/// sabitleyebilir.
void main() {
  late Directory directory;
  late SecureChatDatabase database;
  late LocalAeadCryptoService crypto;
  late InMemorySignalingService signaling;
  late IncomingMessageHandler handler;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ts_clamp_');
    crypto = LocalAeadCryptoService(SecretKey(List.filled(32, 4)));
    database = await SecureChatDatabase.open(
      file: File('${directory.path}/db.securejson'),
      crypto: crypto,
    );
    signaling = InMemorySignalingService();
    await signaling.connect(
      userId: 'me',
      url: 'ws://local',
      accessToken: 'token',
    );
    handler = IncomingMessageHandler(
      signaling: signaling,
      crypto: crypto,
      database: database,
      session: SessionStore(userId: 'me', accessToken: 'token'),
    )..start();
  });

  tearDown(() async {
    await handler.close();
    await database.close();
    await directory.delete(recursive: true);
  });

  Future<void> deliver(String text, DateTime at) async {
    final envelope = await crypto.encryptDirect(
      recipientId: 'me',
      plaintext: 'MSGID:${at.microsecondsSinceEpoch}:$text',
    );
    signaling.addIncoming(
      EncryptedSignalMessage(
        senderId: 'peer',
        recipientId: 'me',
        timestamp: at,
        envelope: envelope,
      ),
    );
    await handler.waitForIdle();
  }

  test('cok ileri tarihli damga simdiye kirpilir', () async {
    final future = DateTime.now().add(const Duration(days: 3650));
    await deliver('gelecekten', future);
    final messages = await database.messages.getMessagesImmediate('peer');
    expect(messages, hasLength(1));
    final stored = DateTime.fromMillisecondsSinceEpoch(messages.single.timestamp);
    expect(
      stored.isBefore(DateTime.now().add(const Duration(minutes: 6))),
      isTrue,
      reason: 'damga simdiye kirpilmali, saklanan: $stored',
    );
  });

  test('kucuk saat kaymasi korunur', () async {
    final slightlyAhead = DateTime.now().add(const Duration(minutes: 2));
    await deliver('hafif ileri', slightlyAhead);
    final messages = await database.messages.getMessagesImmediate('peer');
    expect(
      messages.single.timestamp,
      slightlyAhead.millisecondsSinceEpoch,
      reason: 'tolerans icindeki kayma degistirilmemeli',
    );
  });

  test('gecikmeli teslim edilen eski mesaj degistirilmez', () async {
    final past = DateTime.now().subtract(const Duration(days: 2));
    await deliver('gecmisten', past);
    final messages = await database.messages.getMessagesImmediate('peer');
    expect(
      messages.single.timestamp,
      past.millisecondsSinceEpoch,
      reason: 'geri yonde kirpma yapilmamali',
    );
  });
}
