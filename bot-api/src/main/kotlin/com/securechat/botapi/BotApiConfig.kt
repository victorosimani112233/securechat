package com.securechat.botapi

import org.slf4j.LoggerFactory
import java.util.Base64

private val log = LoggerFactory.getLogger("BotApiConfig")

/**
 * Bot-api konfigurasyonu — env'den yuklenir, eksik zorunlu degerlerde fail-fast.
 * Tum tek erisim noktasi: BotApiConfig.load() main() basinda cagrilir.
 *
 * GUVENLIK: BOT_MASTER_KEY ve JWT_SECRET ham byte olarak tutulur; log'a yazilmaz.
 * NOT: lateinit var'larda Kotlin "private set" syntax'i kullanilamaz; bu object
 *      yalnizca BotApiConfig.load() icinde set ediliyor, runtime'da dis modifier
 *      kullanimi yok.
 */
object BotApiConfig {

    // --- Database ---
    lateinit var databaseUrl: String
    lateinit var databaseUser: String
    lateinit var databasePassword: String

    // --- Redis ---
    lateinit var redisHost: String
    var redisPort: Int = 6379
    var redisPassword: String? = null

    // --- Secrets ---
    /** signaling-server ile paylasilan HS256 secret — bot kendi access token'ini bununla mintler. */
    lateinit var jwtSecret: ByteArray
    /** Bot'un identity private key'ini AES-256-GCM ile saran 32 byte master key. */
    lateinit var botMasterKey: ByteArray
    /** Admin Unix socket uzerinden gelen istekleri dogrulamak icin token. */
    lateinit var botAdminToken: String

    // --- Signaling-server endpoints (internal Docker network) ---
    lateinit var signalingInternalUrl: String
    lateinit var signalingWsUrl: String

    // --- Listener paths ---
    lateinit var publicSocketPath: String
    lateinit var adminSocketPath: String
    var healthPort: Int = 8090

    // --- Logging ---
    lateinit var logLevel: String

    /**
     * Env'i parse et, zorunlu degerleri dogrula, fail-fast.
     * @throws IllegalStateException eksik veya gecersiz secret durumunda
     */
    fun load() {
        databaseUrl = req("DATABASE_URL", "jdbc:postgresql://postgres:5432/securechat")
        databaseUser = req("DATABASE_USER", "securechat")
        databasePassword = reqSecret("DATABASE_PASSWORD")

        redisHost = req("REDIS_HOST", "redis")
        redisPort = opt("REDIS_PORT", "6379").toInt()
        redisPassword = System.getenv("REDIS_PASSWORD")?.takeIf { it.isNotBlank() }

        // JWT_SECRET — signaling-server ile ayni, bot kendi token'ini bununla uretir
        val jwt = reqSecret("JWT_SECRET")
        require(jwt.length >= 32) { "JWT_SECRET en az 32 karakter olmali (ham byte)" }
        jwtSecret = jwt.toByteArray(Charsets.UTF_8)

        // BOT_MASTER_KEY — 32 byte (base64'lu env'den decode)
        val masterB64 = reqSecret("BOT_MASTER_KEY")
        val decoded = try {
            Base64.getDecoder().decode(masterB64.trim())
        } catch (e: Exception) {
            throw IllegalStateException("BOT_MASTER_KEY base64 decode hatasi", e)
        }
        require(decoded.size == 32) { "BOT_MASTER_KEY decode sonrasi 32 byte olmali (${decoded.size} byte bulundu)" }
        botMasterKey = decoded

        botAdminToken = reqSecret("BOT_ADMIN_TOKEN").also {
            require(it.length >= 32) { "BOT_ADMIN_TOKEN en az 32 karakter olmali" }
        }

        signalingInternalUrl = req("SIGNALING_INTERNAL_URL", "http://backend:8080")
        signalingWsUrl = req("SIGNALING_WS_URL", "ws://backend:8080/ws")

        publicSocketPath = req("BOT_PUBLIC_SOCKET", "/run/bot/bot-public.sock")
        adminSocketPath = req("BOT_ADMIN_SOCKET", "/run/bot/bot-admin.sock")
        healthPort = opt("BOT_HEALTH_PORT", "8090").toInt()

        logLevel = opt("LOG_LEVEL", "INFO")

        log.info("[Config] Bot-api konfigurasyonu yuklendi (db={}, redis={}:{}, healthPort={})",
            databaseUrl, redisHost, redisPort, healthPort)
        log.info("[Config] Listener'lar: public={}, admin={}", publicSocketPath, adminSocketPath)
    }

    private fun req(name: String, default: String): String =
        System.getenv(name)?.takeIf { it.isNotBlank() } ?: default

    private fun opt(name: String, default: String): String =
        System.getenv(name)?.takeIf { it.isNotBlank() } ?: default

    /** Zorunlu secret — env'de YOK ise process'i durdur. */
    private fun reqSecret(name: String): String =
        System.getenv(name)?.takeIf { it.isNotBlank() }
            ?: throw IllegalStateException("$name env degiskeni zorunlu (set edilmemis)")
}
