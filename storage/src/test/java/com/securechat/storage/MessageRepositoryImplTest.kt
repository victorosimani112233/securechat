package com.securechat.storage

import com.google.common.truth.Truth.assertThat
import com.securechat.storage.dao.ConversationDao
import com.securechat.storage.dao.MessageDao
import com.securechat.storage.domain.LocalMessage
import com.securechat.storage.entity.ConversationEntity
import com.securechat.storage.entity.MessageEntity
import com.securechat.storage.model.MessageContentType
import com.securechat.storage.model.MessageStatus
import com.securechat.storage.repository.MessageRepositoryImpl
import com.securechat.storage.resolver.ContactNameResolver
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.runTest
import org.junit.Before
import org.junit.Test

/**
 * MessageRepositoryImpl icin unit testler.
 * Mesaj kaydetme, getirme, durumu guncelleme ve silme islemlerini dogrular.
 */
class MessageRepositoryImplTest {

    private lateinit var messageDao: MessageDao
    private lateinit var conversationDao: ConversationDao
    private lateinit var contactNameResolver: ContactNameResolver
    private lateinit var repository: MessageRepositoryImpl

    @Before
    fun setup() {
        messageDao = mockk(relaxed = true)
        conversationDao = mockk(relaxed = true)
        contactNameResolver = mockk(relaxed = true)
        coEvery { contactNameResolver.resolveDisplayName(any()) } returns "Test User"
        coEvery { contactNameResolver.resolvePhoneNumber(any()) } returns "+905551234567"
        repository = MessageRepositoryImpl(messageDao, conversationDao, contactNameResolver)
    }

    private fun createTestMessage(
        id: String = "msg-1",
        conversationId: String = "conv-1",
        senderId: String = "user-1",
        peerId: String = "peer-1",
        content: String = "Merhaba",
        isOutgoing: Boolean = true
    ) = LocalMessage(
        id = id,
        conversationId = conversationId,
        senderId = senderId,
        peerId = peerId,
        content = content,
        contentType = MessageContentType.TEXT,
        timestamp = System.currentTimeMillis(),
        status = MessageStatus.SENDING,
        isOutgoing = isOutgoing
    )

    @Test
    fun `saveMessage inserts entity via DAO`() = runTest {
        val message = createTestMessage()
        coEvery { conversationDao.getById("conv-1") } returns null
        coEvery { conversationDao.getByPeerId("peer-1") } returns null

        repository.saveMessage(message)

        coVerify { messageDao.insert(any()) }
    }

    @Test
    fun `saveMessage updates conversation last message for incoming`() = runTest {
        val conversation = ConversationEntity(
            id = "conv-1",
            peerId = "peer-1",
            peerName = "Peer",
            peerPhone = "+905551234567",
            lastMessage = null,
            lastMessageTimestamp = null,
            unreadCount = 0
        )
        coEvery { conversationDao.getById("conv-1") } returns conversation

        val message = createTestMessage(isOutgoing = false)
        repository.saveMessage(message)

        coVerify {
            conversationDao.update(match { entity ->
                entity.lastMessage == message.content &&
                    entity.unreadCount == 1
            })
        }
    }

    @Test
    fun `saveMessage does not increment unread for outgoing`() = runTest {
        val conversation = ConversationEntity(
            id = "conv-1",
            peerId = "peer-1",
            peerName = "Peer",
            peerPhone = "+905551234567",
            lastMessage = null,
            lastMessageTimestamp = null,
            unreadCount = 5
        )
        coEvery { conversationDao.getById("conv-1") } returns conversation

        val message = createTestMessage(isOutgoing = true)
        repository.saveMessage(message)

        coVerify {
            conversationDao.update(match { entity ->
                entity.unreadCount == 5
            })
        }
    }

    @Test
    fun `saveMessage finds conversation by id for group messages`() = runTest {
        val groupConv = ConversationEntity(
            id = "group-1",
            peerId = "group-1",
            peerName = "Test Grup",
            peerPhone = "",
            lastMessage = null,
            lastMessageTimestamp = null,
            unreadCount = 0,
            isGroup = true,
            groupMembers = "user-1,user-2,user-3"
        )
        coEvery { conversationDao.getById("group-1") } returns groupConv

        val message = createTestMessage(
            conversationId = "group-1",
            senderId = "user-2",
            peerId = "user-2",
            isOutgoing = false
        )
        repository.saveMessage(message)

        coVerify { messageDao.insert(any()) }
        coVerify {
            conversationDao.update(match { entity ->
                entity.id == "group-1" && entity.unreadCount == 1
            })
        }
    }

