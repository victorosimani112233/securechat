import '../crypto/vodozemac/olm_pre_key_publisher.dart';
import '../services/session_store.dart';
import 'auth_api.dart';

/// Access token'i refresh token ile yeniler; on plan ve arka plan ayni
/// yolu kullanir.
///
/// Yenileme isolate'ler ARASI sirali kosar. Refresh token tek kullanimlik:
/// sunucu her yenilemede generation'i donduruyor, yani iki isolate ayni
/// anda yenilerse birinin token'i KALICI olarak olur. Kilidi alan taraf
/// once diske bakar; token zaten degismisse hic yenilemez, digerinin
/// sonucunu kullanir.
///
/// Sunucu refresh token'i 401 ile reddederse oturum kalici olarak bitmistir
/// (QA 2026-10-12 R1): tokenlar silinir, oturum "suresi doldu" olarak
/// isaretlenir ve `null` doner. Ayni olu token'la tekrar tekrar denenmez.
/// Ag hatasi ve 503 gibi gecici hatalar oturumu korur ve hatayi iletir.
///
/// 401'den once [deviceKey] ile cihaz anahtari yolu denenir (QA 2026-10-13
/// R3 madde 3): yenileme yaniti kaybolup token sunucuda olduyse cihazdaki
/// Olm kimligi oturumu geri getirir. Bu yol da 401 alirsa (logout,
/// kurtarma, baska anahtar) oturum biter; gecici hatada oturum korunur ve
/// sonraki denemede yol yeniden denenir.
Future<String?> refreshSessionTokens({
  required SessionStore session,
  required AuthApi api,
  RecoveryIdentity? deviceKey,
}) {
  final failed = session.accessToken;
  return session.withRefreshLock(() async {
    await session.reloadFromDisk();
    final current = session.accessToken;
    // Kilidi beklerken baskasi yeniledi: onun sonucunu kullan, token'i
    // bir kez daha dondurme.
    if (current != null && current.isNotEmpty && current != failed) {
      return current;
    }
    final refresh = session.refreshToken;
    if (refresh == null || refresh.isEmpty) return null;
    TokenPair pair;
    try {
      pair = await api.refresh(refresh);
    } on AuthApiException catch (error) {
      if (error.statusCode != 401) rethrow;
      final restored = await _reauthenticateWithDevice(
        session: session,
        api: api,
        deviceKey: deviceKey,
        refreshToken: refresh,
      );
      if (restored == null) {
        await session.expireCredentialsAndPersist();
        return null;
      }
      pair = restored;
    }
    await session.updateTokensAndPersist(
      accessToken: pair.accessToken,
      refreshToken: pair.refreshToken,
    );
    return pair.accessToken;
  });
}

/// @return yeni cift; cihaz yolu yoksa ya da sunucu reddettiyse null.
/// Gecici hatalar (ag, 503, 429) iletilir.
Future<TokenPair?> _reauthenticateWithDevice({
  required SessionStore session,
  required AuthApi api,
  required RecoveryIdentity? deviceKey,
  required String refreshToken,
}) async {
  final userId = session.userId;
  if (deviceKey == null || userId == null) return null;
  try {
    if (await deviceKey.recoverySigningPublicKey() == null) return null;
    return await api.reauthenticateWithDevice(
      userId: userId,
      refreshToken: refreshToken,
      sign: deviceKey.signRecoveryProof,
    );
  } on AuthApiException catch (error) {
    // 404: cihaz yolunu bilmeyen eski sunucu. Gecici sayilirsa olu oturum
    // hic bitmez ve her yenilemede yeniden denenirdi.
    if (error.statusCode == 401 || error.statusCode == 404) return null;
    rethrow;
  }
}
