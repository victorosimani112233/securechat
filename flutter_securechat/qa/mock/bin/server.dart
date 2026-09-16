// SecureChat QA mock server.
//
// Çok istemcili tasarım: bağlanan her cihaz kendi userId'si ile kayıt olur ve
// mesaj/çağrı signaling'i istemciler arasında gerçekten yönlendirilir. İkinci
// fiziksel cihaz eklendiğinde sunucu tarafında değişiklik gerekmez.
//
// Sanal peer (bot) istemciler gerçek libsignal_protocol_dart kimlikleri taşır;
// uygulamanın gönderdiği X3DH/Double Ratchet zarflarını GERÇEKTEN çözer ve
// gerçek şifreli yanıt üretir. Böylece E2EE yolu uçtan uca doğrulanabilir.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart' as sig;

import 'directory.dart';

const int kDeviceId = 1;
const String kEnvelopePrefix = 'E2EE:v1:';
const String kGroupRoutePrefix = 'GROUPROUTE:v3:';

late final EventLog log;

// ---------------------------------------------------------------------------
// Event log — her senaryo için makine-okunur kanıt üretir.
// ---------------------------------------------------------------------------

class EventLog {
  EventLog(this._file);

  final File _file;
  final List<Map<String, Object?>> memory = [];

  void add(String kind, Map<String, Object?> data) {
    final entry = <String, Object?>{
      'ts': DateTime.now().toIso8601String(),
      'kind': kind,
      ...data,
    };
    memory.add(entry);
    _file.writeAsStringSync('${jsonEncode(entry)}\n', mode: FileMode.append);
    final summary = data.entries
        .where((e) => e.key != 'body')
        .map((e) => '${e.key}=${_short(e.value)}')
        .join(' ');
    stdout.writeln('[${entry['ts']}] $kind $summary');
  }

  static String _short(Object? value) {
    final text = value is String ? value : jsonEncode(value);
    return text.length <= 120 ? text : '${text.substring(0, 117)}...';
  }
}

// ---------------------------------------------------------------------------
// Signal kimlikleri
// ---------------------------------------------------------------------------

/// Sunucunun bir kullanıcı için yayınladığı prekey materyali.
class PublishedKeys {
  PublishedKeys({
    required this.identityPublicKey,
    required this.registrationId,
    required this.signedPreKeyId,
    required this.signedPreKey,
    required this.signedPreKeySignature,
    required this.oneTimePreKeys,
  });

  final Uint8List identityPublicKey;
  final int registrationId;
  final int signedPreKeyId;
  final Uint8List signedPreKey;
  final Uint8List signedPreKeySignature;
  final List<Map<String, Object?>> oneTimePreKeys;

  Map<String, Object?> bundleJson() {
    // Uygulama tek bir oneTimePreKey bekler; havuzdan birini tüketir.
    final oneTime = oneTimePreKeys.isEmpty ? null : oneTimePreKeys.removeAt(0);
    return {
      'identityPublicKey': base64Encode(identityPublicKey),
      'registrationId': registrationId,
      'signedPreKeyId': signedPreKeyId,
      'signedPreKey': base64Encode(signedPreKey),
      'signedPreKeySignature': base64Encode(signedPreKeySignature),
      if (oneTime != null) 'oneTimePreKey': oneTime,
    };
  }
}

/// Gerçek Signal Protocol durumu taşıyan sanal karşı taraf.
class VirtualPeer {
  VirtualPeer(this.userId, this.displayName, {this.stateFile});

  final String userId;
  final String displayName;

  /// Bot kimligi ve ratchet oturumlari diske yazilir; sunucu yeniden
  /// baslatildiginda cihazdaki oturum bozulmaz.
  final File? stateFile;

  late final sig.InMemorySignalProtocolStore store;
  late final PublishedKeys published;
  final Set<String> knownGroups = {};
  int _messageCounter = 0;

  /// Double Ratchet durumu paylasilan mutable state; ayni peer icin gelen
  /// cerceveler sirayla islenmeli yoksa sayac yarisi olusur.
  Future<void> _queue = Future<void>.value();

  Future<T> serialized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  /// Bot davranış anahtarları — senaryo başına testten değiştirilebilir.
  bool echoMessages = false;
  bool autoAnswerCalls = true;
  bool sendReceipts = true;
  Duration replyDelay = const Duration(milliseconds: 400);

