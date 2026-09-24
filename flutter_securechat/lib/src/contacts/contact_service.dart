import 'dart:convert';
import 'dart:math';

import '../auth/phone_privacy.dart';
import '../groups/private_group_control.dart';
import '../network/network_resilience.dart';
import '../platform/native_bridge.dart';
import '../services/session_store.dart';
import '../storage/secure_chat_database.dart';
import '../storage/storage_entities.dart';
import 'contact_discovery_api.dart';

export 'contact_discovery_api.dart';

class DeviceContact {
  const DeviceContact({
    required this.displayName,
    required this.phoneNumber,
    this.avatarUri,
  });

  final String displayName;
  final String phoneNumber;
  final String? avatarUri;
}

abstract interface class DeviceContactsGateway {
  Future<bool> requestPermission();
  Future<List<DeviceContact>> getAllContacts();
}

class NativeDeviceContactsGateway implements DeviceContactsGateway {
  NativeDeviceContactsGateway({NativeBridge? bridge})
    : _bridge = bridge ?? const NativeBridge();

  final NativeBridge _bridge;

  @override
  Future<bool> requestPermission() => _bridge.requestContactsPermission();

  @override
  Future<List<DeviceContact>> getAllContacts() async {
    final records = await _bridge.readContacts();
    return records
        .map(
          (record) => DeviceContact(
            displayName: record['displayName']?.toString() ?? '',
            phoneNumber: record['phoneNumber']?.toString() ?? '',
            avatarUri: record['avatarUri']?.toString(),
          ),
        )
        .where(
          (contact) =>
              contact.displayName.isNotEmpty && contact.phoneNumber.isNotEmpty,
        )
        .toList(growable: false);
  }
}

class ContactIdentity {
  const ContactIdentity({required this.displayName, required this.phoneNumber});

  final String displayName;
  final String phoneNumber;
}

/// Resolves an opaque signaling user ID exclusively from local device data.
///
/// The legacy Kotlin endpoint returned phone ciphertext encrypted with one
/// application-wide embedded key. A reverse-engineered client could recover
/// that key and decrypt every captured server row, so the Flutter privacy
/// protocol deliberately performs no UUID-to-phone lookup. Shared numbers are
/// stored locally only after an encrypted introduction passes directory checks.
class ContactIdentityResolver {
  ContactIdentityResolver({required SecureChatDatabase database})
    : _database = database;

  final SecureChatDatabase _database;

  Future<ContactIdentity> resolve(String userId) async {
    final local = await _database.contacts.getById(userId);
    final conversation = await _database.conversations.getByPeerId(userId);
    return _resolveLocal(userId, local, conversation);
  }

  Future<Map<String, ContactIdentity>> resolveMany(
    Iterable<String> userIds,
  ) async {
    final ids = userIds.toSet();
    if (ids.isEmpty) return const {};
    final contacts = {
      for (final contact in await _database.contacts.getAllOnce())
        if (ids.contains(contact.id)) contact.id: contact,
    };
    final conversations = {
      for (final conversation in await _database.conversations.getByPeerIds(
        ids.toList(),
      ))
        if (!conversation.isGroup) conversation.peerId: conversation,
    };
    return {
      for (final id in ids)
        id: _resolveLocal(id, contacts[id], conversations[id]),
    };
  }

  static ContactIdentity _resolveLocal(
    String userId,
    ContactEntity? local,
    ConversationEntity? conversation,
  ) {
    if (local != null && local.phoneNumber.isNotEmpty) {
      return ContactIdentity(
        displayName: local.displayName.isEmpty
            ? local.phoneNumber
            : local.displayName,
        phoneNumber: local.phoneNumber,
      );
    }
    if (conversation != null &&
        !conversation.isGroup &&
        conversation.peerPhone.isNotEmpty) {
      return ContactIdentity(
        displayName: local?.displayName.isNotEmpty == true
            ? local!.displayName
            : conversation.peerPhone,
        phoneNumber: conversation.peerPhone,
      );
    }
    return ContactIdentity(
      displayName: local?.displayName.isNotEmpty == true
          ? local!.displayName
          : userId,
      phoneNumber: local?.phoneNumber ?? '',
    );
  }

  Future<String> resolveDisplayName(String userId) async =>
      (await resolve(userId)).displayName;

  Future<String> resolvePhoneNumber(String userId) async =>
      (await resolve(userId)).phoneNumber;
}

class ContactService {
  ContactService({
    required DeviceContactsGateway deviceContacts,
    required ContactDiscoveryApi api,
    required SecureChatDatabase database,
    required SessionStore session,
    PrivateGroupControlSender? groupControls,
    OfflineMessageQueue? offlineQueue,
  }) : _deviceContacts = deviceContacts,
       _api = api,
       _database = database,
       _session = session,
       _groupControls = groupControls,
       _offlineQueue = offlineQueue;

  final DeviceContactsGateway _deviceContacts;
  final ContactDiscoveryApi _api;
  final SecureChatDatabase _database;
  final SessionStore _session;
  final PrivateGroupControlSender? _groupControls;
  final OfflineMessageQueue? _offlineQueue;

  Stream<List<ContactEntity>> watchRegistered() =>
      _database.contacts.getRegistered();

  Future<bool> requestContactsPermission() =>
      _deviceContacts.requestPermission();

