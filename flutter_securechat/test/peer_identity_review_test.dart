import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/crypto/vodozemac/olm_pre_key_bundle_api.dart';
import 'package:flutter_securechat/src/crypto/vodozemac/vodozemac_crypto_service.dart';
import 'package:flutter_securechat/src/crypto/vodozemac/vodozemac_protocol_store.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/peer_identity_review_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/vodozemac_test_crypto.dart';

/// Karsi tarafin kimlik degisiminin incelenmesi ve onayi (TOFU).
///
/// Gercek vodozemac ile kosar. libsignal surumundeki su vakalar KASITLI
/// olarak tasinmadi, cunku Olm'da karsiliklari yok ya da baska yerde
/// olculuyor: signed prekey imzasinin gecersizligi/eksikligi ve imza
/// tamponunun libsignal 0.8.2'de yerinde degismesi (Olm'da signed prekey
/// yok; fallback imza reddi `olm_pre_key_bundle_api_test`'te), ve
/// libsignal store API'sinin pini ezememesi (o API artik yok).
void main() {
  test('fingerprint uses the standard SHA-256 vector', () {
    expect(
      PeerIdentityReview.safetyFingerprint([97, 98, 99]),
      'BA78 16BF 8F01 CFEA 4141 40DE 5DAE 2223 '
      'B003 61A3 9617 7A9C B410 FF61 F200 15AD',
    );
  });

  final libraryPath = resolveVodozemacLibrary();
  if (libraryPath == null) {
    test('kimlik incelemesi (atlandi: native kutuphane derlenmemis)', () {
      markTestSkipped(
        'Derlemek icin: cd native/securechat_crypto && cargo build --release',
      );
    }, skip: true);
    return;
  }

  group('identity approval', () {
    late _Fixture f;
    setUp(() async => f = await _Fixture.open(libraryPath));
    tearDown(() => f.close());

    test(
      'HTTP review and approval refetch authenticated current prekeys',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final client = HttpClient();
        addTearDown(() async {
          client.close(force: true);
          await server.close(force: true);
        });
        final paths = <String>[];
        final tokens = <String?>[];
        var current = await publishTestBundle(f.newStore);
        server.listen((request) {
          paths.add(request.uri.path);
          tokens.add(request.headers.value(HttpHeaders.authorizationHeader));
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'protocolVersion': 3,
              'identityKey': current.identityKey,
              'signingKey': current.signingKey,
              'oneTimeKey': current.oneTimeKey,
            }),
          );
          unawaited(request.response.close());
        });
        final crypto = VodozemacCryptoService(
          database: f.database,
          store: f.store,
          preKeyBundles: HttpOlmPreKeyBundleProvider(
            apiBaseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
            httpClient: client,
            accessTokenProvider: () async => 'review-token',
          ),
        );
        final review = await crypto.reviewPeerIdentity('peer');
        expect(review.currentIdentity, f.newKey);
        current = await publishTestBundle(f.freshStore);
        await expectLater(
          crypto.approvePeerIdentity(review),
          throwsA(isA<PeerIdentityReviewStaleException>()),
        );
        expect(paths, List.filled(2, '/api/v1/users/peer/prekeys'));
        expect(tokens, List.filled(2, 'Bearer review-token'));
        expect(await f.pin('peer'), f.oldKey);
        expect(await f.sessions('peer'), isNotEmpty);
      },
    );

    test(
      'review is immutable and never modifies the old pin or session',
      () async {
        final sessions = await f.sessions('peer');
        final review = await f.crypto.reviewPeerIdentity('peer');
        expect(review.previousIdentity, f.oldKey);
        expect(review.currentIdentity, f.newKey);
        expect(review.identityChanged, isTrue);
        expect(review.previousFingerprint, isNot(review.currentFingerprint));
        expect(() => review.currentIdentity[0] = 0, throwsUnsupportedError);
        expect(() => review.previousIdentity![0] = 0, throwsUnsupportedError);
        expect(await f.pin('peer'), f.oldKey);
        expect(await f.sessions('peer'), sessions);
      },
    );

    test(
      'approval replaces exact key, clears only peer sessions, and recovers messaging',
      () async {
        await f.crypto.ensureSession('other');
        final otherPin = await f.pin('other');
        final otherSessions = await f.sessions('other');
        expect(otherSessions, isNotEmpty);

        final review = await f.crypto.reviewPeerIdentity('peer');
        await f.crypto.approvePeerIdentity(review);
        expect(await f.pin('peer'), review.currentIdentity);
        expect(await f.sessions('peer'), isEmpty);
        expect(await f.pin('other'), otherPin);
        expect(await f.sessions('other'), otherSessions);

        final envelope = await f.crypto.encryptDirect(
          recipientId: 'peer',
          plaintext: 'recovered',
        );
        expect(
          await f.remote.decryptDirect(senderId: 'local', envelope: envelope),
          'recovered',
        );
        final reply = await f.remote.encryptDirect(
          recipientId: 'local',
          plaintext: 'reply',
        );
        expect(
          await f.crypto.decryptDirect(senderId: 'peer', envelope: reply),
          'reply',
        );
        await expectLater(
          f.crypto.approvePeerIdentity(review),
          throwsA(isA<PeerIdentityReviewStaleException>()),
        );
      },
    );

    test(
      'a later unseen endpoint identity rejects approval without mutation',
      () async {
        final sessions = await f.sessions('peer');
        final review = await f.crypto.reviewPeerIdentity('peer');
        f.provider.peerOverride = await publishTestBundle(f.freshStore);
        await expectLater(
          f.crypto.approvePeerIdentity(review),
          throwsA(isA<PeerIdentityReviewStaleException>()),
        );
        expect(await f.pin('peer'), f.oldKey);
        expect(await f.sessions('peer'), sessions);
      },
    );

    test('pin changed by another review rejects stale approval', () async {
      final first = await f.crypto.reviewPeerIdentity('peer');
      final second = await f.crypto.reviewPeerIdentity('peer');
      await f.crypto.approvePeerIdentity(first);
      await expectLater(
        f.crypto.approvePeerIdentity(second),
        throwsA(isA<PeerIdentityReviewStaleException>()),
      );
      expect(await f.pin('peer'), f.newKey);
    });

    test('local account identity change invalidates the review', () async {
      final review = await f.crypto.reviewPeerIdentity('peer');
      await f.database.vodozemacAccount.delete();
      await f.store.withAccount((_) async {});
      await expectLater(
        f.crypto.approvePeerIdentity(review),
        throwsA(isA<PeerIdentityReviewStaleException>()),
      );
      expect(await f.pin('peer'), f.oldKey);
    });

    test(
      'forged or foreign-instance snapshot cannot authorize approval',
      () async {
        final review = await f.crypto.reviewPeerIdentity('peer');
        final forged = PeerIdentityReview(
          peerId: 'peer',
          previousIdentity: review.previousIdentity,
          currentIdentity: review.currentIdentity,
          localIdentity: review.localIdentity,
        );
        await expectLater(
          f.crypto.approvePeerIdentity(forged),
          throwsA(isA<PeerIdentityReviewStaleException>()),
        );
        await expectLater(
          f.remote.approvePeerIdentity(review),
          throwsA(isA<PeerIdentityReviewStaleException>()),
        );
        expect(await f.pin('peer'), f.oldKey);
      },
    );

    for (final onApproval in [false, true]) {
      test(
        'missing bundle fails ${onApproval ? 'approval' : 'review'} closed',
        () async {
          final review = onApproval
              ? await f.crypto.reviewPeerIdentity('peer')
              : null;
          f.provider.peerMissing = true;
          await expectLater(
            onApproval
                ? f.crypto.approvePeerIdentity(review!)
                : f.crypto.reviewPeerIdentity('peer'),
            throwsStateError,
          );
          expect(await f.pin('peer'), f.oldKey);
        },
      );
    }

    test('unchanged identity does not discard a healthy session', () async {
      // Kullanici guvenlik numarasini degisiklik yokken "dogruladi". Eskiden
      // vodozemac onayi oturumlari KOSULSUZ siliyordu: karsi tarafin eski
      // oturumla yolda olan mesajlari cozulemez kalirdi.
      f.provider.sources['peer'] = f.oldStore;
      final review = await f.crypto.reviewPeerIdentity('peer');
      expect(review.identityChanged, isFalse);
      final before = await f.sessions('peer');
      expect(before, isNotEmpty);
      await f.crypto.approvePeerIdentity(review);
      expect(await f.sessions('peer'), before);
    });

    test(
      'no previous pin is displayed without silently accepting the fetched key',
      () async {
        await f.database.identities.delete('peer');
        await f.store.deleteSessionsForPeer('peer');
        final review = await f.crypto.reviewPeerIdentity('peer');
        expect(review.previousIdentity, isNull);
        expect(review.previousFingerprint, isNull);
        expect(await f.pin('peer'), isNull);
        await f.crypto.approvePeerIdentity(review);
        expect(await f.pin('peer'), f.newKey);
      },
    );

    test(
      'incoming mismatch emits notice and preserves old pin and session until approval',
      () async {
        final sessions = await f.sessions('peer');
        final envelope = await f.remote.encryptDirect(
          recipientId: 'local',
          plaintext: 'new device',
        );
        // Eskiden bu bir "olu oturum" sayilip pinli kimlige ait SAGLIKLI
        // oturumlar silinir ve bildirim yayilmazdi: tek bir mesaj (yeni
        // cihaz ya da araya giren biri) oturumu yok etmeye yetiyordu.
        await expectLater(
          f.crypto.decryptDirect(senderId: 'peer', envelope: envelope),
          throwsA(isA<PeerIdentityChangedException>()),
        );
        expect(f.notices, ['peer']);
        expect(await f.pin('peer'), f.oldKey);
        expect(await f.sessions('peer'), sessions);

        final review = await f.crypto.reviewPeerIdentity('peer');
        await f.crypto.approvePeerIdentity(review);
        // Hesap durumu degismedigi icin (tek kullanimlik anahtar
        // tuketilmedi) AYNI zarf onaydan sonra cozulur.
        expect(
          await f.crypto.decryptDirect(senderId: 'peer', envelope: envelope),
          'new device',
        );
      },
    );

    test(
      'approval serializes with incoming and outgoing crypto on the same peer',
      () async {
        await f.crypto.ensureSession('other');
        final review = await f.crypto.reviewPeerIdentity('peer');
        final envelope = await f.remote.encryptDirect(
          recipientId: 'local',
          plaintext: 'incoming',
        );
        final entered = Completer<void>();
        final release = Completer<void>();
        f.provider.beforeFetch = () async {
          if (!entered.isCompleted) entered.complete();
          await release.future;
        };
        final approval = f.crypto.approvePeerIdentity(review);
        await entered.future;
        var decrypted = false;
        var encrypted = false;
        final incoming = f.crypto
            .decryptDirect(senderId: 'peer', envelope: envelope)
            .then((value) {
              decrypted = true;
              return value;
            });
        final outgoing = f.crypto
            .encryptDirect(recipientId: 'peer', plaintext: 'outgoing')
            .then((value) {
              encrypted = true;
              return value;
            });
        await Future<void>.delayed(Duration.zero);
        expect(decrypted, isFalse);
        expect(encrypted, isFalse);
        // A different peer is not held behind this network request.
        await f.crypto
            .resetPeerSession('other')
            .timeout(const Duration(seconds: 1));
        f.provider.beforeFetch = null;
        release.complete();
        await approval;
        expect(await incoming, 'incoming');
        expect(
          await f.remote.decryptDirect(
            senderId: 'local',
            envelope: await outgoing,
          ),
          'outgoing',
        );
      },
    );

    test(
      'an identity change after approval is never automatically trusted',
      () async {
        await f.crypto.approvePeerIdentity(
          await f.crypto.reviewPeerIdentity('peer'),
        );
        f.provider.peerOverride = await publishTestBundle(f.freshStore);
        await expectLater(
          f.crypto.encryptDirect(recipientId: 'peer', plaintext: 'blocked'),
          throwsA(isA<PeerIdentityChangedException>()),
        );
        expect(await f.pin('peer'), f.newKey);
      },
    );
  });
}

