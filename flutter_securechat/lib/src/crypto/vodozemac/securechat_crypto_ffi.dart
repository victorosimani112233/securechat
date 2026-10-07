/// `native/securechat_crypto` icindeki dar C ABI'nin Dart tarafi.
///
/// Neden el yazimi: bu katman uygulamanin guvenlik cekirdegi. Uretilmis
/// binlerce satir yerine okunup denetlenebilecek ~20 baglanti tutuluyor ve
/// build zamaninda kod ureten bir bagimlilik eklenmiyor; offline/vendor'lu
/// derleme disiplini korunuyor.
///
/// Bellek sozlesmesi: native taraftan donen her string burada hemen Dart
/// stringine kopyalanip `sc_string_free` ile serbest birakilir. Handle'lar
/// `Account.dispose()` / `OlmSession.dispose()` ile yok edilir.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Dart tarafinin bekledigi ABI surumu. Yanlis `.so` ile sessizce calismak
/// yerine acik hata verilir.
const int expectedAbiVersion = 1;

final class _Bindings {
  _Bindings(DynamicLibrary library)
    : abiVersion = library
          .lookupFunction<Uint32 Function(), int Function()>('sc_abi_version'),
      lastError = library
          .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
            'sc_last_error',
          ),
      stringFree = library.lookupFunction<
        Void Function(Pointer<Utf8>),
        void Function(Pointer<Utf8>)
      >('sc_string_free'),
      accountNew = library
          .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
            'sc_account_new',
          ),
      accountFree = library.lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('sc_account_free'),
      accountFromPickle = library.lookupFunction<
        Pointer<Void> Function(Pointer<Utf8>, Pointer<Uint8>),
        Pointer<Void> Function(Pointer<Utf8>, Pointer<Uint8>)
      >('sc_account_from_pickle'),
      accountPickle = library.lookupFunction<
        Pointer<Utf8> Function(Pointer<Void>, Pointer<Uint8>),
        Pointer<Utf8> Function(Pointer<Void>, Pointer<Uint8>)
      >('sc_account_pickle'),
      accountIdentityKeys = library.lookupFunction<
        Pointer<Utf8> Function(Pointer<Void>),
        Pointer<Utf8> Function(Pointer<Void>)
      >('sc_account_identity_keys'),
      accountSign = library.lookupFunction<
        Pointer<Utf8> Function(Pointer<Void>, Pointer<Uint8>, Size),
        Pointer<Utf8> Function(Pointer<Void>, Pointer<Uint8>, int)
      >('sc_account_sign'),
      accountGenerateOneTimeKeys = library.lookupFunction<
        Pointer<Utf8> Function(Pointer<Void>, Size),
        Pointer<Utf8> Function(Pointer<Void>, int)
      >('sc_account_generate_one_time_keys'),
      accountOneTimeKeys = library.lookupFunction<
        Pointer<Utf8> Function(Pointer<Void>),
        Pointer<Utf8> Function(Pointer<Void>)
      >('sc_account_one_time_keys'),
      accountStoredOneTimeKeyCount = library.lookupFunction<
        IntPtr Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('sc_account_stored_one_time_key_count'),
      accountMarkKeysAsPublished = library.lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('sc_account_mark_keys_as_published'),
      accountGenerateFallbackKey = library.lookupFunction<
        Pointer<Utf8> Function(Pointer<Void>),
        Pointer<Utf8> Function(Pointer<Void>)
      >('sc_account_generate_fallback_key'),
      accountCreateOutboundSession = library.lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>),
        Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)
      >('sc_account_create_outbound_session'),
      accountCreateInboundSession = library.lookupFunction<
        Pointer<Utf8> Function(
          Pointer<Void>,
          Pointer<Utf8>,
          Pointer<Utf8>,
          Pointer<Pointer<Void>>,
        ),
        Pointer<Utf8> Function(
          Pointer<Void>,
          Pointer<Utf8>,
          Pointer<Utf8>,
          Pointer<Pointer<Void>>,
        )
      >('sc_account_create_inbound_session'),
      sessionFree = library.lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('sc_session_free'),
      sessionPickle = library.lookupFunction<
        Pointer<Utf8> Function(Pointer<Void>, Pointer<Uint8>),
        Pointer<Utf8> Function(Pointer<Void>, Pointer<Uint8>)
      >('sc_session_pickle'),
      sessionFromPickle = library.lookupFunction<
        Pointer<Void> Function(Pointer<Utf8>, Pointer<Uint8>),
        Pointer<Void> Function(Pointer<Utf8>, Pointer<Uint8>)
      >('sc_session_from_pickle'),
      sessionId = library.lookupFunction<
        Pointer<Utf8> Function(Pointer<Void>),
        Pointer<Utf8> Function(Pointer<Void>)
      >('sc_session_id'),
      sessionEncrypt = library.lookupFunction<
        Pointer<Utf8> Function(Pointer<Void>, Pointer<Uint8>, Size),
        Pointer<Utf8> Function(Pointer<Void>, Pointer<Uint8>, int)
      >('sc_session_encrypt'),
      sessionDecrypt = library.lookupFunction<
        Pointer<Utf8> Function(Pointer<Void>, Size, Pointer<Utf8>),
        Pointer<Utf8> Function(Pointer<Void>, int, Pointer<Utf8>)
      >('sc_session_decrypt');

  final int Function() abiVersion;
  final Pointer<Utf8> Function() lastError;
  final void Function(Pointer<Utf8>) stringFree;
  final Pointer<Void> Function() accountNew;
  final void Function(Pointer<Void>) accountFree;
  final Pointer<Void> Function(Pointer<Utf8>, Pointer<Uint8>) accountFromPickle;
  final Pointer<Utf8> Function(Pointer<Void>, Pointer<Uint8>) accountPickle;
  final Pointer<Utf8> Function(Pointer<Void>) accountIdentityKeys;
  final Pointer<Utf8> Function(Pointer<Void>, Pointer<Uint8>, int) accountSign;
  final Pointer<Utf8> Function(Pointer<Void>, int) accountGenerateOneTimeKeys;
  final Pointer<Utf8> Function(Pointer<Void>) accountOneTimeKeys;
  final int Function(Pointer<Void>) accountStoredOneTimeKeyCount;
  final int Function(Pointer<Void>) accountMarkKeysAsPublished;
  final Pointer<Utf8> Function(Pointer<Void>) accountGenerateFallbackKey;
  final Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)
  accountCreateOutboundSession;
  final Pointer<Utf8> Function(
    Pointer<Void>,
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<Pointer<Void>>,
  )
  accountCreateInboundSession;
  final void Function(Pointer<Void>) sessionFree;
  final Pointer<Utf8> Function(Pointer<Void>, Pointer<Uint8>) sessionPickle;
  final Pointer<Void> Function(Pointer<Utf8>, Pointer<Uint8>) sessionFromPickle;
  final Pointer<Utf8> Function(Pointer<Void>) sessionId;
  final Pointer<Utf8> Function(Pointer<Void>, Pointer<Uint8>, int)
  sessionEncrypt;
  final Pointer<Utf8> Function(Pointer<Void>, int, Pointer<Utf8>)
  sessionDecrypt;
}

