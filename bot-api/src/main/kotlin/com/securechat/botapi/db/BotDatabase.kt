package com.securechat.botapi.db

import com.securechat.botapi.BotApiConfig
import com.zaxxer.hikari.HikariConfig
import com.zaxxer.hikari.HikariDataSource
import org.slf4j.LoggerFactory
import java.sql.Connection

private val log = LoggerFactory.getLogger("BotDatabase")

/**
 * PostgreSQL baglanti havuzu (HikariCP), bot-api icin.
 *
 * Bot-api Flyway CALISTIRMAZ — schema sahibi signaling-server. Startup'ta
 * api_client tablosunun varligini dogrular; yoksa fail-fast (V3 migration
 * henuz uygulanmamis demektir).
 */
object BotDatabase {

    private lateinit var dataSource: HikariDataSource

    fun init() {
        val config = HikariConfig().apply {
            jdbcUrl = BotApiConfig.databaseUrl
            username = BotApiConfig.databaseUser
            password = BotApiConfig.databasePassword
            driverClassName = "org.postgresql.Driver"
            maximumPoolSize = 10
            minimumIdle = 2
            connectionTimeout = 30_000
            idleTimeout = 600_000
            maxLifetime = 1_800_000
            leakDetectionThreshold = 60_000
            poolName = "bot-api-pool"
        }
        dataSource = HikariDataSource(config)
        log.info("[BotDB] Baglanti havuzu acildi: {}", BotApiConfig.databaseUrl)

        ensureSchemaReady()
    }

    /**
     * V3 migration uygulanmis mi kontrol et. signaling-server bot-api'den once
     * baslamali ve Flyway'i tamamlamali. Yoksa retry yerine durduruyoruz —
     * docker-compose depends_on healthcheck pattern'i bunu zaten ele aliyor.
     */
    private fun ensureSchemaReady() {
        try {
            getConnection().use { conn ->
                conn.prepareStatement("SELECT 1 FROM api_client LIMIT 0").use { it.execute() }
                conn.prepareStatement("SELECT 1 FROM bot_identity LIMIT 0").use { it.execute() }
                conn.prepareStatement("SELECT 1 FROM bot_signal_session LIMIT 0").use { it.execute() }
            }
            log.info("[BotDB] Schema kontrolu basarili — V3 tablolari mevcut")
        } catch (e: Exception) {
            log.error("[BotDB] V3 schema tablolari bulunamadi — signaling-server Flyway'i tamamlamamis olabilir")
            throw IllegalStateException(
                "bot-api startup: V3 migration (api_client/bot_identity/...) tablolari yok. " +
                "signaling-server'in V3'u uyguladigindan emin olun.", e
            )
        }
    }

    fun getConnection(): Connection = dataSource.connection

    fun isHealthy(): Boolean = try {
        getConnection().use { it.isValid(3) }
    } catch (_: Exception) { false }

    fun close() {
        if (::dataSource.isInitialized) {
            dataSource.close()
            log.info("[BotDB] Baglanti havuzu kapatildi")
        }
    }
}
