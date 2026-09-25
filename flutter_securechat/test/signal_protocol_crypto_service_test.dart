import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart' as signal;

import 'package:flutter_securechat/src/crypto/crypto_protocol_store.dart';
import 'package:flutter_securechat/src/crypto/libsignal_protocol_store.dart';
import 'package:flutter_securechat/src/crypto/pre_key_manager.dart';
import 'package:flutter_securechat/src/crypto/signal_protocol_crypto_service.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/chat/private_chat_control.dart';
import 'package:flutter_securechat/src/contacts/phone_number_sharing_service.dart';
import 'package:flutter_securechat/src/domain/send_message_use_case.dart';
import 'package:flutter_securechat/src/groups/private_group_control.dart';
import 'package:flutter_securechat/src/groups/private_group_route.dart';
import 'package:flutter_securechat/src/contacts/contact_service.dart';
import 'package:flutter_securechat/src/network/network_resilience.dart';
import 'package:flutter_securechat/src/incoming/incoming_message_handler.dart';
import 'package:flutter_securechat/src/media/file_transfer_manager.dart';
import 'package:flutter_securechat/src/media/media_attachment.dart';
import 'package:flutter_securechat/src/media/media_message_service.dart';
import 'package:flutter_securechat/src/notifications/message_notification_service.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';

