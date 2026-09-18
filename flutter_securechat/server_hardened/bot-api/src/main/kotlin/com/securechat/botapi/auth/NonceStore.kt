package com.securechat.botapi.auth

import com.securechat.botapi.db.BotRedisManager
import com.securechat.botapi.delivery.BotQueuePrivacy
import redis.clients.jedis.params.SetParams

/**
 * JWT replay korumasi — her jti Redis'te 120 saniye tutulur.
 *
 * tryConsume(jti) ilk cagrida true, aynı jti icin ikinci cagrida false doner.
 * TTL otomatik temizlik saglar; ayrica DB tablosu yok.
 */
object NonceStore {

    private const val TTL_SECONDS = 120

    /**
     * @return jti ilk kez kullaniliyorsa true; replay (zaten kullanilmis) ise false.
     */
    fun tryConsume(jti: String): Boolean {
        require(jti.isNotBlank()) { "jti bos olamaz" }
        return BotRedisManager.use { jedis ->
            val result = jedis.set(
                "bot_jti_v2:${BotQueuePrivacy.blindIndex("nonce", jti)}",
                "1",
                SetParams.setParams().nx().ex(TTL_SECONDS.toLong())
            )
            result == "OK"
        }
    }
}