  Future<void> initialise() async {
    final saved = _readState();
    final sig.IdentityKeyPair identity;
    final int registrationId;
    if (saved != null) {
      identity = sig.IdentityKeyPair.fromSerialized(
        Uint8List.fromList(base64Decode(saved['identity'] as String)),
      );
      registrationId = (saved['registrationId'] as num).toInt();
    } else {
      identity = sig.generateIdentityKeyPair();
      registrationId = sig.generateRegistrationId(false);
    }
    store = sig.InMemorySignalProtocolStore(identity, registrationId);

    final preKeys = saved != null
        ? [
            for (final encoded in (saved['preKeys'] as List))
              sig.PreKeyRecord.fromBuffer(
                Uint8List.fromList(base64Decode('$encoded')),
              ),
          ]
        : sig.generatePreKeys(1, 40);
    for (final key in preKeys) {
      await store.storePreKey(key.id, key);
    }
    final signed = saved != null
        ? sig.SignedPreKeyRecord.fromSerialized(
            Uint8List.fromList(base64Decode(saved['signedPreKey'] as String)),
          )
        : sig.generateSignedPreKey(identity, 1);
    await store.storeSignedPreKey(signed.id, signed);

    if (saved != null) {
      final sessions = (saved['sessions'] as Map).cast<String, Object?>();
      sessions.forEach((address, encoded) {
        final parts = address.split('|');
        store.sessionStore.sessions[sig.SignalProtocolAddress(
          parts.first,
          int.parse(parts.last),
        )] = Uint8List.fromList(base64Decode('$encoded'));
      });
      final consumed = (saved['consumedOneTime'] as List?) ?? const [];
      _consumedOneTime.addAll(consumed.map((e) => (e as num).toInt()));
    }

    published = PublishedKeys(
      identityPublicKey: identity.getPublicKey().serialize(),
      registrationId: registrationId,
      signedPreKeyId: signed.id,
      signedPreKey: signed.getKeyPair().publicKey.serialize(),
      signedPreKeySignature: signed.signature,
      oneTimePreKeys: preKeys
          .where((key) => !_consumedOneTime.contains(key.id))
          .map(
            (key) => <String, Object?>{
              'keyId': key.id,
              'publicKey': base64Encode(key.getKeyPair().publicKey.serialize()),
            },
          )
          .toList(),
    );
    _allPreKeys = preKeys;
    _signedPreKey = signed;
    _identity = identity;
    _registrationId = registrationId;
    persist();
  }

  final Set<int> _consumedOneTime = {};
  late List<sig.PreKeyRecord> _allPreKeys;
  late sig.SignedPreKeyRecord _signedPreKey;
  late sig.IdentityKeyPair _identity;
  late int _registrationId;

  void markOneTimeConsumed(int keyId) {
    _consumedOneTime.add(keyId);
    persist();
  }

  Map<String, Object?>? _readState() {
    final file = stateFile;
    if (file == null || !file.existsSync()) return null;
    try {
      return (jsonDecode(file.readAsStringSync()) as Map)
          .cast<String, Object?>();
    } catch (_) {
      return null;
    }
  }

  void persist() {
    final file = stateFile;
    if (file == null) return;
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      jsonEncode({
        'userId': userId,
        'identity': base64Encode(_identity.serialize()),
        'registrationId': _registrationId,
        'preKeys': _allPreKeys.map((k) => base64Encode(k.serialize())).toList(),
        'signedPreKey': base64Encode(_signedPreKey.serialize()),
        'consumedOneTime': _consumedOneTime.toList(),
        'sessions': {
          for (final entry in store.sessionStore.sessions.entries)
            '${entry.key.getName()}|${entry.key.getDeviceId()}':
                base64Encode(entry.value),
        },
      }),
    );
  }

  /// Sunucu yeniden baslatildiginda sayac sifirlandigi icin ayni messageId
  /// tekrar uretiliyordu; istemci bunlari (dogru sekilde) dedup edip sessizce
  /// atiyordu. Benzersiz bir onek eklenir.
  final String _idSalt = DateTime.now().microsecondsSinceEpoch
      .toRadixString(36);

  String nextMessageId() =>
      '$userId-bot-$_idSalt-${++_messageCounter}';

  /// Gönderenden gelen zarfı çözer. Oturum yoksa PREKEY zarfı oturumu kurar.
  Future<String> decrypt({
    required String senderId,
    required String envelope,
  }) async {
    final parts = envelope.split(':');
    if (parts.length != 5 || parts[0] != 'E2EE' || parts[1] != 'v1') {
      throw FormatException('Unsupported envelope: $envelope');
    }
    final bytes = Uint8List.fromList(base64Decode(parts[4]));
    final cipher = sig.SessionCipher.fromStore(
      store,
      sig.SignalProtocolAddress(senderId, kDeviceId),
    );
    final plaintext = switch (parts[2]) {
      'PREKEY' => await cipher.decrypt(sig.PreKeySignalMessage(bytes)),
      'SIGNAL' => await cipher.decryptFromSignal(
        sig.SignalMessage.fromSerialized(bytes),
      ),
      _ => throw FormatException('Unknown envelope type ${parts[2]}'),
    };
    persist();
    return utf8.decode(plaintext);
  }

  Future<String> encrypt({
    required String recipientId,
    required String plaintext,
  }) async {
    final address = sig.SignalProtocolAddress(recipientId, kDeviceId);
    final message = await sig.SessionCipher.fromStore(
      store,
      address,
    ).encrypt(Uint8List.fromList(utf8.encode(plaintext)));
    final type = message.getType() == sig.CiphertextMessage.prekeyType
        ? 'PREKEY'
        : 'SIGNAL';
    final registrationId = await store.getLocalRegistrationId();
    persist();
    return 'E2EE:v1:$type:$registrationId:${base64Encode(message.serialize())}';
  }

  Future<bool> hasSession(String peerId) =>
      store.containsSession(sig.SignalProtocolAddress(peerId, kDeviceId));
}

// ---------------------------------------------------------------------------
// Bağlı istemci
// ---------------------------------------------------------------------------

class Client {
  Client(this.userId, this.socket, this.remote);

  final String userId;
  final WebSocket socket;
  final String remote;
  int framesIn = 0;
  int framesOut = 0;