    @Test
    fun `saveMessage creates conversation when not found by id or peerId`() = runTest {
        coEvery { conversationDao.getById("conv-1") } returns null
        coEvery { conversationDao.getByPeerId("peer-1") } returns null

        val message = createTestMessage()
        repository.saveMessage(message)

        coVerify {
            conversationDao.insert(match { entity ->
                entity.id == "conv-1" && entity.peerId == "peer-1"
            })
        }
    }

    @Test
    fun `getMessages returns flow of domain models`() = runTest {
        val entities = listOf(
            MessageEntity(
                id = "msg-1",
                conversationId = "conv-1",
                senderId = "user-1",
                content = "Test",
                contentType = MessageContentType.TEXT,
                timestamp = 1000L,
                status = MessageStatus.SENT,
                isOutgoing = true
            )
        )
        every { messageDao.getMessages("conv-1") } returns flowOf(entities)

        val result = repository.getMessages("conv-1").first()

        assertThat(result).hasSize(1)
        assertThat(result[0].id).isEqualTo("msg-1")
        assertThat(result[0].content).isEqualTo("Test")
    }

    @Test
    fun `getConversations returns flow of domain models`() = runTest {
        val entities = listOf(
            ConversationEntity(
                id = "conv-1",
                peerId = "peer-1",
                peerName = "Ali",
                peerPhone = "+905551234567",
                lastMessage = "Selam",
                lastMessageTimestamp = 2000L,
                unreadCount = 3,
                isPinned = true
            )
        )
        every { conversationDao.getAll() } returns flowOf(entities)

        val result = repository.getConversations().first()

        assertThat(result).hasSize(1)
        assertThat(result[0].peerName).isEqualTo("Ali")
        assertThat(result[0].unreadCount).isEqualTo(3)
        assertThat(result[0].isPinned).isTrue()
    }

    @Test
    fun `updateMessageStatus delegates to DAO`() = runTest {
        repository.updateMessageStatus("msg-1", MessageStatus.DELIVERED)

        coVerify { messageDao.updateStatus("msg-1", MessageStatus.DELIVERED) }
    }

    @Test
    fun `markConversationAsRead delegates to DAO`() = runTest {
        repository.markConversationAsRead("conv-1")

        coVerify { conversationDao.markAsRead("conv-1") }
    }

    @Test
    fun `deleteMessage delegates to DAO`() = runTest {
        repository.deleteMessage("msg-1")

        coVerify { messageDao.delete("msg-1") }
    }

    @Test
    fun `deleteConversation deletes both messages and conversation`() = runTest {
        repository.deleteConversation("conv-1")

        coVerify { messageDao.deleteByConversation("conv-1") }
        coVerify { conversationDao.delete("conv-1") }
    }

    // --- Bug 019: Silme ve duzenleme sonrasi lastMessage yeniden hesaplama testleri ---

    @Test
    fun `deleteMessage with conversationId recalculates last message`() = runTest {
        coEvery { conversationDao.getLastMessageContent("conv-1") } returns "Onceki mesaj"
        coEvery { conversationDao.getLastMessageTimestamp("conv-1") } returns 1000L

        repository.deleteMessage("msg-1", "conv-1")

        coVerify { messageDao.delete("msg-1") }
        coVerify { conversationDao.updateLastMessageById("conv-1", "Onceki mesaj", 1000L) }
    }

    @Test
    fun `deleteMessage with conversationId sets empty when no messages remain`() = runTest {
        coEvery { conversationDao.getLastMessageContent("conv-1") } returns null
        coEvery { conversationDao.getLastMessageTimestamp("conv-1") } returns null

        repository.deleteMessage("msg-1", "conv-1")

        coVerify { messageDao.delete("msg-1") }
        coVerify { conversationDao.updateLastMessageById("conv-1", "", 0L) }
    }

