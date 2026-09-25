import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/core/models.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/domain/send_message_use_case.dart';
import 'package:flutter_securechat/src/media/file_transfer_manager.dart';
import 'package:flutter_securechat/src/media/media_attachment.dart';
import 'package:flutter_securechat/src/media/media_message_service.dart';
import 'package:flutter_securechat/src/media/voice_note_service.dart';
import 'package:flutter_securechat/src/services/conversation_repository.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LocalMessage preserves receipt fields through JSON and copy', () {
    final original = LocalMessage.fromJson({
      'id': 'message',
      'receiptRecipients': ['alice', 'bob'],
      'deliveredTo': ['alice', 'bob'],
      'readBy': ['alice'],
    });
    final copy = original.copyWith(content: 'edited');
    final restored = LocalMessage.fromJson(
      jsonDecode(jsonEncode(copy.toJson())) as Map<String, dynamic>,
    );
    expect(restored.receiptRecipients, ['alice', 'bob']);
    expect(restored.deliveredTo, ['alice', 'bob']);
    expect(restored.readBy, ['alice']);
    final updated = restored.copyWith(
      receiptRecipients: ['alice'],
      deliveredTo: [],
      readBy: [],
    );
    expect(updated.receiptRecipients, ['alice']);
    expect(updated.deliveredTo, isEmpty);
    expect(updated.readBy, isEmpty);
    expect(updated.copyWith(receiptRecipients: null).receiptRecipients, isNull);
  });

  test(
    'LocalMessage legacy unknown recipients differ from an empty snapshot',
    () {
      final legacy = LocalMessage.fromJson({});
      expect(legacy.receiptRecipients, isNull);
      expect(legacy.deliveredTo, isEmpty);
      expect(legacy.readBy, isEmpty);
      expect(LocalMessage.fromJson(legacy.toJson()).receiptRecipients, isNull);
      final empty = legacy.copyWith(receiptRecipients: []);
      expect(LocalMessage.fromJson(empty.toJson()).receiptRecipients, isEmpty);
    },
  );

  for (final group in [false, true]) {
    for (final type in [
      StorageMessageContentType.text,
      StorageMessageContentType.poll,
    ]) {
      test(
        'sender snapshots recipients before fast ACK: group=$group ${type.name}',
        () async {
          final f = await _Fixture.open();
          final conversation = await f.conversation(group: group);
          final expected = group ? ['alice', 'bob'] : ['alice'];
          final signals = <String>[];
          final signaling = _InspectSignaling((signal) async {
            final message = (await f.db.messages.getAllMessages()).single;
            expect(message.receiptRecipients, expected);
            if (signals.isEmpty) {
              expect(message.status, StorageMessageStatus.sending);
              expect(message.deliveredTo, isEmpty);
              expect(message.readBy, isEmpty);
              if (group) {
                final current = (await f.db.conversations.getById(
                  conversation.id,
                ))!;
                await f.db.conversations.insert(
                  current.copyWith(groupMembers: 'me,new-member'),
                );
              }
            }
            signals.add(signal.recipientId);
            expect(
              await f.db.messages.recordDeliveryReceipt(
                message.id,
                recipientId: signal.recipientId,
                status: StorageMessageStatus.read,
                localUserId: 'me',
              ),
              isTrue,
            );
          })..setConnected(true);
          addTearDown(signaling.dispose);
          final sender = f.sender(signaling);
          expect(
            await sender(
              SendMessageRequest(
                conversationId: conversation.id,
                content: 'receipt test',
                contentType: type,
              ),
            ),
            SendMessageOutcome.sent,
          );
          expect(signals.toSet(), expected.toSet());
          final stored = (await f.db.messages.getAllMessages()).single;
          expect(stored.receiptRecipients, expected);
          expect(stored.readBy, expected);
          expect(stored.deliveredTo, expected);
          expect(stored.status, StorageMessageStatus.read);
          expect(
            (await f.db.conversations.getById(
              conversation.id,
            ))!.lastMessageStatus,
            'read',
          );
        },
      );
    }
  }

  for (final group in [false, true]) {
    for (final voice in [false, true]) {
      test(
        'media snapshots transfer recipients before fast ACK: group=$group voice=$voice',
        () async {
          final f = await _Fixture.open();
          final conversation = await f.conversation(group: group);
          final expected = group ? ['alice', 'bob'] : ['alice'];
          var transfersStarted = 0;
          final transfers = _InspectTransfers((id, recipients) async {
            transfersStarted++;
            expect(recipients, expected);
            final stored = (await f.db.messages.getById(id))!;
            expect(stored.receiptRecipients, expected);
            expect(stored.status, StorageMessageStatus.sending);
            expect(stored.deliveredTo, isEmpty);
            expect(stored.readBy, isEmpty);
            if (group) {
              final current = (await f.db.conversations.getById(
                conversation.id,
              ))!;
              await f.db.conversations.insert(
                current.copyWith(groupMembers: 'me,new-member'),
              );
            }
            for (final recipient in recipients) {
              expect(
                await f.db.messages.recordDeliveryReceipt(
                  id,
                  recipientId: recipient,
                  status: StorageMessageStatus.read,
                  localUserId: 'me',
                ),
                isTrue,
              );
            }
          });
          final media = MediaMessageService(
            database: f.db,
            transfers: transfers,
            session: SessionStore(userId: 'me'),
            localMediaDirectory: Directory('${f.root.path}/media'),
          );
          addTearDown(media.close);
          final source = File(
            '${f.root.path}/${voice ? 'voice.m4a' : 'image.jpg'}',
          );
          await source.writeAsBytes([1, 2, 3]);
          final attachment = await MediaAttachment.fromPath(source.path);
          if (voice) {
            await media.sendVoiceNote(
              conversationId: conversation.id,
              recipientId: conversation.id,
              draft: VoiceNoteDraft(
                attachment: attachment,
                metadata: const VoiceNoteMetadata(
                  duration: Duration(seconds: 1),
                  waveform: [.2, .8],
                ),
              ),
              isGroup: group,
              groupMembers: const ['me', 'departed-member'],
            );
          } else {
            await media.send(
              conversationId: conversation.id,
              recipientId: conversation.id,
              attachments: [attachment],
              isGroup: group,
              groupMembers: const ['me', 'departed-member'],
            );
          }
          expect(transfersStarted, 1);
          final stored = (await f.db.messages.getAllMessages()).single;
          expect(stored.receiptRecipients, expected);
          expect(stored.readBy, expected);
          expect(stored.status, StorageMessageStatus.read);
          expect(
            (await f.db.conversations.getById(
              conversation.id,
            ))!.lastMessageStatus,
            'read',
          );
          expect(
            stored.contentType,
            voice
                ? StorageMessageContentType.voiceNote
                : StorageMessageContentType.image,
          );
        },
      );
    }
  }

  for (final mediaSend in [false, true]) {
    test(
      'final group send preserves partial receipt and preview: media=$mediaSend',
      () async {
        final f = await _Fixture.open();
        final conversation = await f.conversation(group: true);
        Future<void> acknowledgeAlice(String id) async {
          expect(
            await f.db.messages.recordDeliveryReceipt(
              id,
              recipientId: 'alice',
              status: StorageMessageStatus.read,
              localUserId: 'me',
            ),
            isTrue,
          );
        }

        if (mediaSend) {
          final media = MediaMessageService(
            database: f.db,
            transfers: _InspectTransfers((id, _) => acknowledgeAlice(id)),
            session: SessionStore(userId: 'me'),
            localMediaDirectory: Directory('${f.root.path}/media'),
          );
          addTearDown(media.close);
          final source = File('${f.root.path}/image.jpg');
          await source.writeAsBytes([1, 2, 3]);
          await media.send(
            conversationId: conversation.id,
            recipientId: conversation.id,
            attachments: [await MediaAttachment.fromPath(source.path)],
            isGroup: true,
            groupMembers: const [],
          );
        } else {
          final signaling = _InspectSignaling((signal) async {
            if (signal.recipientId == 'alice') {
              await acknowledgeAlice(
                (await f.db.messages.getAllMessages()).single.id,
              );
            }
          })..setConnected(true);
          addTearDown(signaling.dispose);
          expect(
            await f.sender(signaling)(
              SendMessageRequest(
                conversationId: conversation.id,
                content: 'partial receipt',
              ),
            ),
            SendMessageOutcome.sent,
          );
        }
        final stored = (await f.db.messages.getAllMessages()).single;
        expect(stored.receiptRecipients, ['alice', 'bob']);
        expect(stored.deliveredTo, ['alice']);
        expect(stored.readBy, ['alice']);
        expect(stored.status, StorageMessageStatus.sent);
        expect(
          (await f.db.conversations.getById(
            conversation.id,
          ))!.lastMessageStatus,
          'sent',
        );
      },
    );
  }

  for (final status in [
    StorageMessageStatus.delivered,
    StorageMessageStatus.read,
  ]) {
    test(
      'repository keeps legacy group ${status.name} conservative without fabricating receipts',
      () async {
        final f = await _Fixture.open();
        await f.conversation(group: true);
        await f.conversation(group: false);
        final signaling = InMemorySignalingService();
        addTearDown(signaling.dispose);
        final repository = StorageConversationRepository(
          f.db,
          sender: f.sender(signaling),
        );
        for (final (id, group, snapshot) in [
          ('legacy-group', true, null),
          ('known-group', true, <String>['alice', 'bob']),
          ('legacy-direct', false, null),
        ]) {
          await f.db.messages.insert(
            MessageEntity(
              id: id,
              conversationId: group ? 'group' : 'alice',
              senderId: 'me',
              content: 'search receipt',
              contentType: StorageMessageContentType.text,
              timestamp: 10,
              status: status,
              isOutgoing: true,
              receiptRecipients: snapshot,
              deliveredTo: const ['alice'],
              readBy: const ['alice'],
            ),
          );
        }
        final messages = await repository.watchMessages('group').first;
        final legacy = messages.singleWhere(
          (message) => message.id == 'legacy-group',
        );
        expect(legacy.status, MessageStatus.sent);
        expect(legacy.receiptRecipients, isNull);
        expect(legacy.deliveredTo, ['alice']);
        expect(legacy.readBy, ['alice']);
        final known = messages.singleWhere(
          (message) => message.id == 'known-group',
        );
        expect(known.receiptRecipients, ['alice', 'bob']);
        expect(known.status.name, status.name);
        final direct = (await repository.watchMessages('alice').first).single;
        expect(direct.status.name, status.name);
        expect(direct.receiptRecipients, isNull);
        final searched = await repository.searchAllMessages('search receipt');
        expect(
          searched
              .singleWhere((message) => message.id == 'legacy-group')
              .status,
          MessageStatus.sent,
        );
        expect(
          searched
              .singleWhere((message) => message.id == 'legacy-direct')
              .status
              .name,
          status.name,
        );
        expect(
          (await f.db.messages.getById('legacy-group'))!.receiptRecipients,
          isNull,
        );
      },
    );
  }
}

