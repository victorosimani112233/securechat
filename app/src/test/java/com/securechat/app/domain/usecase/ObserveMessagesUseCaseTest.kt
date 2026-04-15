package com.securechat.app.domain.usecase

import com.securechat.storage.domain.LocalMessage
import com.securechat.storage.model.MessageContentType
import com.securechat.storage.model.MessageStatus
import com.securechat.storage.repository.MessageRepository
import io.mockk.every
import io.mockk.mockk
import io.mockk.verify
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test

/**
 * ObserveMessagesUseCase birim testleri.
 */
class ObserveMessagesUseCaseTest {

    private lateinit var messageRepository: MessageRepository
    private lateinit var observeMessagesUseCase: ObserveMessagesUseCase

    @Before
    fun setup() {
        messageRepository = mockk()
        observeMessagesUseCase = ObserveMessagesUseCase(messageRepository)
    }

    @Test
    fun `invoke delegates to repository getMessages`() = runTest {
        val conversationId = "conv_123"
        every { messageRepository.getMessages(conversationId) } returns flowOf(emptyList())

        observeMessagesUseCase(conversationId)

        verify { messageRepository.getMessages(conversationId) }
    }

    @Test
    fun `invoke returns messages from repository`() = runTest {
        val conversationId = "conv_123"
        val testMessages = listOf(
            createTestMessage("msg_1", conversationId),
            createTestMessage("msg_2", conversationId)
        )
        every { messageRepository.getMessages(conversationId) } returns flowOf(testMessages)

        val result = observeMessagesUseCase(conversationId).first()

        assertEquals(2, result.size)
        assertEquals("msg_1", result[0].id)
        assertEquals("msg_2", result[1].id)
    }

    @Test
    fun `invoke returns empty list when no messages`() = runTest {
        val conversationId = "conv_empty"
        every { messageRepository.getMessages(conversationId) } returns flowOf(emptyList())

        val result = observeMessagesUseCase(conversationId).first()

        assertEquals(0, result.size)
    }

    private fun createTestMessage(id: String, conversationId: String): LocalMessage {
        return LocalMessage(
            id = id,
            conversationId = conversationId,
            senderId = "local_user",
            peerId = "peer_1",
            content = "Test mesaji",
            contentType = MessageContentType.TEXT,
            timestamp = System.currentTimeMillis(),
            status = MessageStatus.SENT,
            isOutgoing = true
        )
    }
}
