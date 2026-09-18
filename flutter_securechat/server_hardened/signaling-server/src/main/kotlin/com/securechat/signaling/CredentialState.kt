package com.securechat.signaling

import com.securechat.signaling.db.Database
import com.securechat.signaling.db.RedisManager
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

    /**
     * Onbellek ust siniri.
     *
     * Girdiler yalniz ustlerine yazildiginda yenilenirdi; bir kez baglanip
     * bir daha donmeyen her hesap kalici bir satir birakiyordu. Sinir asilinca
     * suresi dolmus girdiler toplanir, yine de yer yoksa onbellek bosaltilir:
     * en kotu durumda bir tur DB okumasi olur, dogruluk degismez.
     */
    private const val MAX_CACHED_ACCOUNTS = 50_000

    private val cache = java.util.concurrent.ConcurrentHashMap<String, CachedSnapshot>()

    class Snapshot(val credentialEpoch: String, val refreshGeneration: String)

    /**
     * Diger signaling instance'larina credential iptalini duyuran kanal.
     *
     * Epoch onbellegi process-yereldir ve CACHE_TTL_MS kadar tutulur; yatay
     * olceklenmis bir dagitimda logout/silme yapan instance kendi kopyasini
     * dusurur ama digerleri iptal edilmis bir access token'i TTL boyunca
     * kabul etmeye devam ederdi (whitebox bulgu). Yayin bu pencereyi ag
     * yayilim gecikmesine indirir.
     */
    private const val INVALIDATE_CHANNEL = "signaling:credential_invalidate"

    /** Rotasyon veya hesap silme sonrasi cached kopyayi dusurur. */
    fun forget(userId: String) {
        cache.remove(userId)
    }

    /** Yerel kopyayi dusurur ve butun instance'lara iptali yayar. */
    fun invalidateEverywhere(userId: String) {
        forget(userId)
        broadcastInvalidate(userId)
    }

    /**
     * Iptali diger instance'lara yayar. Yayin basarisiz olsa bile guvenlik
     * bozulmaz: en kotu ihtimalle diger instance'lar eski TTL davranisina
     * (<=10s) doner; bu yuzden hata yutulur, credential bypass'a cevrilmez.
     */
    fun broadcastInvalidate(userId: String) {
        try {
            RedisManager.use { it.publish(INVALIDATE_CHANNEL, userId) }
        } catch (error: Exception) {
            log.warn("[Auth] Credential invalidation yayini basarisiz: {}", error.javaClass.simpleName)
        }
    }

    @Volatile
    private var subscriberThread: Thread? = null

    @Volatile
    private var subscribedLatch: java.util.concurrent.CountDownLatch? = null

    /**
     * Iptal kanalini dinleyen kalici abone. Her mesajda ilgili hesabin
     * yerel epoch kopyasi dusurulur; sonraki kontrol DB'den taze epoch'u
     * okur ve iptal edilmis token reddedilir.
     */
    @Synchronized
    fun startInvalidationSubscriber() {
        if (subscriberThread != null) return
        val latch = java.util.concurrent.CountDownLatch(1)
        subscribedLatch = latch
        val pubSub = object : redis.clients.jedis.JedisPubSub() {
            override fun onMessage(channel: String, message: String) {
                forget(message)
            }

            override fun onSubscribe(channel: String, subscribedChannels: Int) {
                latch.countDown()
            }
        }
        val thread = Thread {
            while (!Thread.currentThread().isInterrupted) {
                try {
                    RedisManager.subscribe(pubSub, INVALIDATE_CHANNEL)
                } catch (error: Exception) {
                    log.warn("[Auth] Invalidation abonesi koptu, yeniden baglanilacak: {}",
                        error.javaClass.simpleName)
                    try {
                        Thread.sleep(1_000)
                    } catch (_: InterruptedException) {
                        Thread.currentThread().interrupt()
                    }
                }
            }
        }
        thread.isDaemon = true
        thread.name = "credential-invalidation-subscriber"
        thread.start()
        subscriberThread = thread
        log.info("[Auth] Credential invalidation abonesi baslatildi")
    }

    internal fun clearCache() {
        cache.clear()
    }

    /** Yalniz test: bir hesabin RAM kopyasi var mi. */
    internal fun isCached(userId: String): Boolean = cache.containsKey(userId)

    /** Yalniz test: abone kanala baglanana kadar bekler. */
    internal fun awaitSubscriberReady(timeoutMillis: Long): Boolean =
        subscribedLatch?.await(timeoutMillis, java.util.concurrent.TimeUnit.MILLISECONDS) ?: false

    fun cachedSnapshot(userId: String): Snapshot? {
        val now = System.currentTimeMillis()
        val cached = cache[userId]
        if (cached != null && now - cached.loadedAtMs < CACHE_TTL_MS) return cached.snapshot
        val loaded = snapshot(userId)
        if (cache.size >= MAX_CACHED_ACCOUNTS) evictStaleEntries(now)
        cache[userId] = CachedSnapshot(loaded, now)
        return loaded
    }

    private fun evictStaleEntries(nowMs: Long) {
        cache.entries.removeIf { (_, cached) -> nowMs - cached.loadedAtMs >= CACHE_TTL_MS }
        if (cache.size >= MAX_CACHED_ACCOUNTS) cache.clear()
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
                }.also { invalidateEverywhere(userId) }
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
