package com.securechat.botapi

import org.slf4j.LoggerFactory
import java.util.Base64

private val log = LoggerFactory.getLogger("BotApiConfig")

/**
 * Bot-api konfigurasyonu — env'den yuklenir, eksik zorunlu degerlerde fail-fast.
 * Tum tek erisim noktasi: BotApiConfig.load() main() basinda cagrilir.
 *
 * GUVENLIK: BOT_MASTER_KEY ham byte olarak tutulur; log'a yazilmaz. Bot,
 * signaling'in kullanici token'larini imzalayan secret'i TASIMAZ; kendi
 * Ed25519 servis anahtariyla dar kapsamli assertion uretir.
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
    /**
     * Bot'un servis kimligini imzaladigi Ed25519 private key'i. Signaling
     * yalniz karsilik gelen public key'i tutar; bu materyal kullanici
     * token'i uretemez.
     */
    lateinit var serviceSigningKey: java.security.PrivateKey
    /** Bot'un identity private key'ini AES-256-GCM ile saran 32 byte master key. */
    lateinit var botMasterKey: ByteArray
    /** Dedicated AES key for short-lived Redis outbound envelopes. */
    lateinit var botQueueEncryptionKey: ByteArray
    /** Shared keyed-index material; never reuse as an encryption key. */
    lateinit var privacyIndexKey: ByteArray
    var outboundQueueTtlSeconds: Long = 900
    var idempotencyTtlSeconds: Long = 900
    var allowLegacyPlaintextQueue: Boolean = false
    /** Admin Unix socket uzerinden gelen istekleri dogrulamak icin token. */
    lateinit var botAdminToken: String
    lateinit var metricsBearerToken: ByteArray

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
        redisPassword = SecretSource.optional("REDIS_PASSWORD")

        // BOT_SERVICE_PRIVATE_KEY — base64 PKCS#8 Ed25519. Signaling'in
        // JWT_SECRET'i bot process'ine hic girmez.
        serviceSigningKeyMaterial = decodeServiceKey(reqSecret("BOT_SERVICE_PRIVATE_KEY"))
        serviceSigningKey = java.security.KeyFactory.getInstance("Ed25519")
            .generatePrivate(java.security.spec.PKCS8EncodedKeySpec(serviceSigningKeyMaterial))

        // BOT_MASTER_KEY — 32 byte (base64'lu env'den decode)
        val masterB64 = reqSecret("BOT_MASTER_KEY")
        val decoded = decodeKey("BOT_MASTER_KEY", masterB64)
        botMasterKey = decoded

        botQueueEncryptionKey = decodeKey(
            "BOT_QUEUE_ENCRYPTION_KEY",
            reqSecret("BOT_QUEUE_ENCRYPTION_KEY")
        )
        privacyIndexKey = decodeKey(
            "PRIVACY_INDEX_KEY",
            reqSecret("PRIVACY_INDEX_KEY")
        )
        require(!botQueueEncryptionKey.contentEquals(privacyIndexKey)) {
            "BOT_QUEUE_ENCRYPTION_KEY ve PRIVACY_INDEX_KEY farkli olmali"
        }
        require(!botQueueEncryptionKey.contentEquals(botMasterKey)) {
            "BOT_QUEUE_ENCRYPTION_KEY ve BOT_MASTER_KEY farkli olmali"
        }
        outboundQueueTtlSeconds = opt("BOT_OUTBOUND_TTL_SECONDS", "900")
            .toLongOrNull()
            ?.also { require(it in 60L..3_600L) { "BOT_OUTBOUND_TTL_SECONDS 60..3600 olmali" } }
            ?: error("BOT_OUTBOUND_TTL_SECONDS integer olmali")
        idempotencyTtlSeconds = opt("BOT_IDEMPOTENCY_TTL_SECONDS", "900")
            .toLongOrNull()
            ?.also { require(it in 60L..3_600L) { "BOT_IDEMPOTENCY_TTL_SECONDS 60..3600 olmali" } }
            ?: error("BOT_IDEMPOTENCY_TTL_SECONDS integer olmali")
        allowLegacyPlaintextQueue =
            System.getenv("ALLOW_LEGACY_PLAINTEXT_QUEUE")?.equals("true", ignoreCase = true) == true

        botAdminToken = reqSecret("BOT_ADMIN_TOKEN").also {
            require(it.length >= 32) { "BOT_ADMIN_TOKEN en az 32 karakter olmali" }
        }
        metricsBearerToken = reqSecret("BOT_METRICS_BEARER_TOKEN").also {
            require(it.length >= 32) { "BOT_METRICS_BEARER_TOKEN en az 32 karakter olmali" }
        }.toByteArray(Charsets.UTF_8)
        requirePurposeSeparatedSecrets()

        signalingInternalUrl = req("SIGNALING_INTERNAL_URL", "http://backend:8080")
        signalingWsUrl = req("SIGNALING_WS_URL", "ws://backend:8080/ws")

        publicSocketPath = req("BOT_PUBLIC_SOCKET", "/run/bot/bot-public.sock")
        adminSocketPath = req("BOT_ADMIN_SOCKET", "/run/bot/bot-admin.sock")
        healthPort = opt("BOT_HEALTH_PORT", "8090").toInt()

        val requestedLogLevel = System.getenv("LOG_LEVEL")?.trim()?.uppercase()
        require(requestedLogLevel == null || requestedLogLevel in setOf("ERROR", "OFF")) {
            "Hardened bot-api LOG_LEVEL yalniz ERROR veya OFF olabilir"
        }
        logLevel = requestedLogLevel ?: "ERROR"

        log.info("[Config] Bot-api konfigurasyonu yuklendi")
    }

    private fun req(name: String, default: String): String =
        System.getenv(name)?.takeIf { it.isNotBlank() } ?: default

    private fun opt(name: String, default: String): String =
        System.getenv(name)?.takeIf { it.isNotBlank() } ?: default

    /** Zorunlu secret — read-only NAME_FILE veya legacy NAME girdisi. */
    private fun reqSecret(name: String): String = SecretSource.required(name)

    /** Purpose-separation kontrolu icin ham anahtar materyali. */
    private lateinit var serviceSigningKeyMaterial: ByteArray

    private fun decodeServiceKey(encoded: String): ByteArray {
        val decoded = try {
            Base64.getDecoder().decode(encoded.trim())
        } catch (e: Exception) {
            throw IllegalStateException("BOT_SERVICE_PRIVATE_KEY base64 decode hatasi", e)
        }
        require(decoded.size >= 48) {
            "BOT_SERVICE_PRIVATE_KEY PKCS#8 Ed25519 anahtari olmali"
        }
        return decoded
    }

    private fun decodeKey(name: String, encoded: String): ByteArray {
        val decoded = try {
            Base64.getDecoder().decode(encoded.trim())
        } catch (e: Exception) {
            throw IllegalStateException("$name base64 decode hatasi", e)
        }
        require(decoded.size == 32) {
            "$name decode sonrasi tam 32 byte olmali (${decoded.size} byte bulundu)"
        }
        return decoded
    }

    private fun requirePurposeSeparatedSecrets() {
        val values = linkedMapOf(
            "BOT_SERVICE_PRIVATE_KEY" to serviceSigningKeyMaterial,
            "BOT_MASTER_KEY" to botMasterKey,
            "BOT_QUEUE_ENCRYPTION_KEY" to botQueueEncryptionKey,
            "PRIVACY_INDEX_KEY" to privacyIndexKey,
            "BOT_ADMIN_TOKEN" to botAdminToken.toByteArray(Charsets.UTF_8),
            "BOT_METRICS_BEARER_TOKEN" to metricsBearerToken,
        )
        val seen = mutableMapOf<String, String>()
        for ((name, value) in values) {
            val fingerprint = java.security.MessageDigest.getInstance("SHA-256")
                .digest(value)
                .joinToString("") { "%02x".format(it) }
            val previous = seen.putIfAbsent(fingerprint, name)
            require(previous == null) {
                "$name must use purpose-separated material; it matches $previous"
            }
        }
    }
}
