import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/groups/private_group_call_routes.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'random call token is re-read after delayed encrypted preparation',
    () async {
      final dir = await Directory.systemTemp.createTemp('group_routes_');
      final db = await SecureChatDatabase.open(
        file: File('${dir.path}/db'),
        crypto: LocalAeadCryptoService(SecretKey(List.filled(32, 3))),
      );
      addTearDown(() async {
        await db.close();
        await dir.delete(recursive: true);
      });
      const group = ConversationEntity(
        id: 'group',
        peerId: 'group',
        peerName: 'Private',
        peerPhone: '',
        isGroup: true,
        groupMembers: 'alice,bob',
        groupAdmins: 'alice',
      );
      await db.conversations.insert(group);
      final routes = PrivateGroupCallRoutes(db, SessionStore(userId: 'bob'));
      final token = newOpaqueRoutingNonce();
      final resolving = routes.resolve(
        token,
        timeout: const Duration(seconds: 2),
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await routes.remember(token, 'group');
      expect(await resolving, 'group');
      expect(await routes.tokensForGroup('group'), [token]);
      await db.conversations.updateGroupMembers('group', 'alice');
      expect(await routes.tokensForGroup('group'), isEmpty);
      expect(await routes.resolve(token, timeout: Duration.zero), isNull);
      expect(await routes.containsMember('group', 'alice'), isFalse);
    },
  );
}
