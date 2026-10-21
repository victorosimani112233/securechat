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
    fun `accounts without an Olm identity are left out of the shared directory`() {
        val ready = RegisteredUser("123e4567-e89b-42d3-a456-426614174000", "t1", "k")
        val stale = RegisteredUser("223e4567-e89b-42d3-a456-426614174000", "t2", "k")
        val abandoned = RegisteredUser("323e4567-e89b-42d3-a456-426614174000", "t3", "k")
        val users = listOf(ready, stale, abandoned)

        // Ne yalniz libsignal kimligi olan hesaba ne de anahtar yuklemeden
        // yarim kalmis kayda mesaj sifrelenebilir; ikisi de davet
        // listesinde gorunmeli.
        assertEquals(
            listOf(ready),
            DirectorySnapshotCache.messageable(users, setOf(stale.userId, abandoned.userId)),
        )
        // Sorgu basarisizsa kimse rehberden kaybolmaz.
        assertEquals(users, DirectorySnapshotCache.messageable(users, null))
    }

    @Test
    fun `a keyless account still finds its own entry`() {
        val token = oprf.tokenForPhoneHash(sha256Hex("+905551230000"))
        val registering = RegisteredUser("423e4567-e89b-42d3-a456-426614174000", token, oprf.keyId)
        val other = RegisteredUser("523e4567-e89b-42d3-a456-426614174000", token, oprf.keyId)
        val shared = (0 until 4).map { oprf.decoyEntry("seed-own-$it") }.sortedBy { it.label }
        val hidden = setOf(registering.userId, other.userId)
        val ownLabel = oprf.sealUserId(token, registering.userId).label

        // Yeni kayit numarasini Olm anahtarlarindan once alir ve hemen
        // kendini arar; kendi kaydini goremezse kurulum durur.
        val own = DirectorySnapshotCache.withOwnEntry(shared, hidden, registering, oprf)
        assertEquals(shared.size + 1, own.size)
        assertTrue(own.any { it.label == ownLabel })
        assertEquals(own.sortedBy { it.label }, own)

        // Anahtari olan hesap ve sorgu hatasi paylasilan listeyi aynen alir.
        val ready = registering.copy(userId = "623e4567-e89b-42d3-a456-426614174000")
        assertEquals(shared, DirectorySnapshotCache.withOwnEntry(shared, hidden, ready, oprf))
        assertEquals(shared, DirectorySnapshotCache.withOwnEntry(shared, null, registering, oprf))
        // Numarasini henuz almamis (eski anahtarli) kayit eklenmez.
        assertEquals(
            shared,
            DirectorySnapshotCache.withOwnEntry(shared, hidden, registering.copy(directoryKeyId = null), oprf),
        )
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