/// Native katmanin bildirdigi hata. Mesaj `sc_last_error()` kaynaklidir.
class SecureChatCryptoException implements Exception {
  const SecureChatCryptoException(this.operation, this.message);

  final String operation;
  final String message;

  @override
  String toString() => 'SecureChatCryptoException($operation): $message';
}

/// Yuklenmis native kutuphane. Uygulama basina bir kez acilir.
class SecureChatCrypto {
  SecureChatCrypto._(this._bindings);

  final _Bindings _bindings;

  /// Kutuphaneyi acar ve ABI surumunu dogrular.
  ///
  /// [libraryPath] verilmezse platform varsayilani kullanilir. iOS'ta
  /// kutuphane uygulama ikilisine statik baglandigi icin `process()` acilir.
  static SecureChatCrypto open({String? libraryPath}) {
    final library = _resolve(libraryPath);
    final crypto = SecureChatCrypto._(_Bindings(library));
    final version = crypto._bindings.abiVersion();
    if (version != expectedAbiVersion) {
      throw SecureChatCryptoException(
        'open',
        'ABI surumu uyusmuyor: native $version, beklenen $expectedAbiVersion',
      );
    }
    return crypto;
  }

  static DynamicLibrary _resolve(String? libraryPath) {
    if (libraryPath != null) return DynamicLibrary.open(libraryPath);
    if (Platform.isIOS || Platform.isMacOS) return DynamicLibrary.process();
    if (Platform.isAndroid || Platform.isLinux) {
      return DynamicLibrary.open('libsecurechat_crypto.so');
    }
    throw SecureChatCryptoException(
      'open',
      'desteklenmeyen platform: ${Platform.operatingSystem}',
    );
  }

