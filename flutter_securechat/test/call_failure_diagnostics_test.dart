import 'dart:async';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/media/call_manager.dart';
import 'package:flutter_securechat/src/media/call_models.dart';
import 'package:flutter_securechat/src/media/ice_server_fetcher.dart';
import 'package:flutter_securechat/src/media/media_engine.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Regresyon: cagri kurulumu basarisiz oldugunda hata teshis sinirina
/// ulasmali.
///
/// `call_manager.dart` icinde sekiz blok `catch (_)` ile yakalayip cagriyi
/// `CallState.failed` durumuna geciriyordu. Kullaniciya dogru davranis, ama
/// HATANIN KENDISI kayboluyordu: sahadan "arama basarisiz" raporu geldiginde
/// nedeni bulunacak hicbir iz yoktu.
void main() {
  test('cagri baslatma hatasi teshis sinirina bildirilir', () async {
    final directory = await Directory.systemTemp.createTemp('call_diag_');
    addTearDown(() => directory.delete(recursive: true));
    final database = await SecureChatDatabase.open(
      file: File('${directory.path}/db.securejson'),
      crypto: LocalAeadCryptoService(SecretKey(List.filled(32, 5))),
    );
    addTearDown(database.close);
    final signaling = InMemorySignalingService();
    await signaling.connect(
      userId: 'me',
      url: 'ws://local',
      accessToken: 'token',
    );

    final failures = <String>[];
    final manager = CallManager(
      session: SessionStore(userId: 'me', accessToken: 'token'),
      signaling: signaling,
      media: _ExplodingMediaEngine(),
      iceServers: const StaticIceServerProvider([
        IceServerConfig(urls: ['stun:test.invalid']),
      ]),
      callLogs: database.callLogs,
      onAsyncFailure: (operation, _, _) => failures.add(operation),
    );
    addTearDown(manager.dispose);

    expect(
      await manager.initiateCall(
        peerId: 'peer',
        peerName: 'Peer',
        callType: CallType.voice,
      ),
      isFalse,
      reason: 'kurulum basarisiz olmali',
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(failures, [
      'call-manager.initiate-call.media-offer',
    ], reason: 'hata sessizce yutulmus: $failures');
  });
}

class _ExplodingMediaEngine implements MediaEngine {
  final _states = StreamController<MediaConnectionState>.broadcast();
  final _local = RTCVideoRenderer();
  final _remote = RTCVideoRenderer();

  @override
  Stream<MediaConnectionState> get connectionStates => _states.stream;
  @override
  RTCVideoRenderer get localRenderer => _local;
  @override
  RTCVideoRenderer get remoteRenderer => _remote;

  /// Kurulum cagrilari patlar, temizlik cagrilari patlamaz: aksi halde
  /// `dispose` da hata firlatip testi asil olcmek istedigimiz seyden
  /// uzaklastiriyordu.
  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName.toString();
    if (name.contains('dispose') ||
        name.contains('close') ||
        name.contains('stop') ||
        name.contains('release')) {
      return Future<void>.value();
    }
    throw StateError('media engine unavailable');
  }
}
