import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart' as signal;
import 'package:flutter_securechat/src/crypto/crypto_protocol_store.dart';
import 'package:flutter_securechat/src/crypto/libsignal_protocol_store.dart';
import 'package:flutter_securechat/src/services/peer_identity_review_service.dart';
import 'package:flutter_securechat/src/crypto/pre_key_manager.dart';
import 'package:flutter_securechat/src/crypto/signal_protocol_crypto_service.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';

void main() {
  test('fingerprint uses the standard SHA-256 vector', () {
    expect(
      PeerIdentityReview.safetyFingerprint([97, 98, 99]),
      'BA78 16BF 8F01 CFEA 4141 40DE 5DAE 2223 '
      'B003 61A3 9617 7A9C B410 FF61 F200 15AD',
    );
  });

  group('identity approval', () {
    late _Fixture f;
    setUp(() async => f = await _Fixture.open());
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
        var current = f.provider.peer!;
        server.listen((request) {
          paths.add(request.uri.path);
          tokens.add(request.headers.value(HttpHeaders.authorizationHeader));
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'identityPublicKey': base64Encode(
                current.getIdentityKey().serialize(),
              ),
              'registrationId': current.getRegistrationId(),
              'signedPreKeyId': current.getSignedPreKeyId(),
              'signedPreKey': base64Encode(
                current.getSignedPreKey()!.serialize(),
              ),
              'signedPreKeySignature': base64Encode(
                current.getSignedPreKeySignature()!,
              ),
              'oneTimePreKey': null,
            }),
          );
          unawaited(request.response.close());
        });
        final crypto = SignalProtocolCryptoService(
          store: f.store,
          preKeyBundles: HttpPreKeyBundleProvider(
            apiBaseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
            httpClient: client,
            accessTokenProvider: () async => 'review-token',
          ),
        );
        final review = await crypto.reviewPeerIdentity('peer');
        expect(review.currentIdentity, f.newKey);
        current = _freshBundle();
        await expectLater(
          crypto.approvePeerIdentity(review),
          throwsA(isA<PeerIdentityReviewStaleException>()),
        );
        expect(paths, List.filled(2, '/api/v1/users/peer/prekeys'));
        expect(tokens, List.filled(2, 'Bearer review-token'));
        expect(await f.raw.loadIdentity('peer'), f.oldKey);
        expect(await f.raw.containsSession('peer', 1), isTrue);
      },
    );

    test(
      'review is immutable and never modifies the old pin or session',
      () async {
        final review = await f.crypto.reviewPeerIdentity('peer');
        expect(review.previousIdentity, f.oldKey);
        expect(review.currentIdentity, f.newKey);
        expect(review.identityChanged, isTrue);
        expect(review.previousFingerprint, isNot(review.currentFingerprint));
        expect(() => review.currentIdentity[0] = 0, throwsUnsupportedError);
        expect(() => review.previousIdentity![0] = 0, throwsUnsupportedError);
        expect(await f.raw.loadIdentity('peer'), f.oldKey);
        expect(await f.raw.containsSession('peer', 1), isTrue);
      },
    );

    test(
      'approval replaces exact key, clears only peer sessions, and recovers messaging',
      () async {
        final otherKey = signal
            .generateIdentityKeyPair()
            .getPublicKey()
            .serialize();
        await f.raw.storeIdentity('other', otherKey);
        await f.raw.storeSession('other', 1, [1, 2, 3]);
        await f.raw.storeSession('peer', 2, [4, 5, 6]);
        final review = await f.crypto.reviewPeerIdentity('peer');
        await f.crypto.approvePeerIdentity(review);
        expect(await f.raw.loadIdentity('peer'), review.currentIdentity);
        expect(await f.raw.containsSession('peer', 1), isFalse);
        expect(await f.raw.containsSession('peer', 2), isFalse);
        expect(await f.raw.loadIdentity('other'), otherKey);
        expect(await f.raw.loadSession('other', 1), [1, 2, 3]);
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
        final review = await f.crypto.reviewPeerIdentity('peer');
        f.provider.peer = _freshBundle();
        await expectLater(
          f.crypto.approvePeerIdentity(review),
          throwsA(isA<PeerIdentityReviewStaleException>()),
        );
        expect(await f.raw.loadIdentity('peer'), f.oldKey);
        expect(await f.raw.containsSession('peer', 1), isTrue);
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
      expect(await f.raw.loadIdentity('peer'), f.newKey);
    });

    test('local account identity change invalidates the review', () async {
      final review = await f.crypto.reviewPeerIdentity('peer');
      await f.raw.storeIdentityKeyPair(
        signal.generateIdentityKeyPair().serialize(),
      );
      await expectLater(
        f.crypto.approvePeerIdentity(review),
        throwsA(isA<PeerIdentityReviewStaleException>()),
      );
      expect(await f.raw.loadIdentity('peer'), f.oldKey);
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
        expect(await f.raw.loadIdentity('peer'), f.oldKey);
      },
    );

    for (final onApproval in [false, true]) {
      test(
        'invalid signed prekey fails ${onApproval ? 'approval' : 'review'} closed',
        () async {
          final review = onApproval
              ? await f.crypto.reviewPeerIdentity('peer')
              : null;
          final valid = f.provider.peer!;
          f.provider.peer = signal.PreKeyBundle(
            valid.getRegistrationId(),
            1,
            null,
            null,
            valid.getSignedPreKeyId(),
            valid.getSignedPreKey(),
            Uint8List(64),
            valid.getIdentityKey(),
          );
          await expectLater(
            onApproval
                ? f.crypto.approvePeerIdentity(review!)
                : f.crypto.reviewPeerIdentity('peer'),
            throwsA(isA<signal.InvalidKeyException>()),
          );
          expect(await f.raw.loadIdentity('peer'), f.oldKey);
          expect(await f.raw.containsSession('peer', 1), isTrue);
        },
      );

      test(
        'missing bundle fails ${onApproval ? 'approval' : 'review'} closed',
        () async {
          final review = onApproval
              ? await f.crypto.reviewPeerIdentity('peer')
              : null;
          f.provider.peer = null;
          await expectLater(
            onApproval
                ? f.crypto.approvePeerIdentity(review!)
                : f.crypto.reviewPeerIdentity('peer'),
            throwsStateError,
          );
          expect(await f.raw.loadIdentity('peer'), f.oldKey);
        },
      );
    }

    test('unchanged identity does not discard a healthy session', () async {
      f.provider.peer = f.oldBundle;
      final review = await f.crypto.reviewPeerIdentity('peer');
      expect(review.identityChanged, isFalse);
      final before = await f.raw.loadSession('peer', 1);
      await f.crypto.approvePeerIdentity(review);
      expect(await f.raw.loadSession('peer', 1), before);
    });

    test(
      'review verification preserves the signature sign bit in cached bundles',
      () async {
        signal.PreKeyBundle bundle;
        do {
          bundle = _freshBundle();
        } while (bundle.getSignedPreKeySignature()![63] & 0x80 == 0);
        f.provider.peer = bundle;
        f.provider.freshCopies = false;
        final signature = List<int>.from(bundle.getSignedPreKeySignature()!);
        final review = await f.crypto.reviewPeerIdentity('peer');
        expect(bundle.getSignedPreKeySignature(), signature);
        await f.crypto.approvePeerIdentity(review);
        expect(bundle.getSignedPreKeySignature(), signature);
      },
    );

    test(
      'no previous pin is displayed without silently accepting the fetched key',
      () async {
        await f.raw.deleteIdentity('peer');
        await f.raw.deleteAllSessions('peer');
        final review = await f.crypto.reviewPeerIdentity('peer');
        expect(review.previousIdentity, isNull);
        expect(review.previousFingerprint, isNull);
        expect(await f.raw.loadIdentity('peer'), isNull);
        await f.crypto.approvePeerIdentity(review);
        expect(await f.raw.loadIdentity('peer'), f.newKey);
      },
    );

    test('a missing signed prekey cannot be displayed or approved', () async {
      final valid = f.provider.peer!;
      f.provider.peer = signal.PreKeyBundle(
        valid.getRegistrationId(),
        1,
        null,
        null,
        valid.getSignedPreKeyId(),
        null,
        valid.getSignedPreKeySignature(),
        valid.getIdentityKey(),
      );
      await expectLater(
        f.crypto.reviewPeerIdentity('peer'),
        throwsA(isA<signal.InvalidKeyException>()),
      );
      expect(await f.raw.loadIdentity('peer'), f.oldKey);
    });

    test('ordinary Signal saves cannot overwrite the pin', () async {
      await expectLater(
        f.store.saveIdentity(
          const signal.SignalProtocolAddress('peer', 1),
          f.provider.peer!.getIdentityKey(),
        ),
        throwsA(isA<signal.UntrustedIdentityException>()),
      );
      expect(await f.raw.loadIdentity('peer'), f.oldKey);
    });

    test(
      'incoming mismatch emits notice and preserves old pin until approval',
      () async {
        final envelope = await f.remote.encryptDirect(
          recipientId: 'local',
          plaintext: 'new device',
        );
        await expectLater(
          f.crypto.decryptDirect(senderId: 'peer', envelope: envelope),
          throwsA(
            isA<SignalSessionUnusableException>().having(
              (e) => e.cause,
              'cause',
              isA<signal.UntrustedIdentityException>(),
            ),
          ),
        );
        expect(f.notices, ['peer']);
        expect(await f.raw.loadIdentity('peer'), f.oldKey);
        await expectLater(
          f.crypto.rebuildPeerSession('peer'),
          throwsA(isA<signal.UntrustedIdentityException>()),
        );
        expect(await f.raw.loadIdentity('peer'), f.oldKey);
        final review = await f.crypto.reviewPeerIdentity('peer');
        await f.crypto.approvePeerIdentity(review);
        expect(
          await f.crypto.decryptDirect(senderId: 'peer', envelope: envelope),
          'new device',
        );
      },
    );

    test(
      'approval serializes with incoming and outgoing crypto on the same peer',
      () async {
        final review = await f.crypto.reviewPeerIdentity('peer');
        final envelope = await f.remote.encryptDirect(
          recipientId: 'local',
          plaintext: 'incoming',
        );
        final entered = Completer<void>();
        final release = Completer<void>();
        f.provider.beforeFetch = () async {
          entered.complete();
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
        f.provider.peer = _freshBundle();
        await expectLater(
          f.crypto.encryptDirect(recipientId: 'peer', plaintext: 'blocked'),
          throwsA(isA<signal.UntrustedIdentityException>()),
        );
        expect(await f.raw.loadIdentity('peer'), f.newKey);
      },
    );
  });
}

