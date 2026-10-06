import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/crypto/crypto_protocol_store.dart';
import 'package:flutter_securechat/src/crypto/pre_key_maintenance_service.dart';
import 'package:flutter_securechat/src/crypto/pre_key_manager.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_test/flutter_test.dart';

/// Access token TTL'i bir saat, background isolate 15 dakikada bir kosuyor.
/// Cihaz bir saatten uzun arka planda kalinca saklanan token oluyordu ve
/// `/api/v1/prekeys/status` 401 donuyordu. Eski kodda bu hata `catch (_)`
/// icinde yutuldugu icin havuz hic yenilenmiyor ve hicbir yerde iz
/// kalmiyordu. Canli sunucuda iki hesabin havuzu 88 ve 92'de takili kalmisti.
void main() {
  test('401 alinca token yenilenir ve istek bir kez tekrar denenir', () async {
    final fixture = await _fixture(
      statuses: [HttpStatus.unauthorized, HttpStatus.ok],
    );

    final replenished = await fixture.service.replenishIfNeeded();

    expect(replenished, isTrue);
    expect(fixture.refreshCount, 1);
    expect(fixture.authorizations, ['Bearer stale', 'Bearer fresh']);
    expect(fixture.failures, isEmpty);
  });

  test('status 200 donunce token bosuna yenilenmez', () async {
    final fixture = await _fixture(statuses: [HttpStatus.ok]);

    final replenished = await fixture.service.replenishIfNeeded();

    expect(replenished, isTrue);
    expect(fixture.refreshCount, 0);
    expect(fixture.authorizations, ['Bearer stale']);
  });

  test('yenileme yoksa hata yutulmaz, cagirana bildirilir', () async {
    final fixture = await _fixture(
      statuses: [HttpStatus.unauthorized],
      withRefresh: false,
    );

    final replenished = await fixture.service.replenishIfNeeded();

    expect(replenished, isFalse);
    expect(fixture.refreshCount, 0);
    expect(fixture.failures.single, 'replenish');
  });

  test('yenilemeden sonra da 401 gelirse sonsuz denenmez', () async {
    final fixture = await _fixture(
      statuses: [HttpStatus.unauthorized, HttpStatus.unauthorized],
    );

    final replenished = await fixture.service.replenishIfNeeded();

    expect(replenished, isFalse);
    expect(fixture.refreshCount, 1);
    expect(fixture.authorizations, ['Bearer stale', 'Bearer fresh']);
    expect(fixture.failures.single, 'replenish');
  });
}

Future<_Fixture> _fixture({
  required List<int> statuses,
  bool withRefresh = true,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final client = HttpClient();
  final directory = await Directory.systemTemp.createTemp('prekey-maint');
  final crypto = LocalAeadCryptoService(
    SecretKey(List<int>.generate(32, (index) => 17 + index)),
  );
  final database = await SecureChatDatabase.open(
    file: File('${directory.path}/database.securejson'),
    crypto: crypto,
  );
  addTearDown(() async {
    client.close(force: true);
    await server.close(force: true);
    await database.close();
    await directory.delete(recursive: true);
  });

  final fixture = _Fixture();
  var token = 'stale';
  var index = 0;
  server.listen((request) async {
    fixture.authorizations.add(
      request.headers.value(HttpHeaders.authorizationHeader) ?? '',
    );
    final status = statuses[index < statuses.length ? index : statuses.length - 1];
    index++;
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      // Esik 20; 100 kalan bildirmek yeni parti uretimini atlatir, boylece
      // test yalniz auth yolunu olcer.
      ..write(jsonEncode(const {'remaining': 100}));
    await request.response.close();
  });

  fixture.service = PreKeyMaintenanceService(
    manager: PreKeyManager(DatabaseCryptoProtocolStore(database)),
    apiBaseUrl: Uri.parse('http://${server.address.address}:${server.port}'),
    httpClient: client,
    accessTokenProvider: () async => token,
    refreshAccessToken: withRefresh
        ? () async {
            fixture.refreshCount++;
            token = 'fresh';
            return token;
          }
        : null,
    onFailure: (operation, error, stackTrace) =>
        fixture.failures.add(operation),
  );
  return fixture;
}

class _Fixture {
  late PreKeyMaintenanceService service;
  final authorizations = <String>[];
  final failures = <String>[];
  int refreshCount = 0;
}
