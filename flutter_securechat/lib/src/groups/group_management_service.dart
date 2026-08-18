import '../services/crypto_service.dart';
import '../services/session_store.dart';
import '../services/signaling_service.dart';
import '../storage/secure_chat_database.dart';
import '../storage/storage_entities.dart';
import 'private_group_control.dart';

class GroupManagementException implements Exception {
  const GroupManagementException(this.message);
  final String message;
  @override
  String toString() => message;
}

class GroupManagementService {
  GroupManagementService({
    required SecureChatDatabase database,
    required SessionStore session,
    required SignalingService signaling,
    required CryptoService crypto,
  }) : _database = database,
       _session = session,
       _controls = PrivateGroupControlSender(
         crypto: crypto,
         signaling: signaling,
       );

  static const maximumMembers = 256;
  final SecureChatDatabase _database;
  final SessionStore _session;
  final PrivateGroupControlSender _controls;

  Stream<ConversationEntity?> watchGroup(String groupId) =>
      _database.conversations.observeById(groupId);

  Stream<List<ContactEntity>> watchContacts() => _database.contacts.getAll();

  bool isLocalAdmin(ConversationEntity group) {
    final members = _split(group.groupMembers);
    final admins = _split(group.groupAdmins);
    final effective = admins.isEmpty && members.isNotEmpty
        ? <String>[members.first]
        : admins;
    return _session.userId != null && effective.contains(_session.userId);
  }

  String? get localUserId => _session.userId;

  Future<void> setMuted(String groupId, bool muted) =>
      _database.conversations.updateMuted(groupId, muted);

  Future<void> setLocked(String groupId, bool locked) =>
      _database.conversations.updateLocked(groupId, locked);

  Future<void> addMembers(String groupId, Iterable<String> newMemberIds) async {
    final state = await _adminState(groupId);
    final additions = newMemberIds
        .where((id) => id.isNotEmpty && !state.members.contains(id))
        .toSet();
    if (additions.isEmpty) {
      throw const GroupManagementException('Eklenecek yeni üye yok.');
    }
    if (state.members.length + additions.length > maximumMembers) {
      throw const GroupManagementException('Grup üye limiti doldu (256).');
    }
    final updated = [...state.members, ...additions];
    await _database.conversations.updateGroupMembers(
      groupId,
      updated.join(','),
    );
    for (final newMember in additions) {
      // A new member has no local group record yet, so bootstrap it with an
      // authenticated private CREATE envelope. Existing members receive the
      // narrower ADD event for their local audit/system-message history.
      await _controls.send(
        senderId: state.userId,
        groupId: state.group.id,
        groupName: state.group.peerName,
        memberIds: updated,
        recipients: [newMember],
        action: 'CREATE',
      );
      await _fanout(
        state.group,
        state.members,
        action: 'ADD_MEMBER',
        targetMemberId: newMember,
        advertisedMembers: updated,
      );
    }
  }

  Future<void> removeMember(String groupId, String memberId) async {
    final state = await _adminState(groupId);
    if (memberId == state.userId) {
      throw const GroupManagementException(
        'Kendinizi yönetici işlemiyle çıkaramazsınız.',
      );
    }
    if (!state.members.contains(memberId)) {
      throw const GroupManagementException('Kullanıcı grup üyesi değil.');
    }
    final updated = state.members.where((id) => id != memberId).toList();
    await _database.conversations.updateGroupMembers(
      groupId,
      updated.join(','),
    );
    if (state.admins.contains(memberId)) {
      await _database.conversations.updateGroupAdmins(
        groupId,
        state.admins.where((id) => id != memberId).join(','),
      );
    }
    await _fanout(
      state.group,
      {...updated, memberId},
      action: 'REMOVE_MEMBER',
      targetMemberId: memberId,
      advertisedMembers: updated,
    );
  }