void main() {
  group('repeated SenderKey distribution', () {
    late _SignalFixture fixture;
    const groupId = 'batch-group';
    Future<String> distribution() => fixture.alice.createSenderKeyDistribution(
      groupId: groupId,
      senderId: 'alice',
    );
    Future<void> install(String value) => fixture.bob
        .processSenderKeyDistribution(senderId: 'alice', plaintext: value);
    Future<String> encrypt(String value) => fixture.alice.encryptGroup(
      senderId: 'alice',
      groupId: groupId,
      plaintext: value,
    );
    Future<String> decrypt(String value) => fixture.bob.decryptGroup(
      senderId: 'alice',
      groupId: groupId,
      envelope: value,
    );

    setUp(() async {
      fixture = await _SignalFixture.open();
    });
    tearDown(() => fixture.close());

    test('later distributions do not skip pending ciphertext', () async {
      final messages = <String>[];
      for (var i = 0; i < 3; i++) {
        await install(await distribution());
        messages.add(await encrypt('file-$i'));
        messages.add(await encrypt('manifest-$i'));
      }
      for (var i = 0; i < messages.length; i++) {
        expect(
          await decrypt(messages[i]),
          '${i.isEven ? 'file' : 'manifest'}-${i ~/ 2}',
        );
      }
    });

    test('redistribution preserves skipped keys and rejects replay', () async {
      final initial = await distribution();
      await install(initial);
      final first = await encrypt('first');
      final second = await encrypt('second');
      expect(await decrypt(second), 'second');
      await install(await distribution());
      expect(await decrypt(first), 'first');
      // An old authenticated distribution must not rewind consumed keys.
      await install(initial);
      await expectLater(
        decrypt(first),
        throwsA(isA<signal.DuplicateMessageException>()),
      );
      await expectLater(
        decrypt(second),
        throwsA(isA<signal.DuplicateMessageException>()),
      );
    });

    test('same key ID with a different signing key fails closed', () async {
      final initial = await distribution();
      await install(initial);
      final parsed = signal.SenderKeyDistributionMessageWrapper.fromSerialized(
        Uint8List.fromList(base64Decode(initial.split(':').last)),
      );
      final conflict = signal.SenderKeyDistributionMessageWrapper(
        parsed.id,
        parsed.iteration,
        parsed.chainKey,
        signal.Curve.generateKeyPair().publicKey,
      );
      await expectLater(
        install('SKDM:$groupId:${base64Encode(conflict.serialize())}'),
        throwsA(isA<signal.InvalidKeyException>()),
      );
      expect(await decrypt(await encrypt('valid')), 'valid');
    });

    test(
      'rotation retains older pending keys without replaying consumed ones',
      () async {
        final old = await distribution();
        await install(old);
        final pending = await encrypt('old pending');
        await fixture.alice.resetLocalSenderKey(groupId, 'alice');
        await install(await distribution());
        final current = await encrypt('new key');
        expect(await decrypt(current), 'new key');
        expect(await decrypt(pending), 'old pending');
        await install(old);
        await expectLater(
          decrypt(pending),
          throwsA(isA<signal.DuplicateMessageException>()),
        );
        expect(await decrypt(await encrypt('still current')), 'still current');
      },
    );
  });

  for (final viewOnce in [false, true]) {
    for (final reverse in [false, true]) {
      test(
        'group attachment batch survives controls first (viewOnce=$viewOnce, reverse=$reverse)',
        () async {
          final f = await _SignalFixture.open();
          addTearDown(f.close);
          final wire = InMemorySignalingService()..setConnected(true);
          final receiver = InMemorySignalingService();
          final failures = <Object>[];
          Future<void> report(String op, Object error, StackTrace stack) async {
            failures.add(error);
          }

          final incoming = IncomingMessageHandler(
            signaling: receiver,
            crypto: f.bob,
            database: f.bobDatabase,
            session: SessionStore(userId: 'bob'),
            onAsyncFailure: report,
          )..start();
          final outgoing = FileTransferManager(
            signaling: wire,
            crypto: f.alice,
            filesDirectory: Directory('${f.directory.path}/out'),
            metadataCrypto: LocalAeadCryptoService(
              SecretKey(List.filled(32, 8)),
            ),
            onAsyncFailure: report,
          );
          final receiving = FileTransferManager(
            signaling: receiver,
            crypto: f.bob,
            filesDirectory: Directory('${f.directory.path}/in'),
            metadataCrypto: LocalAeadCryptoService(
              SecretKey(List.filled(32, 9)),
            ),
            beforeReceive: incoming.waitForIdle,
            onAsyncFailure: report,
          );
          final sendingMedia = MediaMessageService(
            database: f.aliceDatabase,
            transfers: outgoing,
            session: SessionStore(userId: 'alice'),
            localMediaDirectory: Directory('${f.directory.path}/alice-media'),
            groupControls: PrivateGroupControlSender(
              crypto: f.alice,
              signaling: wire,
            ),
            onAsyncFailure: report,
          );
          final receivingMedia = MediaMessageService(
            database: f.bobDatabase,
            transfers: receiving,
            session: SessionStore(userId: 'bob'),
            localMediaDirectory: Directory('${f.directory.path}/bob-media'),
            onAsyncFailure: report,
          )..start();
          final received = <ReceivedFile>[];
          final sub = receiving.receivedFiles.listen(received.add);
          addTearDown(() async {
            await sendingMedia.close();
            await receivingMedia.close();
            await sub.cancel();
            await outgoing.dispose();
            await receiving.dispose();
            await incoming.close();
            await wire.dispose();
            await receiver.dispose();
          });
          await f.aliceDatabase.conversations.insert(
            const ConversationEntity(
              id: 'batch-group',
              peerId: 'batch-group',
              peerName: 'Batch',
              peerPhone: '',
              isGroup: true,
              groupMembers: 'alice,bob',
            ),
          );
          final payloads = <String, Uint8List>{};
          final attachments = <MediaAttachment>[];
          for (final item in [
            ('agenda.txt', 280),
            ('audio.m4a', 6590),
            ('video.mp4', 41540),
          ]) {
            final bytes = Uint8List.fromList(
              List.generate(item.$2, (i) => i % 251),
            );
            payloads[item.$1] = bytes;
            final file = await File(
              '${f.directory.path}/${item.$1}',
            ).writeAsBytes(bytes);
            attachments.add(await MediaAttachment.fromPath(file.path));
          }
          final outcomes = await sendingMedia.send(
            conversationId: 'batch-group',
            recipientId: 'batch-group',
            attachments: attachments,
            isGroup: true,
            groupMembers: ['alice', 'bob'],
            isViewOnce: viewOnce,
            caption: 'batch caption',
          );
          expect(outcomes, hasLength(3));
          expect(
            outcomes.map((item) => item.result),
            everyElement(isA<FileTransferSuccess>()),
          );
          // Reproduce queue draining: all direct controls arrive before any media.
          for (final frame
              in wire.sentMessages.whereType<EncryptedSignalMessage>()) {
            receiver.addIncoming(SignalMessage.decode(frame.encode()));
          }
          await incoming.waitForIdle();
          final chunks = wire.sentMessages
              .whereType<FileTransferSignal>()
              .toList();
          for (final chunk in reverse ? chunks.reversed : chunks) {
            await receiving.receiveChunk(
              SignalMessage.decode(chunk.encode()) as FileTransferSignal,
            );
          }
          await receivingMedia.waitForIdle();
          expect(failures, isEmpty);
          expect(received, hasLength(3));
          expect(
            received.map((file) => file.fileName).toSet(),
            payloads.keys.toSet(),
          );
          for (final file in received) {
            expect(await file.file.readAsBytes(), payloads[file.fileName]);
            final row = await f.bobDatabase.messages.getById(
              file.originalMessageId!,
            );
            expect(row, isNotNull);
            expect(row!.isViewOnce, viewOnce);
            expect(row.status, StorageMessageStatus.delivered);
            expect(
              row.caption,
              file.fileName == 'agenda.txt' ? 'batch caption' : isNull,
            );
          }
        },
      );
    }
  }

  for (final mode in [
    (false, false, 600 * 1024),
    (false, true, 600 * 1024),
    (true, false, 600 * 1024),
    (true, true, 600 * 1024),
    (false, false, 21390950),
    (true, false, 21390950),
  ]) {
    final isGroup = mode.$1;
    final viewOnce = mode.$2;
    test(
      'production-sized media fits frames and decrypts (group=$isGroup, viewOnce=$viewOnce, bytes=${mode.$3})',
      () async {
        final f = await _SignalFixture.open();
        addTearDown(f.close);
        final sender = InMemorySignalingService()..setConnected(true);
        final receiver = InMemorySignalingService();
        final incoming = IncomingMessageHandler(
          signaling: receiver,
          crypto: f.bob,
          database: f.bobDatabase,
          session: SessionStore(userId: 'bob'),
        )..start();
        final outgoing = FileTransferManager(
          signaling: sender,
          crypto: f.alice,
          filesDirectory: Directory('${f.directory.path}/send'),
          metadataCrypto: LocalAeadCryptoService(SecretKey(List.filled(32, 8))),
        );
        final receiving = FileTransferManager(
          signaling: receiver,
          crypto: f.bob,
          filesDirectory: Directory('${f.directory.path}/receive'),
          metadataCrypto: LocalAeadCryptoService(SecretKey(List.filled(32, 9))),
          beforeReceive: incoming.waitForIdle,
        );
        addTearDown(() async {
          await outgoing.dispose();
          await receiving.dispose();
          await incoming.close();
          await sender.dispose();
          await receiver.dispose();
        });
        final payload = Uint8List.fromList(
          List.generate(mode.$3, (i) => i % 251),
        );
        final caption = List.filled(4096, isGroup ? '\u0000' : '\u0800').join();
        final result = await outgoing.sendStream(
          localUserId: 'alice',
          recipientId: isGroup ? 'photo-group' : 'bob',
          stream: Stream.value(payload),
          fileSize: payload.length,
          fileName: 'photo.jpg',
          mimeType: 'image/jpeg',
          isGroup: isGroup,
          groupMembers: ['alice', 'bob'],
          caption: caption,
          isViewOnce: viewOnce,
          originalMessageId: 'photo-message',
        );
        expect(result, isA<FileTransferSuccess>());
        final chunks = sender.sentMessages
            .whereType<FileTransferSignal>()
            .toList();
        for (final frame in chunks) {
          expect(
            utf8.encode(frame.encode()).length,
            lessThanOrEqualTo(SignalMessage.maxEncodedBytes),
            reason: 'Group envelope exceeds the production server frame limit',
          );
        }
        final completed = receiving.receivedFiles.first;
        for (final frame in sender.sentMessages) {
          receiver.addIncoming(SignalMessage.decode(frame.encode()));
        }
        final file = await completed.timeout(const Duration(minutes: 2));
        expect(await file.file.readAsBytes(), payload);
        expect(file.groupId, isGroup ? 'photo-group' : null);
        expect(file.isViewOnce, viewOnce);
        expect(file.caption, caption);
        expect(file.originalMessageId, 'photo-message');
      },
      timeout: const Timeout(Duration(minutes: 4)),
    );
  }

  test(
    'missing group recipient key sends no media and commits no partial group',
    () async {
      final f = await _SignalFixture.open();
      addTearDown(f.close);
      final wire = InMemorySignalingService()..setConnected(true);
      final queue = OfflineMessageQueue(
        database: f.aliceDatabase,
        signaling: wire,
      );
      final sender = FileTransferManager(
        signaling: wire,
        crypto: f.alice,
        filesDirectory: Directory('${f.directory.path}/out'),
        metadataCrypto: LocalAeadCryptoService(SecretKey(List.filled(32, 7))),
      );
      addTearDown(() async {
        await sender.dispose();
        await queue.close();
        await wire.dispose();
      });
      final result = await sender.sendStream(
        localUserId: 'alice',
        recipientId: 'group',
        stream: Stream.value([1]),
        fileSize: 1,
        fileName: 'voice.m4a',
        mimeType: 'audio/mp4',
        isGroup: true,
        groupMembers: ['alice', 'missing'],
      );
      expect(result, isA<FileTransferFailure>());
      expect(wire.sentMessages.whereType<FileTransferSignal>(), isEmpty);
      final contacts = ContactService(
        deviceContacts: _NoContacts(),
        api: _UnusedDirectory(),
        database: f.aliceDatabase,
        session: SessionStore(userId: 'alice'),
        groupControls: PrivateGroupControlSender(
          crypto: f.alice,
          signaling: wire,
        ),
        offlineQueue: queue,
      );
      await expectLater(
        contacts.createGroup('Partial', [
          const ContactEntity(
            id: 'bob',
            phoneNumber: '',
            phoneHash: '',
            displayName: 'Bob',
            isRegistered: true,
          ),
          const ContactEntity(
            id: 'missing',
            phoneNumber: '',
            phoneHash: '',
            displayName: 'Missing',
            isRegistered: true,
          ),
        ]),
        throwsStateError,
      );
      expect(await f.aliceDatabase.conversations.getAllGroups(), isEmpty);
      expect(await queue.getPendingCount(), 0);
      expect(wire.sentMessages, isEmpty);
    },
  );
  for (final privateContent in [true, false]) {
    test(
      'new group notifies without chat text, privacy=$privateContent',
      () async {
        final f = await _SignalFixture.open();
        addTearDown(f.close);
        final wire = InMemorySignalingService()..setConnected(true);
        final receiver = InMemorySignalingService();
        final queue = OfflineMessageQueue(
          database: f.aliceDatabase,
          signaling: wire,
        );
        final session = SessionStore(
          userId: 'bob',
          languagePreference: 'tr',
          showNotificationContent: !privateContent,
        );
        final incoming = IncomingMessageHandler(
          signaling: receiver,
          crypto: f.bob,
          database: f.bobDatabase,
          session: session,
        )..start();
        final presenter = _GroupPresenter();
        final notifications = MessageNotificationCoordinator(
          incomingMessages: incoming.acceptedMessages,
          session: session,
          presenter: presenter,
          unreadCounts: f.bobDatabase.conversations.unreadCounts,
        );
        await notifications.start();
        notifications.setAppForeground(false);
        addTearDown(() async {
          await incoming.close();
          await notifications.close();
          await queue.close();
          await wire.dispose();
          await receiver.dispose();
        });
        final contacts = ContactService(
          deviceContacts: _NoContacts(),
          api: _UnusedDirectory(),
          database: f.aliceDatabase,
          session: SessionStore(userId: 'alice'),
          groupControls: PrivateGroupControlSender(
            crypto: f.alice,
            signaling: wire,
          ),
          offlineQueue: queue,
        );
        final group = await contacts.createGroup('Private team', [
          const ContactEntity(
            id: 'bob',
            phoneNumber: '',
            phoneHash: '',
            displayName: 'Bob',
            isRegistered: true,
          ),
        ]);
        receiver.addIncoming(wire.sentMessages.single);
        await incoming.waitForIdle();
        await Future<void>.delayed(Duration.zero);
        await notifications.waitForIdle();
        expect(
          (await f.bobDatabase.conversations.getById(group.id))?.unreadCount,
          1,
        );
        expect(presenter.shown, hasLength(1));
        expect(
          presenter.shown.single.body,
          privateContent ? '1 sohbetten 1 yeni mesaj' : 'Bir gruba eklendiniz.',
        );
        expect(
          presenter.shown.single.payload,
          privateContent ? isNull : group.id,
        );
        if (privateContent)
          expect(presenter.shown.single.title, isNot(contains('Private team')));
        // A freshly encrypted repeat is valid ratchet traffic, but not a second invitation.
        await PrivateGroupControlSender(crypto: f.alice, signaling: wire).send(
          senderId: 'alice',
          groupId: group.id,
          groupName: group.peerName,
          memberIds: ['alice', 'bob'],
          recipients: ['bob'],
          action: 'CREATE',
        );
        receiver.addIncoming(wire.sentMessages.last);
        await incoming.waitForIdle();
        await notifications.waitForIdle();
        expect(presenter.shown, hasLength(1));
        expect(
          (await f.bobDatabase.conversations.getById(group.id))?.unreadCount,
          1,
        );
      },
    );
  }

  test(
    'first group voice attachment distributes SenderKey before chunks and after reset',
    () async {
      final f = await _SignalFixture.open();
      addTearDown(f.close);
      final sender = InMemorySignalingService()..setConnected(true);
      final receiver = InMemorySignalingService();
      final incoming = IncomingMessageHandler(
        signaling: receiver,
        crypto: f.bob,
        database: f.bobDatabase,
        session: SessionStore(userId: 'bob'),
      )..start();
      final outgoing = FileTransferManager(
        signaling: sender,
        crypto: f.alice,
        filesDirectory: Directory('${f.directory.path}/send'),
        metadataCrypto: LocalAeadCryptoService(SecretKey(List.filled(32, 8))),
      );
      final receiving = FileTransferManager(
        signaling: receiver,
        crypto: f.bob,
        filesDirectory: Directory('${f.directory.path}/receive'),
        metadataCrypto: LocalAeadCryptoService(SecretKey(List.filled(32, 9))),
        beforeReceive: incoming.waitForIdle,
      );
      addTearDown(() async {
        await outgoing.dispose();
        await receiving.dispose();
        await incoming.close();
        await sender.dispose();
        await receiver.dispose();
      });
      final received = <ReceivedFile>[];
      final subscription = receiving.receivedFiles.listen(received.add);
      addTearDown(subscription.cancel);
      for (var round = 0; round < 2; round++) {
        if (round == 1)
          await f.alice.resetLocalSenderKey('voice-group', 'alice');
        final offset = sender.sentMessages.length;
        final result = await outgoing.sendStream(
          localUserId: 'alice',
          recipientId: 'voice-group',
          stream: Stream.value([1, 2, 3, round]),
          fileSize: 4,
          fileName: 'voice.m4a',
          mimeType: 'audio/mp4',
          isGroup: true,
          groupMembers: ['alice', 'bob'],
        );
        expect(result, isA<FileTransferSuccess>());
        final frames = sender.sentMessages.skip(offset).toList();
        expect(frames.first, isA<EncryptedSignalMessage>());
        expect(frames.last, isA<FileTransferSignal>());
        for (final frame in frames) {
          receiver.addIncoming(frame);
        }
        for (var wait = 0; wait < 100 && received.length <= round; wait++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(received, hasLength(round + 1));
        expect(await received.last.file.readAsBytes(), [1, 2, 3, round]);
      }
    },
  );
  test(
    'phone disclosure uses the production Signal ratchet without changing text',
    () async {
      final fixture = await _SignalFixture.open();
      addTearDown(fixture.close);
      final socket = InMemorySignalingService()..setConnected(true);
      addTearDown(socket.dispose);
      final session = SessionStore(
        userId: 'alice',
        accessToken: 'token',
        phoneNumber: '+905551234567',
        sharePhoneNumber: true,
      );
      final sharing = PhoneNumberSharingService(
        session: session,
        crypto: fixture.alice,
        signaling: socket,
        database: fixture.aliceDatabase,
        discovery: _UnusedDirectory(),
      );
      final sender = SendMessageUseCase(
        database: fixture.aliceDatabase,
        signaling: socket,
        session: session,
        crypto: fixture.alice,
        phoneSharing: sharing,
      );
      for (var i = 0; i < 2; i++) {
        expect(
          await sender(
            const SendMessageRequest(
              conversationId: 'bob',
              content: 'private hello',
            ),
          ),
          SendMessageOutcome.sent,
        );
      }
      final wires = socket.sentMessages.cast<EncryptedSignalMessage>();
      expect(wires, hasLength(4));
      expect(wires[0].envelope, isNot(wires[2].envelope));
      for (var i = 0; i < wires.length; i++) {
        expect(wires[i].encode(), isNot(contains(session.phoneNumber!)));
        final clear = await fixture.bob.decryptDirect(
          senderId: 'alice',
          envelope: wires[i].envelope,
        );
        if (i.isEven) {
          final control =
              decodePrivateChatControl(
                    plaintext: clear,
                    authenticatedSenderId: 'alice',
                    localRecipientId: 'bob',
                  )
                  as SharedPhoneSignal;
          expect(control.phoneNumber, session.phoneNumber);
          expect(control.senderId, 'alice');
          expect(control.recipientId, 'bob');
        } else {
          expect(clear, startsWith('MSGID:'));
          expect(clear, endsWith(':private hello'));
          expect(clear, isNot(contains(session.phoneNumber!)));
        }
      }
    },
  );

  test(
    'persistent Signal service ratchets direct messages both ways',
    () async {
      final fixture = await _SignalFixture.open();
      addTearDown(fixture.close);

      final first = await fixture.alice.encryptDirect(
        recipientId: 'bob',
        plaintext: 'hello from alice',
      );
      expect(first, startsWith('E2EE:v1:PREKEY:'));
      expect(
        await fixture.bob.decryptDirect(senderId: 'alice', envelope: first),
        'hello from alice',
      );
      final reply = await fixture.bob.encryptDirect(
        recipientId: 'alice',
        plaintext: 'hello from bob',
      );
      expect(reply, startsWith('E2EE:v1:SIGNAL:'));
      expect(
        await fixture.alice.decryptDirect(senderId: 'bob', envelope: reply),
        'hello from bob',
      );
    },
  );

  test(
    'parallel direct operations serialize the ratchet state per peer',
    () async {
      final fixture = await _SignalFixture.open();
      addTearDown(fixture.close);

      final bootstrap = await fixture.alice.encryptDirect(
        recipientId: 'bob',
        plaintext: 'bootstrap',
      );
      expect(
        await fixture.bob.decryptDirect(senderId: 'alice', envelope: bootstrap),
        'bootstrap',
      );

      final outbound = await Future.wait(
        List.generate(
          64,
          (index) => fixture.alice.encryptDirect(
            recipientId: 'bob',
            plaintext: 'parallel-$index',
          ),
        ),
      );
      final clear = await Future.wait(
        outbound.map(
          (envelope) =>
              fixture.bob.decryptDirect(senderId: 'alice', envelope: envelope),
        ),
      );

      expect(clear.toSet(), {
        for (var index = 0; index < 64; index++) 'parallel-$index',
      });
    },
  );

  test(
    'direct ratchet produces distinct ciphertext for identical plaintext',
    () async {
      final fixture = await _SignalFixture.open();
      addTearDown(fixture.close);

      final first = await fixture.alice.encryptDirect(
        recipientId: 'bob',
        plaintext: 'same plaintext',
      );
      final second = await fixture.alice.encryptDirect(
        recipientId: 'bob',
        plaintext: 'same plaintext',
      );

      expect(second, isNot(first));
      expect(
        await fixture.bob.decryptDirect(senderId: 'alice', envelope: first),
        'same plaintext',
      );
      expect(
        await fixture.bob.decryptDirect(senderId: 'alice', envelope: second),
        'same plaintext',
      );
    },
  );

  test('SenderKey distribution enables authenticated group messages', () async {
    final fixture = await _SignalFixture.open();
    addTearDown(fixture.close);
    final skdm = await fixture.alice.createSenderKeyDistribution(
      groupId: 'group-1',
      senderId: 'alice',
    );
    final transport = await fixture.alice.encryptDirect(
      recipientId: 'bob',
      plaintext: skdm,
    );
    final received = await fixture.bob.decryptDirect(
      senderId: 'alice',
      envelope: transport,
    );
    await fixture.bob.processSenderKeyDistribution(
      senderId: 'alice',
      plaintext: received,
    );
    final group = await fixture.alice.encryptGroup(
      senderId: 'alice',
      groupId: 'group-1',
      plaintext: 'sender-key payload',
    );
    expect(group, startsWith('GROUPSK:v2:'));
    expect(group, isNot(contains('group-1')));
    expect(
      await fixture.bob.decryptGroup(
        senderId: 'alice',
        groupId: 'group-1',
        envelope: group,
      ),
      'sender-key payload',
    );

    // Legacy Kotlin envelopes remain receive-only during the coordinated
    // rollout; new sends must never reveal either value.
    final second = await fixture.alice.encryptGroup(
      senderId: 'alice',
      groupId: 'group-1',
      plaintext: 'legacy receive path',
    );
    final secondParts = second.split(':');
    final legacy = 'GROUPSK:v1:group-1:Legacy Group:${secondParts.last}';
    expect(
      await fixture.bob.decryptGroup(
        senderId: 'alice',
        groupId: 'group-1',
        envelope: legacy,
      ),
      'legacy receive path',
    );
  });

  test(
    'group sender-key ratchet produces distinct ciphertext for identical plaintext',
    () async {
      final fixture = await _SignalFixture.open();
      addTearDown(fixture.close);
      final distribution = await fixture.alice.createSenderKeyDistribution(
        groupId: 'group-ratchet',
        senderId: 'alice',
      );
      await fixture.bob.processSenderKeyDistribution(
        senderId: 'alice',
        plaintext: distribution,
      );

      final first = await fixture.alice.encryptGroup(
        senderId: 'alice',
        groupId: 'group-ratchet',
        plaintext: 'same group plaintext',
      );
      final second = await fixture.alice.encryptGroup(
        senderId: 'alice',
        groupId: 'group-ratchet',
        plaintext: 'same group plaintext',
      );

      expect(second, isNot(first));
      expect(
        await fixture.bob.decryptGroup(
          senderId: 'alice',
          groupId: 'group-ratchet',
          envelope: first,
        ),
        'same group plaintext',
      );
      expect(
        await fixture.bob.decryptGroup(
          senderId: 'alice',
          groupId: 'group-ratchet',
          envelope: second,
        ),
        'same group plaintext',
      );
    },
  );

  test('group send distributes SKDM before the shared ciphertext', () async {
    final fixture = await _SignalFixture.open();
    addTearDown(fixture.close);
    await fixture.aliceDatabase.conversations.insert(
      const ConversationEntity(
        id: 'group-1',
        peerId: 'group-1',
        peerName: 'Compat group',
        peerPhone: '',
        isGroup: true,
        groupMembers: 'alice,bob',
      ),
    );
    final signaling = InMemorySignalingService()..setConnected(true);
    final sender = SendMessageUseCase(
      database: fixture.aliceDatabase,
      signaling: signaling,
      session: SessionStore(userId: 'alice', accessToken: 'token'),
      crypto: fixture.alice,
      retryDelay: Duration.zero,
    );

    expect(
      await sender(
        const SendMessageRequest(
          conversationId: 'group-1',
          content: 'group integration',
        ),
      ),
      SendMessageOutcome.sent,
    );
    expect(signaling.sentMessages, hasLength(3));
    final controlSignal = signaling.sentMessages[0] as EncryptedSignalMessage;
    final controlPlaintext = await fixture.bob.decryptDirect(
      senderId: 'alice',
      envelope: controlSignal.envelope,
    );
    final control = await decodePrivateGroupControl(
      plaintext: controlPlaintext,
      authenticatedSenderId: 'alice',
      localRecipientId: 'bob',
    );
    expect(control.action, 'CREATE');
    expect(control.groupId, 'group-1');

    final skdmSignal = signaling.sentMessages[1] as EncryptedSignalMessage;
    final distribution = await fixture.bob.decryptDirect(
      senderId: 'alice',
      envelope: skdmSignal.envelope,
    );
    await fixture.bob.processSenderKeyDistribution(
      senderId: 'alice',
      plaintext: distribution,
    );
    final routedSignal = signaling.sentMessages[2] as EncryptedSignalMessage;
    expect(routedSignal.recipientId, 'bob');
    expect(routedSignal.envelope, isNot(contains('group-1')));
    final route = await decodePrivateGroupRoute(
      await fixture.bob.decryptDirect(
        senderId: 'alice',
        envelope: routedSignal.envelope,
      ),
    );
    final recipientEnvelope = route.groupEnvelope;
    expect(route.groupId, 'group-1');
    expect(recipientEnvelope, startsWith('GROUPSK:v2:'));
    expect(recipientEnvelope, isNot(contains('group-1')));
    expect(recipientEnvelope, isNot(contains('Compat group')));
    final plaintext = await fixture.bob.decryptGroup(
      senderId: 'alice',
      groupId: 'group-1',
      envelope: recipientEnvelope,
    );
    expect(plaintext, contains('group integration'));
  });

  test(
    'missing PreKey bundle fails closed without a local AEAD fallback',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'securechat_signal_missing_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final storage = LocalAeadCryptoService(SecretKey(List.filled(32, 7)));
      final database = await SecureChatDatabase.open(
        file: File('${directory.path}/db.securejson'),
        crypto: storage,
      );
      addTearDown(database.close);
      final raw = DatabaseCryptoProtocolStore(database);
      await PreKeyManager(raw).generateAndSerializeInitialBundle();
      final service = SignalProtocolCryptoService(
        store: PersistentSignalProtocolStore(raw),
        preKeyBundles: const _MapBundleProvider({}),
      );
      await expectLater(
        service.encryptDirect(recipientId: 'missing', plaintext: 'secret'),
        throwsStateError,
      );
    },
  );
}

