package com.securechat.signaling

import com.securechat.signaling.db.Database
import java.security.SecureRandom
import org.slf4j.LoggerFactory

private val log = LoggerFactory.getLogger("CredentialState")

/**
 * Durable authentication invalidation state.
 *
 * Onceki tasarimda logout/revoke bilgisi yalniz persistence'siz ve
 * `allkeys-lru` calisan Redis'teydi; restart veya eviction iptal edilmis bir
 * credential'i yeniden gecerli kiliyordu. Burada state PostgreSQL'dedir:
 * restart, eviction ve failover sonrasi ayni kalir.
 *
 * Iki opaque rastgele deger tutulur:
 *
 *  - `credential_epoch` her token'a gomulur. Logout bunu dondurur ve hesabin
 *    tum access/refresh token'lari ayni anda gecersizlesir.
 *  - `refresh_generation` yalniz refresh token'a gomulur ve her rotasyonda
 *    atomik olarak degisir. Supersede edilmis bir refresh token'in yeniden
 *    kullanilmasi (token reuse) bu yuzden fail-closed olur.
 *
 * Hesabin `users` satiri yoksa hicbir token gecerli degildir; silinen hesap
 * icin ayrica bir "revoked" kaydi tutmaya gerek kalmaz.
 */
object CredentialState {

    private val random = SecureRandom()

    /**
     * Her istekte DB'ye gitmemek icin cok kisa omurlu bir RAM kopyasi.
     *
     * Bu process tek yazicidir: rotasyon ve hesap silme girisi hemen
     * gecersiz kilar, yani ayni instance icinde etki aninda gorunur. TTL
     * yalniz disaridan yapilmis bir degisiklige karsi ust sinirdir.
     */
    private const val CACHE_TTL_MS = 10_000L

    private class CachedSnapshot(val snapshot: Snapshot?, val loadedAtMs: Long)

    private val cache = java.util.concurrent.ConcurrentHashMap<String, CachedSnapshot>()

    class Snapshot(val credentialEpoch: String, val refreshGeneration: String)

    /** Rotasyon veya hesap silme sonrasi cached kopyayi dusurur. */
    fun forget(userId: String) {
        cache.remove(userId)
    }

    internal fun clearCache() {
        cache.clear()
    }

    fun cachedSnapshot(userId: String): Snapshot? {
        val now = System.currentTimeMillis()
        val cached = cache[userId]
        if (cached != null && now - cached.loadedAtMs < CACHE_TTL_MS) return cached.snapshot
        val loaded = snapshot(userId)
        cache[userId] = CachedSnapshot(loaded, now)
        return loaded
    }

    fun snapshot(userId: String): Snapshot? =
        Database.getConnection().use { connection ->
            connection.prepareStatement(
                "SELECT credential_epoch, refresh_generation FROM users WHERE user_id = ?::uuid",
            ).use { statement ->
                statement.setString(1, userId)
                statement.executeQuery().use { rows ->
                    if (!rows.next()) {
                        null
                    } else {
                        Snapshot(
                            credentialEpoch = rows.getString("credential_epoch"),
                            refreshGeneration = rows.getString("refresh_generation"),
                        )
                    }
                }
            }
        }

    /** Hesabin butun token'larini gecersiz kilar; yeni epoch degerini doner. */
    fun rotateCredentialEpoch(userId: String): String? {
        val next = newValue()
        return Database.getConnection().use { connection ->
            connection.prepareStatement(
                """UPDATE users
                   SET credential_epoch = ?, refresh_generation = ?
                   WHERE user_id = ?::uuid
                   RETURNING credential_epoch""",
            ).use { statement ->
                statement.setString(1, next)
                statement.setString(2, newValue())
                statement.setString(3, userId)
                statement.executeQuery().use { rows ->
                    if (rows.next()) rows.getString("credential_epoch") else null
                }.also { forget(userId) }
            }
        }
    }

    /**
     * Refresh rotasyonunu tek atomik adimda yapar.
     *
     * Compare-and-set oldugu icin ayni eski token ile paralel iki istek
     * gonderilse bile en fazla biri yeni bir aile uretebilir; digeri
     * `null` alir ve reddedilir.
     */
    fun rotateRefreshGeneration(userId: String, presentedGeneration: String): Snapshot? {
        val next = newValue()
        return Database.getConnection().use { connection ->
            connection.prepareStatement(
                """UPDATE users
                   SET refresh_generation = ?
                   WHERE user_id = ?::uuid AND refresh_generation = ?
                   RETURNING credential_epoch, refresh_generation""",
            ).use { statement ->
                statement.setString(1, next)
                statement.setString(2, userId)
                statement.setString(3, presentedGeneration)
                statement.executeQuery().use { rows ->
                    if (!rows.next()) {
                        null
                    } else {
                        Snapshot(
                            credentialEpoch = rows.getString("credential_epoch"),
                            refreshGeneration = rows.getString("refresh_generation"),
                        )
                    }
                }.also { forget(userId) }
            }
        }
    }

    private fun newValue(): String {
        val bytes = ByteArray(16)
        random.nextBytes(bytes)
        return bytes.joinToString("") { "%02x".format(it) }
    }

    fun initialize() {
        log.info("[Auth] Durable credential state hazir")
    }
}
