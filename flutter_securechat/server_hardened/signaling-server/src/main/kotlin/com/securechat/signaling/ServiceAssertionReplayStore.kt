package com.securechat.signaling

import com.securechat.signaling.db.RedisManager
import org.slf4j.LoggerFactory
import redis.clients.jedis.params.SetParams

private val serviceReplayLog = LoggerFactory.getLogger("ServiceAssertionReplayStore")

/** Atomically consumes a signed service assertion's jti. */
object ServiceAssertionReplayStore {

    fun tryConsume(jti: String): Boolean {
        val key = keyFor(jti)
        return try {
            RedisManager.use { jedis ->
                jedis.set(
                    key,
                    "1",
                    SetParams.setParams().nx().ex(ServiceAssertion.REPLAY_TTL_SECONDS),
                ) == "OK"
            }
        } catch (error: Exception) {
            // Replay takibi yoksa servis assertion'i kabul edilmez.
            serviceReplayLog.error("[Service] Assertion replay store okunamadi (fail-closed)")
            false
        }
    }

    internal fun keyFor(jti: String): String =
        "service_assertion_v1:${ServerPrivacy.blindIndex("service-assertion-jti", jti)}"
}
