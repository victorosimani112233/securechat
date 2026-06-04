package com.securechat.botapi.send

import com.securechat.botapi.db.BotRedisManager
import redis.clients.jedis.params.SetParams

/**
 * Idempotency store — script ayni X-Idempotency-Key ile retry yaparsa
 * ayni response donulur, mesaj duplicate gonderilmez.
 *
 * Redis key: "bot_idem:<clientId>:<key>"
 * TTL: 24 saat
 *
 * State'ler:
 *   - PENDING   → istek isleniyor (henuz cevap yok); ikinci istege 409 don
 *   - <json>    → istek tamamlandi, cached response var; ayni cevabi don
 */
object IdempotencyStore {

    private const val TTL_SECONDS = 86400L

    sealed class CheckResult {
        /** Ilk kez gorulen; islem devam edebilir. */
        object Fresh : CheckResult()
        /** Hala isleniyor (PENDING). 409 don. */
        object Pending : CheckResult()
        /** Daha once tamamlanmis, cached response. */
        data class Cached(val responseJson: String) : CheckResult()
    }

    private fun key(clientId: String, idemKey: String) = "bot_idem:$clientId:$idemKey"

    /**
     * Ilk gorulen key icin PENDING reserve eder ve Fresh doner.
     * Zaten varsa state'i doner.
     */
    fun checkAndReserve(clientId: String, idemKey: String): CheckResult {
        require(idemKey.isNotBlank() && idemKey.length <= 128) { "Idempotency-Key 1-128 karakter" }
        val k = key(clientId, idemKey)
        return BotRedisManager.use { jedis ->
            val result = jedis.set(k, "PENDING", SetParams.setParams().nx().ex(TTL_SECONDS))
            if (result == "OK") {
                CheckResult.Fresh
            } else {
                val existing = jedis.get(k) ?: return@use CheckResult.Fresh
                if (existing == "PENDING") CheckResult.Pending
                else CheckResult.Cached(existing)
            }
        }
    }

    /** Islem tamamlandi — sonucu cache'le (24h). */
    fun storeResult(clientId: String, idemKey: String, responseJson: String) {
        BotRedisManager.use { jedis ->
            jedis.set(key(clientId, idemKey), responseJson, SetParams.setParams().ex(TTL_SECONDS))
        }
    }

    /** Hata oldu, PENDING'i sil — script ayni key ile retry edebilsin. */
    fun release(clientId: String, idemKey: String) {
        BotRedisManager.use { jedis ->
            jedis.del(key(clientId, idemKey))
        }
    }
}
