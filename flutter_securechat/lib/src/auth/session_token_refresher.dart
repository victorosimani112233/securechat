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
Future<String?> refreshSessionTokens({
  required SessionStore session,
  required AuthApi api,
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
    final TokenPair pair;
    try {
      pair = await api.refresh(refresh);
    } on AuthApiException catch (error) {
      if (error.statusCode != 401) rethrow;
      await session.expireCredentialsAndPersist();
      return null;
    }
    await session.updateTokensAndPersist(
      accessToken: pair.accessToken,
      refreshToken: pair.refreshToken,
    );
    return pair.accessToken;
  });
}
