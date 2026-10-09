
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_securechat/src/crypto/call_crypto_manager.dart';
import 'package:flutter_securechat/src/services/key_material_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('platform key material is created once and validated', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final store = PlatformKeyMaterialStore();
    final first = await store.readOrCreateMasterKey();
    final second = await store.readOrCreateMasterKey();

    expect(first, hasLength(32));
    expect(second, first);
  });

  test('call crypto derives peer-bound keys and clears them', () async {
    final keys = await CallCryptoManager().deriveCallEncryptionKey('alice');
    expect(keys.masterKey, hasLength(32));
    expect(keys.masterSalt, hasLength(32));
    expect(keys.masterKey, isNot(everyElement(0)));

    keys.clear();
    expect(keys.masterKey, everyElement(0));
    expect(keys.masterSalt, everyElement(0));
  });
}
