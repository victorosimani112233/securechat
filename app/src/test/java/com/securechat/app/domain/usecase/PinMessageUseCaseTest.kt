package com.securechat.app.domain.usecase

import com.google.common.truth.Truth.assertThat
import com.securechat.app.data.UserSession
import com.securechat.network.SignalMessage
import com.securechat.network.SignalingClient
import com.securechat.storage.dao.ConversationDao
import com.securechat.storage.domain.LocalMessage
import com.securechat.storage.entity.ConversationEntity
import com.securechat.storage.model.MessageContentType
import com.securechat.storage.model.MessageStatus
import com.securechat.storage.repository.MessageRepository
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import io.mockk.slot
import kotlinx.coroutines.test.runTest
import org.junit.Before
import org.junit.Test

/**
 * PinMessageUseCase birim testleri.
 *
 * Kontroller:
 *   - 1:1 sohbette her iki taraf da pin/unpin yapabilir
 *   - Grupta yalniz admin pin yapabilir; non-admin IllegalAccessException alir
 *   - Repository ve signaling client'a dogru cagrilar yapilir
 */
class PinMessageUseCaseTest {

    private lateinit var conversationDao: ConversationDao
    private lateinit var messageRepository: MessageRepository
    private lateinit var userSession: UserSession
    private lateinit var signalingClient: SignalingClient
    private lateinit var useCase: PinMessageUseCase

    private val localUserId = "user-local"
    private val peerId = "user-peer"
    private val groupId = "group-1"
    private val messageId = "msg-1"

    @Before
    fun setup() {
        conversationDao = mockk(relaxed = true)
        messageRepository = mockk(relaxed = true)
        userSession = mockk(relaxed = true)
        signalingClient = mockk(relaxed = true)
        every { userSession.userId } returns localUserId
        coEvery { messageRepository.getMessageById(messageId) } returns dummyMessage()
        useCase = PinMessageUseCase(
            conversationDao = conversationDao,
            messageRepository = messageRepository,
            userSession = userSession,
            signalingClient = signalingClient
        )
    }

    @Test
    fun `1to1 pin — kullanici pin yapabilir`() = runTest {
        coEvery { conversationDao.getById(peerId) } returns directConversation()

        useCase(peerId, messageId, isPinned = true)

        coVerify { messageRepository.updateMessagePinned(messageId, true, any()) }
        // 1:1: tek MessagePin signal'i karsi tarafa
        val captured = slot<SignalMessage>()
        coVerify { signalingClient.sendSignal(capture(captured)) }
        val pin = captured.captured as SignalMessage.MessagePin
        assertThat(pin.recipientId).isEqualTo(peerId)
        assertThat(pin.isPinned).isTrue()
        assertThat(pin.groupId).isNull()
    }

    @Test
    fun `grup pin — admin yapabilir`() = runTest {
        coEvery { conversationDao.getById(groupId) } returns groupConversation(
            adminIds = listOf(localUserId),
            memberIds = listOf(localUserId, peerId, "user-3")
        )

        useCase(groupId, messageId, isPinned = true)

        coVerify { messageRepository.updateMessagePinned(messageId, true, any()) }
        // Gruptaki diger uyelere fanout (localUserId haric — 2 uye)
        coVerify(exactly = 2) { signalingClient.sendSignal(any()) }
    }

    @Test(expected = IllegalAccessException::class)
    fun `grup pin — non-admin denenirse exception`() = runTest {
        coEvery { conversationDao.getById(groupId) } returns groupConversation(
            adminIds = listOf("user-3"),  // localUserId admin DEGIL
            memberIds = listOf(localUserId, peerId, "user-3")
        )

        useCase(groupId, messageId, isPinned = true)
    }

    @Test
    fun `unpin — pinnedAt null gonderilir`() = runTest {
        coEvery { conversationDao.getById(peerId) } returns directConversation()

        useCase(peerId, messageId, isPinned = false)

        coVerify { messageRepository.updateMessagePinned(messageId, false, null) }
    }

    private fun dummyMessage() = LocalMessage(
        id = messageId,
        conversationId = peerId,
        senderId = peerId,
        peerId = peerId,
        content = "test",
        contentType = MessageContentType.TEXT,
        timestamp = 1000L,
        status = MessageStatus.DELIVERED,
        isOutgoing = false
    )

    private fun directConversation() = ConversationEntity(
        id = peerId,
        peerId = peerId,
        peerName = "Peer",
        peerPhone = "",
        lastMessage = null,
        lastMessageTimestamp = null,
        isGroup = false
    )

    private fun groupConversation(adminIds: List<String>, memberIds: List<String>) = ConversationEntity(
        id = groupId,
        peerId = groupId,
        peerName = "Grup",
        peerPhone = "",
        lastMessage = null,
        lastMessageTimestamp = null,
        isGroup = true,
        groupMembers = memberIds.joinToString(","),
        groupAdmins = adminIds.joinToString(",")
    )
}
