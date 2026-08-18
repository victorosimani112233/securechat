import 'dart:convert';
import 'dart:math';

import '../auth/phone_privacy.dart';
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
/// protocol deliberately performs no remote phone lookup. Unknown peers stay
/// opaque until the user associates them with a local contact.
class ContactIdentityResolver {
  ContactIdentityResolver({required SecureChatDatabase database})
    : _database = database;

  final SecureChatDatabase _database;

  Future<ContactIdentity> resolve(String userId) async {
    final local = await _database.contacts.getById(userId);
    if (local != null && local.phoneNumber.isNotEmpty) {
      return ContactIdentity(
        displayName: local.displayName.isEmpty
            ? local.phoneNumber
            : local.displayName,
        phoneNumber: local.phoneNumber,
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
  }) : _deviceContacts = deviceContacts,
       _api = api,
       _database = database,
       _session = session;

  final DeviceContactsGateway _deviceContacts;
  final ContactDiscoveryApi _api;
  final SecureChatDatabase _database;
  final SessionStore _session;

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

  Future<void> ensureConversation(ContactEntity contact) async {
    final existing = await _database.conversations.getByPeerId(contact.id);
    if (existing != null) return;
    await _database.conversations.insert(
      ConversationEntity(
        id: contact.id,
        peerId: contact.id,
        peerName: contact.displayName,
        peerPhone: contact.phoneNumber,
      ),
    );
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
    final id = _newPrivateGroupId();
    final group = ConversationEntity(
      id: id,
      peerId: id,
      peerName: name.trim().isEmpty ? 'Yeni Grup' : name.trim(),
      peerPhone: '',
      isGroup: true,
      groupMembers: [
        if (_session.userId != null) _session.userId!,
        ...members.map((member) => member.id),
      ].toSet().join(','),
      groupAdmins: _session.userId ?? '',
    );
    await _database.conversations.insert(group);
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