/// Bellek ici bundle saglayicisi; testler peer'in kimligini degistirebilir.
class _Provider implements OlmPreKeyBundleProvider {
  final sources = <String, VodozemacProtocolStore>{};
  OlmPreKeyBundle? peerOverride;
  bool peerMissing = false;
  Future<void> Function()? beforeFetch;

  @override
  Future<OlmPreKeyBundle?> fetch(String recipientId) async {
    await beforeFetch?.call();
    if (recipientId == 'peer') {
      if (peerMissing) return null;
      if (peerOverride != null) return peerOverride;
    }
    final store = sources[recipientId];
    return store == null ? null : publishTestBundle(store);
  }
}

class _Fixture {
  _Fixture._(this.directory);

  final Directory directory;
  late final SecureChatDatabase database;
  late final VodozemacProtocolStore store;

  /// Peer'in ESKI kimligi (A): oturum bununla kurulup pinlendi.
  late final VodozemacProtocolStore oldStore;

  /// Peer'in YENI kimligi (B): yeni cihaz; [remote] bunu kullanir.
  late final VodozemacProtocolStore newStore;

  /// Hic gorulmemis ucuncu bir kimlik (C).
  late final VodozemacProtocolStore freshStore;
  final provider = _Provider();
  final notices = <String>[];
  final _databases = <SecureChatDatabase>[];
  late final VodozemacCryptoService crypto;
  late final VodozemacCryptoService remote;
  late final List<int> oldKey;
  late final List<int> newKey;