  void send(Map<String, Object?> frame) {
    final raw = jsonEncode(frame);
    if (utf8.encode(raw).length > 256 * 1024) {
      log.add('drop_oversize', {'to': userId, 'type': frame['type']});
      return;
    }
    socket.add(raw);
    framesOut++;
    log.add('ws_out', {'to': userId, 'type': frame['type'], 'bytes': raw.length});
  }
}

// ---------------------------------------------------------------------------
// Sunucu
// ---------------------------------------------------------------------------

class MockServer {
  MockServer({
    required this.port,
    required this.peers,
    this.certificatePath,
    this.privateKeyPath,
    this.directory,
  });

  final int port;
  final Map<String, VirtualPeer> peers;
  final String? certificatePath;
  final String? privateKeyPath;
  final DirectoryModule? directory;
  String? _statePath;
  set statePath(String? value) => _statePath = value;

  final Map<String, Client> clients = {};
  final Map<String, List<Map<String, Object?>>> offlineQueue = {};
  final Map<String, PublishedKeys> realUserKeys = {};
  final Map<String, String> fcmTokens = {};
  final Set<String> registeredUsers = {};

  /// Test kancaları — HTTP kontrol yüzeyi üzerinden değiştirilir.
  bool rejectAuth = false;
  bool dropWrites = false;
  int otpFailures = 0;

