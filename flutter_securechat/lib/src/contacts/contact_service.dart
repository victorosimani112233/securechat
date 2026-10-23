import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../auth/phone_privacy.dart';
import '../groups/private_group_control.dart';
import '../network/network_resilience.dart';
import '../platform/native_bridge.dart';
import '../services/session_store.dart';
import '../storage/secure_chat_database.dart';
import 'profile_name_sharing_service.dart';
import '../storage/storage_entities.dart';
import 'contact_discovery_api.dart';
import 'contact_index.dart';

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

  /// Sistemin kisi ekleme ekranini acar; acilamazsa `false`.
  Future<bool> openAddContact({required String phone, String name = ''});
}

class NativeDeviceContactsGateway implements DeviceContactsGateway {
  NativeDeviceContactsGateway({NativeBridge? bridge})
    : _bridge = bridge ?? const NativeBridge();

  final NativeBridge _bridge;

  @override
  Future<bool> requestPermission() => _bridge.requestContactsPermission();

  @override
  Future<bool> openAddContact({required String phone, String name = ''}) =>
      _bridge.addDeviceContact(phone: phone, name: name);

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
    // Birebir sohbetin basligi karsi tarafin paylastigi "~Ad" olabilir.
    // Ad yazilmamis (numarayla eklenmis) kiside grup uye etiketi de onu
    // gostersin; yoksa grupta numara gorunuyordu (QA 2026-10-14, T2'nin
    // grup tarafi).
    final directTitle = conversation == null || conversation.isGroup
        ? ''
        : conversation.peerName.trim();
    final hasDirectTitle =
        directTitle.isNotEmpty &&
        directTitle != userId &&
        directTitle != conversation?.peerPhone.trim() &&
        directTitle != local?.phoneNumber.trim();
    if (local != null && local.phoneNumber.isNotEmpty) {
      return ContactIdentity(
        displayName:
            hasDirectTitle && ProfileNameSharingService.isUnnamedContact(local)
            ? directTitle
            : local.displayName.isEmpty
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
            : hasDirectTitle
            ? directTitle
            : conversation.peerPhone,
        phoneNumber: conversation.peerPhone,
      );
    }
    // Numara paylasilmamis olsa da birebir sohbetin "~Ad" basligi bilinir;
    // grupta "Bilinmeyen uye" yerine o gorunur (QA 2026-10-14).
    return ContactIdentity(
      displayName: local?.displayName.isNotEmpty == true
          ? local!.displayName
          : hasDirectTitle
          ? directTitle
          : userId,
      phoneNumber: local?.phoneNumber ?? '',
    );
  }

  Future<String> resolveDisplayName(String userId) async =>
      (await resolve(userId)).displayName;

  Future<String> resolvePhoneNumber(String userId) async =>
      (await resolve(userId)).phoneNumber;
}

/// Dizine gore kullanicinin girdigi kendi numarasi.
enum OwnPhoneStatus { matches, otherAccount, notRegistered }

class ContactService {
  ContactService({
    required DeviceContactsGateway deviceContacts,
    required ContactDiscoveryApi api,
    required SecureChatDatabase database,
    required SessionStore session,
    PrivateGroupControlSender? groupControls,
    OfflineMessageQueue? offlineQueue,
    DateTime Function() now = DateTime.now,
  }) : _deviceContacts = deviceContacts,
       _api = api,
       _database = database,
       _session = session,
       _groupControls = groupControls,
       _offlineQueue = offlineQueue,
       _now = now;

  /// Otomatik eslemenin en sik araligi. Rehber ekrani her acildiginda tum
  /// rehber listesi sunucudan yeniden indiriliyor ve her numara icin
  /// sunucuda RSA islemi yapiliyordu. Rehber degistiyse ya da kullanici
  /// elle yenilediyse aralik beklenmez.
  static const discoveryInterval = Duration(minutes: 10);

  final DeviceContactsGateway _deviceContacts;
  final ContactDiscoveryApi _api;
  final SecureChatDatabase _database;
  final SessionStore _session;
  final PrivateGroupControlSender? _groupControls;
  final OfflineMessageQueue? _offlineQueue;
  final DateTime Function() _now;
  DateTime? _lastDiscoveryAt;
  Set<String> _lastDiscoveryHashes = const {};
  String? _lastDiscoveryUser;

