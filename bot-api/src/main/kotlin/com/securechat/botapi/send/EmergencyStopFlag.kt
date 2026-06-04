package com.securechat.botapi.send

import com.securechat.botapi.db.BotRedisManager

/**
 * Global emergency stop. Admin "bot-admin emergency-stop" calistirinca
 * Redis'te bu key set edilir; tum /v1/send istekleri 503 doner.
 *
 * Redis key: "bot_api:emergency_stop" (varligi yetiyor; deger onemli degil)
 */
object EmergencyStopFlag {

    private const val KEY = "bot_api:emergency_stop"

    fun isTripped(): Boolean = BotRedisManager.use { jedis -> jedis.exists(KEY) }

    fun set() { BotRedisManager.use { it.set(KEY, "1") } }

    fun clear() { BotRedisManager.use { it.del(KEY) } }
}
