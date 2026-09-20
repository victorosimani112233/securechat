import 'package:flutter_securechat/src/push/push_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regresyon: Android tarafinda Firebase app id'si varsayilan olarak gomulu
/// oldugu icin push kutudan calisiyordu; iOS tarafinda varsayilan yoktu ve
/// derleme sirasinda define verilmeyince FirebaseOptions null donuyordu.
/// Sonuc, iOS'ta push'un SESSIZCE devre disi kalmasiydi.
void main() {
  test('Firebase secenekleri ayni proje ile tutarli', () {
    final options = SecureChatFirebaseOptions.current;
    // Testler VM uzerinde kosar; Platform.isAndroid/isIOS false olabilir.
    if (options == null) return;
    expect(options.projectId, 'chat-3e219');
    expect(options.messagingSenderId, '791820453236');
    expect(options.appId, startsWith('1:791820453236:'));
  });

  test('appId proje numarasiyla ayni sender id"yi tasir', () {
    final options = SecureChatFirebaseOptions.current;
    if (options == null) return;
    expect(
      options.appId.split(':')[1],
      options.messagingSenderId,
      reason: 'appId ve senderId ayni Firebase projesine ait olmali',
    );
  });
}