class _Provider implements PreKeyBundleProvider {
  bool freshCopies = true;
  signal.PreKeyBundle? peer;
  signal.PreKeyBundle? local;
  Future<void> Function()? beforeFetch;

  @override
  Future<signal.PreKeyBundle?> fetch(String recipientId) async {
    await beforeFetch?.call();
    final bundle = recipientId == 'peer' ? peer : local;
    if (bundle == null) return null;
    if (!freshCopies) return bundle;
    // Match HTTP: each fetch returns fresh bytes. SessionBuilder mutates the
    // signature buffer when verifying it in libsignal 0.8.2.
    return signal.PreKeyBundle(
      bundle.getRegistrationId(),
      bundle.getDeviceId(),
      bundle.getPreKeyId(),
      bundle.getPreKey(),
      bundle.getSignedPreKeyId(),
      bundle.getSignedPreKey(),
      Uint8List.fromList(bundle.getSignedPreKeySignature()!),
      bundle.getIdentityKey(),
    );
  }
}

class _Fixture {
  _Fixture(
    this.directory,
    this.database,
    this.remoteDatabase,
    this.raw,
    this.store,
    this.provider,
    this.oldBundle,
    this.newKey,
  ) {
    crypto = SignalProtocolCryptoService(
      store: store,
      preKeyBundles: provider,
      onPeerIdentityRotated: (id) async => notices.add(id),
    );
    remote = SignalProtocolCryptoService(
      store: PersistentSignalProtocolStore(
        DatabaseCryptoProtocolStore(remoteDatabase),
      ),
      preKeyBundles: provider,
    );
  }

