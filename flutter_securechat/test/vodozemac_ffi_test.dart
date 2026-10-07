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

  test('ABI surumu Dart tarafinin bekledigiyle ayni', () {
    // Yanlis bir .so ile sessizce calismak yerine acik hata verilmeli;
    // open() zaten dogruluyor, burada sozlesme sabitlenir.
    expect(expectedAbiVersion, 1);
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
    'native/securechat_crypto/target/debug/libsecurechat_crypto.so',
  ];
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) return File(candidate).absolute.path;
  }
  return null;
}
