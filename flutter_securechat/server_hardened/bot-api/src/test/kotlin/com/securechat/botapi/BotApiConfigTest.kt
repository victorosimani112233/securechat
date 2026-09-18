package com.securechat.botapi

import com.google.common.truth.Truth.assertThat
import java.security.KeyPairGenerator
import java.util.Base64
import org.junit.jupiter.api.Test

/**
 * Yapilandirma yuklemesi fail-closed'dir.
 *
 * Bu adim process ayaga kalkmadan once calisir ve butun anahtar
 * materyalinin amac ayrimini dogrular. Ayni bayti iki amaca vermek
 * kriptografik yalitimi bozar: ornegin kuyruk sifreleme anahtari ile blind
 * index anahtari ayni olursa, indeksi gorebilen taraf govdeyi de acabilir.
 */
class BotApiConfigTest {

    private fun key(seed: Int): String =
        Base64.getEncoder().encodeToString(ByteArray(32) { (seed + it).toByte() })

    private fun serviceKey(): String =
        Base64.getEncoder().encodeToString(
            KeyPairGenerator.getInstance("Ed25519").generateKeyPair().private.encoded,
        )

    private fun environment(vararg overrides: Pair<String, String>): Map<String, String> {
        val base = mutableMapOf(
            "DATABASE_URL" to "jdbc:postgresql://db:5432/securechat",
            "DATABASE_USER" to "securechat",
            "DATABASE_PASSWORD" to "db-password",
            "BOT_SERVICE_PRIVATE_KEY" to serviceKey(),
            "BOT_MASTER_KEY" to key(1),
            "BOT_QUEUE_ENCRYPTION_KEY" to key(60),
            "PRIVACY_INDEX_KEY" to key(120),
            "BOT_ADMIN_TOKEN" to "admin-token-0123456789abcdefghijklmno",
            "BOT_METRICS_BEARER_TOKEN" to "metrics-token-0123456789abcdefghijkl",
        )
        for ((name, value) in overrides) {
            if (value.isEmpty()) base.remove(name) else base[name] = value
        }
        return base
    }

    private fun load(vararg overrides: Pair<String, String>) =
        BotApiConfig.load(environment(*overrides))

    private fun failure(vararg overrides: Pair<String, String>): String {
        return try {
            load(*overrides)
            ""
        } catch (error: Exception) {
            error.message ?: error.javaClass.simpleName
        }
    }

    @Test
    fun `a complete environment loads`() {
        load()

        assertThat(BotApiConfig.databaseUrl).isEqualTo("jdbc:postgresql://db:5432/securechat")
        assertThat(BotApiConfig.botMasterKey).hasLength(32)
        assertThat(BotApiConfig.logLevel).isEqualTo("ERROR")
        assertThat(BotApiConfig.allowLegacyPlaintextQueue).isFalse()
    }

    @Test
    fun `every mandatory secret is required`() {
        for (name in listOf(
            "DATABASE_PASSWORD",
            "BOT_SERVICE_PRIVATE_KEY",
            "BOT_MASTER_KEY",
            "BOT_QUEUE_ENCRYPTION_KEY",
            "PRIVACY_INDEX_KEY",
            "BOT_ADMIN_TOKEN",
            "BOT_METRICS_BEARER_TOKEN",
        )) {
            assertThat(failure(name to "")).isNotEmpty()
        }
    }

    @Test
    fun `a secret cannot be supplied twice`() {
        // Eski bir env degeri rotasyona ugramis bir dosyayi golgeleyemez.
        val message = failure("BOT_MASTER_KEY_FILE" to "/run/secrets/bot_master_key")

        assertThat(message).contains("cannot both be set")
    }

    @Test
    fun `key material must be purpose separated`() {
        val shared = key(7)

        assertThat(
            failure("BOT_QUEUE_ENCRYPTION_KEY" to shared, "PRIVACY_INDEX_KEY" to shared),
        ).isNotEmpty()
        assertThat(
            failure("BOT_QUEUE_ENCRYPTION_KEY" to shared, "BOT_MASTER_KEY" to shared),
        ).isNotEmpty()
        assertThat(
            failure("BOT_MASTER_KEY" to shared, "PRIVACY_INDEX_KEY" to shared),
        ).contains("purpose-separated")
    }

