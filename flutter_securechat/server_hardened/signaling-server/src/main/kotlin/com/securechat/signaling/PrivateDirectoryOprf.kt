package com.securechat.signaling

import java.math.BigInteger
import java.nio.ByteBuffer
import java.nio.charset.StandardCharsets
import java.security.KeyFactory
import java.security.KeyStore
import java.security.MessageDigest
import java.security.PrivateKey
import java.security.Provider
import java.security.Security
import java.security.SecureRandom
import java.security.interfaces.RSAPrivateCrtKey
import java.security.interfaces.RSAPublicKey
import java.security.spec.PKCS8EncodedKeySpec
import java.security.spec.RSAPublicKeySpec
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

data class DirectoryPublicConfig(
    val version: String,
    val keyId: String,
    val modulus: String,
    val exponent: String,
    val batchSize: Int,
)

data class PrivateDirectoryEntry(
    val label: String,
    val sealedUserId: String,
)

/**
 * Blind-RSA OPRF used for private contact discovery.
 *
 * The client blinds locally-derived phone hashes before evaluation. The
 * server therefore sees a fixed-size batch of uniformly random RSA group
 * elements, not the address-book hashes. PostgreSQL stores only finalized
 * OPRF tokens. A database snapshot without this independent private key
 * cannot run an offline phone-number dictionary attack.
 *
 * This key is dedicated to directory OPRF only. It must never be reused for
 * TLS, JWT, signatures or encryption. Production should load it from a
 * secret manager/HSM and keep a recoverable encrypted backup: changing the
 * key intentionally requires clients to re-index their own account.
 */
