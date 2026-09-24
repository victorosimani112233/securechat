import 'dart:convert';

import '../services/crypto_service.dart';
import '../services/session_store.dart';
import '../storage/secure_chat_database.dart';
import 'private_group_control.dart';

/// Call-scoped routing tokens live only in the encrypted local database.
class PrivateGroupCallRoutes {
  const PrivateGroupCallRoutes(this.database, this.session);
  final SecureChatDatabase database;
  final SessionStore session;

  Future<bool> containsMember(String groupId, String peerId) async {
    final group = await database.conversations.getById(groupId);
    final members = (group?.groupMembers ?? '').split(',').toSet();
    return group?.isGroup == true &&
        members.contains(session.userId) &&
        members.contains(peerId);
  }

  Future<void> remember(String token, String groupId) =>
      database.cryptoState.put(
        privateGroupCallRouteStateKey(token),
        jsonEncode({
          'groupId': groupId,
          'expiresAt': DateTime.now()
              .add(const Duration(hours: 4))
              .millisecondsSinceEpoch,
        }),
      );

  Future<String?> resolve(
    String token, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final deadline = DateTime.now().add(timeout);
    do {
      // Re-read the encrypted route on EVERY attempt: PREPARE_CALL is decrypted
      // asynchronously and a random call token cannot match the legacy hash.
      final stored = await database.cryptoState.get(
        privateGroupCallRouteStateKey(token),
      );
      if (stored != null) {
        final groupId = _validGroup(stored);
        if (groupId != null &&
            await containsMember(groupId, session.userId ?? '')) {
          return groupId;
        }
      }
      for (final group in await database.conversations.getAllGroups()) {
        if (await containsMember(group.id, session.userId ?? '') &&
            await groupRoutingToken(group.id) == token)
          return group.id;
      }
      if (!DateTime.now().isBefore(deadline)) break;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    } while (true);
    return null;
  }

  Future<List<String>> tokensForGroup(String groupId) async {
    if (!await containsMember(groupId, session.userId ?? '')) return const [];
    const prefix = 'private-group-call-route:';
    final records = await database.cryptoState.getByPrefix(prefix);
    final tokens = <String>[];
    for (final entry in records.entries) {
      final storedGroup = _validGroup(entry.value);
      if (storedGroup == null) {
        await database.cryptoState.delete(entry.key);
      } else if (storedGroup == groupId) {
        tokens.add(entry.key.substring(prefix.length));
      }
    }
    return tokens.reversed.take(16).toList();
  }

  String? _validGroup(String encoded) {
    try {
      final value = jsonDecode(encoded) as Map<String, dynamic>;
      if ((value['expiresAt'] as num).toInt() <=
          DateTime.now().millisecondsSinceEpoch)
        return null;
      return value['groupId'] as String;
    } catch (_) {
      return null;
    }
  }
}