    @Test
    fun `the admin and metrics tokens cannot be the same value`() {
        val shared = "same-token-0123456789abcdefghijklmnop"

        val message = failure("BOT_ADMIN_TOKEN" to shared, "BOT_METRICS_BEARER_TOKEN" to shared)

        assertThat(message).contains("purpose-separated")
    }

    @Test
    fun `short operator tokens are refused`() {
        assertThat(failure("BOT_ADMIN_TOKEN" to "short")).contains("32")
        assertThat(failure("BOT_METRICS_BEARER_TOKEN" to "short")).contains("32")
    }

    @Test
    fun `a key of the wrong size is refused`() {
        val short = Base64.getEncoder().encodeToString(ByteArray(16))

        assertThat(failure("BOT_MASTER_KEY" to short)).isNotEmpty()
        assertThat(failure("BOT_QUEUE_ENCRYPTION_KEY" to short)).isNotEmpty()
        assertThat(failure("PRIVACY_INDEX_KEY" to short)).isNotEmpty()
    }

    @Test
    fun `low diversity keys and operator tokens are refused`() {
        val weakKey = Base64.getEncoder().encodeToString(ByteArray(32) { 7 })
        assertThat(failure("BOT_MASTER_KEY" to weakKey)).contains("cesitliligine")
        assertThat(
            failure("BOT_ADMIN_TOKEN" to "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
        ).contains("cesitliligine")
    }

    @Test
    fun `a non base64 key is refused`() {
        assertThat(failure("BOT_MASTER_KEY" to "!!! not base64 !!!")).isNotEmpty()
    }

    @Test
    fun `a service key that is not an ed25519 private key is refused`() {
        assertThat(failure("BOT_SERVICE_PRIVATE_KEY" to key(9))).isNotEmpty()
    }

    @Test
    fun `queue and idempotency ttls stay inside their bounds`() {
        assertThat(failure("BOT_OUTBOUND_TTL_SECONDS" to "30")).isNotEmpty()
        assertThat(failure("BOT_OUTBOUND_TTL_SECONDS" to "7200")).isNotEmpty()
        assertThat(failure("BOT_OUTBOUND_TTL_SECONDS" to "abc")).isNotEmpty()
        assertThat(failure("BOT_IDEMPOTENCY_TTL_SECONDS" to "30")).isNotEmpty()
        assertThat(failure("BOT_IDEMPOTENCY_TTL_SECONDS" to "7200")).isNotEmpty()

        load("BOT_OUTBOUND_TTL_SECONDS" to "600", "BOT_IDEMPOTENCY_TTL_SECONDS" to "600")
        assertThat(BotApiConfig.outboundQueueTtlSeconds).isEqualTo(600L)
        assertThat(BotApiConfig.idempotencyTtlSeconds).isEqualTo(600L)
    }

    @Test
    fun `only silent log levels are accepted`() {
        // Hardened dagitimda uygulama logu tutulmaz; DEBUG bir gizlilik
        // sozlesmesi ihlalidir, sessizce yok sayilmamalidir.
        assertThat(failure("LOG_LEVEL" to "DEBUG")).isNotEmpty()
        assertThat(failure("LOG_LEVEL" to "INFO")).isNotEmpty()

        load("LOG_LEVEL" to "OFF")
        assertThat(BotApiConfig.logLevel).isEqualTo("OFF")
    }

    @Test
    fun `the legacy plaintext queue stays off unless explicitly enabled`() {
        load()
        assertThat(BotApiConfig.allowLegacyPlaintextQueue).isFalse()

        load("ALLOW_LEGACY_PLAINTEXT_QUEUE" to "yes please")
        assertThat(BotApiConfig.allowLegacyPlaintextQueue).isFalse()

        load("ALLOW_LEGACY_PLAINTEXT_QUEUE" to "true")
        assertThat(BotApiConfig.allowLegacyPlaintextQueue).isTrue()
    }

    @Test
    fun `socket paths and endpoints fall back to the hardened defaults`() {
        load()

        assertThat(BotApiConfig.publicSocketPath).isEqualTo("/run/bot/bot-public.sock")
        assertThat(BotApiConfig.adminSocketPath).isEqualTo("/run/bot/bot-admin.sock")
        assertThat(BotApiConfig.signalingWsUrl).startsWith("ws")
    }
}