class PrivateDirectoryOprf private constructor(
    private val privateKey: PrivateKey,
    private val publicKey: RSAPublicKey,
    private val random: SecureRandom,
    private val cipherProvider: Provider? = null,
) {
    private val modulus = publicKey.modulus
    private val modulusBytes = (modulus.bitLength() + 7) / 8
    private val encoder = Base64.getUrlEncoder().withoutPadding()
    private val decoder = Base64.getUrlDecoder()
    val keyId: String

    init {
        require(modulus.bitLength() >= MINIMUM_RSA_BITS) {
            "Directory OPRF RSA key must be at least $MINIMUM_RSA_BITS bits"
        }
        require(publicKey.publicExponent == PUBLIC_EXPONENT) {
            "Directory OPRF RSA public exponent must be 65537"
        }
        keyId = encoder.encodeToString(sha256(publicKey.encoded))
    }

    fun publicConfig(): DirectoryPublicConfig = DirectoryPublicConfig(
        version = PROTOCOL_VERSION,
        keyId = keyId,
        modulus = encoder.encodeToString(unsignedBytes(modulus, modulusBytes)),
        exponent = encoder.encodeToString(unsignedBytes(publicKey.publicExponent)),
        batchSize = AUTHENTICATED_BATCH_SIZE,
    )

    fun evaluateBatch(blindedValues: List<String>): List<String> {
        require(blindedValues.size == AUTHENTICATED_BATCH_SIZE) {
            "Directory OPRF requests must contain exactly $AUTHENTICATED_BATCH_SIZE values"
        }
        return blindedValues.map(::evaluate)
    }

    fun tokenForPhoneHash(phoneHash: String): String {
        require(phoneHash.matches(SHA256_HEX)) { "Invalid phone discovery hash" }
        val point = fullDomainPoint(phoneHash.lowercase())
        return finalizeToken(privateOperation(point))
    }

    fun validateToken(token: String): String {
        val decoded = decodeToken(token)
        require(decoded.size == TOKEN_BYTES) { "Invalid directory token" }
        return encoder.encodeToString(decoded)
    }

    fun sealUserId(token: String, userId: String): PrivateDirectoryEntry {
        require(userId.matches(UUID)) { "Invalid directory user id" }
        val tokenBytes = decodeToken(validateToken(token))
        val label = encoder.encodeToString(derive(LABEL_DOMAIN, tokenBytes))
        val key = derive(ENTRY_KEY_DOMAIN, tokenBytes)
        val nonce = ByteArray(12).also(random::nextBytes)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.ENCRYPT_MODE,
            SecretKeySpec(key, "AES"),
            GCMParameterSpec(128, nonce),
        )
        cipher.updateAAD(entryAad(label))
        val ciphertext = cipher.doFinal(userId.toByteArray(StandardCharsets.UTF_8))
        key.fill(0)
        return PrivateDirectoryEntry(
            label = label,
            sealedUserId = encoder.encodeToString(nonce + ciphertext),
        )
    }

    internal fun openUserIdForTest(token: String, entry: PrivateDirectoryEntry): String {
        val tokenBytes = decodeToken(validateToken(token))
        val expectedLabel = encoder.encodeToString(derive(LABEL_DOMAIN, tokenBytes))
        require(MessageDigest.isEqual(expectedLabel.toByteArray(), entry.label.toByteArray())) {
            "Directory entry label mismatch"
        }
        val envelope = decoder.decode(entry.sealedUserId)
        require(envelope.size >= 12 + 16) { "Directory entry envelope is too short" }
        val key = derive(ENTRY_KEY_DOMAIN, tokenBytes)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.DECRYPT_MODE,
            SecretKeySpec(key, "AES"),
            GCMParameterSpec(128, envelope.copyOfRange(0, 12)),
        )
        cipher.updateAAD(entryAad(entry.label))
        return try {
            String(cipher.doFinal(envelope.copyOfRange(12, envelope.size)), StandardCharsets.UTF_8)
        } finally {
            key.fill(0)
        }
    }

    private fun evaluate(encoded: String): String {
        val bytes = try {
            decoder.decode(encoded)
        } catch (_: IllegalArgumentException) {
            throw IllegalArgumentException("Invalid blinded directory value")
        }
        require(bytes.size == modulusBytes) { "Invalid blinded directory value size" }
        val value = BigInteger(1, bytes)
        require(value > BigInteger.ONE && value < modulus && value.gcd(modulus) == BigInteger.ONE) {
            "Blinded directory value is outside the RSA group"
        }
        return encoder.encodeToString(unsignedBytes(privateOperation(value), modulusBytes))
    }

    private fun privateOperation(value: BigInteger): BigInteger {
        // RSA/NoPadding is deliberate: this is a dedicated blind-RSA OPRF,
        // not encryption. The software JCA provider uses CRT/RSA blinding;
        // the PKCS#11 provider keeps the private operation inside the HSM.
        // Every input/output is a fixed-width group value.
        val cipher = if (cipherProvider == null) {
            Cipher.getInstance("RSA/ECB/NoPadding")
        } else {
            Cipher.getInstance("RSA/ECB/NoPadding", cipherProvider)
        }
        cipher.init(Cipher.DECRYPT_MODE, privateKey, random)
        return BigInteger(1, cipher.doFinal(unsignedBytes(value, modulusBytes)))
    }

    private fun fullDomainPoint(phoneHash: String): BigInteger {
        for (attempt in 0..255) {
            val seed = sha256(
                PHONE_INPUT_DOMAIN +
                    phoneHash.toByteArray(StandardCharsets.US_ASCII) +
                    int32(attempt),
            )
            val expanded = ArrayList<Byte>(modulusBytes + 16)
            var counter = 0
            while (expanded.size < modulusBytes + 16) {
                expanded.addAll(sha256(seed + int32(counter)).toList())
                counter++
            }
            val candidate = BigInteger(1, expanded.toByteArray())
                .mod(modulus - BigInteger.ONE) + BigInteger.ONE
            if (candidate > BigInteger.ONE && candidate.gcd(modulus) == BigInteger.ONE) {
                return candidate
            }
        }
        error("Could not map phone hash into the directory RSA group")
    }

    private fun finalizeToken(evaluated: BigInteger): String = encoder.encodeToString(
        sha256(TOKEN_DOMAIN + unsignedBytes(evaluated, modulusBytes)),
    )

    private fun derive(domain: ByteArray, token: ByteArray): ByteArray = sha256(domain + token)

    private fun entryAad(label: String): ByteArray =
        ENTRY_AAD_DOMAIN + keyId.toByteArray(StandardCharsets.US_ASCII) + byteArrayOf(0) +
            label.toByteArray(StandardCharsets.US_ASCII)

    private fun decodeToken(token: String): ByteArray = try {
        decoder.decode(token)
    } catch (_: IllegalArgumentException) {
        throw IllegalArgumentException("Invalid directory token")
    }

    companion object {
        const val PROTOCOL_VERSION = "elcim-directory-oprf-v1"
        const val AUTHENTICATED_BATCH_SIZE = 256
        private const val MINIMUM_RSA_BITS = 3072
        private const val TOKEN_BYTES = 32
        private val PUBLIC_EXPONENT = BigInteger.valueOf(65_537)
        private val SHA256_HEX = Regex("(?i)^[0-9a-f]{64}$")
        private val UUID = Regex(
            "(?i)^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
        )
        private val PHONE_INPUT_DOMAIN = "elcim-directory-phone-v1\u0000"
            .toByteArray(StandardCharsets.US_ASCII)
        private val TOKEN_DOMAIN = "elcim-directory-token-v1\u0000"
            .toByteArray(StandardCharsets.US_ASCII)
        private val LABEL_DOMAIN = "elcim-directory-label-v1\u0000"
            .toByteArray(StandardCharsets.US_ASCII)
        private val ENTRY_KEY_DOMAIN = "elcim-directory-entry-key-v1\u0000"
            .toByteArray(StandardCharsets.US_ASCII)
        private val ENTRY_AAD_DOMAIN = "elcim-directory-entry-aad-v1\u0000"
            .toByteArray(StandardCharsets.US_ASCII)

        fun fromEnvironment(environment: Map<String, String> = System.getenv()): PrivateDirectoryOprf =
            when (environment["DIRECTORY_OPRF_KEY_BACKEND"]?.trim()?.uppercase() ?: "PKCS8") {
                "PKCS8" -> fromPkcs8Environment(environment)
                "PKCS11" -> fromPkcs11Environment(environment)
                else -> error("DIRECTORY_OPRF_KEY_BACKEND must be PKCS8 or PKCS11")
            }

        private fun fromPkcs8Environment(environment: Map<String, String>): PrivateDirectoryOprf {
            val encoded = SecretSource.required("DIRECTORY_OPRF_PRIVATE_KEY", environment)
            val der = try {
                Base64.getDecoder().decode(encoded)
            } catch (_: IllegalArgumentException) {
                error("DIRECTORY_OPRF_PRIVATE_KEY must be valid Base64")
            }
            val key = try {
                KeyFactory.getInstance("RSA").generatePrivate(PKCS8EncodedKeySpec(der))
            } catch (_: Exception) {
                error("DIRECTORY_OPRF_PRIVATE_KEY must be a valid PKCS#8 RSA private key")
            }
            require(key is RSAPrivateCrtKey) {
                "DIRECTORY_OPRF_PRIVATE_KEY must include RSA CRT parameters"
            }
            val publicKey = KeyFactory.getInstance("RSA").generatePublic(
                RSAPublicKeySpec(key.modulus, key.publicExponent),
            ) as RSAPublicKey
            return PrivateDirectoryOprf(key, publicKey, SecureRandom())
        }

        /**
         * Loads a non-exportable RSA key exposed by a preconfigured PKCS#11
         * JCA provider. No fallback to an environment/private-key copy exists:
         * provider, alias, certificate or private operation failure aborts
         * startup before a listener opens.
         */
        private fun fromPkcs11Environment(environment: Map<String, String>): PrivateDirectoryOprf {
            val providerName = environment["DIRECTORY_OPRF_PKCS11_PROVIDER"]
                ?.takeIf { it.isNotBlank() }
                ?: error("DIRECTORY_OPRF_PKCS11_PROVIDER is required for PKCS11 backend")
            val alias = environment["DIRECTORY_OPRF_KEY_ALIAS"]?.takeIf { it.isNotBlank() }
                ?: error("DIRECTORY_OPRF_KEY_ALIAS is required for PKCS11 backend")
            val pinText = SecretSource.required("DIRECTORY_OPRF_KEYSTORE_PIN", environment)
            val provider = Security.getProvider(providerName)
                ?: error("Configured directory PKCS11 provider is not installed")
            val pin = pinText.toCharArray()
            return try {
                val keyStore = KeyStore.getInstance("PKCS11", provider)
                keyStore.load(null, pin)
                val privateKey = keyStore.getKey(alias, pin) as? PrivateKey
                    ?: error("Directory PKCS11 alias does not contain a private key")
                require(privateKey.algorithm.equals("RSA", ignoreCase = true)) {
                    "Directory PKCS11 private key must be RSA"
                }
                val publicKey = keyStore.getCertificate(alias)?.publicKey as? RSAPublicKey
                    ?: error("Directory PKCS11 alias must expose an RSA certificate/public key")
                PrivateDirectoryOprf(
                    privateKey = privateKey,
                    publicKey = publicKey,
                    random = SecureRandom(),
                    cipherProvider = provider,
                )
            } finally {
                pin.fill('\u0000')
            }
        }

        internal fun forTest(
            key: RSAPrivateCrtKey,
            random: SecureRandom = SecureRandom(),
        ): PrivateDirectoryOprf {
            val publicKey = KeyFactory.getInstance("RSA").generatePublic(
                RSAPublicKeySpec(key.modulus, key.publicExponent),
            ) as RSAPublicKey
            return PrivateDirectoryOprf(key, publicKey, random)
        }

        private fun sha256(input: ByteArray): ByteArray =
            MessageDigest.getInstance("SHA-256").digest(input)

        private fun int32(value: Int): ByteArray = ByteBuffer.allocate(4).putInt(value).array()

        private fun unsignedBytes(value: BigInteger, size: Int? = null): ByteArray {
            val raw = value.toByteArray().let {
                if (it.size > 1 && it[0] == 0.toByte()) it.copyOfRange(1, it.size) else it
            }
            if (size == null) return raw
            require(raw.size <= size) { "Integer does not fit expected width" }
            return ByteArray(size - raw.size) + raw
        }
    }
}

object PrivateDirectory {
    val oprf: PrivateDirectoryOprf by lazy { PrivateDirectoryOprf.fromEnvironment() }

    fun initialize() {
        oprf
    }
}
