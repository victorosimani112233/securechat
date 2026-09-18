package com.securechat.signaling.db

import com.securechat.signaling.SecretSource
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
        password: String = SecretSource.required("DATABASE_PASSWORD")
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
        log.info("[DB] PostgreSQL baglanti havuzu baslatildi")
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
     *
     * `validateOnMigrate` acik: uygulanmis bir migration dosyasi sonradan
     * degisirse checksum uyusmazligi startup'i durdurur. Kapaliyken sema ile
     * kod sessizce ayrisabiliyordu ve bunu fark edecek hicbir kontrol yoktu.
     *
     * `baselineOnMigrate` yalniz bos/legacy bir veritabanini V0'a indirger.
     * Beklenmeyen bir semanin sessizce baseline sayilmamasi icin migration
     * sonrasi ulasilan surum ayrica dogrulanir.
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
                .validateOnMigrate(true)
                .load()
            val info = flyway.info()
            log.info("[DB] Flyway: {} migration bulundu, {} pending",
                info.all().size, info.pending().size)
            val result = flyway.migrate()
            log.info("[DB] Flyway: {} migration uygulandi (current version: {})",
                result.migrationsExecuted, result.targetSchemaVersion ?: "—")
            requireExpectedSchemaVersion(flyway)
        } catch (e: Exception) {
            log.error("[DB] Flyway migration hatasi: {}", e.javaClass.simpleName)
            throw e
        }
    }

    /**
     * Kodun bekledigi sema surumu ile veritabanindaki surum ayni olmalidir.
     *
     * Eksik migration sessizce "calisan ama yanlis sema" uretir; fazla surum
     * ise kodun bilmedigi bir sema demektir. Ikisi de startup'i durdurur.
     */
    private fun requireExpectedSchemaVersion(flyway: org.flywaydb.core.Flyway) {
        val applied = flyway.info().current()?.version?.version
        val expected = expectedSchemaVersion()
        check(applied != null) { "Flyway could not determine the applied schema version" }
        check(applied == expected) {
            "Schema version mismatch: database is at V$applied, this build expects V$expected"
        }
    }

    /**
     * Beklenen surum build manifestinden gelir; manifest de migration
     * klasorunun en yuksek surumunden turer. Boylece yeni bir migration
     * eklendiginde beklenti elle guncellenmek zorunda kalmaz.
     */
    private fun expectedSchemaVersion(): String =
        com.securechat.signaling.BuildManifest.migrationTarget.removePrefix("V")
}