  /// Yeni identity anahtar cifti uretir.
  OlmAccount createAccount() {
    final handle = _bindings.accountNew();
    if (handle == nullptr) _throw('createAccount');
    return OlmAccount._(this, handle);
  }

  /// Sifreli pickle'dan hesabi geri yukler.
  OlmAccount accountFromPickle(String pickle, Uint8List pickleKey) {
    _requireKey(pickleKey);
    final pickleNative = pickle.toNativeUtf8();
    final keyNative = _allocateKey(pickleKey);
    try {
      final handle = _bindings.accountFromPickle(pickleNative, keyNative);
      if (handle == nullptr) _throw('accountFromPickle');
      return OlmAccount._(this, handle);
    } finally {
      calloc.free(pickleNative);
      calloc.free(keyNative);
    }
  }

  /// Sifreli pickle'dan oturumu geri yukler.
  OlmSession sessionFromPickle(String pickle, Uint8List pickleKey) {
    _requireKey(pickleKey);
    final pickleNative = pickle.toNativeUtf8();
    final keyNative = _allocateKey(pickleKey);
    try {
      final handle = _bindings.sessionFromPickle(pickleNative, keyNative);
      if (handle == nullptr) _throw('sessionFromPickle');
      return OlmSession._(this, handle);
    } finally {
      calloc.free(pickleNative);
      calloc.free(keyNative);
    }
  }

  // --- ic yardimcilar ---------------------------------------------------

  static void _requireKey(Uint8List pickleKey) {
    if (pickleKey.length != 32) {
      throw SecureChatCryptoException(
        'pickleKey',
        'pickle anahtari tam 32 bayt olmali, ${pickleKey.length} verildi',
      );
    }
  }

  Pointer<Uint8> _allocateKey(Uint8List pickleKey) {
    final native = calloc<Uint8>(32);
    native.asTypedList(32).setAll(0, pickleKey);
    return native;
  }

  /// Native stringi Dart'a kopyalar ve native tamponu serbest birakir.
  String _takeString(Pointer<Utf8> value, String operation) {
    if (value == nullptr) _throw(operation);
    try {
      return value.toDartString();
    } finally {
      _bindings.stringFree(value);
    }
  }

  Never _throw(String operation) {
    final errorPointer = _bindings.lastError();
    if (errorPointer == nullptr) {
      throw SecureChatCryptoException(operation, 'bilinmeyen native hata');
    }
    try {
      throw SecureChatCryptoException(operation, errorPointer.toDartString());
    } finally {
      _bindings.stringFree(errorPointer);
    }
  }
}

/// Olm hesabi: identity anahtari, tek kullanimlik anahtar havuzu ve fallback.
///
/// libsignal'in aksine tek kullanimlik anahtarlar ayri kayitlarda degil
/// hesabin icinde tutulur. Anahtar ureten her cagridan sonra [pickle]
/// cagirip sonucu saklamak ZORUNLU; aksi halde uretilen anahtarlar kaybolur.
class OlmAccount {
  OlmAccount._(this._crypto, this._handle);

