package com.securechat.app.domain.usecase

import com.securechat.storage.repository.MessageRepository
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import org.junit.Before
import org.junit.Test

/**
 * MarkAsReadUseCase birim testleri.
 */
class MarkAsReadUseCaseTest {

    private lateinit var messageRepository: MessageRepository
    private lateinit var markAsReadUseCase: MarkAsReadUseCase

    @Before
    fun setup() {
        messageRepository = mockk(relaxed = true)
        markAsReadUseCase = MarkAsReadUseCase(messageRepository)
    }

    @Test
    fun `invoke delegates to repository markConversationAsRead`() = runTest {
        val conversationId = "conv_123"

        markAsReadUseCase(conversationId)

        coVerify { messageRepository.markConversationAsRead(conversationId) }
    }

    @Test
    fun `invoke calls repository exactly once`() = runTest {
        markAsReadUseCase("conv_1")

        coVerify(exactly = 1) { messageRepository.markConversationAsRead(any()) }
    }

    @Test
    fun `invoke passes correct conversationId`() = runTest {
        val conversationId = "specific_conv_id"

        markAsReadUseCase(conversationId)

        coVerify { messageRepository.markConversationAsRead(conversationId) }
    }
}
