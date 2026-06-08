package com.securechat.crypto

import com.google.common.truth.Truth.assertThat
import com.securechat.crypto.store.CryptoSenderKeyStore
import org.junit.Test
import org.whispersystems.libsignal.SignalProtocolAddress
import org.whispersystems.libsignal.groups.GroupCipher
import org.whispersystems.libsignal.groups.GroupSessionBuilder
import org.whispersystems.libsignal.groups.SenderKeyName

/**
 * Sender Keys uçtan uca round-trip testi.
 * Gercek libsignal cagrilarini in-memory backing store ile dogrular —
 * server'a deploy etmeden hizli regression korumasi saglar.
 *
 * Senaryo: A (gonderici) -> B, C (alici)
 *   1. A SKDM uretir (GroupSessionBuilder.create)
 *   2. B ve C SKDM'i process eder
 *   3. A mesaj sifreler (GroupCipher.encrypt)
 *   4. B ve C ayni ciphertext'i decrypt eder → plaintext esit
 */
class GroupSenderKeyRoundTripTest {

    /** Bellekte tutulan basit CryptoSenderKeyStore implementasyonu. */
    private class InMemoryBackingStore : CryptoSenderKeyStore {
        private val data = mutableMapOf<Triple<String, String, Int>, ByteArray>()
        override suspend fun loadSenderKey(groupId: String, senderId: String, deviceId: Int): ByteArray? =
            data[Triple(groupId, senderId, deviceId)]
        override suspend fun storeSenderKey(
            groupId: String, senderId: String, deviceId: Int, record: ByteArray
        ) { data[Triple(groupId, senderId, deviceId)] = record }
        override suspend fun deleteSenderKey(groupId: String, senderId: String, deviceId: Int) {
            data.remove(Triple(groupId, senderId, deviceId))
        }
        override suspend fun deleteAllForGroup(groupId: String) {
            data.entries.removeAll { it.key.first == groupId }
        }
        override suspend fun containsSenderKey(groupId: String, senderId: String, deviceId: Int): Boolean =
            data.containsKey(Triple(groupId, senderId, deviceId))
    }

    @Test
    fun `3 kullanici - A sifreler B ve C decrypt eder`() {
        val groupId = "group-rt-1"
        val senderA = SignalProtocolAddress("user-A", 1)
        val senderKeyName = SenderKeyName(groupId, senderA)

        // Her kullanici icin ayri store (gercekte ayri cihazlardir)
        val storeA = SecureChatSenderKeyStore(InMemoryBackingStore())
        val storeB = SecureChatSenderKeyStore(InMemoryBackingStore())
        val storeC = SecureChatSenderKeyStore(InMemoryBackingStore())

        // 1. A SKDM uretir
        val builderA = GroupSessionBuilder(storeA)
        val skdm = builderA.create(senderKeyName)

        // 2. B ve C SKDM'i process eder (1:1 session uzerinden geldigini varsayarak)
        GroupSessionBuilder(storeB).process(senderKeyName, skdm)
        GroupSessionBuilder(storeC).process(senderKeyName, skdm)

        // 3. A mesaj sifreler
        val plaintext = "Selam grup — gizli mesaj".toByteArray(Charsets.UTF_8)
        val cipherA = GroupCipher(storeA, senderKeyName)
        val ciphertext = cipherA.encrypt(plaintext)

        // 4. B ve C decrypt eder
        val cipherB = GroupCipher(storeB, senderKeyName)
        val cipherC = GroupCipher(storeC, senderKeyName)
        val ptB = cipherB.decrypt(ciphertext)
        val ptC = cipherC.decrypt(ciphertext)

        assertThat(String(ptB, Charsets.UTF_8)).isEqualTo("Selam grup — gizli mesaj")
        assertThat(String(ptC, Charsets.UTF_8)).isEqualTo("Selam grup — gizli mesaj")
    }

    @Test
    fun `SKDM olmadan decrypt - NoSessionException`() {
        val groupId = "group-rt-2"
        val senderA = SignalProtocolAddress("user-A", 1)
        val senderKeyName = SenderKeyName(groupId, senderA)

        val storeA = SecureChatSenderKeyStore(InMemoryBackingStore())
        val storeB = SecureChatSenderKeyStore(InMemoryBackingStore())

        GroupSessionBuilder(storeA).create(senderKeyName)
        val ciphertext = GroupCipher(storeA, senderKeyName).encrypt("test".toByteArray())

        // B hic SKDM almadi — decrypt NoSessionException firlatmali
        val cipherB = GroupCipher(storeB, senderKeyName)
        var thrown: Throwable? = null
        try {
            cipherB.decrypt(ciphertext)
        } catch (e: org.whispersystems.libsignal.NoSessionException) {
            thrown = e
        }
        assertThat(thrown).isNotNull()
    }

    @Test
    fun `rotate sonrasi eski uye yeni mesaji decrypt edemez`() {
        val groupId = "group-rt-3"
        val senderA = SignalProtocolAddress("user-A", 1)
        val senderKeyName = SenderKeyName(groupId, senderA)

        val storeA = SecureChatSenderKeyStore(InMemoryBackingStore())
        val storeRemoved = SecureChatSenderKeyStore(InMemoryBackingStore())

        // Faz 1: A SKDM dagitti, removed user aldi
        val skdm1 = GroupSessionBuilder(storeA).create(senderKeyName)
        GroupSessionBuilder(storeRemoved).process(senderKeyName, skdm1)

        // Faz 2: A rotate eder — yeni bos record + yeni SKDM
        storeA.storeSenderKey(senderKeyName, org.whispersystems.libsignal.groups.state.SenderKeyRecord())
        val skdm2 = GroupSessionBuilder(storeA).create(senderKeyName)
        // removed user skdm2'yi ALMAZ (cikarildigi icin)

        // Faz 3: A yeni mesaj sifreler
        val ct2 = GroupCipher(storeA, senderKeyName).encrypt("rotate sonrasi".toByteArray())

        // removed user eski key ile decrypt etmeye calisir → bozulur
        var thrown: Throwable? = null
        try {
            GroupCipher(storeRemoved, senderKeyName).decrypt(ct2)
        } catch (e: Exception) {
            thrown = e
        }
        assertThat(thrown).isNotNull()
    }
}