  final SecureChatCrypto _crypto;
  Pointer<Void> _handle;

  bool get isDisposed => _handle == nullptr;

  /// `{'curve25519': ..., 'ed25519': ...}`
  Map<String, String> identityKeys() {
    _check();
    final raw = _crypto._takeString(
      _crypto._bindings.accountIdentityKeys(_handle),
      'identityKeys',
    );
    return (jsonDecode(raw) as Map).cast<String, String>();
  }

  /// Ed25519 imzasi, base64.
  String sign(Uint8List message) {
    _check();
    final native = calloc<Uint8>(message.length == 0 ? 1 : message.length);
    native.asTypedList(message.length).setAll(0, message);
    try {
      return _crypto._takeString(
        _crypto._bindings.accountSign(_handle, native, message.length),
        'sign',
      );
    } finally {
      calloc.free(native);
    }
  }

  /// [count] tek kullanimlik anahtar uretir, yayinlanmamis havuzu dondurur.
  Map<String, String> generateOneTimeKeys(int count) {
    _check();
    final raw = _crypto._takeString(
      _crypto._bindings.accountGenerateOneTimeKeys(_handle, count),
      'generateOneTimeKeys',
    );
    return (jsonDecode(raw) as Map).cast<String, String>();
  }

  /// Henuz sunucuya yuklenmemis tek kullanimlik anahtarlar.
  Map<String, String> unpublishedOneTimeKeys() {
    _check();
    final raw = _crypto._takeString(
      _crypto._bindings.accountOneTimeKeys(_handle),
      'unpublishedOneTimeKeys',
    );
    return (jsonDecode(raw) as Map).cast<String, String>();
  }

  /// Yerelde duran toplam tek kullanimlik anahtar sayisi.
  int get storedOneTimeKeyCount {
    _check();
    final count = _crypto._bindings.accountStoredOneTimeKeyCount(_handle);
    if (count < 0) _crypto._throw('storedOneTimeKeyCount');
    return count;
  }

  /// Sunucuya yuklenen anahtarlari yayinlandi olarak isaretler.
  void markKeysAsPublished() {
    _check();
    if (_crypto._bindings.accountMarkKeysAsPublished(_handle) != 0) {
      _crypto._throw('markKeysAsPublished');
    }
  }

  /// Last-resort fallback anahtari uretir; signed prekey karsiligi.
  Map<String, String> generateFallbackKey() {
    _check();
    final raw = _crypto._takeString(
      _crypto._bindings.accountGenerateFallbackKey(_handle),
      'generateFallbackKey',
    );
    return (jsonDecode(raw) as Map).cast<String, String>();
  }

  /// Karsi tarafin bundle'iyla giden oturum kurar.
  OlmSession createOutboundSession({
    required String theirIdentityKey,
    required String theirOneTimeKey,
  }) {
    _check();
    final identity = theirIdentityKey.toNativeUtf8();
    final oneTime = theirOneTimeKey.toNativeUtf8();
    try {
      final handle = _crypto._bindings.accountCreateOutboundSession(
        _handle,
        identity,
        oneTime,
      );
      if (handle == nullptr) _crypto._throw('createOutboundSession');
      return OlmSession._(_crypto, handle);
    } finally {
      calloc.free(identity);
      calloc.free(oneTime);
    }
  }

  /// Gelen PreKey mesajindan oturum kurar ve ilk plaintext'i dondurur.
  InboundSessionResult createInboundSession({
    required String theirIdentityKey,
    required String preKeyMessageBase64,
  }) {
    _check();
    final identity = theirIdentityKey.toNativeUtf8();
    final message = preKeyMessageBase64.toNativeUtf8();
    final out = calloc<Pointer<Void>>();
    try {
      final plaintext = _crypto._bindings.accountCreateInboundSession(
        _handle,
        identity,
        message,
        out,
      );
      if (plaintext == nullptr) _crypto._throw('createInboundSession');
      final decoded = base64Decode(
        _crypto._takeString(plaintext, 'createInboundSession'),
      );
      return InboundSessionResult(
        session: OlmSession._(_crypto, out.value),
        plaintext: decoded,
      );
    } finally {
      calloc.free(identity);
      calloc.free(message);
      calloc.free(out);
    }
  }

