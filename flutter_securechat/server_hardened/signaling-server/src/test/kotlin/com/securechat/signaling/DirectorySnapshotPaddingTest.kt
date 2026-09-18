package com.securechat.signaling

import java.security.KeyPairGenerator
import java.security.interfaces.RSAPrivateCrtKey
import java.util.Base64
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.BeforeAll
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestInstance

/**
 * Snapshot dolgusu.
 *
 * Yanit her hesaba ayni listeyi verdigi icin eleman sayisi dogrudan kayitli
 * hesap sayisiydi: kimlik dogrulamis herhangi bir istemci sunucunun
 * buyuklugunu ve buyume hizini olcebiliyordu.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class DirectorySnapshotPaddingTest {

    private lateinit var oprf: PrivateDirectoryOprf

    @BeforeAll
    fun setUp() {
        val generator = KeyPairGenerator.getInstance("RSA")
        generator.initialize(3072)
        oprf = PrivateDirectoryOprf.forTest(
            generator.generateKeyPair().private as RSAPrivateCrtKey,
        )
    }

    @Test
    fun `the entry count is rounded up to a bucket`() {
        assertEquals(256, DirectorySnapshotCache.paddedSize(0))
        assertEquals(256, DirectorySnapshotCache.paddedSize(1))
        assertEquals(256, DirectorySnapshotCache.paddedSize(255))
        // Tam kova sinirinda bir ust kovaya gecilir; aksi halde "tam 256
        // kullanici var" durumu ayirt edilebilirdi.
        assertEquals(512, DirectorySnapshotCache.paddedSize(256))
        assertEquals(512, DirectorySnapshotCache.paddedSize(300))
    }

    @Test
    fun `a decoy is the same shape as a real entry`() {
        val token = oprf.tokenForPhoneHash(sha256Hex("+905551234567"))
        val real = oprf.sealUserId(token, "123e4567-e89b-42d3-a456-426614174000")
        val decoy = oprf.decoyEntry("seed-0")

        val decoder = Base64.getUrlDecoder()
        assertEquals(decoder.decode(real.label).size, decoder.decode(decoy.label).size)
        assertEquals(
            decoder.decode(real.sealedUserId).size,
            decoder.decode(decoy.sealedUserId).size,
        )
    }

    @Test
    fun `a decoy label is stable across rebuilds while the envelope is not`() {
        val first = oprf.decoyEntry("seed-7")
        val second = oprf.decoyEntry("seed-7")

        // Gercek etiketler token'dan deterministik turer. Her rebuild'de
        // degisen bir dolgu etiketi dolguyu ele verirdi.
        assertEquals(first.label, second.label)
        // Zarf ise gercek kayitlarda da her muhurlemede degisir.
        assertNotEquals(first.sealedUserId, second.sealedUserId)
    }

    @Test
    fun `different seeds produce different decoys`() {
        val labels = (0 until 64).map { oprf.decoyEntry("seed-$it").label }.toSet()

        assertEquals(64, labels.size)
    }

    @Test
    fun `a decoy never collides with a real label`() {
        val token = oprf.tokenForPhoneHash(sha256Hex("+905559998877"))
        val real = oprf.sealUserId(token, "123e4567-e89b-42d3-a456-426614174001")
        val decoyLabels = (0 until 256).map { oprf.decoyEntry("seed-$it").label }.toSet()

        assertTrue(real.label !in decoyLabels)
    }

    private fun sha256Hex(value: String): String =
        java.security.MessageDigest.getInstance("SHA-256")
            .digest(value.toByteArray())
            .joinToString("") { "%02x".format(it) }
}
