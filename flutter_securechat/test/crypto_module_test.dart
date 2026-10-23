import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
}