  Future<List<ContactEntity>> importAndDiscover() async {
    if (!await _deviceContacts.requestPermission()) {
      throw StateError('Rehber izni verilmedi');
    }
    final token = _session.accessToken;
    if (token == null || token.isEmpty) {
      throw StateError('Contact discovery icin login gerekli');
    }
    final contacts = await _deviceContacts.getAllContacts();
    final byHash = <String, DeviceContact>{};
    for (final contact in contacts) {
      final hash = await hashPhoneNumber(contact.phoneNumber);
      byHash[hash] = contact;
    }
    final matches = await _discover(byHash.keys.toList(), token);
    final registered = matches
        .map((match) {
          if (match.userId == _session.userId) return null;
          final contact = byHash[match.phoneHash];
          return contact == null
              ? null
              : ContactEntity(
                  id: match.userId,
                  phoneNumber: contact.phoneNumber,
                  phoneHash: match.phoneHash,
                  displayName: contact.displayName,
                  isRegistered: true,
                  avatarUri: contact.avatarUri,
                );
        })
        .whereType<ContactEntity>()
        .toList(growable: false);
    await _database.contacts.insertAll(registered);
    for (final contact in registered) {
      final conversation = await _database.conversations.getByPeerId(
        contact.id,
      );
      if (conversation != null && !conversation.isGroup) {
        await _database.conversations.updatePeerIdentity(
          conversation.id,
          contact.displayName,
          contact.phoneNumber,
        );
      }
    }

    final deviceHashes = byHash.keys.toSet();
    for (final existing in await _database.contacts.getAllOnce()) {
      if (!deviceHashes.contains(existing.phoneHash)) {
        await _database.contacts.delete(existing.id);
      }
    }
    return registered;
  }

  Future<ContactEntity?> resolvePhone(String input) async {
    final token = _session.accessToken;
    if (token == null || token.isEmpty) throw StateError('Login gerekli');
    final normalized = normalizePhoneDigits(input);
    final hash = await hashPhoneNumber(normalized);
    final match = (await _discover([hash], token)).firstOrNull;
    if (match == null) return null;
    if (match.userId == _session.userId) return null;
    final contact = ContactEntity(
      id: match.userId,
      phoneNumber: '+$normalized',
      phoneHash: hash,
      displayName: '+$normalized',
      isRegistered: true,
    );
    await _database.contacts.insert(contact);
    await ensureConversation(contact);
    return contact;
  }

  Future<ConversationEntity> ensureConversation(ContactEntity contact) async {
    final existing = await _database.conversations.getByPeerId(contact.id);
    if (existing != null) {
      if (!existing.isGroup) {
        await _database.conversations.updatePeerIdentity(
          existing.id,
          contact.displayName,
          contact.phoneNumber,
        );
        return (await _database.conversations.getById(existing.id))!;
      }
      return existing;
    }
    final conversation = ConversationEntity(
      id: contact.id,
      peerId: contact.id,
      peerName: contact.displayName,
      peerPhone: contact.phoneNumber,
    );
    await _database.conversations.insert(conversation);
    return conversation;
  }

  Future<List<RegisteredUserMatch>> _discover(
    List<String> hashes,
    String accessToken,
  ) async {
    final ownPhone = _session.phoneNumber;
    final ownHash = ownPhone == null || ownPhone.isEmpty
        ? null
        : await hashPhoneNumber(ownPhone);
    return _api.checkUsers(
      hashes,
      accessToken,
      ownPhoneHash: ownHash,
      ownUserId: _session.userId,
    );
  }

  Future<ConversationEntity> createGroup(
    String name,
    List<ContactEntity> members,
  ) async {
    if (members.isEmpty) throw ArgumentError('En az bir uye secin');
    final senderId = _session.userId;
    final controls = _groupControls;
    final queue = _offlineQueue;
    if (senderId == null || controls == null || queue == null) {
      throw StateError('Authenticated group delivery is unavailable');
    }
    final id = _newPrivateGroupId();
    final group = ConversationEntity(
      id: id,
      peerId: id,
      peerName: name.trim().isEmpty ? 'Yeni Grup' : name.trim(),
      peerPhone: '',
      isGroup: true,
      groupMembers: [
        senderId,
        ...members.map((member) => member.id),
      ].toSet().join(','),
      groupAdmins: senderId,
    );
    final recipients = members.map((m) => m.id).toSet()..remove(senderId);
    if (recipients.isEmpty || group.peerName.length > 256) {
      throw ArgumentError('Invalid group name or members');
    }
    final pending = <PendingSignalEntity>[];
    final now = DateTime.now();
    // Prepare every encrypted invitation before committing the group. A failed
    // prekey lookup must not leave a local-only or partially invited group.
    await controls.send(
      senderId: senderId,
      groupId: id,
      groupName: group.peerName,
      memberIds: [senderId, ...recipients],
      recipients: recipients,
      action: 'CREATE',
      timestamp: now,
      sendSignal: (signal) async {
        pending.add(
          PendingSignalEntity(
            id: '$id-invite-${pending.length}',
            encodedSignal: signal.encode(),
            createdAt: now.millisecondsSinceEpoch,
          ),
        );
        return true;
      },
    );
    await _database.conversations.insertWithPendingSignals(group, pending);
    await queue.flushEnqueuedSignals();
    return group;
  }
}

String _newPrivateGroupId() {
  final random = Random.secure();
  final bytes = List<int>.generate(24, (_) => random.nextInt(256));
  return 'group-${base64UrlEncode(bytes).replaceAll('=', '')}';
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
