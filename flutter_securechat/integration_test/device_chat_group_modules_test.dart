import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_securechat/src/auth/phone_privacy.dart';
import 'package:flutter_securechat/src/chat/chat_info_service.dart';
import 'package:flutter_securechat/src/chat/message_forwarding_service.dart';
import 'package:flutter_securechat/src/chat/message_interaction_service.dart';
import 'package:flutter_securechat/src/chat/poll_service.dart';
import 'package:flutter_securechat/src/contacts/contact_service.dart';
import 'package:flutter_securechat/src/core/models.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/domain/send_message_use_case.dart';
import 'package:flutter_securechat/src/groups/group_management_service.dart';
import 'package:flutter_securechat/src/media/file_transfer_manager.dart';
import 'package:flutter_securechat/src/media/media_message_service.dart';
import 'package:flutter_securechat/src/services/conversation_repository.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('physical chat, contact and group module lifecycle', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp('device_chat_group_');
    final databaseFile = File('${root.path}/storage.securejson');
    final crypto = LocalAeadCryptoService(
      SecretKey(List<int>.generate(32, (index) => index + 41)),
    );
    var databaseClosed = false;
    final database = await SecureChatDatabase.open(
      file: databaseFile,
      crypto: crypto,
    );
    final session = SessionStore(
      userId: 'me',
      displayName: 'Device User',
      phoneNumber: '+905000000000',
      accessToken: 'device-access-token',
    );
    final signaling = InMemorySignalingService();
    await signaling.connect(
      userId: 'me',
      url: 'wss://device.invalid',
      accessToken: 'device-access-token',
    );
    final transfers = FileTransferManager(
      signaling: signaling,
      crypto: crypto,
      filesDirectory: Directory('${root.path}/incoming'),
      chunkSize: 8,
    );
    final media = MediaMessageService(
      database: database,
      transfers: transfers,
      session: session,
      localMediaDirectory: Directory('${root.path}/media'),
    );
    addTearDown(() async {
      await media.close();
      await transfers.dispose();
      await signaling.disconnect();
      if (!databaseClosed) await database.close();
      if (await root.exists()) await root.delete(recursive: true);
    });

    for (final conversation in const [
      ConversationEntity(
        id: 'peer-alice',
        peerId: 'peer-alice',
        peerName: 'Alice',
        peerPhone: '+905551111111',
      ),
      ConversationEntity(
        id: 'peer-bob',
        peerId: 'peer-bob',
        peerName: 'Bob',
        peerPhone: '+905552222222',
      ),
    ]) {
      await database.conversations.insert(conversation);
    }
    await database.messages.insert(
      MessageEntity(
        id: 'incoming-1',
        conversationId: 'peer-alice',
        senderId: 'peer-alice',
        content: 'Incoming device seed',
        contentType: StorageMessageContentType.text,
        timestamp: DateTime.now()
            .subtract(const Duration(minutes: 1))
            .millisecondsSinceEpoch,
        status: StorageMessageStatus.delivered,
        isOutgoing: false,
      ),
    );

    final sender = SendMessageUseCase(
      database: database,
      signaling: signaling,
      session: session,
      crypto: crypto,
      maxRetryCount: 0,
      retryDelay: Duration.zero,
    );
    final repository = StorageConversationRepository(database, sender: sender);
    final interactions = MessageInteractionService(
      database: database,
      signaling: signaling,
      session: session,
      crypto: crypto,
    );
    final polls = PollService(
      database: database,
      sender: sender,
      signaling: signaling,
      session: session,
      crypto: crypto,
    );
    final forwarding = MessageForwardingService(
      sender: sender,
      polls: polls,
      media: media,
    );
    final chatInfo = ChatInfoService(
      database: database,
      session: session,
      signaling: signaling,
      crypto: crypto,
    );

    await repository.sendText(
      'peer-alice',
      'Device reply secret',
      replyToId: 'incoming-1',
    );
    var aliceMessages = await database.messages.getMessagesImmediate(
      'peer-alice',
    );
    final reply = aliceMessages.singleWhere(
      (message) => message.content == 'Device reply secret',
    );
    expect(reply.replyToId, 'incoming-1');
    expect(reply.status, StorageMessageStatus.sent);

    expect(await interactions.edit(reply.id, 'Device edited secret'), isTrue);
    expect(await interactions.toggleReaction(reply.id, '👍'), isTrue);
    await interactions.setStarred(reply.id, true);
    expect(await interactions.setPinned(reply.id, true), isTrue);
    var edited = await database.messages.getById(reply.id);
    expect(edited?.content, 'Device edited secret');
    expect(edited?.editedAt, isNotNull);
    expect(parseReactions(edited?.reactions), {
      '👍': {'me'},
    });
    expect(edited?.isStarred, isTrue);
    expect(edited?.isPinned, isTrue);

    expect(
      await polls.create(
        'peer-alice',
        PollData(
          question: 'Ship device build?',
          options: const ['Yes', 'No'],
          singleChoice: true,
        ),
      ),
      SendMessageOutcome.sent,
    );
    aliceMessages = await database.messages.getMessagesImmediate('peer-alice');
    final poll = aliceMessages.singleWhere(
      (message) => message.contentType == StorageMessageContentType.poll,
    );
    expect(await polls.vote(poll.id, 0), isTrue);
    expect(
      PollData.parse(
        (await database.messages.getById(poll.id))!.content,
      ).votes[0],
      ['me'],
    );

    final source = (await repository.watchMessages('peer-alice').first)
        .singleWhere((message) => message.id == reply.id);
    expect(
      await forwarding.forward(
        source: source,
        target: const Conversation(
          id: 'peer-bob',
          peerId: 'peer-bob',
          peerName: 'Bob',
          peerPhone: '+905552222222',
        ),
      ),
      ForwardMessageOutcome.sent,
    );
    final forwarded = (await database.messages.getMessagesImmediate(
      'peer-bob',
    )).singleWhere((message) => message.content == 'Device edited secret');
    expect(forwarded.id, isNot(reply.id));
    expect(forwarded.replyToId, isNull);

    expect(await chatInfo.search('peer-alice', 'edited').first, hasLength(1));
    await chatInfo.setMuted('peer-alice', true);
    await repository.setArchived('peer-bob', true);
    await repository.setPinned('peer-alice', true);
    await repository.setFavorite('peer-alice', true);
    await repository.setManuallyUnread('peer-alice', true);
    final alice = await database.conversations.getById('peer-alice');
    final bob = await database.conversations.getById('peer-bob');
    expect(alice?.isMuted, isTrue);
    expect(alice?.isPinned, isTrue);
    expect(alice?.isFavorite, isTrue);
    expect(alice?.manuallyUnread, isTrue);
    expect(bob?.isArchived, isTrue);
    debugPrint('[device-chat-group] chat-controls-poll-forward-search');

    final aliceHash = await hashPhoneNumber('05551111111');
    final bobHash = await hashPhoneNumber('05552222222');
    final discovery = _DeviceDiscovery({
      aliceHash: 'peer-alice',
      bobHash: 'peer-bob',
    });
    final contacts = ContactService(
      deviceContacts: const _SeededDeviceContacts(),
      api: discovery,
      database: database,
      session: session,
    );
    final registered = await contacts.importAndDiscover();
    expect(registered.map((contact) => contact.id).toSet(), {
      'peer-alice',
      'peer-bob',
    });
    expect(discovery.receivedHashes, hasLength(2));
    expect(discovery.receivedHashes, isNot(contains('05551111111')));
    expect(await database.contacts.getRegisteredCount(), 2);

    final group = await contacts.createGroup('Device Team', [registered.first]);
    final groups = GroupManagementService(
      database: database,
      session: session,
      signaling: signaling,
      crypto: crypto,
    );
    final firstMember = registered.first.id;
    final addedMember = registered.last.id;
    await groups.addMembers(group.id, [addedMember]);
    await groups.promoteToAdmin(group.id, firstMember);
    await groups.updateName(group.id, 'Device Operations');
    await groups.setReadOnly(group.id, true);
    await groups.setMuted(group.id, true);
    await groups.setLocked(group.id, true);
    var storedGroup = await groups.watchGroup(group.id).first;
    expect(storedGroup?.peerName, 'Device Operations');
    expect(storedGroup?.isReadOnly, isTrue);
    expect(storedGroup?.isMuted, isTrue);
    expect(storedGroup?.isLocked, isTrue);
    expect(storedGroup?.groupAdmins?.split(',').toSet(), {'me', firstMember});
    expect(storedGroup?.groupMembers?.split(',').toSet(), {
      'me',
      firstMember,
      addedMember,
    });

    final nonAdminGroups = GroupManagementService(
      database: database,
      session: SessionStore(userId: addedMember),
      signaling: signaling,
      crypto: crypto,
    );
    await expectLater(
      nonAdminGroups.updateName(group.id, 'Unauthorized name'),
      throwsA(isA<GroupManagementException>()),
    );
    await groups.removeMember(group.id, addedMember);
    storedGroup = await database.conversations.getById(group.id);
    expect(storedGroup?.groupMembers?.split(','), isNot(contains(addedMember)));
    debugPrint('[device-chat-group] contacts-group-admin-announcement');

    expect(await interactions.deleteForEveryone(reply.id), isTrue);
    edited = await database.messages.getById(reply.id);
    expect(edited?.contentType, StorageMessageContentType.deleted);
    final encryptedSignals = signaling.sentMessages
        .whereType<EncryptedSignalMessage>()
        .toList(growable: false);
    expect(encryptedSignals, isNotEmpty);
    expect(
      encryptedSignals.every(
        (signal) =>
            !signal.envelope.contains('Device edited secret') &&
            !signal.envelope.contains('Device Operations'),
      ),
      isTrue,
    );
    for (final signal in encryptedSignals) {
      expect(signal.toJson(), isNot(containsPair('groupId', anything)));
      expect(signal.toJson(), isNot(containsPair('groupName', anything)));
    }
    final rawStorage = await databaseFile.readAsString();
    expect(rawStorage, isNot(contains('Device edited secret')));
    expect(rawStorage, isNot(contains('Device Operations')));
    debugPrint('[device-chat-group] encrypted-wire-and-storage');

    await database.close();
    databaseClosed = true;
    final reopened = await SecureChatDatabase.open(
      file: databaseFile,
      crypto: crypto,
    );
    expect(
      (await reopened.conversations.getById(group.id))?.isReadOnly,
      isTrue,
    );
    expect(
      (await reopened.messages.getById(reply.id))?.contentType,
      StorageMessageContentType.deleted,
    );
    await reopened.close();
    debugPrint('[device-chat-group] encrypted-reopen-persisted');
  });
}

class _SeededDeviceContacts implements DeviceContactsGateway {
  const _SeededDeviceContacts();

  @override
  Future<List<DeviceContact>> getAllContacts() async => const [
    DeviceContact(displayName: 'Alice Device', phoneNumber: '0555 111 11 11'),
    DeviceContact(displayName: 'Bob Device', phoneNumber: '0555 222 22 22'),
  ];

  @override
  Future<bool> requestPermission() async => true;
}

class _DeviceDiscovery implements ContactDiscoveryApi {
  _DeviceDiscovery(this.userIdByHash);

  final Map<String, String> userIdByHash;
  List<String> receivedHashes = const [];

  @override
  Future<List<RegisteredUserMatch>> checkUsers(
    List<String> phoneHashes,
    String accessToken, {
    String? ownPhoneHash,
    String? ownUserId,
  }) async {
    receivedHashes = List.unmodifiable(phoneHashes);
    return [
      for (final hash in phoneHashes)
        if (userIdByHash[hash] case final userId?)
          RegisteredUserMatch(userId: userId, phoneHash: hash),
    ];
  }
}