  Future<void> start() async {
    final HttpServer server;
    final certificate = certificatePath;
    final privateKey = privateKeyPath;
    if (certificate != null && privateKey != null) {
      final context = SecurityContext()
        ..useCertificateChain(certificate)
        ..usePrivateKey(privateKey);
      // Cihaz uygulaması pin doğrulamasını kendi yaptığı için sistem trust
      // store'una eklenmemiş kısa ömürlü sertifika yeterlidir.
      //
      // Dinlenen adres `anyIPv4` olmak ZORUNDA: fiziksel bir telefon
      // geliştirme makinesine ancak LAN adresinden ulaşabilir. Burası
      // `loopbackIPv4` olduğu sürece sunucu ayakta görünüyor, aynı makineden
      // yapılan `curl` çalışıyor, ama telefon hiç bağlanamıyor — belirti
      // "bağlantı kurulamadı" olduğu için ağ ya da sertifika sorunu
      // sanılıyor. Düz HTTP dalı zaten `anyIPv4` kullanıyordu; ikisi
      // ayrışmış durumdaydı.
      //
      // Bu sunucu yalnız QA içindir: sahte veri taşır, gerçek posta
      // göndermez, OTP kodu sabittir. LAN'a açılması bilinçli.
      server = await HttpServer.bindSecure(
        InternetAddress.anyIPv4,
        port,
        context,
        shared: false,
      );
    } else {
      server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    }
    log.add('server_start', {
      'port': port,
      'tls': certificate != null,
      'peers': peers.keys.toList(),
    });
    await for (final request in server) {
      unawaited(_handle(request));
    }
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      final path = request.uri.path;
      if (path == '/ws' || path.endsWith('/ws')) {
        await _handleWebSocket(request);
        return;
      }
      await _handleRest(request, path);
    } catch (error, stack) {
      log.add('handler_error', {'error': '$error', 'stack': '$stack'});
      try {
        request.response.statusCode = 500;
        await request.response.close();
      } catch (_) {}
    }
  }

  // -------------------------------------------------------------------------
  // REST
  // -------------------------------------------------------------------------

  Future<void> _handleRest(HttpRequest request, String path) async {
    final body = await utf8.decoder.bind(request).join();
    Map<String, Object?> json = const {};
    if (body.isNotEmpty) {
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map) json = decoded.cast<String, Object?>();
      } catch (_) {}
    }
    log.add('http_in', {
      'method': request.method,
      'path': path,
      'bytes': body.length,
    });

    // /api/v1/users/{id}/prekeys — X3DH bundle dağıtımı
    final preKeyMatch = RegExp(
      r'^/api/v1/users/([^/]+)/prekeys$',
    ).firstMatch(path);
    if (preKeyMatch != null && request.method == 'GET') {
      final target = Uri.decodeComponent(preKeyMatch.group(1)!);
      final peer = peers[target];
      final keys = peer?.published ?? realUserKeys[target];
      if (keys == null) {
        log.add('prekey_miss', {'user': target});
        return _json(request, 404, {'error': 'unknown user'});
      }
      log.add('prekey_served', {'user': target});
      return _json(request, 200, keys.bundleJson());
    }

    switch (path) {
      case '/api/v1/otp/request':
        if (otpFailures > 0) {
          otpFailures--;
          return _json(request, 429, {'retryAfter': 3});
        }
        log.add('otp_request', {'email': json['email']});
        return _json(request, 200, {'sent': true});

      case '/api/v1/otp/verify':
        final otp = '${json['otp']}';
        if (otp != '123456') {
          return _json(request, 400, {'error': 'Dogrulama kodu gecersiz'});
        }
        return _json(request, 200, {
          'verified': true,
          'registrationToken': 'mock-registration-token',
        });

      case '/api/v1/users/register':
        final userId = '${json['userId']}';
        final isNew = registeredUsers.add(userId);
        log.add('register', {'userId': userId, 'isNew': isNew});
        return _json(request, 200, {
          'userId': userId,
          'isNew': isNew,
          'accessToken': _token(userId, 'access'),
          'refreshToken': _token(userId, 'refresh'),
        });

      case '/api/v1/auth/refresh':
        if (rejectAuth) return _json(request, 401, {'error': 'rejected'});
        log.add('token_refresh', {});
        return _json(request, 200, {
          'accessToken': _token('refreshed', 'access'),
          'refreshToken': _token('refreshed', 'refresh'),
        });

      case '/api/v1/auth/logout':
        log.add('logout', {});
        return _json(request, 200, {'ok': true});

      case '/api/v1/account/delete':
        log.add('account_delete', {});
        return _json(request, 200, {'ok': true});

      case '/api/v1/prekeys/upload':
        _storeUploadedKeys(json);
        log.add('prekeys_upload', {
          'registrationId': json['registrationId'],
          'oneTimeCount': (json['oneTimePreKeys'] as List?)?.length ?? 0,
        });
        return _json(request, 200, {'ok': true});

      case '/api/v1/prekeys/refresh':
        log.add('prekeys_refresh', {'bytes': body.length});
        return _json(request, 200, {'ok': true});

      case '/api/v1/fcm/register':
        fcmTokens['${json['userId']}'] = '${json['fcmToken']}';
        log.add('fcm_register', {'userId': json['userId']});
        return _json(request, 200, {'ok': true});

      case '/api/v1/fcm/unregister':
        fcmTokens.remove('${json['userId']}');
        log.add('fcm_unregister', {'userId': json['userId']});
        return _json(request, 200, {'ok': true});

      // ---- Private contact discovery (blind-RSA OPRF) ----
      case '/api/v1/directory/config':
        final module = directory;
        if (module == null) {
          return _json(request, 501, {'error': 'directory disabled'});
        }
        log.add('directory_config', {'keyId': module.keyId});
        return _json(request, 200, module.configJson());

      case '/api/v1/directory/evaluate':
        final module = directory;
        if (module == null) {
          return _json(request, 501, {'error': 'directory disabled'});
        }
        final result = module.evaluate(json);
        final status = (result.remove('__status') as int?) ?? 200;
        log.add('directory_evaluate', {
          'status': status,
          'batch': (json['blinded'] as List?)?.length ?? 0,
        });
        return _json(request, status, result);

      case '/api/v1/directory/snapshot':
        final module = directory;
        if (module == null) {
          return _json(request, 501, {'error': 'directory disabled'});
        }
        final snapshot = await module.snapshot();
        log.add('directory_snapshot', {
          'entries': (snapshot['entries'] as List).length,
        });
        return _json(request, 200, snapshot);

      case '/api/v1/users/directory-token':
        final module = directory;
        if (module == null) {
          return _json(request, 501, {'error': 'directory disabled'});
        }
        final phoneHash = '${json['phoneHash']}';
        // Kaydi gercekten dizine yaz: istemci kendi kaydini snapshot'ta
        // goremezse dogrulamayi basarisiz sayiyor.
        final owner = clients.keys.firstWhere(
          (id) => !peers.containsKey(id),
          orElse: () => '',
        );
        if (owner.isNotEmpty) {
          module.users[phoneHash] = DirectoryUser(
            userId: owner,
            phoneHash: phoneHash,
          );
        }
        log.add('directory_enroll', {
          'phoneHashPrefix':
              phoneHash.length >= 8 ? phoneHash.substring(0, 8) : phoneHash,
          'boundTo': owner.isEmpty ? null : owner,
          'directorySize': module.users.length,
        });
        return _json(request, 200, {'keyId': module.keyId});

      case '/__qa/directory-add':
        final module = directory;
        if (module == null) {
          return _json(request, 501, {'error': 'directory disabled'});
        }
        module.users['${json['phoneHash']}'] = DirectoryUser(
          userId: '${json['userId']}',
          phoneHash: '${json['phoneHash']}',
        );
        log.add('directory_add', {'userId': json['userId']});
        return _json(request, 200, {'ok': true, 'users': module.users.length});

      case '/api/v1/ice/config':
        return _json(request, 200, {
          'iceServers': [
            {
              'urls': ['stun:127.0.0.1:3478'],
            },
          ],
        });

      // ---- QA kontrol yüzeyi (uygulama kullanmaz) ----
      case '/__qa/state':
        return _json(request, 200, {
          'clients': clients.keys.toList(),
          'peers': peers.keys.toList(),
          'offlineQueued': offlineQueue.map((k, v) => MapEntry(k, v.length)),
          'registeredUsers': registeredUsers.toList(),
          'fcmTokens': fcmTokens.keys.toList(),
          'events': log.memory.length,
        });

      case '/__qa/events':
        final since = int.tryParse(request.uri.queryParameters['since'] ?? '0');
        return _json(request, 200, {
          'total': log.memory.length,
          'events': log.memory.skip(since ?? 0).toList(),
        });

      case '/__qa/config':
        rejectAuth = json['rejectAuth'] as bool? ?? rejectAuth;
        dropWrites = json['dropWrites'] as bool? ?? dropWrites;
        otpFailures = (json['otpFailures'] as num?)?.toInt() ?? otpFailures;
        for (final peer in peers.values) {
          peer.echoMessages = json['echoMessages'] as bool? ?? peer.echoMessages;
          peer.autoAnswerCalls =
              json['autoAnswerCalls'] as bool? ?? peer.autoAnswerCalls;
          peer.sendReceipts = json['sendReceipts'] as bool? ?? peer.sendReceipts;
        }
        return _json(request, 200, {'ok': true});

      case '/__qa/inject':
        // Testin herhangi bir sinyali cihaza itmesine izin verir.
        final target = '${json['to']}';
        final frame = (json['frame'] as Map).cast<String, Object?>();
        final client = clients[target];
        if (client == null) return _json(request, 404, {'error': 'offline'});
        client.send(frame);
        return _json(request, 200, {'ok': true});

      case '/__qa/peer-create':
        // Calisma zamaninda yeni sanal peer: temiz X3DH senaryolari icin.
        final id = '${json['userId']}';
        if (id.isEmpty || id == 'null') {
          return _json(request, 400, {'error': 'userId required'});
        }
        if (!peers.containsKey(id)) {
          final created = VirtualPeer(
            id,
            '${json['displayName'] ?? id}',
            stateFile: File('${_statePath ?? 'qa/mock/state'}/$id.json'),
          );
          await created.initialise();
          peers[id] = created;
          log.add('peer_created', {
            'userId': id,
            'registrationId': created.published.registrationId,
          });
        }
        return _json(request, 200, {'ok': true, 'peers': peers.keys.toList()});

      case '/__qa/peer-send':
        // Sanal peer'in istenen anda gerçek şifreli mesaj göndermesi.
        final from = '${json['from']}';
        final to = '${json['to']}';
        final text = '${json['text']}';
        final peer = peers[from];
        if (peer == null) return _json(request, 404, {'error': 'no peer'});
        final ok = await _peerSendText(
          peer,
          to,
          text,
          viewOnce: json['viewOnce'] == true,
          expiresInMs: (json['expiresInMs'] as num?)?.toInt(),
        );
        return _json(request, ok ? 200 : 409, {'ok': ok});
    }

    log.add('http_404', {'path': path});
    return _json(request, 404, {'error': 'not found'});
  }

  void _storeUploadedKeys(Map<String, Object?> json) {
    try {
      final identity = json['identityPublicKey'] as String?;
      if (identity == null) return;
      realUserKeys['__last_upload'] = PublishedKeys(
        identityPublicKey: Uint8List.fromList(base64Decode(identity)),
        registrationId: (json['registrationId'] as num).toInt(),
        signedPreKeyId: (json['signedPreKeyId'] as num).toInt(),
        signedPreKey: Uint8List.fromList(
          base64Decode(json['signedPreKey'] as String),
        ),
        signedPreKeySignature: Uint8List.fromList(
          base64Decode(json['signedPreKeySignature'] as String),
        ),
        oneTimePreKeys: ((json['oneTimePreKeys'] as List?) ?? const [])
            .map((e) => (e as Map).cast<String, Object?>())
            .toList(),
      );
    } catch (error) {
      log.add('prekey_upload_parse_error', {'error': '$error'});
    }
  }

  Future<void> _json(
    HttpRequest request,
    int status,
    Map<String, Object?> body,
  ) async {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await request.response.close();
  }

  String _token(String subject, String kind) {
    final header = base64Url.encode(
      utf8.encode(jsonEncode({'alg': 'none', 'typ': 'JWT'})),
    );
    final payload = base64Url.encode(
      utf8.encode(
        jsonEncode({
          'sub': subject,
          'kind': kind,
          // Cihaz saati geride olduğu için uzun geçerlilik veriyoruz.
          'exp': DateTime.now()
                  .add(const Duration(days: 3650))
                  .millisecondsSinceEpoch ~/
              1000,
        }),
      ),
    );
    return '$header.$payload.mock';
  }

  // -------------------------------------------------------------------------
  // WebSocket
  // -------------------------------------------------------------------------

  Future<void> _handleWebSocket(HttpRequest request) async {
    final userId = request.uri.queryParameters['userId'];
    final auth = request.headers.value(HttpHeaders.authorizationHeader);
    if (userId == null || userId.isEmpty) {
      request.response.statusCode = 400;
      await request.response.close();
      return;
    }
    if (rejectAuth || auth == null || !auth.startsWith('Bearer ')) {
      log.add('ws_auth_reject', {'userId': userId, 'hasAuth': auth != null});
      // 1008 policy violation → istemci token yenilemeyi denemeli.
      final socket = await WebSocketTransformer.upgrade(request);
      await socket.close(1008, 'policy');
      return;
    }

    final socket = await WebSocketTransformer.upgrade(request);
    socket.pingInterval = const Duration(seconds: 20);
    final remote = '${request.connectionInfo?.remoteAddress.address}';
    final client = Client(userId, socket, remote);
    clients[userId] = client;
    log.add('ws_connect', {'userId': userId, 'remote': remote});

    // Çevrimdışıyken biriken mesajları teslim et.
    final queued = offlineQueue.remove(userId) ?? const [];
    if (queued.isNotEmpty) {
      log.add('offline_flush', {'userId': userId, 'count': queued.length});
      for (final frame in queued) {
        client.send(frame);
      }
    }

    socket.listen(
      (dynamic event) {
        if (event is! String) return;
        client.framesIn++;
        unawaited(_onFrame(client, event));
      },
      onError: (Object error) =>
          log.add('ws_error', {'userId': userId, 'error': '$error'}),
      onDone: () {
        if (identical(clients[userId], client)) clients.remove(userId);
        log.add('ws_disconnect', {
          'userId': userId,
          'code': socket.closeCode,
          'framesIn': client.framesIn,
          'framesOut': client.framesOut,
        });
      },
    );
  }

  Future<void> _onFrame(Client from, String raw) async {
    Map<String, Object?> frame;
    try {
      frame = (jsonDecode(raw) as Map).cast<String, Object?>();
    } catch (error) {
      log.add('ws_bad_frame', {'userId': from.userId, 'error': '$error'});
      return;
    }
    final type = '${frame['type']}';
    final to = '${frame['recipientId']}';
    log.add('ws_in', {
      'from': from.userId,
      'to': to,
      'type': type,
      'bytes': raw.length,
      'body': frame,
    });

    if (dropWrites) {
      log.add('drop_write', {'type': type});
      return;
    }

    // Grup fanout: her alıcıya kendi payload'u ile ayrı encrypted_message.
    if (type == 'group_message_fanout') {
      final payloads = (frame['recipientPayloads'] as Map?)
          ?.cast<String, Object?>();
      payloads?.forEach((recipient, payload) {
        _deliver(recipient, {
          'type': 'encrypted_message',
          'senderId': from.userId,
          'recipientId': recipient,
          'timestamp': frame['timestamp'],
          'envelope': '$payload',
        });
      });
      return;
    }

    // Peer kuyruguna SENKRON gir: araya 'await' girerse cerceveler WebSocket
    // sirasindan farkli sirayla kuyruga dusuyor ve ratchet sayaci bozuluyor.
    final peer = peers[to];
    if (peer != null) {
      unawaited(peer.serialized(() => _peerReact(peer, from.userId, type, frame)));
      return;
    }
    await _deliver(to, frame);
  }

  Future<void> _deliver(String to, Map<String, Object?> frame) async {
    // 'server' sunucuya yönelik kontrol trafiğidir; kuyruğa girmez.
    if (to == 'server' || to.isEmpty) {
      log.add('server_directed', {'type': frame['type']});
      return;
    }
    if (peers.containsKey(to)) return; // bot; ayrıca işlenir
    final client = clients[to];
    if (client != null) {
      client.send(frame);
      return;
    }
    offlineQueue.putIfAbsent(to, () => []).add(frame);
    log.add('offline_queue', {
      'to': to,
      'type': frame['type'],
      'depth': offlineQueue[to]!.length,
    });
  }

  // -------------------------------------------------------------------------
  // Sanal peer davranışı
  // -------------------------------------------------------------------------

  Future<void> _peerReact(
    VirtualPeer peer,
    String from,
    String type,
    Map<String, Object?> frame,
  ) async {
    try {
      switch (type) {
        case 'encrypted_message':
          await _peerOnEncrypted(peer, from, frame);
        case 'call_control':
          await _peerOnCallControl(peer, from, frame);
        case 'sdp_offer':
          await _peerOnOffer(peer, from, frame);
        case 'ice_candidate':
          log.add('peer_ice_seen', {'peer': peer.userId, 'from': from});
        case 'typing_indicator':
          break;
        case 'presence_subscribe':
          _peerSend(peer, from, {
            'type': 'presence_update',
            'isOnline': true,
            'lastSeen': DateTime.now().millisecondsSinceEpoch,
            'hideLastSeen': false,
          });
        case 'group_notification':
          peer.knownGroups.add('${frame['groupId']}');
          log.add('peer_group_seen', {
            'peer': peer.userId,
            'groupId': frame['groupId'],
            'action': frame['action'],
          });
        case 'file_transfer':
          _onFileTransfer(peer, from, frame);
        case 'group_call_status_query':
          _peerSend(peer, from, {
            'type': 'group_call_status_response',
            'groupId': frame['groupId'],
            'isActive': false,
            'participants': <String>[],
          });
      }
    } catch (error, stack) {
      log.add('peer_error', {
        'peer': peer.userId,
        'type': type,
        'error': '$error',
        'stack': '$stack',
      });
    }
  }

  /// Dosya parcalarini toplayip butunlugu dogrular. Icerik cozulmez;
  /// yalniz parca sayimi, boyut ve metadata sizintisi denetlenir.
  final Map<String, Map<String, Object?>> _transfers = {};

  void _onFileTransfer(
    VirtualPeer peer,
    String from,
    Map<String, Object?> frame,
  ) {
    final id = '${frame['transferId'] ?? 'no-id'}';
    final total = (frame['totalChunks'] as num?)?.toInt() ?? 0;
    final index = (frame['chunkIndex'] as num?)?.toInt() ?? 0;
    final state = _transfers.putIfAbsent(
      id,
      () => {'received': <int>{}, 'bytes': 0, 'total': total},
    );
    (state['received'] as Set<int>).add(index);
    state['bytes'] = (state['bytes'] as int) +
        '${frame['data'] ?? ''}'.length;
    final got = (state['received'] as Set<int>).length;
    log.add('file_chunk', {
      'peer': peer.userId,
      'transferId': id,
      'chunk': '$index/$total',
      'chunkBytes': '${frame['data'] ?? ''}'.length,
      // Wire'da ad/mime/caption sizmamali: bos olmalari beklenir.
      'fileNameOnWire': '${frame['fileName'] ?? ''}',
      'mimeOnWire': '${frame['mimeType'] ?? ''}',
      'captionOnWire': '${frame['caption'] ?? ''}',
      'groupIdOnWire': '${frame['groupId'] ?? ''}',
      'declaredFileSize': frame['fileSize'],
      'encryption': frame['encryption'],
      'isViewOnce': frame['isViewOnce'],
    });
    if (total > 0 && got == total) {
      log.add('file_complete', {
        'peer': peer.userId,
        'transferId': id,
        'chunks': total,
        'totalEncodedBytes': state['bytes'],
      });
    }
  }

  Future<void> _peerOnEncrypted(
    VirtualPeer peer,
    String from,
    Map<String, Object?> frame,
  ) async {
    final envelope = '${frame['envelope']}';
    final plaintext = await peer.decrypt(senderId: from, envelope: envelope);
    final isGroupRoute = plaintext.startsWith(kGroupRoutePrefix);
    final messageId = _extractMessageId(plaintext);
    log.add('peer_decrypt_ok', {
      'peer': peer.userId,
      'from': from,
      'envelopeType': envelope.split(':').elementAtOrNull(2),
      'messageId': messageId,
      'groupRoute': isGroupRoute,
      'plaintextLength': plaintext.length,
      'preview': _preview(plaintext),
      // Yapisal bayraklar: icerik degil, yalniz protokol onekleri.
      'flags': _structuralFlags(plaintext),
    });

    if (peer.sendReceipts && messageId != null) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      _peerSend(peer, from, {
        'type': 'delivery_receipt',
        'messageId': messageId,
        'status': 'DELIVERED',
      });
      await Future<void>.delayed(const Duration(milliseconds: 150));
      _peerSend(peer, from, {
        'type': 'delivery_receipt',
        'messageId': messageId,
        'status': 'READ',
      });
    }

    if (!peer.echoMessages || isGroupRoute) return;
    // Kontrol zarflari (typing/receipt/reaction vb.) sohbet metni degildir.
    const controlPrefixes = ['CHATCTRL:', 'SKDM:', 'GROUPROUTE:', 'GROUPCTRL:', 'MEDIAMANIFEST:'];
    if (controlPrefixes.any(plaintext.startsWith)) {
      log.add('peer_control_seen', {
        'peer': peer.userId,
        'prefix': plaintext.split(':').take(2).join(':'),
        'paddedBytes': plaintext.length,
      });
      return;
    }
    final content = _extractContent(plaintext);
    if (content == null || content.isEmpty) return;
    await Future<void>.delayed(peer.replyDelay);
    await _peerSendText(peer, from, 'echo: $content');
  }

  Future<bool> _peerSendText(
    VirtualPeer peer,
    String to,
    String text, {
    bool viewOnce = false,
    int? expiresInMs,
  }) async {
    if (!await peer.hasSession(to)) {
      log.add('peer_no_session', {'peer': peer.userId, 'to': to});
      return false;
    }
    final expiry = expiresInMs == null
        ? ''
        : 'EXP:${DateTime.now().millisecondsSinceEpoch + expiresInMs}:';
    final envelope = await peer.encrypt(
      recipientId: to,
      plaintext:
          'MSGID:${peer.nextMessageId()}:$expiry${viewOnce ? 'VIEWONCE:' : ''}$text',
    );
    _peerSend(peer, to, {'type': 'encrypted_message', 'envelope': envelope});
    log.add('peer_reply_sent', {'peer': peer.userId, 'to': to, 'text': text});
    return true;
  }

  Future<void> _peerOnCallControl(
    VirtualPeer peer,
    String from,
    Map<String, Object?> frame,
  ) async {
    final action = '${frame['action']}';
    log.add('peer_call_control', {
      'peer': peer.userId,
      'from': from,
      'action': action,
    });
    if (!peer.autoAnswerCalls) return;
    if (action == 'HANGUP' || action == 'REJECT') return;
    _peerSend(peer, from, {
      'type': 'call_control_ack',
      'messageId': '${frame['messageId'] ?? ''}',
      'action': action,
    });
  }

  Future<void> _peerOnOffer(
    VirtualPeer peer,
    String from,
    Map<String, Object?> frame,
  ) async {
    log.add('peer_sdp_offer', {
      'peer': peer.userId,
      'from': from,
      'callType': frame['callType'],
      'sdpLength': '${frame['sdp']}'.length,
    });
    if (!peer.autoAnswerCalls) return;
    _peerSend(peer, from, {'type': 'call_control', 'action': 'RINGING'});
    await Future<void>.delayed(const Duration(milliseconds: 900));
    // Gelen offer'dan minimal geçerli bir answer türet.
    _peerSend(peer, from, {
      'type': 'sdp_answer',
      'sdp': _deriveAnswer('${frame['sdp']}'),
    });
    _peerSend(peer, from, {'type': 'call_control', 'action': 'ACCEPT'});
  }

  void _peerSend(VirtualPeer peer, String to, Map<String, Object?> body) {
    final frame = <String, Object?>{
      'senderId': peer.userId,
      'recipientId': to,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      ...body,
    };
    final client = clients[to];
    if (client == null) {
      offlineQueue.putIfAbsent(to, () => []).add(frame);
      log.add('peer_queued', {'peer': peer.userId, 'to': to, 'type': body['type']});
      return;
    }
    client.send(frame);
  }

  static String _deriveAnswer(String offer) =>
      offer.replaceAll('a=setup:actpass', 'a=setup:active');

  static String? _extractMessageId(String plaintext) {
    if (!plaintext.startsWith('MSGID:')) return null;
    final end = plaintext.indexOf(':', 6);
    return end < 0 ? null : plaintext.substring(6, end);
  }

  static String? _extractContent(String plaintext) {
    if (!plaintext.startsWith('MSGID:')) return plaintext;
    var rest = plaintext.substring(plaintext.indexOf(':', 6) + 1);
    for (final prefix in const ['REPLY', 'EXP', 'MENTION']) {
      if (rest.startsWith('$prefix:')) {
        final first = rest.indexOf(':');
        final second = rest.indexOf(':', first + 1);
        if (second < 0) return null;
        rest = rest.substring(second + 1);
      }
    }
    for (final flag in const ['VIEWONCE:', 'POLL:']) {
      if (rest.startsWith(flag)) rest = rest.substring(flag.length);
    }
    return rest;
  }

  /// Duz metni loglamadan hangi protokol oneklerinin bulundugunu bildirir.
  static List<String> _structuralFlags(String plaintext) {
    final flags = <String>[];
    var rest = plaintext;
    if (rest.startsWith('MSGID:')) {
      flags.add('MSGID');
      rest = rest.substring(rest.indexOf(':', 6) + 1);
    }
    for (final prefix in const ['REPLY', 'EXP', 'MENTION']) {
      if (rest.startsWith('$prefix:')) {
        flags.add(prefix);
        final first = rest.indexOf(':');
        final second = rest.indexOf(':', first + 1);
        if (second < 0) break;
        rest = rest.substring(second + 1);
      }
    }
    for (final flag in const ['VIEWONCE:', 'POLL:']) {
      if (rest.startsWith(flag)) {
        flags.add(flag.replaceAll(':', ''));
        rest = rest.substring(flag.length);
      }
    }
    flags.add('bodyLen=${rest.length}');
    return flags;
  }

  static String _preview(String plaintext) {
    // Düz metin içeriği loglanmaz; yalnızca yapısal önek tutulur.
    final head = plaintext.length <= 24 ? plaintext : plaintext.substring(0, 24);
    return head.replaceAll(RegExp(r'[^A-Za-z0-9:_-]'), '.');
  }
}