  Future<void> promoteToAdmin(String groupId, String memberId) async {
    final state = await _adminState(groupId);
    if (!state.members.contains(memberId)) {
      throw const GroupManagementException('Kullanıcı grup üyesi değil.');
    }
    if (state.admins.contains(memberId)) {
      throw const GroupManagementException('Kullanıcı zaten yönetici.');
    }
    await _database.conversations.updateGroupAdmins(
      groupId,
      [...state.admins, memberId].join(','),
    );
    await _fanout(
      state.group,
      state.members,
      action: 'UPDATE_ADMIN',
      targetMemberId: memberId,
    );
  }

  Future<void> updateName(String groupId, String newName) async {
    final state = await _adminState(groupId);
    final clean = newName.trim();
    if (clean.isEmpty) {
      throw const GroupManagementException('Grup adı boş olamaz.');
    }
    if (clean == state.group.peerName) {
      throw const GroupManagementException('Grup adı zaten bu.');
    }
    await _database.conversations.updatePeerName(groupId, clean);
    await _fanout(
      state.group.copyWith(peerName: clean),
      state.members,
      action: 'UPDATE_NAME',
    );
  }

  Future<void> setReadOnly(String groupId, bool enabled) async {
    final state = await _adminState(groupId);
    await _database.conversations.updateReadOnly(groupId, enabled);
    await _fanout(
      state.group,
      state.members,
      action: 'SET_READ_ONLY',
      targetMemberId: enabled.toString(),
    );
  }

  Future<void> leaveGroup(String groupId) async {
    final userId = _session.userId;
    final group = await _group(groupId);
    if (userId == null) {
      throw const GroupManagementException('Kullanıcı giriş yapmamış.');
    }
    final remaining = _split(
      group.groupMembers,
    ).where((id) => id != userId).toList();
    await _controls.send(
      senderId: userId,
      groupId: group.id,
      groupName: group.peerName,
      memberIds: remaining,
      recipients: remaining,
      action: 'LEAVE_GROUP',
    );
    await _database.conversations.updateGroupMembers(
      groupId,
      remaining.join(','),
    );
    await _database.conversations.updateArchived(groupId, true);
  }

  Future<_AdminState> _adminState(String groupId) async {
    final userId = _session.userId;
    if (userId == null) {
      throw const GroupManagementException('Kullanıcı giriş yapmamış.');
    }
    final group = await _group(groupId);
    final members = _split(group.groupMembers);
    final storedAdmins = _split(group.groupAdmins);
    final admins = storedAdmins.isEmpty && members.isNotEmpty
        ? <String>[members.first]
        : storedAdmins;
    if (!admins.contains(userId)) {
      throw const GroupManagementException(
        'Bu işlem yalnızca grup yöneticilerine açık.',
      );
    }
    return _AdminState(
      userId: userId,
      group: group,
      members: members,
      admins: admins,
    );
  }

  Future<ConversationEntity> _group(String groupId) async {
    final group = await _database.conversations.getById(groupId);
    if (group == null || !group.isGroup) {
      throw const GroupManagementException('Grup bulunamadı.');
    }
    return group;
  }

  Future<void> _fanout(
    ConversationEntity group,
    Iterable<String> recipients, {
    required String action,
    String? targetMemberId,
    List<String>? advertisedMembers,
  }) async {
    final userId = _session.userId!;
    await _controls.send(
      senderId: userId,
      groupId: group.id,
      groupName: group.peerName,
      memberIds: advertisedMembers ?? _split(group.groupMembers),
      recipients: recipients,
      action: action,
      targetMemberId: targetMemberId,
    );
  }

  static List<String> _split(String? value) =>
      value?.split(',').where((id) => id.isNotEmpty).toList() ?? const [];
}

class _AdminState {
  const _AdminState({
    required this.userId,
    required this.group,
    required this.members,
    required this.admins,
  });
  final String userId;
  final ConversationEntity group;
  final List<String> members;
  final List<String> admins;
}
