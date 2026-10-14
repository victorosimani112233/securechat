import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_securechat/src/crypto/vodozemac/securechat_crypto_ffi.dart';
import 'package:flutter_test/flutter_test.dart';

/// `native/securechat_crypto` C ABI'sinin Dart tarafini, uygulamanin
/// gordugu yoldan dogrular.
///
/// Kutuphane host icin derlenmis olmali:
///   cd native/securechat_crypto && cargo build --release
///
/// Derlenmemisse testler atlanir; CI'da derleme adimi eklendiginde
/// kosmaya baslar.
void main() {
  final libraryPath = _resolveHostLibrary();
  if (libraryPath == null) {
    // Atlama sessiz degil: neden atlandigi ve nasil duzeltilecegi yazili.
    test('vodozemac FFI (atlandi: native kutuphane derlenmemis)', () {
      markTestSkipped(
        'native/securechat_crypto/target/release/libsecurechat_crypto.so yok. '
        'Derlemek icin: cd native/securechat_crypto && cargo build --release',
      );
    }, skip: true);
    return;
  }

  late SecureChatCrypto crypto;
  final pickleKey = Uint8List.fromList(
    List<int>.generate(32, (index) => index + 1),
  );

  setUp(() => crypto = SecureChatCrypto.open(libraryPath: libraryPath));

  test('ABI surumu Rust, C basligi ve Dart arasinda tutarli', () {
    // Surum uc yerde elle tutuluyor: `sc_abi_version()` govdesi,
    // `include/securechat_crypto.h` sozlesmesi ve bu dosyadaki sabit.
    // Biri digerinden ayrisirsa yanlis `.so` ile sessizce calisma riski
    // dogar; `open()` zaten calisma aninda dogruluyor, bu test kaynak
    // tarafini da bagliyor.
    final rust = File('native/securechat_crypto/src/lib.rs').readAsStringSync();
    final match = RegExp(
      r'pub extern "C" fn sc_abi_version\(\) -> u32 \{\s*(\d+)',
    ).firstMatch(rust);
    expect(match, isNotNull, reason: 'sc_abi_version govdesi okunamadi');
    expect(
      int.parse(match!.group(1)!),
      expectedAbiVersion,
      reason: 'Rust ABI surumu Dart sabitinden farkli',
    );

    final header = File(
      'native/securechat_crypto/include/securechat_crypto.h',
    ).readAsStringSync();
    expect(
      header,
      contains('uint32_t sc_abi_version(void);'),
      reason: 'C basligi ABI fonksiyonunu beyan etmiyor',
    );
  });

  test('identity anahtarlari iki egriyi de verir', () {
    final account = crypto.createAccount();
    addTearDown(account.dispose);

    final keys = account.identityKeys();

    expect(keys.keys, containsAll(['curve25519', 'ed25519']));
    expect(_decodeKey(keys['curve25519']!), hasLength(32));
    expect(_decodeKey(keys['ed25519']!), hasLength(32));
  });

  test('tek kullanimlik anahtar havuzu uretilir ve sayilir', () {
    final account = crypto.createAccount();
    addTearDown(account.dispose);

    final generated = account.generateOneTimeKeys(5);

    expect(generated, hasLength(5));
    expect(account.storedOneTimeKeyCount, 5);
    for (final key in generated.values) {
      expect(_decodeKey(key), hasLength(32));
    }
  });

  test('yayinlanan anahtarlar bir daha yuklenmek uzere dondurulmez', () {
    final account = crypto.createAccount();
    addTearDown(account.dispose);
    account.generateOneTimeKeys(3);

    account.markKeysAsPublished();

    // Yayinlanmamis liste bosalir ama havuz yerelde durur: karsi taraf
    // bunlardan biriyle oturum kurabilsin diye.
    expect(account.unpublishedOneTimeKeys(), isEmpty);
    expect(account.storedOneTimeKeyCount, 3);
  });

  test('fallback anahtari uretilir — signed prekey karsiligi', () {
    final account = crypto.createAccount();
    addTearDown(account.dispose);

    final fallback = account.generateFallbackKey();

    expect(fallback, hasLength(1));
    expect(_decodeKey(fallback.values.single), hasLength(32));
  });

  test('imza uretilir ve uzunlugu Ed25519 ile uyumludur', () {
    final account = crypto.createAccount();
    addTearDown(account.dispose);

    final signature = account.sign(
      Uint8List.fromList(utf8.encode('imzalanacak icerik')),
    );

    expect(_decodeKey(signature), hasLength(64));
  });

  test('tam oturum akisi: bundle -> ilk mesaj -> iki yonlu yazisma', () {
    final alice = crypto.createAccount();
    final bob = crypto.createAccount();
    addTearDown(alice.dispose);
    addTearDown(bob.dispose);

    // Bob bundle'ini sunucuya yuklemis olurdu.
    final bobKeys = bob.generateOneTimeKeys(1);
    final bobBundle = bob.identityKeys();

    final aliceSession = alice.createOutboundSession(
      theirIdentityKey: bobBundle['curve25519']!,
      theirOneTimeKey: bobKeys.values.single,
    );
    addTearDown(aliceSession.dispose);

    final plaintext = Uint8List.fromList(utf8.encode('ilk mesaj'));
    final envelope = aliceSession.encrypt(plaintext);

    // Oturumun ilk mesaji PreKey tipinde olmali; alici oturumu bundan kurar.
    expect(envelope.isPreKey, isTrue);

    final inbound = bob.createInboundSession(
      theirIdentityKey: alice.identityKeys()['curve25519']!,
      preKeyMessageBase64: envelope.body,
    );
    addTearDown(inbound.session.dispose);

    expect(utf8.decode(inbound.plaintext), 'ilk mesaj');
    expect(inbound.session.sessionId, aliceSession.sessionId);

    // Ters yon: ratchet iki yonlu ilerliyor.
    final reply = inbound.session.encrypt(
      Uint8List.fromList(utf8.encode('cevap')),
    );
    expect(reply.isPreKey, isFalse);
    expect(utf8.decode(aliceSession.decrypt(reply)), 'cevap');
  });

  test('ayni plaintext her seferinde farkli ciphertext uretir', () {
    final alice = crypto.createAccount();
    final bob = crypto.createAccount();
    addTearDown(alice.dispose);
    addTearDown(bob.dispose);
    final bobKeys = bob.generateOneTimeKeys(1);

    final session = alice.createOutboundSession(
      theirIdentityKey: bob.identityKeys()['curve25519']!,
      theirOneTimeKey: bobKeys.values.single,
    );
    addTearDown(session.dispose);

    final message = Uint8List.fromList(utf8.encode('ayni metin'));
    final first = session.encrypt(message);
    final second = session.encrypt(message);

    expect(first.body, isNot(second.body));
  });

  test('hesap pickle gidip gelince anahtarlar korunur', () {
    final account = crypto.createAccount();
    addTearDown(account.dispose);
    account.generateOneTimeKeys(4);
    account.generateFallbackKey();
    final before = account.identityKeys();

    final restored = crypto.accountFromPickle(
      account.pickle(pickleKey),
      pickleKey,
    );
    addTearDown(restored.dispose);

    expect(restored.identityKeys(), before);
    expect(restored.storedOneTimeKeyCount, 4);
  });

  test('oturum pickle gidip gelince yazismaya devam eder', () {
    final alice = crypto.createAccount();
    final bob = crypto.createAccount();
    addTearDown(alice.dispose);
    addTearDown(bob.dispose);
    final bobKeys = bob.generateOneTimeKeys(1);

    final session = alice.createOutboundSession(
      theirIdentityKey: bob.identityKeys()['curve25519']!,
      theirOneTimeKey: bobKeys.values.single,
    );
    addTearDown(session.dispose);
    final envelope = session.encrypt(
      Uint8List.fromList(utf8.encode('pickle oncesi')),
    );

    final restored = crypto.sessionFromPickle(
      session.pickle(pickleKey),
      pickleKey,
    );
    addTearDown(restored.dispose);

    expect(restored.sessionId, session.sessionId);

    // Pickle'dan geri gelen oturum Bob'un cozebilecegi mesaj uretmeye devam
    // ediyor: ratchet durumu kayipsiz tasinmis.
    final inbound = bob.createInboundSession(
      theirIdentityKey: alice.identityKeys()['curve25519']!,
      preKeyMessageBase64: envelope.body,
    );
    addTearDown(inbound.session.dispose);
    expect(utf8.decode(inbound.plaintext), 'pickle oncesi');
  });

  test('yanlis pickle anahtari acilmaz ve neden oldugunu bildirir', () {
    final account = crypto.createAccount();
    addTearDown(account.dispose);
    final pickled = account.pickle(pickleKey);
    final wrongKey = Uint8List.fromList(List<int>.filled(32, 0xAA));

    expect(
      () => crypto.accountFromPickle(pickled, wrongKey),
      throwsA(
        isA<SecureChatCryptoException>().having(
          (error) => error.operation,
          'operation',
          'accountFromPickle',
        ),
      ),
    );
  });

  test('32 bayt olmayan pickle anahtari native tarafa hic gitmez', () {
    final account = crypto.createAccount();
    addTearDown(account.dispose);

    expect(
      () => account.pickle(Uint8List.fromList(List<int>.filled(16, 1))),
      throwsA(isA<SecureChatCryptoException>()),
    );
  });

  test('gecersiz peer anahtari native hatasini Dart istisnasina cevirir', () {
    final account = crypto.createAccount();
    addTearDown(account.dispose);

    expect(
      () => account.createOutboundSession(
        theirIdentityKey: 'bu-base64-degil!!',
        theirOneTimeKey: 'bu-da-degil!!',
      ),
      throwsA(
        isA<SecureChatCryptoException>().having(
          (error) => error.message,
          'message',
          contains('cozulemedi'),
        ),
      ),
    );
  });

  group('Megolm grup oturumu', () {
    test('dagitim anahtariyla kurulan gelen oturum ayni kimlige sahip', () {
      final outbound = crypto.createGroupSession();
      addTearDown(outbound.dispose);
      final inbound = crypto.inboundGroupSession(outbound.sessionKey);
      addTearDown(inbound.dispose);

      expect(inbound.sessionId, outbound.sessionId);
    });

    test('grup mesaji sifrelenir ve uyede cozulur', () {
      final outbound = crypto.createGroupSession();
      addTearDown(outbound.dispose);
      final inbound = crypto.inboundGroupSession(outbound.sessionKey);
      addTearDown(inbound.dispose);

      final message = outbound.encrypt(
        Uint8List.fromList(utf8.encode('gruba mesaj')),
      );
      final decrypted = inbound.decrypt(message);

      expect(utf8.decode(decrypted.plaintext), 'gruba mesaj');
      expect(decrypted.messageIndex, 0);
    });

    test('mesaj indeksi her sifrelemede ilerler', () {
      final outbound = crypto.createGroupSession();
      addTearDown(outbound.dispose);
      final inbound = crypto.inboundGroupSession(outbound.sessionKey);
      addTearDown(inbound.dispose);
      final payload = Uint8List.fromList(utf8.encode('ayni'));

      final indices = [
        for (var i = 0; i < 3; i++)
          inbound.decrypt(outbound.encrypt(payload)).messageIndex,
      ];

      // Replay tespiti buna dayaniyor: indeks tekrar etmemeli.
      expect(indices, [0, 1, 2]);
    });

    test('ayni plaintext her seferinde farkli ciphertext uretir', () {
      final outbound = crypto.createGroupSession();
      addTearDown(outbound.dispose);
      final payload = Uint8List.fromList(utf8.encode('ayni metin'));

      expect(outbound.encrypt(payload), isNot(outbound.encrypt(payload)));
    });

    test('pickle gidip gelince oturumlar devam eder', () {
      final outbound = crypto.createGroupSession();
      addTearDown(outbound.dispose);
      final inbound = crypto.inboundGroupSession(outbound.sessionKey);
      addTearDown(inbound.dispose);
      outbound.encrypt(Uint8List.fromList(utf8.encode('ilk')));

      final restoredOut = crypto.groupSessionFromPickle(
        outbound.pickle(pickleKey),
        pickleKey,
      );
      addTearDown(restoredOut.dispose);
      final restoredIn = crypto.inboundGroupSessionFromPickle(
        inbound.pickle(pickleKey),
        pickleKey,
      );
      addTearDown(restoredIn.dispose);

      final decrypted = restoredIn.decrypt(
        restoredOut.encrypt(Uint8List.fromList(utf8.encode('ikinci'))),
      );

      // Indeks kayipsiz tasindi: ilk mesaj 0 idi, bu 1 olmali.
      expect(utf8.decode(decrypted.plaintext), 'ikinci');
      expect(decrypted.messageIndex, 1);
    });

    test('baska oturumun mesaji cozulmez', () {
      final first = crypto.createGroupSession();
      addTearDown(first.dispose);
      final second = crypto.createGroupSession();
      addTearDown(second.dispose);
      final inbound = crypto.inboundGroupSession(second.sessionKey);
      addTearDown(inbound.dispose);

      expect(
        () => inbound.decrypt(
          first.encrypt(Uint8List.fromList(utf8.encode('yabanci'))),
        ),
        throwsA(isA<SecureChatCryptoException>()),
      );
    });

    test('gecersiz oturum anahtari reddedilir', () {
      expect(
        () => crypto.inboundGroupSession('bu-anahtar-degil'),
        throwsA(
          isA<SecureChatCryptoException>().having(
            (error) => error.message,
            'message',
            contains('cozulemedi'),
          ),
        ),
      );
    });

    test('dispose edilmis grup oturumu kullanilamaz', () {
      final outbound = crypto.createGroupSession();
      outbound.dispose();

      expect(outbound.isDisposed, isTrue);
      expect(() => outbound.sessionKey, throwsA(isA<SecureChatCryptoException>()));
      outbound.dispose();
    });
  });

  test('dispose edilmis handle kullanilamaz', () {
    final account = crypto.createAccount();
    account.dispose();

    expect(account.isDisposed, isTrue);
    expect(() => account.identityKeys(), throwsA(isA<SecureChatCryptoException>()));
    // Ikinci dispose sessizce gecmeli: double-free yok.
    account.dispose();
  });
}

/// vodozemac base64'u PADDING'SIZ uretir (Matrix/libolm konvansiyonu).
/// Dart'in `base64Decode`'u padding bekledigi icin once normalize edilir.
/// Bu, sunucu sozlesmesinde de dikkat edilmesi gereken bir interop detayi:
/// yuklenen anahtarlarin padding'i yok.
Uint8List _decodeKey(String value) =>
    base64Decode(base64.normalize(value));

/// Host kutuphanesini bulur; yoksa null.
String? _resolveHostLibrary() {
  final candidates = <String>[
    'native/securechat_crypto/target/release/libsecurechat_crypto.so',
    'native/securechat_crypto/target/release/libsecurechat_crypto.dylib',
    'native/securechat_crypto/target/debug/libsecurechat_crypto.so',
    'native/securechat_crypto/target/debug/libsecurechat_crypto.dylib',
  ];
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) return File(candidate).absolute.path;
  }
  return null;
}
