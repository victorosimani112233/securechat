import 'dart:io';

import 'package:flutter_securechat/src/crypto/vodozemac/securechat_crypto_ffi.dart';
import 'package:flutter_securechat/src/crypto/vodozemac/vodozemac_crypto_service.dart';
import 'package:flutter_securechat/src/crypto/vodozemac/vodozemac_protocol_store.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';

/// Uygulama seviyesi testler icin gercek vodozemac kriptosu.
///
/// Bu testler eskiden libsignal servisini kullaniyordu. Uretim artik
/// vodozemac (Olm + Megolm) calistirdigi icin, akisi URETIMDEKI kriptoyla
/// olcmeleri gerekiyor; sahte bir kripto, tel formatini ve oturum kurulumunu
/// test disi birakirdi.

/// Host icin derlenmis native kutuphane, yoksa null (test atlanir).
String? resolveVodozemacLibrary() {
  for (final candidate in const [
    'native/securechat_crypto/target/release/libsecurechat_crypto.so',
    'native/securechat_crypto/target/release/libsecurechat_crypto.dylib',
    'native/securechat_crypto/target/debug/libsecurechat_crypto.so',
    'native/securechat_crypto/target/debug/libsecurechat_crypto.dylib',
  ]) {
    if (File(candidate).existsSync()) return File(candidate).absolute.path;
  }
  return null;
}

/// Taraflarin birbirinin bundle'ini cekebildigi bellek ici dizin.
///
/// Her `fetch` taze bir tek kullanimlik anahtar uretip yayinlanmis sayar;
/// sunucunun her bundle isteginde bir anahtar tuketmesinin karsiligi.
class OlmBundleDirectory implements OlmPreKeyBundleProvider {
  final _stores = <String, VodozemacProtocolStore>{};

  void register(String userId, VodozemacProtocolStore store) =>
      _stores[userId] = store;

  @override
  Future<OlmPreKeyBundle?> fetch(String recipientId) async {
    final store = _stores[recipientId];
    if (store == null) return null;
    return publishTestBundle(store);
  }
}

/// Bir tarafin yayinlayacagi bundle: kimlik + taze tek kullanimlik anahtar.
Future<OlmPreKeyBundle> publishTestBundle(VodozemacProtocolStore store) =>
    store.withAccount((account) async {
      final keys = account.identityKeys();
      final oneTime = account.generateOneTimeKeys(1);
      account.markKeysAsPublished();
      return OlmPreKeyBundle(
        identityKey: keys['curve25519']!,
        signingKey: keys['ed25519']!,
        oneTimeKey: oneTime.values.single,
      );
    });

/// [database] uzerinde uretimdeki gibi kurulmus vodozemac store'u.
Future<VodozemacProtocolStore> openTestVodozemacStore(
  SecureChatDatabase database,
  List<int> masterKey,
  String libraryPath,
) async => VodozemacProtocolStore(
  database: database,
  crypto: SecureChatCrypto.open(libraryPath: libraryPath),
  pickleKey: await VodozemacProtocolStore.derivePickleKey(masterKey),
);
