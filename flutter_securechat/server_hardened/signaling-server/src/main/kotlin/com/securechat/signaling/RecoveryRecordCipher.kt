package com.securechat.signaling

import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64
import java.util.Locale
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import java.security.KeyFactory
import java.security.Signature
import java.security.spec.X509EncodedKeySpec

internal class RecoveryRecordCipher(indexKey: ByteArray, encryptionKey: ByteArray) {
    private val indexKey = indexKey.copyOf()
    private val encryptionKey = encryptionKey.copyOf()

    init {
        SecretPolicy.requireStrongKey("RECOVERY_INDEX_KEY", indexKey)
        SecretPolicy.requireStrongKey("RECOVERY_ENCRYPTION_KEY", encryptionKey)
        require(!MessageDigest.isEqual(indexKey, encryptionKey))
    }

    fun index(purpose: String, value: String): String = Mac.getInstance("HmacSHA256").run {
        init(SecretKeySpec(indexKey, "HmacSHA256"))
        doFinal("securechat/recovery/$purpose/v1\u0000$value".toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
    }

    fun seal(aad: String, value: String): ByteArray {
        val nonce = ByteArray(12).also(random::nextBytes)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(encryptionKey, "AES"), GCMParameterSpec(128, nonce))
        cipher.updateAAD(aad.toByteArray(Charsets.UTF_8))
        return nonce + cipher.doFinal(value.toByteArray(Charsets.UTF_8))
    }

    fun open(aad: String, value: ByteArray): String {
        require(value.size >= 28)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(encryptionKey, "AES"), GCMParameterSpec(128, value.copyOfRange(0, 12)))
        cipher.updateAAD(aad.toByteArray(Charsets.UTF_8))
        return cipher.doFinal(value.copyOfRange(12, value.size)).toString(Charsets.UTF_8)
    }

    companion object {
        private val random = SecureRandom()
        fun opaque(): String = Base64.getUrlEncoder().withoutPadding()
            .encodeToString(ByteArray(32).also(random::nextBytes))
        fun otp(): String = random.nextInt(1_000_000).toString().padStart(6, '0')

        fun configured(environment: Map<String, String> = System.getenv()): RecoveryRecordCipher? {
            val index = SecretSource.optional("RECOVERY_INDEX_KEY", environment)
            val encryption = SecretSource.optional("RECOVERY_ENCRYPTION_KEY", environment)
            if (index == null && encryption == null) return null
            require(index != null && encryption != null) { "Both dedicated recovery secrets are required" }
            PurposeSeparatedSecrets.validate(environment)
            return RecoveryRecordCipher(Base64.getDecoder().decode(index), Base64.getDecoder().decode(encryption))
        }

        fun normalizeEmail(value: String): String {
            val email = value.trim().lowercase(Locale.ROOT)
            require(email.length in 3..254 && email.all { it.code in 33..126 })
            require(email.matches(Regex("[a-z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?\\.[a-z]{2,63}")))
            require(email.substringBefore('@').length <= 64 && !email.contains(".."))
            return email
        }

        // Kurtarma kimligi libsignal Curve25519/XEdDSA'dan vodozemac'in
        // Ed25519 imzalama anahtarina tasindi: istemci `account.sign()`
        // (standart Ed25519) uretiyor, pin ettigimiz anahtar `users.
        // signing_public_key` (ham 32 bayt). JDK'nin Ed25519'u ham anahtar
        // degil X.509 SPKI bekliyor, bu yuzden 32 bayt sabit bir
        // SubjectPublicKeyInfo onekiyle sariliyor.
        private val ed25519Spki = byteArrayOf(
            0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00,
        )

        fun verify(key: ByteArray, preimage: String, signature: String): Boolean = runCatching {
            val bytes = Base64.getDecoder().decode(signature)
            if (key.size != 32 || bytes.size != 64) return@runCatching false
            val pub = KeyFactory.getInstance("Ed25519")
                .generatePublic(X509EncodedKeySpec(ed25519Spki + key))
            Signature.getInstance("Ed25519").run {
                initVerify(pub)
                update(preimage.toByteArray(Charsets.UTF_8))
                verify(bytes)
            }
        }.getOrDefault(false)
    }
}
