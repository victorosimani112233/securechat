package com.securechat.app.data

import com.google.common.truth.Truth.assertThat
import com.securechat.network.SignalMessage
import com.securechat.network.SignalingClient
import com.securechat.storage.dao.PendingTimerUpdateDao
import com.securechat.storage.entity.PendingTimerUpdateEntity
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import io.mockk.slot
import kotlinx.coroutines.test.runTest
import org.junit.Test

/**
 * `PendingTimerFlusher` testleri.
 *
 * WS bagliyken sendOrQueue direkt gonderir; bagli degilse persistent kuyruga eklenir.
 * Reconnect callback flush() cagirir — basarilar silinir, basarisizlar kalir.
 */
class PendingTimerFlusherTest {

    private val signalingClient: SignalingClient = mockk(relaxed = true)
    private val dao: PendingTimerUpdateDao = mockk(relaxed = true)
    private val userSession: UserSession = mockk<UserSession>().apply {
        every { userId } returns "self"
    }
    private val flusher = PendingTimerFlusher(signalingClient, dao, userSession)

    @Test
    fun `sendOrQueue - WS bagliyken kuyruga eklemez`() = runTest {
        every { signalingClient.sendSignal(any()) } returns true

        flusher.sendOrQueue(targetUserId = "peer", conversationId = "conv", duration = 60_000L)

        coVerify(exactly = 0) { dao.insert(any()) }
    }

    @Test
    fun `sendOrQueue - WS kapaliysa kuyruga ekler`() = runTest {
        every { signalingClient.sendSignal(any()) } returns false

        flusher.sendOrQueue(targetUserId = "peer", conversationId = "conv", duration = 60_000L)

        val entitySlot = slot<PendingTimerUpdateEntity>()
        coVerify { dao.insert(capture(entitySlot)) }
        assertThat(entitySlot.captured.conversationId).isEqualTo("conv")
        assertThat(entitySlot.captured.targetUserId).isEqualTo("peer")
        assertThat(entitySlot.captured.duration).isEqualTo(60_000L)
    }

    @Test
    fun `sendOrQueue - userId yoksa sessizce no-op`() = runTest {
        every { userSession.userId } returns null

        flusher.sendOrQueue("peer", "conv", 60_000L)

        coVerify(exactly = 0) { dao.insert(any()) }
        coVerify(exactly = 0) { signalingClient.sendSignal(any()) }
    }

    @Test
    fun `flush - basarililari siler basarisizlari birakir`() = runTest {
        val pending = listOf(
            PendingTimerUpdateEntity(id = "1", conversationId = "c1", targetUserId = "u1", duration = 30_000L),
            PendingTimerUpdateEntity(id = "2", conversationId = "c2", targetUserId = "u2", duration = 60_000L)
        )
        coEvery { dao.getAll() } returns pending
        every { signalingClient.sendSignal(any()) } returns true

        flusher.flush()

        coVerify { dao.deleteById("1") }
        coVerify { dao.deleteById("2") }
    }

    @Test
    fun `flush - bir guncellem fail olursa sonrakilere devam etmez`() = runTest {
        val pending = listOf(
            PendingTimerUpdateEntity(id = "1", conversationId = "c1", targetUserId = "u1", duration = 30_000L),
            PendingTimerUpdateEntity(id = "2", conversationId = "c2", targetUserId = "u2", duration = 60_000L)
        )
        coEvery { dao.getAll() } returns pending
        // Ilki basarili, ikincisi fail
        every { signalingClient.sendSignal(any()) } returnsMany listOf(true, false)

        flusher.flush()

        coVerify { dao.deleteById("1") }
        coVerify(exactly = 0) { dao.deleteById("2") }
    }

    @Test
    fun `flush - bos kuyruk no-op`() = runTest {
        coEvery { dao.getAll() } returns emptyList()

        flusher.flush()

        coVerify(exactly = 0) { signalingClient.sendSignal(any()) }
    }

    @Test
    fun `sendOrQueue - DisappearingTimer signal dogru alanlarla gonderilir`() = runTest {
        every { signalingClient.sendSignal(any()) } returns true

        flusher.sendOrQueue(targetUserId = "peer", conversationId = "conv", duration = 120_000L)

        val signalSlot = slot<SignalMessage>()
        coVerify { signalingClient.sendSignal(capture(signalSlot)) }
        val signal = signalSlot.captured as SignalMessage.DisappearingTimer
        assertThat(signal.senderId).isEqualTo("self")
        assertThat(signal.recipientId).isEqualTo("peer")
        assertThat(signal.conversationId).isEqualTo("conv")
        assertThat(signal.duration).isEqualTo(120_000L)
    }
}