  final Directory directory;
  final SecureChatDatabase database;
  final SecureChatDatabase remoteDatabase;
  final DatabaseCryptoProtocolStore raw;
  final PersistentSignalProtocolStore store;
  final _Provider provider;
  final signal.PreKeyBundle oldBundle;
  final List<int> newKey;
  final notices = <String>[];
  late final SignalProtocolCryptoService crypto;
  late final SignalProtocolCryptoService remote;
  List<int> get oldKey => oldBundle.getIdentityKey().serialize();

  static Future<_Fixture> open() async {
    final directory = await Directory.systemTemp.createTemp('identity_review_');
    Future<SecureChatDatabase> openDb(String name) => SecureChatDatabase.open(
      file: File('${directory.path}/$name.db'),
      crypto: LocalAeadCryptoService(SecretKey(List.filled(32, 7))),
    );
    final database = await openDb('local');
    final remoteDatabase = await openDb('remote');
    final raw = DatabaseCryptoProtocolStore(database);
    final provider = _Provider()
      ..local = _bundle(
        await PreKeyManager(
          raw,
          batchSize: 1,
        ).generateAndSerializeInitialBundle(),
      )
      ..peer = _bundle(
        await PreKeyManager(
          DatabaseCryptoProtocolStore(remoteDatabase),
          batchSize: 1,
        ).generateAndSerializeInitialBundle(),
      );
    final fresh = provider.peer!;
    final old = _freshBundle();
    final f = _Fixture(
      directory,
      database,
      remoteDatabase,
      raw,
      PersistentSignalProtocolStore(raw),
      provider,
      old,
      fresh.getIdentityKey().serialize(),
    );
    provider.peer = old;
    await f.crypto.ensureSession('peer');
    provider.peer = fresh;
    return f;
  }

  Future<void> close() async {
    await database.close();
    await remoteDatabase.close();
    await directory.delete(recursive: true);
  }
}

signal.PreKeyBundle _freshBundle() {
  final identity = signal.generateIdentityKeyPair();
  final signed = signal.generateSignedPreKey(identity, 1);
  return signal.PreKeyBundle(
    17,
    1,
    null,
    null,
    signed.id,
    signed.getKeyPair().publicKey,
    signed.signature,
    identity.getPublicKey(),
  );
}

signal.PreKeyBundle _bundle(SerializedPreKeyBundle bundle) =>
    signal.PreKeyBundle(
      bundle.registrationId,
      1,
      null,
      null,
      bundle.signedPreKeyId,
      signal.Curve.decodePoint(Uint8List.fromList(bundle.signedPreKey), 0),
      Uint8List.fromList(bundle.signedPreKeySignature),
      signal.IdentityKey.fromBytes(
        Uint8List.fromList(bundle.identityPublicKey),
        0,
      ),
    );