class _Fixture {
  _Fixture(this.root, this.db);
  final Directory root;
  final SecureChatDatabase db;

  static Future<_Fixture> open() async {
    final root = await Directory.systemTemp.createTemp('receipt_sender_');
    addTearDown(() => root.delete(recursive: true));
    final db = await SecureChatDatabase.open(
      file: File('${root.path}/db'),
      crypto: LocalAeadCryptoService(SecretKey(List.filled(32, 17))),
    );
    addTearDown(db.close);
    return _Fixture(root, db);
  }

  Future<ConversationEntity> conversation({required bool group}) async {
    final conversation = ConversationEntity(
      id: group ? 'group' : 'alice',
      peerId: group ? 'group' : 'alice',
      peerName: 'Receipt test',
      peerPhone: '',
      isGroup: group,
      groupMembers: group ? ' me,alice, bob,alice,me, ' : null,
    );
    await db.conversations.insert(conversation);
    return conversation;
  }

  SendMessageUseCase sender(SignalingService signaling) => SendMessageUseCase(
    database: db,
    signaling: signaling,
    session: SessionStore(userId: 'me'),
    crypto: _Crypto(),
    maxRetryCount: 0,
    retryDelay: Duration.zero,
  );
}

class _Crypto extends Fake implements CryptoService {
  @override
  Future<String> encryptDirect({
    required String recipientId,
    required String plaintext,
  }) async => 'encrypted-direct';
  @override
  Future<String> encryptGroup({
    required String senderId,
    required String groupId,
    required String plaintext,
  }) async => 'encrypted-group';
}

class _InspectSignaling extends InMemorySignalingService {
  _InspectSignaling(this.inspect);
  final Future<void> Function(EncryptedSignalMessage) inspect;
  @override
  Future<bool> send(SignalMessage message) async {
    if (message is EncryptedSignalMessage) await inspect(message);
    return super.send(message);
  }
}

class _InspectTransfers extends Fake implements FileTransferManager {
  _InspectTransfers(this.inspect);
  final Future<void> Function(String, List<String>) inspect;
  @override
  Future<FileTransferResult> sendFile({
    required String localUserId,
    required String recipientId,
    required File file,
    required String mimeType,
    String? fileName,
    bool isGroup = false,
    List<String> groupMembers = const [],
    String? caption,
    bool isViewOnce = false,
    String? originalMessageId,
    DateTime? absoluteExpiresAt,
  }) async {
    if (isGroup) expect(groupMembers, contains(localUserId));
    final recipients = isGroup
        ? groupMembers.where((id) => id != localUserId).toSet().toList()
        : [recipientId];
    await inspect(originalMessageId!, recipients);
    return FileTransferSuccess(
      transferId: 'transfer',
      fileName: fileName!,
      mimeType: mimeType,
      fileSize: await file.length(),
    );
  }
}
