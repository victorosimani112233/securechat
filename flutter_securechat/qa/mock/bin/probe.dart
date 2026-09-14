// Mock sunucuyu uygulamanın yaptığı işin aynısını yaparak doğrular:
// X3DH bundle çek -> oturum kur -> gerçek zarf gönder -> bot çözsün ->
// botun şifreli cevabını çöz. Cihaza dokunmadan önce sözleşme kanıtı.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart' as sig;

const deviceId = 1;

Future<void> main(List<String> args) async {
  final base = args.isNotEmpty ? args[0] : 'http://127.0.0.1:8080';
  final me = 'probe-client';
  final peer = 'peer-ayse';
  final http = HttpClient()..badCertificateCallback = (_, __, ___) => true;
  var failures = 0;

  void check(String name, bool ok, [String detail = '']) {
    stdout.writeln('${ok ? 'PASS' : 'FAIL'}  $name${detail.isEmpty ? '' : '  ($detail)'}');
    if (!ok) failures++;
  }

  // 1) Kendi kimliğimizi kur
  final identity = sig.generateIdentityKeyPair();
  final registrationId = sig.generateRegistrationId(false);
  final store = sig.InMemorySignalProtocolStore(identity, registrationId);

  // 2) OTP + register akışı
  final otp = await _post(http, '$base/api/v1/otp/request', {'email': 'qa@test'});
  check('otp/request 200', otp.status == 200, 'status=${otp.status}');
  final verify = await _post(http, '$base/api/v1/otp/verify', {
    'email': 'qa@test',
    'otp': '123456',
  });
  check('otp/verify verified', verify.json['verified'] == true);
  final badOtp = await _post(http, '$base/api/v1/otp/verify', {
    'email': 'qa@test',
    'otp': '000000',
  });
  check('otp/verify rejects wrong code', badOtp.status == 400);

  final reg = await _post(http, '$base/api/v1/users/register', {
    'userId': me,
    'phoneHash': 'deadbeef',
    'registrationToken': verify.json['registrationToken'],
  });
  final token = reg.json['accessToken'] as String? ?? '';
  check('register returns accessToken', token.isNotEmpty);

  // 3) Peer bundle çek ve X3DH oturumu kur
  final bundleResponse = await _get(http, '$base/api/v1/users/$peer/prekeys', token);
  check('prekey bundle 200', bundleResponse.status == 200);
  final b = bundleResponse.json;
  final oneTime = (b['oneTimePreKey'] as Map?)?.cast<String, Object?>();
  check('bundle carries one-time prekey', oneTime != null);
  final bundle = sig.PreKeyBundle(
    (b['registrationId'] as num).toInt(),
    1,
    (oneTime?['keyId'] as num?)?.toInt(),
    oneTime == null
        ? null
        : sig.Curve.decodePoint(base64Decode(oneTime['publicKey'] as String), 0),
    (b['signedPreKeyId'] as num).toInt(),
    sig.Curve.decodePoint(base64Decode(b['signedPreKey'] as String), 0),
    Uint8List.fromList(base64Decode(b['signedPreKeySignature'] as String)),
    sig.IdentityKey.fromBytes(
      Uint8List.fromList(base64Decode(b['identityPublicKey'] as String)),
      0,
    ),
  );
  final address = sig.SignalProtocolAddress(peer, deviceId);
  await sig.SessionBuilder.fromSignalStore(store, address).processPreKeyBundle(bundle);
  check('X3DH session established', await store.containsSession(address));

  // 4) WebSocket bağlan
  final ws = await WebSocket.connect(
    '${base.replaceFirst('http', 'ws')}/ws?userId=$me',
    headers: {'Authorization': 'Bearer $token'},
    customClient: HttpClient()..badCertificateCallback = (_, __, ___) => true,
  );
  final inbox = StreamController<Map<String, Object?>>.broadcast();
  ws.listen((dynamic e) {
    if (e is String) inbox.add((jsonDecode(e) as Map).cast<String, Object?>());
  });
  check('websocket connected', ws.readyState == WebSocket.open);

  // 5) Gerçek şifreli mesaj gönder
  const plaintext = 'MSGID:probe-1:merhaba dünya';
  final cipher = sig.SessionCipher.fromStore(store, address);
  final message = await cipher.encrypt(Uint8List.fromList(utf8.encode(plaintext)));
  final type = message.getType() == sig.CiphertextMessage.prekeyType ? 'PREKEY' : 'SIGNAL';
  final envelope = 'E2EE:v1:$type:$registrationId:${base64Encode(message.serialize())}';
  check('outbound envelope is PREKEY on first send', type == 'PREKEY');

  ws.add(jsonEncode({
    'type': 'encrypted_message',
    'senderId': me,
    'recipientId': peer,
    'timestamp': DateTime.now().millisecondsSinceEpoch,
    'envelope': envelope,
  }));

  // 6) Teslim makbuzu + botun şifreli cevabı
  final receipts = <String>[];
  String? echoPlaintext;
  final done = Completer<void>();
  final sub = inbox.stream.listen((frame) async {
    switch (frame['type']) {
      case 'delivery_receipt':
        receipts.add('${frame['status']}');
      case 'encrypted_message':
        final parts = '${frame['envelope']}'.split(':');
        final bytes = Uint8List.fromList(base64Decode(parts[4]));
        final c = sig.SessionCipher.fromStore(store, address);
        final clear = parts[2] == 'PREKEY'
            ? await c.decrypt(sig.PreKeySignalMessage(bytes))
            : await c.decryptFromSignal(sig.SignalMessage.fromSerialized(bytes));
        echoPlaintext = utf8.decode(clear);
        if (!done.isCompleted) done.complete();
    }
  });
  await done.future.timeout(const Duration(seconds: 10), onTimeout: () {});
  await Future<void>.delayed(const Duration(milliseconds: 300));
  await sub.cancel();

  check('bot decrypted and replied', echoPlaintext != null, '${echoPlaintext}');
  check('reply carries echoed content',
      echoPlaintext?.contains('merhaba dünya') ?? false);
  check('DELIVERED receipt received', receipts.contains('DELIVERED'), '$receipts');
  check('READ receipt received', receipts.contains('READ'), '$receipts');

  // 7) Offline kuyruk: bağlantıyı kapat, peer mesaj yollasın, tekrar bağlan
  await ws.close();
  await Future<void>.delayed(const Duration(milliseconds: 300));
  final queued = await _post(http, '$base/__qa/peer-send', {
    'from': peer,
    'to': me,
    'text': 'offline mesaji',
  });
  check('peer-send accepted while offline', queued.status == 200);
  final state = await _get(http, '$base/__qa/state', token);
  final depth = (state.json['offlineQueued'] as Map)[me];
  check('message parked in offline queue', depth == 1, 'depth=$depth');

  final ws2 = await WebSocket.connect(
    '${base.replaceFirst('http', 'ws')}/ws?userId=$me',
    headers: {'Authorization': 'Bearer $token'},
    customClient: HttpClient()..badCertificateCallback = (_, __, ___) => true,
  );
  final flushed = Completer<Map<String, Object?>>();
  ws2.listen((dynamic e) {
    if (e is String && !flushed.isCompleted) {
      flushed.complete((jsonDecode(e) as Map).cast<String, Object?>());
    }
  });
  final replayed = await flushed.future
      .timeout(const Duration(seconds: 5), onTimeout: () => const {});
  check('offline queue flushed on reconnect',
      replayed['type'] == 'encrypted_message', '${replayed['type']}');
  await ws2.close();

  // 8) Auth reddi 1008 ile kapanmalı
  await _post(http, '$base/__qa/config', {'rejectAuth': true});
  var closeCode = -1;
  try {
    final bad = await WebSocket.connect(
      '${base.replaceFirst('http', 'ws')}/ws?userId=$me',
      headers: {'Authorization': 'Bearer $token'},
      customClient: HttpClient()..badCertificateCallback = (_, __, ___) => true,
    );
    await bad.listen((_) {}).asFuture<void>().timeout(
        const Duration(seconds: 3), onTimeout: () {});
    closeCode = bad.closeCode ?? -1;
  } catch (_) {}
  check('auth rejection closes with 1008', closeCode == 1008, 'code=$closeCode');
  await _post(http, '$base/__qa/config', {'rejectAuth': false});

  http.close(force: true);
  stdout.writeln('\n${failures == 0 ? 'ALL PROBES PASSED' : '$failures PROBE(S) FAILED'}');
  exit(failures == 0 ? 0 : 1);
}

class _Res {
  _Res(this.status, this.json);
  final int status;
  final Map<String, Object?> json;
}

Future<_Res> _post(HttpClient c, String url, Map<String, Object?> body) async {
  final req = await c.postUrl(Uri.parse(url));
  req.headers.contentType = ContentType.json;
  req.write(jsonEncode(body));
  final res = await req.close();
  final raw = await utf8.decoder.bind(res).join();
  return _Res(res.statusCode,
      raw.isEmpty ? {} : (jsonDecode(raw) as Map).cast<String, Object?>());
}

Future<_Res> _get(HttpClient c, String url, String token) async {
  final req = await c.getUrl(Uri.parse(url));
  req.headers.set('Authorization', 'Bearer $token');
  final res = await req.close();
  final raw = await utf8.decoder.bind(res).join();
  return _Res(res.statusCode,
      raw.isEmpty ? {} : (jsonDecode(raw) as Map).cast<String, Object?>());
}
