package com.securechat.app.domain.usecase

import com.securechat.app.data.UserSession
import com.securechat.network.SignalingClient
import com.securechat.storage.domain.LocalMessage
import com.securechat.storage.model.MessageContentType
import com.securechat.storage.model.MessageStatus
import com.securechat.storage.repository.MessageRepository
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import io.mockk.slot
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * SendMessageUseCase birim testleri.
 */
class SendMessageUseCaseTest {

    private lateinit var messageRepository: MessageRepository
    private lateinit var signalingClient: SignalingClient
    private lateinit var userSession: UserSession
    private lateinit var conversationDao: com.securechat.storage.dao.ConversationDao
    private lateinit var sendMessageUseCase: SendMessageUseCase

    @Before
    fun setup() {
        messageRepository = mockk(relaxed = true)
        signalingClient = mockk(relaxed = true)
        userSession = mockk(relaxed = true)
        conversationDao = mockk(relaxed = true)
        every { userSession.userId } returns "local_user"
        every { signalingClient.sendSignal(any()) } returns true
        sendMessageUseCase = SendMessageUseCase(messageRepository, signalingClient, userSession, conversationDao)
    }

    @Test
    fun `invoke creates message with correct conversationId`() = runTest {
        val conversationId = "conv_123"
        val content = "Merhaba"

        sendMessageUseCase(conversationId, content)

        val messageSlot = slot<LocalMessage>()
        coVerify { messageRepository.saveMessage(capture(messageSlot)) }

        assertEquals(conversationId, messageSlot.captured.conversationId)
    }

    @Test
    fun `invoke creates message with correct content`() = runTest {
        val content = "Test mesaji"

        sendMessageUseCase("conv_1", content)

        val messageSlot = slot<LocalMessage>()
        coVerify { messageRepository.saveMessage(capture(messageSlot)) }

        assertEquals(content, messageSlot.captured.content)
    }

    @Test
    fun `invoke creates message with TEXT content type`() = runTest {
        sendMessageUseCase("conv_1", "test")

        val messageSlot = slot<LocalMessage>()
        coVerify { messageRepository.saveMessage(capture(messageSlot)) }

        assertEquals(MessageContentType.TEXT, messageSlot.captured.contentType)
    }

    @Test
    fun `invoke creates message with SENDING status`() = runTest {
        sendMessageUseCase("conv_1", "test")

        val messageSlot = slot<LocalMessage>()
        coVerify { messageRepository.saveMessage(capture(messageSlot)) }

        assertEquals(MessageStatus.SENDING, messageSlot.captured.status)
    }

    @Test
    fun `invoke creates outgoing message`() = runTest {
        sendMessageUseCase("conv_1", "test")

        val messageSlot = slot<LocalMessage>()
        coVerify { messageRepository.saveMessage(capture(messageSlot)) }

        assertTrue(messageSlot.captured.isOutgoing)
    }

    @Test
    fun `invoke creates message with unique id`() = runTest {
        sendMessageUseCase("conv_1", "test1")
        sendMessageUseCase("conv_1", "test2")

        val messages = mutableListOf<LocalMessage>()
        coVerify(exactly = 2) { messageRepository.saveMessage(capture(messages)) }

        assertTrue(messages[0].id != messages[1].id)
    }

    @Test
    fun `invoke uses userId from UserSession as senderId`() = runTest {
        sendMessageUseCase("conv_1", "test")

        val messageSlot = slot<LocalMessage>()
        coVerify { messageRepository.saveMessage(capture(messageSlot)) }

        assertEquals("local_user", messageSlot.captured.senderId)
    }

    @Test
    fun `invoke calls repository saveMessage`() = runTest {
        sendMessageUseCase("conv_1", "test")

        coVerify(exactly = 1) { messageRepository.saveMessage(any()) }
    }

    @Test
    fun `invoke sends signal via signalingClient`() = runTest {
        sendMessageUseCase("conv_1", "test")

        coVerify(exactly = 1) { signalingClient.sendSignal(any()) }
    }

    @Test
    fun `invoke updates status to SENT on success`() = runTest {
        every { signalingClient.sendSignal(any()) } returns true

        sendMessageUseCase("conv_1", "test")

        coVerify { messageRepository.updateMessageStatus(any(), MessageStatus.SENT) }
    }

    @Test
    fun `invoke updates status to FAILED on signaling failure`() = runTest {
        every { signalingClient.sendSignal(any()) } returns false

        sendMessageUseCase("conv_1", "test")

        coVerify { messageRepository.updateMessageStatus(any(), MessageStatus.FAILED) }
    }
}