  static Future<_Fixture> open(String libraryPath) async {
    final f = _Fixture._(
      await Directory.systemTemp.createTemp('identity_review_'),
    );
    Future<(SecureChatDatabase, VodozemacProtocolStore)> party(
      String name,
    ) async {
      final masterKey = List<int>.filled(32, name.length + 7);
      final database = await SecureChatDatabase.open(
        file: File('${f.directory.path}/$name.db'),
        crypto: LocalAeadCryptoService(SecretKey(masterKey)),
      );
      f._databases.add(database);
      final store = await openTestVodozemacStore(
        database,
        masterKey,
        libraryPath,
      );
      await store.withAccount((_) async {});
      return (database, store);
    }

    final (database, store) = await party('local');
    f.database = database;
    f.store = store;
    f.oldStore = (await party('peer-old')).$2;
    final (newDatabase, newStore) = await party('peer-new');
    f.newStore = newStore;
    f.freshStore = (await party('fresh')).$2;
    final otherStore = (await party('other')).$2;

    f.provider.sources
      ..['local'] = store
      ..['other'] = otherStore
      ..['peer'] = f.oldStore;
    f.crypto = VodozemacCryptoService(
      database: database,
      store: store,
      preKeyBundles: f.provider,
      onPeerIdentityRotated: (id) async => f.notices.add(id),
    );
    f.remote = VodozemacCryptoService(
      database: newDatabase,
      store: newStore,
      preKeyBundles: f.provider,
    );
    f.oldKey = await _identity(f.oldStore);
    f.newKey = await _identity(newStore);

    // Eski kimlikle oturum kur ve pinle, sonra peer cihaz degistirir.
    await f.crypto.ensureSession('peer');
    f.provider.sources['peer'] = newStore;
    return f;
  }

  Future<List<int>?> pin(String peerId) async =>
      (await database.identities.get(peerId))?.identityKey;

  Future<List<String>> sessions(String peerId) =>
      store.sessionIdsForPeer(peerId);

  Future<void> close() async {
    for (final database in _databases) {
      await database.close();
    }
    await directory.delete(recursive: true);
  }
}

/// Pinlenen bicim: Ed25519 || Curve25519 (bkz. `OlmPreKeyBundle.identityBytes`).
Future<List<int>> _identity(VodozemacProtocolStore store) =>
    store.readAccount((account) async {
      final keys = account.identityKeys();
      return Uint8List.fromList([
        ...base64Decode(base64.normalize(keys['ed25519']!)),
        ...base64Decode(base64.normalize(keys['curve25519']!)),
      ]);
    });
