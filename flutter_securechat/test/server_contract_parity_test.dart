import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/contacts/contact_service.dart';
import 'package:flutter_securechat/src/crypto/crypto_protocol_store.dart';
import 'package:flutter_securechat/src/crypto/pre_key_maintenance_service.dart';
import 'package:flutter_securechat/src/crypto/pre_key_manager.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('prekey refresh uses Ktor list contract and bearer auth', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.close);
    final manager = PreKeyManager(
      fixture.store,
      batchSize: 4,
      refreshThreshold: 2,
    );
    await manager.generateAndSerializeInitialBundle();
    await manager.discardOneTimePreKeys([0, 1, 2, 3]);
    late List<Object?> received;
    late String authorization;
    final server = await _serve((request) async {
      authorization =
          request.headers.value(HttpHeaders.authorizationHeader) ?? '';
      received = jsonDecode(await utf8.decoder.bind(request).join()) as List;
      request.response
        ..statusCode = HttpStatus.ok
        ..write('{"status":"ok","remaining":"4"}');
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    final service = _preKeyService(server, manager);

    expect(await service.replenishIfNeeded(), isTrue);
    expect(authorization, 'Bearer access-token');
    expect(received, hasLength(4));
    expect((received.first as Map).keys.toSet(), {'keyId', 'publicKey'});
    expect(await manager.availablePreKeyCount(), 4);
  });

  test('failed prekey refresh rolls back and remains retryable', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.close);
    final manager = PreKeyManager(
      fixture.store,
      batchSize: 3,
      refreshThreshold: 2,
    );
    await manager.generateAndSerializeInitialBundle();
    await manager.discardOneTimePreKeys([0, 1, 2]);
    var requests = 0;
    final server = await _serve((request) async {
      requests++;
      await request.drain<void>();
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    final service = _preKeyService(server, manager);

    expect(await service.replenishIfNeeded(), isFalse);
    expect(await manager.availablePreKeyCount(), 0);
    expect(await service.replenishIfNeeded(), isFalse);
    expect(requests, 2);
  });

  test(
    'unknown identity remains opaque and never creates phone data',
    () async {
      final fixture = await _Fixture.open();
      addTearDown(fixture.close);
      final resolver = ContactIdentityResolver(database: fixture.database);

      final identity = await resolver.resolve('alice-id');

      expect(identity.displayName, 'alice-id');
      expect(identity.phoneNumber, isEmpty);
      expect(await fixture.database.contacts.getById('alice-id'), isNull);
    },
  );

  test('phone resolver preserves contact name and fails closed', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.close);
    await fixture.database.contacts.insert(
      const ContactEntity(
        id: 'known',
        phoneNumber: '+90 555 000 0000',
        phoneHash: 'hash',
        displayName: 'Alice',
        isRegistered: true,
      ),
    );
    final resolver = ContactIdentityResolver(database: fixture.database);

    expect(await resolver.resolveDisplayName('known'), 'Alice');
    expect(await resolver.resolvePhoneNumber('unknown'), '');
  });
}

PreKeyMaintenanceService _preKeyService(
  HttpServer server,
  PreKeyManager manager,
) => PreKeyMaintenanceService(
  manager: manager,
  apiBaseUrl: Uri.parse(_baseUrl(server)),
  httpClient: HttpClient(),
  accessTokenProvider: () async => 'access-token',
);

Future<HttpServer> _serve(
  Future<void> Function(HttpRequest request) handler,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen(handler);
  return server;
}

String _baseUrl(HttpServer server) =>
    'http://${server.address.address}:${server.port}';

class _Fixture {
  const _Fixture(this.directory, this.database, this.store);

  final Directory directory;
  final SecureChatDatabase database;
  final DatabaseCryptoProtocolStore store;

  static Future<_Fixture> open() async {
    final directory = await Directory.systemTemp.createTemp(
      'securechat_server_contract_',
    );
    final database = await SecureChatDatabase.open(
      file: File('${directory.path}/storage.securejson'),
      crypto: LocalAeadCryptoService(
        SecretKey(List<int>.generate(32, (index) => index + 1)),
      ),
    );
    return _Fixture(directory, database, DatabaseCryptoProtocolStore(database));
  }

  Future<void> close() async {
    await database.close();
    await directory.delete(recursive: true);
  }
}