class _SignalFixture {
  _SignalFixture({
    required this.directory,
    required this.aliceDatabase,
    required this.bobDatabase,
    required this.alice,
    required this.bob,
  });

  final Directory directory;
  final SecureChatDatabase aliceDatabase;
  final SecureChatDatabase bobDatabase;
  final SignalProtocolCryptoService alice;
  final SignalProtocolCryptoService bob;

  static Future<_SignalFixture> open() async {
    final directory = await Directory.systemTemp.createTemp(
      'securechat_signal_service_',
    );
    final aliceDatabase = await SecureChatDatabase.open(
      file: File('${directory.path}/alice.securejson'),
      crypto: LocalAeadCryptoService(SecretKey(List.filled(32, 1))),
    );
    final bobDatabase = await SecureChatDatabase.open(
      file: File('${directory.path}/bob.securejson'),
      crypto: LocalAeadCryptoService(SecretKey(List.filled(32, 2))),
    );
    final aliceRaw = DatabaseCryptoProtocolStore(aliceDatabase);
    final bobRaw = DatabaseCryptoProtocolStore(bobDatabase);
    final aliceBundle = await PreKeyManager(
      aliceRaw,
      batchSize: 4,
    ).generateAndSerializeInitialBundle();
    final bobBundle = await PreKeyManager(
      bobRaw,
      batchSize: 4,
    ).generateAndSerializeInitialBundle();
    final bundles = _MapBundleProvider({
      'alice': _toSignalBundle(aliceBundle),
      'bob': _toSignalBundle(bobBundle),
    });
    return _SignalFixture(
      directory: directory,
      aliceDatabase: aliceDatabase,
      bobDatabase: bobDatabase,
      alice: SignalProtocolCryptoService(
        store: PersistentSignalProtocolStore(aliceRaw),
        preKeyBundles: bundles,
      ),
      bob: SignalProtocolCryptoService(
        store: PersistentSignalProtocolStore(bobRaw),
        preKeyBundles: bundles,
      ),
    );
  }