// ---------------------------------------------------------------------------

Future<void> main(List<String> args) async {
  final port = int.tryParse(_arg(args, '--port') ?? '') ?? 8080;
  final logPath = _arg(args, '--log') ?? 'qa/logs/mock_server.jsonl';
  final logFile = File(logPath);
  logFile.parent.createSync(recursive: true);
  logFile.writeAsStringSync('');
  log = EventLog(logFile);

  final names = (_arg(args, '--peers') ?? 'peer-ayse,peer-mehmet,peer-zeynep')
      .split(',')
      .where((name) => name.trim().isNotEmpty)
      .map((name) => name.trim())
      .toList(growable: true);

  // Calisma zamaninda olusturulmus peer'ler de state dizininden geri yuklenir,
  // yoksa sunucu restart'i cihazdaki oturumu sessizce kopariyor.
  final statePath = _arg(args, '--state') ?? 'qa/mock/state';
  final stateDir = Directory(statePath);
  if (stateDir.existsSync()) {
    for (final file in stateDir.listSync().whereType<File>()) {
      if (!file.path.endsWith('.json')) continue;
      final name = file.uri.pathSegments.last.replaceAll('.json', '');
      if (!names.contains(name)) names.add(name);
    }
  }

  final peers = <String, VirtualPeer>{};
  for (final name in names) {
    final peer = VirtualPeer(
      name,
      name,
      stateFile: File('$statePath/$name.json'),
    );
    await peer.initialise();
    peers[name] = peer;
    log.add('peer_ready', {
      'userId': name,
      'registrationId': peer.published.registrationId,
      'oneTimeKeys': peer.published.oneTimePreKeys.length,
    });
  }

  final directoryPath = _arg(args, '--directory');
  if (directoryPath != null) {
    final module = DirectoryModule.load(directoryPath);
    log.add('directory_ready', {
      'keyId': module.keyId,
      'modulusBytes': module.modulusBytes,
    });
  }

  final server = MockServer(
    port: port,
    peers: peers,
    certificatePath: _arg(args, '--cert'),
    privateKeyPath: _arg(args, '--key'),
    directory: directoryPath == null ? null : DirectoryModule.load(directoryPath),
  );
  server.statePath = _arg(args, '--state');
  await server.start();
}

String? _arg(List<String> args, String flag) {
  final index = args.indexOf(flag);
  if (index >= 0 && index + 1 < args.length) return args[index + 1];
  for (final arg in args) {
    if (arg.startsWith('$flag=')) return arg.substring(flag.length + 1);
  }
  return null;
}

// Dart 3.9 uyumluluğu için küçük yardımcı.
extension _ElementAtOrNull<T> on List<T> {
  T? elementAtOrNull(int index) =>
      index >= 0 && index < length ? this[index] : null;
}

final _random = Random.secure();
// ignore: unused_element
int _nonce() => _random.nextInt(1 << 32);
