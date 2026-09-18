package com.securechat.botapi.delivery

import com.securechat.botapi.BotApiConfig
import com.securechat.botapi.GcmNonceSequence
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

class BotQueuePrimitives(
    private val indexKey: ByteArray,
    private val encryptionKey: ByteArray,
    private val allowLegacyPlaintext: Boolean = false,
    random: SecureRandom = SecureRandom(),
    nonceBudget: Long = 1L shl 32,
) {
    private val nonces = GcmNonceSequence(random, nonceBudget)
    private val keyId = keyId(encryptionKey)
    init {
        require(indexKey.size == 32 && encryptionKey.size == 32)
        require(!indexKey.contentEquals(encryptionKey))
    }

    fun key(botUserId: String): String =
        "bot_outbound_v2:${blindIndex("outbound", botUserId)}"

    fun blindIndex(namespace: String, value: String): String {
        require(namespace.matches(Regex("[a-z0-9_-]{1,32}"))) {
            "Invalid bot blind-index namespace"
        }
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(indexKey, "HmacSHA256"))
        return Base64.getUrlEncoder().withoutPadding().encodeToString(
            mac.doFinal("bot-$namespace\u0000$value".toByteArray(StandardCharsets.UTF_8))
        )
    }

    fun seal(botUserId: String, plaintext: String): String {
        return encrypt("BQ2:", queueAadV2(botUserId), plaintext)
    }

    fun open(botUserId: String, envelope: String): String {
        return when {
            envelope.startsWith("BQ2:") ->
                decryptVersioned("BQ2:", queueAadV2(botUserId), envelope)
            envelope.startsWith("BQ1:") -> decryptLegacy("BQ1:", queueAadV1(botUserId), envelope)
            allowLegacyPlaintext -> envelope
            else -> throw IllegalArgumentException("Legacy plaintext bot queue entry rejected")
        }
    }

    fun sealPrivate(purpose: String, binding: String, plaintext: String): String =
        encrypt("BP2:", privateAadV2(purpose, binding), plaintext)

    fun openPrivate(purpose: String, binding: String, envelope: String): String {
        return when {
            envelope.startsWith("BP2:") ->
                decryptVersioned("BP2:", privateAadV2(purpose, binding), envelope)
            envelope.startsWith("BP1:") ->
                decryptLegacy("BP1:", privateAadV1(purpose, binding), envelope)
            else -> throw IllegalArgumentException("Legacy private bot value rejected")
        }
    }

    private fun encrypt(prefix: String, aad: ByteArray, plaintext: String): String {
        val nonce = nonces.next()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.ENCRYPT_MODE,
            SecretKeySpec(encryptionKey, "AES"),
            GCMParameterSpec(128, nonce)
        )
        cipher.updateAAD(aad)
        val encrypted = cipher.doFinal(plaintext.toByteArray(StandardCharsets.UTF_8))
        return "$prefix$keyId:" +
            Base64.getUrlEncoder().withoutPadding().encodeToString(nonce + encrypted)
    }

    fun redact(message: String): String = redactMessage(message)

    private fun decryptVersioned(prefix: String, aad: ByteArray, envelope: String): String {
        val separator = envelope.indexOf(':', startIndex = prefix.length)
        require(separator > prefix.length) { "Bot envelope key id is missing" }
        require(envelope.substring(prefix.length, separator) == keyId) {
            "Unknown bot queue encryption key"
        }
        return decryptPayload(aad, envelope.substring(separator + 1))
    }

    private fun decryptLegacy(prefix: String, aad: ByteArray, envelope: String): String =
        decryptPayload(aad, envelope.removePrefix(prefix))

    private fun decryptPayload(aad: ByteArray, encoded: String): String {
        val payload = Base64.getUrlDecoder().decode(encoded)
        require(payload.size >= 28) { "Bot private envelope is too short" }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.DECRYPT_MODE,
            SecretKeySpec(encryptionKey, "AES"),
            GCMParameterSpec(128, payload.copyOfRange(0, 12))
        )
        cipher.updateAAD(aad)
        return String(cipher.doFinal(payload.copyOfRange(12, payload.size)), StandardCharsets.UTF_8)
    }

    private fun queueAadV1(botUserId: String): ByteArray =
        "securechat-bot-outbound-v1\u0000$botUserId".toByteArray(StandardCharsets.UTF_8)

    private fun queueAadV2(botUserId: String): ByteArray =
        "securechat-bot-outbound-v2\u0000$keyId\u0000$botUserId"
            .toByteArray(StandardCharsets.UTF_8)

    private fun privateAadV1(purpose: String, binding: String): ByteArray {
        require(purpose.matches(Regex("[a-z0-9_-]{1,32}"))) { "Invalid bot private purpose" }
        return "securechat-bot-private-v1\u0000$purpose\u0000$binding"
            .toByteArray(StandardCharsets.UTF_8)
    }

    private fun privateAadV2(purpose: String, binding: String): ByteArray {
        require(purpose.matches(Regex("[a-z0-9_-]{1,32}"))) { "Invalid bot private purpose" }
        return "securechat-bot-private-v2\u0000$keyId\u0000$purpose\u0000$binding"
            .toByteArray(StandardCharsets.UTF_8)
    }

    private fun keyId(key: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256")
        digest.update("securechat-bot-queue-key-id-v1".toByteArray(StandardCharsets.US_ASCII))
        digest.update(0.toByte())
        digest.update(key)
        return Base64.getUrlEncoder().withoutPadding()
            .encodeToString(digest.digest().copyOfRange(0, 9))
    }

    companion object {
        private val EMAIL = Regex("(?i)[a-z0-9._%+-]+@[a-z0-9.-]+\\.[a-z]{2,}")
        private val UUID = Regex("(?i)\\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\\b")
        private val IPV4 = Regex("(?<![0-9])(?:[0-9]{1,3}\\.){3}[0-9]{1,3}(?![0-9])")
        private val BEARER = Regex("(?i)Bearer\\s+[^\\s,;]+")
        private val JWT = Regex("\\beyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\b")

        fun redactMessage(message: String): String = message
            .replace(EMAIL, "<email:redacted>")
            .replace(UUID, "<id:redacted>")
            .replace(IPV4, "<ip:redacted>")
            .replace(BEARER, "Bearer <token:redacted>")
            .replace(JWT, "<jwt:redacted>")
    }
}