  Stream<List<ContactEntity>> watchRegistered() =>
      _database.contacts.getRegistered();

  /// Kisi kaydi var mi (rehberden ya da numarayla elle eklenmis).
  Future<bool> isKnownContact(String userId) async =>
      await _database.contacts.getById(userId) != null;

  /// Grup uye secicisi icin: rehber kisileri + birebir sohbet karsi taraflari.
  Stream<List<ContactEntity>> watchGroupCandidates() =>
      _database.contacts.watchGroupCandidates();

  Future<bool> requestContactsPermission() =>
      _deviceContacts.requestPermission();

  /// Rehberde olmayan birini cihaz rehberine eklemek icin sistem ekranini
  /// acar. "~Ad" karsi tarafin kendi verdigi ad; rehbere isaretsiz onerilir.
  /// Kayit sistem ekraninda yapilir; donuste [importAndDiscover] kisiyi
  /// bilinir kilar.
  Future<bool> openAddToDeviceContacts({
    required String phone,
    String sharedName = '',
  }) {
    final number = phone.trim();
    if (number.isEmpty) return Future.value(false);
    var name = sharedName.trim();
    if (name.startsWith('~')) name = name.substring(1).trim();
    if (name == number) name = '';
    return _deviceContacts.openAddContact(phone: number, name: name);
  }

  /// Rehberde olup ELÇİM'de bulunmayan kisiler (davet listesi).
  ///
  /// Tamamen cihazda hesaplanir: sunucuya bir sey gitmez ve sonuc
  /// veritabanina yazilmaz. Kayitli kisiler rehber eslemesinin yerel
  /// sonucundan (telefon ozeti) ayiklanir; ayni numara bir kez listelenir.
  Future<List<DeviceContact>> loadInvitableContacts() async {
    if (!await _deviceContacts.requestPermission()) return const [];
    final registeredHashes = {
      for (final contact in await _database.contacts.getAllOnce())
        if (contact.isRegistered && contact.phoneHash.isNotEmpty)
          contact.phoneHash,
    };
    final ownPhone = _session.phoneNumber;
    final seen = <String>{
      if (ownPhone != null && ownPhone.trim().isNotEmpty)
        await hashPhoneNumber(ownPhone),
    };
    final invitable = <DeviceContact>[];
    for (final contact in await _deviceContacts.getAllContacts()) {
      if (normalizePhoneDigits(contact.phoneNumber).length < 8) continue;
      final hash = await hashPhoneNumber(contact.phoneNumber);
      if (registeredHashes.contains(hash) || !seen.add(hash)) continue;
      invitable.add(contact);
    }
    invitable.sort(
      (left, right) => compareContactNames(left.displayName, right.displayName),
    );
    return invitable;
  }

