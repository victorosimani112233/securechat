import 'package:flutter_securechat/src/chat/chat_activity_service.dart';
import 'package:flutter_securechat/src/core/models.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';

/// Her kontrol paketi trafik analizi direnci icin sabit 16 KiB'a padlenir ve
/// tel uzerinde ~29 KB'a cikar. Yaziyor-gostergesinin basla/dur dongusu her
/// turda iki paket demektir; araliklarla yazan bir kullanici bunu surekli
/// tetikler. Paket BOYUTU gizlilik ozelligi oldugu icin degistirilmedi;
/// bunun yerine gonderim SIKLIGI dusuruldu.
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
  int typingFrames() => signaling.sentMessages
      .whereType<EncryptedSignalMessage>()
      .length;

  Future<void> setUpService({
    Future<bool> Function()? metered,
    Duration cooldown = const Duration(seconds: 12),
  }) async {
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
      isMeteredConnection: metered,
      reannounceCooldown: cooldown,
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

  test('cooldown icinde yeniden duyuru yapilmaz', () async {
    await setUpService();
    await activity.updateTyping(conversation, true);
    await activity.stopTyping();
    final afterFirstBurst = typingFrames(); // start + stop = 2
    expect(afterFirstBurst, 2);

    // Hemen tekrar yazmaya basla: cooldown icinde oldugu icin yeni duyuru yok.
    await activity.updateTyping(conversation, true);
    await activity.stopTyping();
    expect(
      typingFrames(),
      afterFirstBurst,
      reason: 'cooldown icindeki dongu ek paket uretmemeli',
    );
  });

  test('cooldown dolunca yeniden duyurulur', () async {
    await setUpService(cooldown: Duration.zero);
    await activity.updateTyping(conversation, true);
    await activity.stopTyping();
    await activity.updateTyping(conversation, true);
    await activity.stopTyping();
    expect(typingFrames(), 4, reason: 'cooldown sifirken normal davranmali');
  });

  test('sayacli baglantida hic gonderilmez', () async {
    await setUpService(metered: () async => true);
    for (var i = 0; i < 5; i++) {
      await activity.updateTyping(conversation, true);
    }
    await activity.stopTyping();
    expect(typingFrames(), 0, reason: 'mobil veride gosterge kapali olmali');
  });
}
