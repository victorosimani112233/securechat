import 'dart:async';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/incoming/incoming_message_handler.dart';
import 'package:flutter_securechat/src/services/async_operation_tracker.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regresyon: signaling akisina basilan hatalar sahipli async sinirinda
/// toplanmali, root zone'a kacmamali.
///
/// Onceden `signaling.incoming.listen(...)` cagrilari `onError` vermiyordu.
/// `SignalMessage.decode` bir cerceveyi reddettiginde (bozuk zarf veya
/// 256 KiB limitini asan dosya parcasi) `WebSocketSignalingService`
/// `_controller.addError` cagiriyor; `onError` olmayinca hata islenmemis
/// sayilip root zone'a dusuyor ve orada `fatal: true` isaretli crash raporu
/// uretiyordu. Cihaz turunda 13 saniyede 18 adet olculdu.
void main() {
  late Directory directory;
  late SecureChatDatabase database;
  late LocalAeadCryptoService crypto;
  late InMemorySignalingService signaling;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('signal_error_test_');
    crypto = LocalAeadCryptoService(
      SecretKey(List.generate(32, (index) => index + 3)),
    );
    database = await SecureChatDatabase.open(
      file: File('${directory.path}/db.securejson'),
      crypto: crypto,
    );
    signaling = InMemorySignalingService();
    await signaling.connect(
      userId: 'me',
      url: 'ws://local',
      accessToken: 'token',
    );
  });

  tearDown(() async {
    await signaling.dispose();
    await database.close();
    await directory.delete(recursive: true);
  });

  IncomingMessageHandler buildHandler({
    AsyncOperationFailureHandler? onAsyncFailure,
  }) => IncomingMessageHandler(
    signaling: signaling,
    crypto: crypto,
    database: database,
    session: SessionStore(userId: 'me', accessToken: 'token'),
    onAsyncFailure: onAsyncFailure,
  )..start();

  test('akis hatasi async sinirina yonlendirilir, root zone temiz kalir',
      () async {
    final failures = <String>[];
    final handler = buildHandler(
      onAsyncFailure: (operation, error, stackTrace) async =>
          failures.add(operation),
    );
    addTearDown(handler.close);

    final escaped = <Object>[];
    await runZonedGuarded(() async {
      signaling.addIncomingError(
        const FormatException('Signal frame exceeds the 256 KiB limit'),
      );
      await pumpEventQueue();
    }, (error, stackTrace) => escaped.add(error));

    expect(
      escaped,
      isEmpty,
      reason: 'signaling akis hatasi root zone a kacmamali',
    );
    expect(failures, contains('incoming-message.signal-stream'));
  });

  test('kapatilmis handler akis hatasinda StateError atmaz', () async {
    final handler = buildHandler();
    await handler.close();

    final escaped = <Object>[];
    await runZonedGuarded(() async {
      signaling.addIncomingError(const FormatException('bozuk zarf'));
      await pumpEventQueue();
    }, (error, stackTrace) => escaped.add(error));

    expect(escaped, isEmpty);
  });
}
