package com.securechat.botapi.send

import com.securechat.botapi.BotApiConfig
import com.securechat.botapi.db.BotRedisManager
import com.securechat.botapi.delivery.BotQueuePrivacy
import redis.clients.jedis.params.SetParams

/**
 * Idempotency store — script ayni X-Idempotency-Key ile retry yaparsa
 * ayni response donulur, mesaj duplicate gonderilmez.
 *
 * Redis key and completed response are opaque/encrypted at rest.
 * TTL privacy-first varsayilanla 1 saattir; production config 24 saatlik sert
 * ust siniri asamaz.
 *
 * State'ler:
 *   - PENDING   → istek isleniyor (henuz cevap yok); ikinci istege 409 don
 *   - <json>    → istek tamamlandi, cached response var; ayni cevabi don
 */
object IdempotencyStore {

    sealed class CheckResult {
        /** Ilk kez gorulen; islem devam edebilir. */
        object Fresh : CheckResult()
        /** Hala isleniyor (PENDING). 409 don. */
        object Pending : CheckResult()
        /** Daha once tamamlanmis, cached response. */
        data class Cached(val responseJson: String) : CheckResult()
    }

    private fun binding(clientId: String, idemKey: String) = "$clientId\u0000$idemKey"

    private fun key(clientId: String, idemKey: String) =
        "bot_idem_v2:${BotQueuePrivacy.blindIndex("idempotency", binding(clientId, idemKey))}"

    /**
     * Ilk gorulen key icin PENDING reserve eder ve Fresh doner.
     * Zaten varsa state'i doner.
     */
    fun checkAndReserve(clientId: String, idemKey: String): CheckResult {
        require(idemKey.isNotBlank() && idemKey.length <= 128) { "Idempotency-Key 1-128 karakter" }
        val k = key(clientId, idemKey)
        return BotRedisManager.use { jedis ->
            val result = jedis.set(
                k,
                "PENDING",
                SetParams.setParams().nx().ex(BotApiConfig.idempotencyTtlSeconds)
            )
            if (result == "OK") {
                CheckResult.Fresh
            } else {
                val existing = jedis.get(k) ?: return@use CheckResult.Fresh
                if (existing == "PENDING") {
                    CheckResult.Pending
                } else {
                    val opened = try {
                        BotQueuePrivacy.openPrivate(
                            "idempotency",
                            binding(clientId, idemKey),
                            existing
                        )
                    } catch (_: Exception) {
                        // Never return legacy/plaintext cache values.
                        jedis.del(k)
                        val reclaimed = jedis.set(
                            k,
                            "PENDING",
                            SetParams.setParams().nx().ex(BotApiConfig.idempotencyTtlSeconds)
                        )
                        return@use if (reclaimed == "OK") {
                            CheckResult.Fresh
                        } else {
                            CheckResult.Pending
                        }
                    }
                    CheckResult.Cached(opened)
                }
            }
        }
    }

    /** Islem tamamlandi — sonucu ayni bounded privacy TTL ile cache'le. */
    fun storeResult(clientId: String, idemKey: String, responseJson: String) {
        BotRedisManager.use { jedis ->
            val sealed = BotQueuePrivacy.sealPrivate(
                "idempotency",
                binding(clientId, idemKey),
                responseJson
            )
            jedis.set(
                key(clientId, idemKey),
                sealed,
                SetParams.setParams().ex(BotApiConfig.idempotencyTtlSeconds)
            )
        }
    }

    /** Hata oldu, PENDING'i sil — script ayni key ile retry edebilsin. */
    fun release(clientId: String, idemKey: String) {
        BotRedisManager.use { jedis ->
            jedis.del(key(clientId, idemKey))
        }
    }
}