  /// Hesabi sifreli pickle olarak serilestirir.
  String pickle(Uint8List pickleKey) {
    _check();
    SecureChatCrypto._requireKey(pickleKey);
    final keyNative = _crypto._allocateKey(pickleKey);
    try {
      return _crypto._takeString(
        _crypto._bindings.accountPickle(_handle, keyNative),
        'pickle',
      );
    } finally {
      calloc.free(keyNative);
    }
  }

  void dispose() {
    if (_handle == nullptr) return;
    _crypto._bindings.accountFree(_handle);
    _handle = nullptr;
  }

  void _check() {
    if (_handle == nullptr) {
      throw const SecureChatCryptoException('account', 'hesap dispose edildi');
    }
  }
}

/// Gelen oturum kurulumunun sonucu.
class InboundSessionResult {
  const InboundSessionResult({required this.session, required this.plaintext});

  final OlmSession session;
  final Uint8List plaintext;
}

/// Tasima icin hazir Olm zarfi. [type] 0 = PreKey, 1 = normal mesaj.
class OlmEnvelope {
  const OlmEnvelope({required this.type, required this.body});

  static const int preKeyType = 0;
  static const int messageType = 1;

  final int type;
  final String body;

  bool get isPreKey => type == preKeyType;
}

/// Iki taraf arasinda Double Ratchet oturumu.
///
/// [encrypt] ve [decrypt] ratchet durumunu ilerletir. Her cagridan sonra
/// [pickle] cagirip sonucu saklamak ZORUNLU; aksi halde ayni mesaj anahtari
/// tekrar kullanilir.
class OlmSession {
  OlmSession._(this._crypto, this._handle);

  final SecureChatCrypto _crypto;
  Pointer<Void> _handle;

  bool get isDisposed => _handle == nullptr;

  String get sessionId {
    _check();
    return _crypto._takeString(
      _crypto._bindings.sessionId(_handle),
      'sessionId',
    );
  }

  OlmEnvelope encrypt(Uint8List plaintext) {
    _check();
    final native = calloc<Uint8>(plaintext.length == 0 ? 1 : plaintext.length);
    native.asTypedList(plaintext.length).setAll(0, plaintext);
    try {
      final raw = _crypto._takeString(
        _crypto._bindings.sessionEncrypt(_handle, native, plaintext.length),
        'encrypt',
      );
      final decoded = jsonDecode(raw) as Map<String, Object?>;
      return OlmEnvelope(
        type: decoded['type']! as int,
        body: decoded['body']! as String,
      );
    } finally {
      calloc.free(native);
    }
  }

  Uint8List decrypt(OlmEnvelope envelope) {
    _check();
    final body = envelope.body.toNativeUtf8();
    try {
      final raw = _crypto._takeString(
        _crypto._bindings.sessionDecrypt(_handle, envelope.type, body),
        'decrypt',
      );
      return base64Decode(raw);
    } finally {
      calloc.free(body);
    }
  }

  String pickle(Uint8List pickleKey) {
    _check();
    SecureChatCrypto._requireKey(pickleKey);
    final keyNative = _crypto._allocateKey(pickleKey);
    try {
      return _crypto._takeString(
        _crypto._bindings.sessionPickle(_handle, keyNative),
        'pickle',
      );
    } finally {
      calloc.free(keyNative);
    }
  }

  void dispose() {
    if (_handle == nullptr) return;
    _crypto._bindings.sessionFree(_handle);
    _handle = nullptr;
  }

  void _check() {
    if (_handle == nullptr) {
      throw const SecureChatCryptoException('session', 'oturum dispose edildi');
    }
  }
}
