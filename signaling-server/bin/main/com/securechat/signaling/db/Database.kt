package com.securechat.signaling.db

import com.zaxxer.hikari.HikariConfig
import com.zaxxer.hikari.HikariDataSource
import java.sql.Connection
import org.slf4j.LoggerFactory

private val log = LoggerFactory.getLogger("Database")

/**
 * PostgreSQL baglanti havuzu (HikariCP).
 * Tum DB erisimi bu sinif uzerinden yapilir.
 */
object Database {

    private lateinit var dataSource: HikariDataSource

    fun init(
        jdbcUrl: String = System.getenv("DATABASE_URL") ?: "jdbc:postgresql://localhost:5432/securechat",
        user: String = System.getenv("DATABASE_USER") ?: "securechat",
        password: String = System.getenv("DATABASE_PASSWORD") ?: ""
    ) {
        val config = HikariConfig().apply {
            this.jdbcUrl = jdbcUrl
            this.username = user
            this.password = password
            this.driverClassName = "org.postgresql.Driver"
            maximumPoolSize = 20
            minimumIdle = 5
            connectionTimeout = 30_000
            idleTimeout = 600_000
            maxLifetime = 1_800_000
            leakDetectionThreshold = 60_000
            poolName = "securechat-pool"
        }
        dataSource = HikariDataSource(config)
        log.info("[DB] PostgreSQL baglanti havuzu baslatildi ($jdbcUrl)")
    }

    fun getConnection(): Connection = dataSource.connection

    fun isHealthy(): Boolean {
        return try {
            getConnection().use { it.isValid(3) }
        } catch (_: Exception) {
            false
        }
    }

    fun close() {
        if (::dataSource.isInitialized) {
            dataSource.close()
            log.info("[DB] Baglanti havuzu kapatildi")
        }
    }

    /**
     * Flyway ile schema migration calistir.
     * Migrations: src/main/resources/db/migration/V*.sql
     *
     * baselineOnMigrate=true: mevcut tablolari olan DB'ler icin baseline'a indirgenir,
     * sonraki migration'lar uygulanir.
     */
    fun ensureSchema() {
        try {
            val flyway = org.flywaydb.core.Flyway.configure()
                .dataSource(dataSource)
                .baselineOnMigrate(true)
                .baselineVersion(org.flywaydb.core.api.MigrationVersion.fromVersion("0"))
                // Classpath search — fat JAR'da resources/db/migration altinda
                .locations("classpath:db/migration")
                .table("flyway_schema_history")
                .validateOnMigrate(false)
                .load()
            val info = flyway.info()
            log.info("[DB] Flyway: {} migration bulundu, {} pending",
                info.all().size, info.pending().size)
            val result = flyway.migrate()
            log.info("[DB] Flyway: {} migration uygulandi (current version: {})",
                result.migrationsExecuted, result.targetSchemaVersion ?: "—")
        } catch (e: Exception) {
            log.error("[DB] Flyway migration hatasi: {}", e.message, e)
            throw e
        }
    }
}
