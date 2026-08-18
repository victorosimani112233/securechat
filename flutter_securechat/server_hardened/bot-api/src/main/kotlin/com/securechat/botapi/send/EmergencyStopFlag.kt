package com.securechat.botapi.send

import com.securechat.botapi.db.BotDatabase
import org.slf4j.LoggerFactory

private val log = LoggerFactory.getLogger("EmergencyStopFlag")

/**
 * Global emergency stop. Admin `bot-admin emergency-stop` calistirinca
 * durum set edilir ve tum `/v1/send` istekleri reddedilir.
 *
 * Durum PostgreSQL'dedir. Onceki tasarim TTL'siz tek bir Redis key'iydi;
 * o Redis bilerek persistence'siz ve `allkeys-lru` calistigi icin bir
 * restart veya bellek baskisi durdurmayi kendiliginden kaldirabiliyordu.
 * Acil durum kontrolu ancak acikca temizlenene kadar surdugunde anlamlidir.
 *
 * Okuma cache'lenmez: birkac saniyelik bayat bir "acik" cevabi tam da
 * durdurmanin engellemesi gereken pencereyi geri acardi.
 */
object EmergencyStopFlag {

    /** Depolama okunamiyorsa gonderim durdurulmus sayilir (fail-closed). */
    fun isTripped(): Boolean =
        try {
            BotDatabase.getConnection().use { connection ->
                connection.prepareStatement(
                    "SELECT emergency_stop FROM bot_control WHERE id = 1",
                ).use { statement ->
                    statement.executeQuery().use { rows ->
                        if (rows.next()) rows.getBoolean("emergency_stop") else true
                    }
                }
            }
        } catch (_: Exception) {
            log.error("[EmergencyStop] Durum okunamadi (fail-closed)")
            true
        }

    fun set() = write(true)

    fun clear() = write(false)

    private fun write(tripped: Boolean) {
        BotDatabase.getConnection().use { connection ->
            connection.prepareStatement(
                """INSERT INTO bot_control(id, emergency_stop) VALUES (1, ?)
                   ON CONFLICT (id) DO UPDATE SET emergency_stop = EXCLUDED.emergency_stop""",
            ).use { statement ->
                statement.setBoolean(1, tripped)
                statement.executeUpdate()
            }
        }
    }
}
