package com.securechat.signaling

import java.math.BigInteger
import java.nio.ByteBuffer
import java.nio.charset.StandardCharsets
import java.security.KeyPairGenerator
import java.security.MessageDigest
import java.security.SecureRandom
import java.security.interfaces.RSAPrivateCrtKey
import java.util.Base64
import javax.crypto.AEADBadTagException
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.BeforeAll
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestInstance

@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class PrivateDirectoryOprfTest {
    private lateinit var privateKey: RSAPrivateCrtKey
    private lateinit var directory: PrivateDirectoryOprf
    private val random = SecureRandom()
    private val encoder = Base64.getUrlEncoder().withoutPadding()
    private val decoder = Base64.getUrlDecoder()

    @BeforeAll
    fun createDedicatedTestKey() {
        val generator = KeyPairGenerator.getInstance("RSA")
        generator.initialize(3072, random)
        privateKey = generator.generateKeyPair().private as RSAPrivateCrtKey
        directory = PrivateDirectoryOprf.forTest(privateKey, random)
    }

    @Test
    fun `public config is self identifying and fixed size`() {
        val config = directory.publicConfig()

        assertEquals(PrivateDirectoryOprf.PROTOCOL_VERSION, config.version)
        assertEquals(directory.keyId, config.keyId)
        assertEquals(PrivateDirectoryOprf.AUTHENTICATED_BATCH_SIZE, config.batchSize)
        assertEquals(BigInteger.valueOf(65_537), BigInteger(1, decoder.decode(config.exponent)))
        assertTrue(BigInteger(1, decoder.decode(config.modulus)).bitLength() >= 3072)
    }

    @Test
    fun `key backend selection is explicit and fail closed`() {
        val encoded = Base64.getEncoder().encodeToString(privateKey.encoded)
        val loaded = PrivateDirectoryOprf.fromEnvironment(
            mapOf(
                "DIRECTORY_OPRF_KEY_BACKEND" to "PKCS8",
                "DIRECTORY_OPRF_PRIVATE_KEY" to encoded,
            ),
        )
        assertEquals(directory.keyId, loaded.keyId)

        assertThrows(IllegalStateException::class.java) {
            PrivateDirectoryOprf.fromEnvironment(
                mapOf("DIRECTORY_OPRF_KEY_BACKEND" to "filesystem-fallback"),
            )
        }
        assertThrows(IllegalStateException::class.java) {
            PrivateDirectoryOprf.fromEnvironment(
                mapOf("DIRECTORY_OPRF_KEY_BACKEND" to "PKCS11"),
            )
        }
    }

    @Test
    fun `independent blinds unblind to the same server enrollment token`() {
        val phoneHash = sha256Hex("+905551234567")
        val first = blind(phoneHash)
        val second = blind(phoneHash)

        assertNotEquals(first.encoded, second.encoded)
        val evaluatedFirst = directory.evaluateBatch(paddedBatch(first.encoded)).first()
        val evaluatedSecond = directory.evaluateBatch(paddedBatch(second.encoded)).first()

        val firstToken = unblind(evaluatedFirst, first.inverse)
        val secondToken = unblind(evaluatedSecond, second.inverse)
        assertEquals(directory.tokenForPhoneHash(phoneHash), firstToken)
        assertEquals(firstToken, secondToken)
    }

    @Test
    fun `snapshot entry discloses neither token nor user id and is token bound`() {
        val token = directory.tokenForPhoneHash(sha256Hex("+905551234567"))
        val otherToken = directory.tokenForPhoneHash(sha256Hex("+905559999999"))
        val userId = "123e4567-e89b-42d3-a456-426614174000"

        val first = directory.sealUserId(token, userId)
        val second = directory.sealUserId(token, userId)

        assertFalse(first.label.contains(token))
        assertFalse(first.sealedUserId.contains(userId))
        assertNotEquals(first.sealedUserId, second.sealedUserId)
        assertEquals(userId, directory.openUserIdForTest(token, first))
        assertThrows(IllegalArgumentException::class.java) {
            directory.openUserIdForTest(otherToken, first)
        }

        val tamperedBytes = decoder.decode(first.sealedUserId)
        tamperedBytes[tamperedBytes.lastIndex] = (tamperedBytes.last().toInt() xor 1).toByte()
        val tampered = first.copy(sealedUserId = encoder.encodeToString(tamperedBytes))
        assertThrows(AEADBadTagException::class.java) {
            directory.openUserIdForTest(token, tampered)
        }
    }

    @Test
    fun `evaluation rejects count encoding and group violations`() {
        assertThrows(IllegalArgumentException::class.java) {
            directory.evaluateBatch(emptyList())
        }
        assertThrows(IllegalArgumentException::class.java) {
            directory.evaluateBatch(List(256) { "not-base64" })
        }
        assertThrows(IllegalArgumentException::class.java) {
            directory.evaluateBatch(List(256) { encoder.encodeToString(ByteArray(modulusBytes)) })
        }
    }

    private fun blind(phoneHash: String): BlindFixture {
        val point = fullDomainPoint(phoneHash)
        val factor = randomGroupElement()
        val blinded = point.multiply(factor.modPow(privateKey.publicExponent, privateKey.modulus))
            .mod(privateKey.modulus)
        return BlindFixture(
            encoded = encoder.encodeToString(unsignedBytes(blinded, modulusBytes)),
            inverse = factor.modInverse(privateKey.modulus),
        )
    }

    private fun unblind(evaluated: String, inverse: BigInteger): String {
        val value = BigInteger(1, decoder.decode(evaluated))
            .multiply(inverse)
            .mod(privateKey.modulus)
        return encoder.encodeToString(
            sha256(TOKEN_DOMAIN + unsignedBytes(value, modulusBytes)),
        )
    }

    private fun paddedBatch(first: String): List<String> = buildList(256) {
        add(first)
        repeat(255) {
            add(encoder.encodeToString(unsignedBytes(randomGroupElement(), modulusBytes)))
        }
    }

    private fun randomGroupElement(): BigInteger {
        while (true) {
            val candidate = BigInteger(privateKey.modulus.bitLength(), random)
            if (
                candidate > BigInteger.ONE &&
                candidate < privateKey.modulus &&
                candidate.gcd(privateKey.modulus) == BigInteger.ONE
            ) {
                return candidate
            }
        }
    }

    private fun fullDomainPoint(phoneHash: String): BigInteger {
        for (attempt in 0..255) {
            val seed = sha256(
                PHONE_INPUT_DOMAIN +
                    phoneHash.lowercase().toByteArray(StandardCharsets.US_ASCII) +
                    int32(attempt),
            )
            val expanded = ArrayList<Byte>(modulusBytes + 16)
            var counter = 0
            while (expanded.size < modulusBytes + 16) {
                expanded.addAll(sha256(seed + int32(counter)).toList())
                counter++
            }
            val candidate = BigInteger(1, expanded.toByteArray())
                .mod(privateKey.modulus - BigInteger.ONE) + BigInteger.ONE
            if (candidate > BigInteger.ONE && candidate.gcd(privateKey.modulus) == BigInteger.ONE) {
                return candidate
            }
        }
        error("Could not map test input into RSA group")
    }

    private val modulusBytes: Int
        get() = (privateKey.modulus.bitLength() + 7) / 8

    private fun sha256Hex(value: String): String = sha256(
        value.toByteArray(StandardCharsets.UTF_8),
    ).joinToString("") { "%02x".format(it) }

    private fun sha256(value: ByteArray): ByteArray =
        MessageDigest.getInstance("SHA-256").digest(value)

    private fun int32(value: Int): ByteArray = ByteBuffer.allocate(4).putInt(value).array()

    private fun unsignedBytes(value: BigInteger, size: Int): ByteArray {
        val raw = value.toByteArray().let {
            if (it.size > 1 && it[0] == 0.toByte()) it.copyOfRange(1, it.size) else it
        }
        require(raw.size <= size)
        return ByteArray(size - raw.size) + raw
    }

    private data class BlindFixture(val encoded: String, val inverse: BigInteger)

    companion object {
        private val PHONE_INPUT_DOMAIN = "elcim-directory-phone-v1\u0000"
            .toByteArray(StandardCharsets.US_ASCII)
        private val TOKEN_DOMAIN = "elcim-directory-token-v1\u0000"
            .toByteArray(StandardCharsets.US_ASCII)
    }
}