  Future<void> close() async {
    await aliceDatabase.close();
    await bobDatabase.close();
    await directory.delete(recursive: true);
  }
}

class _NoContacts implements DeviceContactsGateway {
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<List<DeviceContact>> getAllContacts() async => [];
}

class _GroupPresenter implements LocalNotificationPresenter {
  final shown = <LocalMessageNotification>[];
  @override
  Stream<String> get taps => const Stream.empty();
  @override
  Stream<NotificationDismissal> get dismissals => const Stream.empty();
  @override
  Future<void> initialize() async {}
  @override
  Future<void> show(LocalMessageNotification notification) async {
    shown.add(notification);
  }

  @override
  Future<void> reconcileDismissals() async {}
  @override
  Future<void> cancelAll() async {
    shown.clear();
  }
}

class _MapBundleProvider implements PreKeyBundleProvider {
  const _MapBundleProvider(this.bundles);
  final Map<String, signal.PreKeyBundle> bundles;

  @override
  Future<signal.PreKeyBundle?> fetch(String recipientId) async =>
      bundles[recipientId];
}

class _UnusedDirectory implements ContactDiscoveryApi {
  @override
  Future<List<RegisteredUserMatch>> checkUsers(
    List<String> phoneHashes,
    String accessToken, {
    String? ownPhoneHash,
    String? ownUserId,
  }) async => throw StateError('Outgoing sharing must not query the directory');
}

signal.PreKeyBundle _toSignalBundle(SerializedPreKeyBundle bundle) {
  final oneTime = bundle.oneTimePreKeys.first;
  return signal.PreKeyBundle(
    bundle.registrationId,
    1,
    oneTime.keyId,
    signal.Curve.decodePoint(Uint8List.fromList(oneTime.publicKey), 0),
    bundle.signedPreKeyId,
    signal.Curve.decodePoint(Uint8List.fromList(bundle.signedPreKey), 0),
    Uint8List.fromList(bundle.signedPreKeySignature),
    signal.IdentityKey.fromBytes(
      Uint8List.fromList(bundle.identityPublicKey),
      0,
    ),
  );
}
