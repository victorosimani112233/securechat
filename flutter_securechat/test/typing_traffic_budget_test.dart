import 'package:flutter_securechat/src/chat/chat_activity_service.dart';
import 'package:flutter_securechat/src/core/models.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';

/// Her kontrol paketi trafik analizi direnci icin sabit 16 KiB'a padlenir ve
/// tel uzerinde ~29 KB'a cikar. Tus basina paket gonderilmez; bir yazma turu
/// yalnizca basla/dur paketleri uretir. Paket boyutu ve E2EE korunurken mobil
/// baglantida da kullaniciya vaat edilen yaziyor bilgisi calismalidir.
void main() {
  late InMemorySignalingService signaling;
  late ChatActivityService activity;

  const conversation = Conversation(
    id: 'peer-1',
    peerId: 'peer-1',
    peerName: 'Peer',
    peerPhone: '',
  );

  /// Yaziyor-gostergesi `sendPrivateChatControl` tarafindan sabit boyutlu
  /// `CHATCTRL:` zarfina sarilip `EncryptedSignalMessage` olarak gonderilir.
  /// Dogru metrik tel uzerindeki paket sayisidir.
  int typingFrames() =>
      signaling.sentMessages.whereType<EncryptedSignalMessage>().length;

  Future<void> setUpService() async {
    signaling = InMemorySignalingService();
    await signaling.connect(
      userId: 'me',
      url: 'ws://local',
      accessToken: 'token',
    );
    activity = ChatActivityService(
      session: SessionStore(userId: 'me', accessToken: 'token'),
      signaling: signaling,
      crypto: LocalAeadCryptoService(SecretKey(List.filled(32, 5))),
    );
  }

  tearDown(() async {
    await activity.dispose();
    await signaling.dispose();
  });

  test('surekli yazma tek bir duyuru uretir', () async {
    await setUpService();
    for (var i = 0; i < 10; i++) {
      await activity.updateTyping(conversation, true);
    }
    expect(typingFrames(), 1, reason: 'tus basina paket gonderilmemeli');
  });

  test('durduktan sonra yeniden yazma hemen duyurulur', () async {
    await setUpService();
    await activity.updateTyping(conversation, true);
    await activity.stopTyping();
    expect(typingFrames(), 2);
    await activity.updateTyping(conversation, true);
    await activity.stopTyping();
    expect(
      typingFrames(),
      4,
      reason: 'ikinci yazma turu aliciya hemen gorunmeli',
    );
  });
}