  /// [force] olmadan, ayni hesapla [discoveryInterval] icinde ve rehber
  /// degismeden yapilan cagri sunucuya gitmez; son eslesme kullanilir.
  Future<List<ContactEntity>> importAndDiscover({bool force = false}) async {
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
    final hashes = byHash.keys.toSet();
    final last = _lastDiscoveryAt;
    if (!force &&
        last != null &&
        _lastDiscoveryUser == _session.userId &&
        _now().difference(last) < discoveryInterval &&
        hashes.length == _lastDiscoveryHashes.length &&
        hashes.containsAll(_lastDiscoveryHashes)) {
      return [
        for (final contact in await _database.contacts.getAllOnce())
          if (contact.isRegistered &&
              !contact.addedManually &&
              hashes.contains(contact.phoneHash))
            contact,
      ];
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

    // Yalniz rehber kaynakli kisiler rehberle eslenir. Elle eklenen kisi
    // (tus takimindan numara) rehberde olmadigi icin siliniyordu.
    final deviceHashes = byHash.keys.toSet();
    final matchedIds = {for (final contact in registered) contact.id};
    for (final existing in await _database.contacts.getAllOnce()) {
      if (existing.addedManually || matchedIds.contains(existing.id)) {
        continue;
      }
      if (deviceHashes.contains(existing.phoneHash)) {
        // Rehberde duruyor ama artik bu hesapla eslesmiyor: hesap ELÇİM'den
        // ayrilmis ya da numara yeni bir hesaba gecmis. Eski kayit kalirsa
        // kisi "ELÇİM'de" gorunmeye ve ona ulasilamayan eski hesaba mesaj
        // gitmeye devam ederdi. Sohbet gecmisi silinmez.
        await _database.contacts.delete(existing.id);
        continue;
      }
      final conversation = await _database.conversations.getByPeerId(
        existing.id,
      );
      if (conversation != null && !conversation.isGroup) {
        // Rehberden silinen ama sohbeti suren kisi kaybolmaz.
        await _database.contacts.insert(existing.asManual());
      } else {
        await _database.contacts.delete(existing.id);
      }
    }
    _lastDiscoveryAt = _now();
    _lastDiscoveryHashes = hashes;
    _lastDiscoveryUser = _session.userId;
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
    final known = await _database.contacts.getById(match.userId);
    if (known != null && !known.addedManually) {
      // Rehber kaydi (adiyla) zaten var; numarayla ezilmez.
      await ensureConversation(known);
      return known;
    }
    final contact = ContactEntity(
      id: match.userId,
      phoneNumber: '+$normalized',
      phoneHash: hash,
      displayName: '+$normalized',
      isRegistered: true,
      addedManually: true,
    );
    await _database.contacts.insert(contact);
    await ensureConversation(contact);
    return contact;
  }

  /// Kurtarmadan sonra yeniden girilen kendi numaranin dizinde bu hesaba
  /// kayitli olup olmadigini okur. Dizine yazmaz: yanlis yazilan bir numara
  /// hesabin dizin kaydini degistirmemeli (QA 2026-10-13 O5).
  Future<OwnPhoneStatus> ownPhoneStatus(String input) async {
    final token = _session.accessToken;
    final userId = _session.userId;
    if (token == null || token.isEmpty || userId == null) {
      throw StateError('Login gerekli');
    }
    final hash = await hashPhoneNumber(input);
    final matches = await _api.checkUsers([hash], token);
    final owner = matches.where((m) => m.phoneHash == hash).firstOrNull;
    if (owner == null) return OwnPhoneStatus.notRegistered;
    return owner.userId == userId
        ? OwnPhoneStatus.matches
        : OwnPhoneStatus.otherAccount;
  }

  Future<ConversationEntity> ensureConversation(ContactEntity contact) async {
    final existing = await _database.conversations.getByPeerId(contact.id);
    // Yalniz numarayla eklenen kiside karsi tarafin paylastigi "~Ad"
    // numaradan once gelir (QA 2026-10-13 T2).
    final title = ProfileNameSharingService.isUnnamedContact(contact)
        ? await ProfileNameSharingService.storedLabel(_database, contact.id) ??
              contact.displayName
        : contact.displayName;
    if (existing != null) {
      if (!existing.isGroup) {
        await _database.conversations.updatePeerIdentity(
          existing.id,
          title,
          contact.phoneNumber,
        );
        return (await _database.conversations.getById(existing.id))!;
      }
      return existing;
    }
    final conversation = ConversationEntity(
      id: contact.id,
      peerId: contact.id,
      peerName: title,
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

  /// Grubu kurar ve her uyeye sifreli davet hazirlar.
  ///
  /// Anahtarina ulasilamayan uye (hesabi silinmis, uygulamayi guncel
  /// surumle hic acmamis vb.) artik butun grubu dusurmez: o uye atlanir,
  /// grup kalanlarla kurulur ve atlananlar [onUnreachable] ile bildirilir.
  /// Hicbir uyeye ulasilamazsa [GroupMembersUnreachableException] firlatilir.
  Future<ConversationEntity> createGroup(
    String name,
    List<ContactEntity> members, {
    void Function(List<ContactEntity> skipped)? onUnreachable,
  }) async {
    if (members.isEmpty) throw ArgumentError('En az bir uye secin');
    final senderId = _session.userId;
    final controls = _groupControls;
    final queue = _offlineQueue;
    if (senderId == null || controls == null || queue == null) {
      throw StateError('Authenticated group delivery is unavailable');
    }
    final id = _newPrivateGroupId();
    final groupName = name.trim().isEmpty ? 'Yeni Grup' : name.trim();
    final byId = {for (final member in members) member.id: member}
      ..remove(senderId);
    if (byId.isEmpty || groupName.length > 256) {
      throw ArgumentError('Invalid group name or members');
    }
    final now = DateTime.now();
    final unreachable = <String>{};
    var pending = await _prepareGroupInvites(
      controls: controls,
      senderId: senderId,
      groupId: id,
      groupName: groupName,
      recipients: byId.keys.toList(growable: false),
      now: now,
      onRecipientUnavailable: (recipientId, error) {
        unreachable.add(recipientId);
        debugPrint(
          'GROUP-CREATE member_unreachable '
          'error=${error.runtimeType}: ${_diagnostic(error)}',
        );
      },
    );
    if (unreachable.isNotEmpty) {
      final reachable = byId.keys
          .where((memberId) => !unreachable.contains(memberId))
          .toList(growable: false);
      if (reachable.isEmpty) {
        throw GroupMembersUnreachableException([
          for (final memberId in unreachable) byId[memberId]!,
        ]);
      }
      // Ilk turdaki davetler atlanan uyeyi de listeliyordu; uye listesi
      // kalanlarla yeniden sifrelenir. Bu turda hata yine butun islemi durdurur.
      pending = await _prepareGroupInvites(
        controls: controls,
        senderId: senderId,
        groupId: id,
        groupName: groupName,
        recipients: reachable,
        now: now,
      );
    }
    final group = ConversationEntity(
      id: id,
      peerId: id,
      peerName: groupName,
      peerPhone: '',
      isGroup: true,
      groupMembers: [
        senderId,
        ...byId.keys.where((memberId) => !unreachable.contains(memberId)),
      ].join(','),
      groupAdmins: senderId,
    );
    await _database.conversations.insertWithPendingSignals(group, pending);
    await queue.flushEnqueuedSignals();
    if (unreachable.isNotEmpty) {
      onUnreachable?.call([
        for (final memberId in unreachable) byId[memberId]!,
      ]);
    }
    return group;
  }

  // Prepare every encrypted invitation before committing the group. A failed
  // prekey lookup must not leave a local-only or partially invited group.
  Future<List<PendingSignalEntity>> _prepareGroupInvites({
    required PrivateGroupControlSender controls,
    required String senderId,
    required String groupId,
    required String groupName,
    required List<String> recipients,
    required DateTime now,
    void Function(String recipientId, Object error)? onRecipientUnavailable,
  }) async {
    final pending = <PendingSignalEntity>[];
    await controls.send(
      senderId: senderId,
      groupId: groupId,
      groupName: groupName,
      memberIds: [senderId, ...recipients],
      recipients: recipients,
      action: 'CREATE',
      timestamp: now,
      onRecipientUnavailable: onRecipientUnavailable,
      sendSignal: (signal) async {
        pending.add(
          PendingSignalEntity(
            id: '$groupId-invite-${pending.length}',
            encodedSignal: signal.encode(),
            createdAt: now.millisecondsSinceEpoch,
          ),
        );
        return true;
      },
    );
    return pending;
  }
}

/// Secilen uyelerin hicbirine sifreli davet hazirlanamadi.
class GroupMembersUnreachableException implements Exception {
  const GroupMembersUnreachableException(this.members);

  final List<ContactEntity> members;

  @override
  String toString() =>
      'GroupMembersUnreachableException(${members.length} member)';
}

/// Hata mesajini loga yazilabilir uzunlukta tutar.
String _diagnostic(Object error) {
  final text = error.toString().replaceAll('\n', ' ');
  return text.length <= 160 ? text : '${text.substring(0, 160)}...';
}

String _newPrivateGroupId() {
  final random = Random.secure();
  final bytes = List<int>.generate(24, (_) => random.nextInt(256));
  return 'group-${base64UrlEncode(bytes).replaceAll('=', '')}';
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
