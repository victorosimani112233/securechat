package com.securechat.crypto

import com.google.common.truth.Truth.assertThat
import com.securechat.crypto.store.CryptoSenderKeyStore
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.slot
import io.mockk.mockk
import org.junit.Before
import org.junit.Test
import org.whispersystems.libsignal.SignalProtocolAddress
import org.whispersystems.libsignal.groups.SenderKeyName
import org.whispersystems.libsignal.groups.state.SenderKeyRecord

/**
 * SecureChatSenderKeyStore icin unit testler.
 * libsignal SenderKeyStore async-storage koprusunun davranisini dogrular.
 */
class SecureChatSenderKeyStoreTest {

    private lateinit var backing: CryptoSenderKeyStore
    private lateinit var store: SecureChatSenderKeyStore

    @Before
    fun setUp() {
        backing = mockk(relaxed = true)
        store = SecureChatSenderKeyStore(backing)
    }

    @Test
    fun `loadSenderKey - kayit yoksa bos SenderKeyRecord doner`() {
        coEvery { backing.loadSenderKey("g1", "alice", 1) } returns null

        val record = store.loadSenderKey(
            SenderKeyName("g1", SignalProtocolAddress("alice", 1))
        )

        // Bos record — sender key state bos baslar
        assertThat(record).isNotNull()
        assertThat(record.serialize()).isNotNull()
    }

    @Test
    fun `loadSenderKey - kayit varsa SenderKeyRecord rehydrate edilir`() {
        // Bos record serialize et, sonra ayni bytes ile rehydrate ediyoruz
        val emptyRecord = SenderKeyRecord()
        val serialized = emptyRecord.serialize()
        coEvery { backing.loadSenderKey("g2", "bob", 1) } returns serialized

        val record = store.loadSenderKey(
            SenderKeyName("g2", SignalProtocolAddress("bob", 1))
        )

        assertThat(record.serialize()).isEqualTo(serialized)
    }

    @Test
    fun `storeSenderKey - backing store'a (groupId, senderId, deviceId, bytes) gecirir`() {
        val record = SenderKeyRecord()
        val groupIdSlot = slot<String>()
        val senderIdSlot = slot<String>()
        val deviceIdSlot = slot<Int>()
        val bytesSlot = slot<ByteArray>()
        coEvery {
            backing.storeSenderKey(
                capture(groupIdSlot), capture(senderIdSlot), capture(deviceIdSlot), capture(bytesSlot)
            )
        } returns Unit

        store.storeSenderKey(
            SenderKeyName("group-x", SignalProtocolAddress("user-y", 1)),
            record
        )

        assertThat(groupIdSlot.captured).isEqualTo("group-x")
        assertThat(senderIdSlot.captured).isEqualTo("user-y")
        assertThat(deviceIdSlot.captured).isEqualTo(1)
        assertThat(bytesSlot.captured).isEqualTo(record.serialize())
    }
}
