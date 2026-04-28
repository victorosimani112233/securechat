package com.securechat.network

import com.google.common.truth.Truth.assertThat
import com.securechat.storage.repository.MessageRepository
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import io.mockk.slot
import kotlinx.coroutines.test.runTest
import org.junit.Before
import org.junit.Test

/**
 * StuckMessageRecovery sinifinin unit testleri (Bug 003).
 * SENDING durumunda takili kalan mesajlarin FAILED olarak isaretlenmesini test eder.
 */
class StuckMessageRecoveryTest {

    private lateinit var mockMessageRepository: MessageRepository
    private lateinit var stuckMessageRecovery: StuckMessageRecovery

    @Before
    fun setUp() {
        mockMessageRepository = mockk(relaxed = true)
        stuckMessageRecovery = StuckMessageRecovery(mockMessageRepository)
    }

    @Test
    fun `recoverStuckMessages calls repository with correct cutoff`() = runTest {
        val cutoffSlot = slot<Long>()
        coEvery { mockMessageRepository.markStuckMessagesAsFailed(capture(cutoffSlot)) } returns 0

        val beforeCall = System.currentTimeMillis()
        stuckMessageRecovery.recoverStuckMessages()
        val afterCall = System.currentTimeMillis()

        // Cutoff degeri, suan - 30 saniye olmali
        val cutoff = cutoffSlot.captured
        val expectedMin = beforeCall - SignalingClient.STUCK_MESSAGE_TIMEOUT_MS
        val expectedMax = afterCall - SignalingClient.STUCK_MESSAGE_TIMEOUT_MS
        assertThat(cutoff).isAtLeast(expectedMin)
        assertThat(cutoff).isAtMost(expectedMax)
    }

    @Test
    fun `recoverStuckMessages returns count of recovered messages`() = runTest {
        coEvery { mockMessageRepository.markStuckMessagesAsFailed(any()) } returns 5

        val result = stuckMessageRecovery.recoverStuckMessages()

        assertThat(result).isEqualTo(5)
    }

    @Test
    fun `recoverStuckMessages returns zero when no stuck messages`() = runTest {
        coEvery { mockMessageRepository.markStuckMessagesAsFailed(any()) } returns 0

        val result = stuckMessageRecovery.recoverStuckMessages()

        assertThat(result).isEqualTo(0)
    }

    @Test
    fun `recoverStuckMessages uses custom timeout`() = runTest {
        val cutoffSlot = slot<Long>()
        coEvery { mockMessageRepository.markStuckMessagesAsFailed(capture(cutoffSlot)) } returns 0

        val customTimeout = 60_000L // 60 saniye
        val beforeCall = System.currentTimeMillis()
        stuckMessageRecovery.recoverStuckMessages(customTimeout)
        val afterCall = System.currentTimeMillis()

        val cutoff = cutoffSlot.captured
        val expectedMin = beforeCall - customTimeout
        val expectedMax = afterCall - customTimeout
        assertThat(cutoff).isAtLeast(expectedMin)
        assertThat(cutoff).isAtMost(expectedMax)
    }

    @Test
    fun `recoverStuckMessages calls markStuckMessagesAsFailed exactly once`() = runTest {
        coEvery { mockMessageRepository.markStuckMessagesAsFailed(any()) } returns 3

        stuckMessageRecovery.recoverStuckMessages()

        coVerify(exactly = 1) { mockMessageRepository.markStuckMessagesAsFailed(any()) }
    }

    @Test
    fun `default timeout is 30 seconds`() {
        assertThat(SignalingClient.STUCK_MESSAGE_TIMEOUT_MS).isEqualTo(30_000L)
    }
}