object BotQueuePrivacy {

    private val lock = Any()

    @Volatile
    private var cached: BotQueuePrimitives? = null

    @Volatile
    private var cachedFingerprint: Int = 0

    /**
     * Anahtar materyaline bagli onbellek.
     *
     * Onceki `by lazy` ilk kullanimda sabitleniyordu: yapilandirma sonradan
     * degistirilirse (rotasyon, yeniden baslatma olmadan yeniden yukleme)
     * eski anahtar sessizce kullanilmaya devam ederdi — blind index'ler ve
     * muhurler o noktadan sonra tutarsiz olurdu. Anahtarin kimligi
     * degistiginde primitifler yeniden kurulur.
     */
    val primitives: BotQueuePrimitives
        get() {
            val fingerprint = fingerprint()
            val current = cached
            if (current != null && cachedFingerprint == fingerprint) return current
            synchronized(lock) {
                val existing = cached
                if (existing != null && cachedFingerprint == fingerprint) return existing
                val built = BotQueuePrimitives(
                    indexKey = BotApiConfig.privacyIndexKey,
                    encryptionKey = BotApiConfig.botQueueEncryptionKey,
                    allowLegacyPlaintext = BotApiConfig.allowLegacyPlaintextQueue,
                )
                cached = built
                cachedFingerprint = fingerprint
                return built
            }
        }

    /** Anahtar materyalinin kimligi; ham anahtar hicbir yerde tutulmaz. */
    private fun fingerprint(): Int {
        val digest = java.security.MessageDigest.getInstance("SHA-256")
        digest.update(BotApiConfig.privacyIndexKey)
        digest.update(BotApiConfig.botQueueEncryptionKey)
        digest.update(if (BotApiConfig.allowLegacyPlaintextQueue) 1 else 0)
        return digest.digest().fold(0) { acc, byte -> acc * 31 + byte }
    }

    fun key(botUserId: String): String = primitives.key(botUserId)
    fun blindIndex(namespace: String, value: String): String =
        primitives.blindIndex(namespace, value)
    fun seal(botUserId: String, plaintext: String): String = primitives.seal(botUserId, plaintext)
    fun open(botUserId: String, envelope: String): String = primitives.open(botUserId, envelope)
    fun sealPrivate(purpose: String, binding: String, plaintext: String): String =
        primitives.sealPrivate(purpose, binding, plaintext)
    fun openPrivate(purpose: String, binding: String, envelope: String): String =
        primitives.openPrivate(purpose, binding, envelope)
    fun redact(message: String): String = BotQueuePrimitives.redactMessage(message)
}
