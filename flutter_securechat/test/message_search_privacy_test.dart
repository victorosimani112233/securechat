import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/chat/conversation_preview.dart';
import 'package:flutter_securechat/src/chat/message_search.dart';
import 'package:flutter_securechat/src/core/models.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('local search excludes expired text and file path components', () {
    final expired = LocalMessage(
      id: 'expired',
      conversationId: 'chat',
      senderId: 'peer',
      peerId: 'me',
      content: 'Expired visible text',
      contentType: MessageContentType.text,
      timestamp: DateTime(2020),
      expiresAt: DateTime(2021),
      status: MessageStatus.read,
      isOutgoing: false,
    );
    expect(expired.searchText, isEmpty);
    expect(
      messageSearchText(
        content: '/private/user/report.pdf|application/pdf|10|/secret/storage',
        contentType: 'file',
        isViewOnce: false,
        caption: 'Report caption',
      ),
      'report.pdf\nReport caption',
    );
  });

  late Directory root;
  late File file;
  late LocalAeadCryptoService crypto;
  late SecureChatDatabase db;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('search_privacy_');
    file = File('${root.path}/db');
    crypto = LocalAeadCryptoService(SecretKey(List.generate(32, (i) => i)));
    db = await SecureChatDatabase.open(file: file, crypto: crypto);
    await db.conversations.insert(
      const ConversationEntity(
        id: 'chat',
        peerId: 'chat',
        peerName: 'Chat',
        peerPhone: '',
      ),
    );
  });
  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });

  MessageEntity message(
    String id,
    StorageMessageContentType type,
    String content, {
    String? caption,
    bool once = false,
    int? expiresAt,
  }) => MessageEntity(
    id: id,
    conversationId: 'chat',
    senderId: 'peer',
    content: content,
    contentType: type,
    timestamp: 10,
    status: StorageMessageStatus.delivered,
    isOutgoing: false,
    isViewOnce: once,
    caption: caption,
    isStarred: true,
    expiresAt: expiresAt,
  );

  test(
    'chat and global search index visible text only and exclude view-once',
    () async {
      final entries = [
        message('text', StorageMessageContentType.text, 'Visible needle'),
        message(
          'once-text',
          StorageMessageContentType.text,
          'secret needle',
          once: true,
        ),
        message(
          'image',
          StorageMessageContentType.image,
          'hidden-image.jpg|image/jpeg|12|/private/path-token',
          caption: 'photo needle',
        ),
        message(
          'once-image',
          StorageMessageContentType.image,
          'secret.jpg|image/jpeg|12|/private/path-token',
          caption: 'secret needle',
          once: true,
        ),
        message(
          'voice',
          StorageMessageContentType.voiceNote,
          'voice-token.m4a|audio/mp4|12|/private/path-token|12000|0.001',
        ),
        message(
          'poll',
          StorageMessageContentType.poll,
          jsonEncode({
            'question': 'Visible needle question',
            'options': ['Tea', 'Coffee'],
            'singleChoice': true,
            'votes': {
              '0': ['hidden-voter-token'],
            },
          }),
        ),
        message(
          'call',
          StorageMessageContentType.system,
          'CALL|call-token|voice|incoming|duration-token',
        ),
        message(
          'document',
          StorageMessageContentType.file,
          'Report.pdf|application/pdf|12|/private/path-token',
          caption: 'document needle',
        ),
        message(
          'once-document',
          StorageMessageContentType.file,
          'Secret.pdf|application/pdf|12|/private/path-token',
          caption: 'secret needle',
          once: true,
        ),
        message(
          'expired',
          StorageMessageContentType.text,
          'expired needle',
          expiresAt: 1,
        ),
      ];
      for (final entry in entries) {
        await db.messages.insert(entry);
      }
      for (final query in ['needle', 'NEEDLE']) {
        expect(
          (await db.messages.searchMessages('chat', query).first)
              .map((m) => m.id)
              .toSet(),
          {'text', 'image', 'poll', 'document'},
        );
        expect(
          (await db.messages.searchAllMessages(query)).map((m) => m.id).toSet(),
          {'text', 'image', 'poll', 'document'},
        );
      }
      for (final query in [
        'path-token',
        'hidden-voter-token',
        'singleChoice',
        'duration-token',
        'voice-token',
        'hidden-image',
        'secret',
      ]) {
        expect(
          await db.messages.searchMessages('chat', query).first,
          isEmpty,
          reason: query,
        );
        expect(
          await db.messages.searchAllMessages(query),
          isEmpty,
          reason: query,
        );
      }
      expect(
        (await db.messages.searchMessages('chat', 'Coffee').first).single.id,
        'poll',
      );
      expect(
        (await db.messages.searchMessages('chat', 'Report').first).single.id,
        'document',
      );
      expect(
        (await db.messages.getMediaMessages('chat').first).map((m) => m.id),
        ['image'],
      );
      expect(
        (await db.messages.getDocumentMessages('chat').first).map((m) => m.id),
        ['document'],
      );
      expect(
        (await db.messages.getStarredMessages('chat').first).any(
          (m) => m.isViewOnce || m.id == 'expired',
        ),
        isFalse,
      );
    },
  );

  test(
    'malformed polls and empty queries do not match hidden serialization',
    () async {
      expect(
        messageSearchText(
          content: '{"question":"needle","options":[]}',
          contentType: 'poll',
          isViewOnce: false,
        ),
        '',
      );
      await db.messages.insert(
        message('text', StorageMessageContentType.text, '100% visible'),
      );
      expect(await db.messages.searchMessages('chat', ' ').first, isEmpty);
      expect(
        (await db.messages.searchMessages('chat', '%').first).single.id,
        'text',
      );
    },
  );

  test(
    'reopening repairs legacy private captions and stale sending summaries',
    () async {
      final once = message(
        'once',
        StorageMessageContentType.image,
        'secret.jpg|image/jpeg|12|private',
        caption: 'secret caption',
        once: true,
      );
      await db.messages.insert(once);
      await db.conversations.updateLastMessageById(
        'chat',
        'Photo secret caption',
        10,
      );
      await db.conversations.insert(
        const ConversationEntity(
          id: 'voice',
          peerId: 'voice',
          peerName: 'Voice',
          peerPhone: '',
          lastMessage: 'Voice message',
          lastMessageTimestamp: 11,
          lastMessageStatus: 'sending',
          lastMessageOutgoing: true,
        ),
      );
      await db.messages.insert(
        const MessageEntity(
          id: 'voice',
          conversationId: 'voice',
          senderId: 'me',
          content: 'voice.m4a|audio/mp4|12|private',
          contentType: StorageMessageContentType.voiceNote,
          timestamp: 11,
          status: StorageMessageStatus.delivered,
          isOutgoing: true,
        ),
      );
      await db.close();
      db = await SecureChatDatabase.open(file: file, crypto: crypto);
      expect(
        (await db.conversations.getById('chat'))!.lastMessage,
        viewOncePreviewLabel,
      );
      expect(
        (await db.conversations.getById('voice'))!.lastMessageStatus,
        'delivered',
      );
    },
  );

  test(
    'expiry revealing an older view-once message cannot leak its body',
    () async {
      await db.messages.insert(
        message(
          'once',
          StorageMessageContentType.text,
          'secret body',
          once: true,
        ),
      );
      await db.messages.insert(
        message(
          'expired',
          StorageMessageContentType.text,
          'newer',
          expiresAt: 1,
        ),
      );
      await db.messages.deleteExpiredMessages(
        DateTime.now().millisecondsSinceEpoch,
      );
      expect(
        (await db.conversations.getById('chat'))!.lastMessage,
        viewOncePreviewLabel,
      );
    },
  );
}
