package com.securechat.app.ui.viewmodel.chat

import com.securechat.storage.repository.MessageRepository
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class ChatDisappearingManagerTest {

    private val messageRepository = mockk<MessageRepository>()
    private val manager = ChatDisappearingManager(
        conversationId = "conversation",
        userSession = mockk(relaxed = true),
        signalingClient = mockk(relaxed = true),
        conversationDao = mockk(relaxed = true),
        messageRepository = messageRepository
    )

    @Test
    fun `disabled timer performs startup cleanup without scheduling a loop`() = runTest {
        coEvery { messageRepository.deleteExpiredMessages() } returns 0

        manager.startCleanupLoop(backgroundScope)
        runCurrent()
        advanceTimeBy(180_000)
        runCurrent()

        coVerify(exactly = 1) { messageRepository.deleteExpiredMessages() }
    }

    @Test
    fun `enabled timer starts and disabling it stops periodic cleanup`() = runTest {
        coEvery { messageRepository.deleteExpiredMessages() } returns 0
        manager.setLocalCachedDuration(30_000)

        manager.startCleanupLoop(backgroundScope)
        runCurrent()
        advanceTimeBy(5_000)
        runCurrent()
        coVerify(exactly = 2) { messageRepository.deleteExpiredMessages() }

        manager.setLocalCachedDuration(0)
        runCurrent()
        advanceTimeBy(60_000)
        runCurrent()

        coVerify(exactly = 2) { messageRepository.deleteExpiredMessages() }
    }
}
