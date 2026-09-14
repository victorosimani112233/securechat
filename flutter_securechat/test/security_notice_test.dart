import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/chat/security_notice_service.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';

/// Kimlik rotasyonu otomatik kabul ediliyor (aksi halde sohbet olur, bkz
/// BUG-009). Kabul sessiz kalirsa prekey bundle'i degistirebilen bir sunucu
/// fark edilmeden araya girebilir; bu yuzden kullanici degisikligi GORMELI.
void main() {
  late Directory directory;
  late SecureChatDatabase database;
  late SecurityNoticeService notices;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('security_notice_');
    database = await SecureChatDatabase.open(
      file: File('${directory.path}/db.securejson'),
      crypto: LocalAeadCryptoService(SecretKey(List.filled(32, 9))),
    );
    notices = SecurityNoticeService(database: database);
    await database.conversations.insert(
      const ConversationEntity(
        id: 'peer-1',
        peerId: 'peer-1',
        peerName: 'Peer',
        peerPhone: '',
      ),
    );
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  test('kimlik rotasyonu sohbete gorunur sistem mesaji yazar', () async {
    await notices.peerIdentityRotated('peer-1');
    final messages = await database.messages.getMessagesImmediate('peer-1');
    expect(messages, hasLength(1));
    expect(messages.single.contentType, StorageMessageContentType.system);
    expect(messages.single.senderId, 'SYSTEM');
    expect(messages.single.content, contains('Güvenlik numarası değişti'));

    final conversation = await database.conversations.getById('peer-1');
    expect(conversation!.lastMessage, contains('Güvenlik numarası değişti'));
    expect(conversation.unreadCount, 1, reason: 'kullanicinin dikkatini cekmeli');
  });

  test('ayni gun tekrarlanan rotasyon sohbeti doldurmaz', () async {
    final now = DateTime(2026, 8, 25, 10);
    await notices.peerIdentityRotated('peer-1', at: now);
    await notices.peerIdentityRotated('peer-1', at: now.add(const Duration(minutes: 5)));
    final messages = await database.messages.getMessagesImmediate('peer-1');
    expect(messages, hasLength(1));
  });

  test('bilinmeyen sohbet icin sessiz kalir', () async {
    await notices.peerIdentityRotated('hic-konusulmamis');
    final messages = await database.messages.getMessagesImmediate('hic-konusulmamis');
    expect(messages, isEmpty);
  });
}