    @Test
    fun `recalculateLastMessage updates conversation with latest message`() = runTest {
        coEvery { conversationDao.getLastMessageContent("conv-1") } returns "Son mesaj"
        coEvery { conversationDao.getLastMessageTimestamp("conv-1") } returns 5000L

        repository.recalculateLastMessage("conv-1")

        coVerify { conversationDao.updateLastMessageById("conv-1", "Son mesaj", 5000L) }
    }

    @Test
    fun `editMessage updates last message when edited message is most recent`() = runTest {
        val entity = MessageEntity(
            id = "msg-1",
            conversationId = "conv-1",
            senderId = "user-1",
            content = "Eski icerik",
            contentType = MessageContentType.TEXT,
            timestamp = 3000L,
            status = MessageStatus.SENT,
            isOutgoing = true
        )
        coEvery { messageDao.getById("msg-1") } returns entity
        coEvery { conversationDao.getLastMessageTimestamp("conv-1") } returns 3000L

        repository.editMessage("msg-1", "Yeni icerik", 4000L)

        coVerify { messageDao.updateContentEdited("msg-1", "Yeni icerik", 4000L, any()) }
        coVerify { conversationDao.updateLastMessageById("conv-1", "Yeni icerik", 3000L) }
    }

    @Test
    fun `editMessage does not update last message when not most recent`() = runTest {
        val entity = MessageEntity(
            id = "msg-1",
            conversationId = "conv-1",
            senderId = "user-1",
            content = "Eski icerik",
            contentType = MessageContentType.TEXT,
            timestamp = 1000L,
            status = MessageStatus.SENT,
            isOutgoing = true
        )
        coEvery { messageDao.getById("msg-1") } returns entity
        // En son mesajin zaman damgasi farkli — duzenlenen mesaj en son degil
        coEvery { conversationDao.getLastMessageTimestamp("conv-1") } returns 5000L

        repository.editMessage("msg-1", "Yeni icerik", 4000L)

        coVerify { messageDao.updateContentEdited("msg-1", "Yeni icerik", 4000L, any()) }
        coVerify(exactly = 0) { conversationDao.updateLastMessageById(any(), any(), any()) }
    }

    @Test
    fun `updateMessageContent updates last message when content is most recent`() = runTest {
        val entity = MessageEntity(
            id = "msg-1",
            conversationId = "conv-1",
            senderId = "user-1",
            content = "Silinecek mesaj",
            contentType = MessageContentType.TEXT,
            timestamp = 3000L,
            status = MessageStatus.SENT,
            isOutgoing = true
        )
        coEvery { messageDao.getById("msg-1") } returns entity
        coEvery { conversationDao.getLastMessageTimestamp("conv-1") } returns 3000L

        repository.updateMessageContent("msg-1", "Bu mesaj silindi", "DELETED")

        coVerify { messageDao.updateContent("msg-1", "Bu mesaj silindi", "DELETED") }
        coVerify { conversationDao.updateLastMessageById("conv-1", "Bu mesaj silindi", 3000L) }
    }

    // --- Bug 017: Takili mesajlari kurtarma testleri ---

    @Test
    fun `getStuckSendingMessages returns messages older than threshold`() = runTest {
        val stuckEntities = listOf(
            MessageEntity(
                id = "stuck-1",
                conversationId = "conv-1",
                senderId = "user-1",
                content = "Takili mesaj",
                contentType = MessageContentType.TEXT,
                timestamp = 1000L,
                status = MessageStatus.SENDING,
                isOutgoing = true
            )
        )
        coEvery { messageDao.getStuckSendingMessages(any()) } returns stuckEntities

        val result = repository.getStuckSendingMessages(120_000L)

        assertThat(result).hasSize(1)
        assertThat(result[0].id).isEqualTo("stuck-1")
        assertThat(result[0].status).isEqualTo(MessageStatus.SENDING)
    }

    @Test
    fun `getStuckSendingMessages returns empty when no stuck messages`() = runTest {
        coEvery { messageDao.getStuckSendingMessages(any()) } returns emptyList()

        val result = repository.getStuckSendingMessages(120_000L)

        assertThat(result).isEmpty()
    }
}
