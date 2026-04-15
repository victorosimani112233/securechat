package com.securechat.storage

import com.google.common.truth.Truth.assertThat
import com.securechat.storage.dao.ConversationDao
import com.securechat.storage.dao.MessageDao
import com.securechat.storage.domain.Conversation
import com.securechat.storage.domain.LocalMessage
import com.securechat.storage.entity.ConversationEntity
import com.securechat.storage.entity.MessageEntity
import com.securechat.storage.model.MessageContentType
import com.securechat.storage.model.MessageStatus
import com.securechat.storage.repository.MessageRepositoryImpl
import com.securechat.storage.repository.toDomain
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
 * Grup sohbeti depolama islemleri icin unit testler.
 * ConversationEntity isGroup/groupMembers alanlari, domain donusumleri
 * ve repository davranislarini dogrular.
 */
class GroupChatStorageTest {

    private lateinit var messageDao: MessageDao
    private lateinit var conversationDao: ConversationDao
    private lateinit var repository: MessageRepositoryImpl

    @Before
    fun setup() {
        messageDao = mockk(relaxed = true)
        conversationDao = mockk(relaxed = true)
        repository = MessageRepositoryImpl(messageDao, conversationDao)
    }

    // --- ConversationEntity grup alanlari ---

    @Test
    fun `ConversationEntity defaults isGroup to false`() {
        val entity = ConversationEntity(
            id = "conv-1",
            peerId = "peer-1",
            peerName = "Ali",
            peerPhone = "+905551234567",
            lastMessage = null,
            lastMessageTimestamp = null
        )
        assertThat(entity.isGroup).isFalse()
        assertThat(entity.groupMembers).isNull()
    }

    @Test
    fun `ConversationEntity group fields set correctly`() {
        val entity = ConversationEntity(
            id = "group-1",
            peerId = "group-1",
            peerName = "Test Grup",
            peerPhone = "",
            lastMessage = null,
            lastMessageTimestamp = null,
            isGroup = true,
            groupMembers = "user-1,user-2,user-3"
        )
        assertThat(entity.isGroup).isTrue()
        assertThat(entity.groupMembers).isEqualTo("user-1,user-2,user-3")
    }

    // --- Domain donusumleri ---

    @Test
    fun `toDomain maps isGroup correctly for group conversation`() {
        val entity = ConversationEntity(
            id = "group-1",
            peerId = "group-1",
            peerName = "Proje Grubu",
            peerPhone = "",
            lastMessage = "Merhaba",
            lastMessageTimestamp = 1000L,
            unreadCount = 2,
            isGroup = true,
            groupMembers = "user-a,user-b,user-c"
        )

        val domain = entity.toDomain()

        assertThat(domain.isGroup).isTrue()
        assertThat(domain.groupMembers).containsExactly("user-a", "user-b", "user-c")
        assertThat(domain.peerName).isEqualTo("Proje Grubu")
    }

    @Test
    fun `toDomain maps isGroup false for 1-1 conversation`() {
        val entity = ConversationEntity(
            id = "peer-1",
            peerId = "peer-1",
            peerName = "Ali",
            peerPhone = "+905551234567",
            lastMessage = "Selam",
            lastMessageTimestamp = 2000L,
            unreadCount = 0,
            isGroup = false,
            groupMembers = null
        )

        val domain = entity.toDomain()

        assertThat(domain.isGroup).isFalse()
        assertThat(domain.groupMembers).isEmpty()
    }

    @Test
    fun `toDomain handles empty groupMembers string`() {
        val entity = ConversationEntity(
            id = "group-1",
            peerId = "group-1",
            peerName = "Bos Grup",
            peerPhone = "",
            lastMessage = null,
            lastMessageTimestamp = null,
            isGroup = true,
            groupMembers = ""
        )

        val domain = entity.toDomain()

        assertThat(domain.isGroup).isTrue()
        assertThat(domain.groupMembers).isEmpty()
    }

    @Test
    fun `toDomain filters blank entries in groupMembers`() {
        val entity = ConversationEntity(
            id = "group-1",
            peerId = "group-1",
            peerName = "Grup",
            peerPhone = "",
            lastMessage = null,
            lastMessageTimestamp = null,
            isGroup = true,
            groupMembers = "user-a,,user-b,"
        )

        val domain = entity.toDomain()

        assertThat(domain.groupMembers).containsExactly("user-a", "user-b")
    }

    // --- Conversation domain modeli ---

    @Test
    fun `Conversation domain model defaults isGroup to false`() {
        val conversation = Conversation(
            id = "conv-1",
            peerId = "peer-1",
            peerName = "Ali",
            peerPhone = "+905551234567",
            lastMessage = null,
            lastMessageTimestamp = null,
            unreadCount = 0,
            isMuted = false,
            isPinned = false
        )
        assertThat(conversation.isGroup).isFalse()
        assertThat(conversation.groupMembers).isEmpty()
    }

    @Test
    fun `Conversation domain model with group fields`() {
        val conversation = Conversation(
            id = "group-1",
            peerId = "group-1",
            peerName = "Proje Grubu",
            peerPhone = "",
            lastMessage = "Son mesaj",
            lastMessageTimestamp = 5000L,
            unreadCount = 3,
            isMuted = false,
            isPinned = true,
            isGroup = true,
            groupMembers = listOf("user-1", "user-2", "user-3")
        )
        assertThat(conversation.isGroup).isTrue()
        assertThat(conversation.groupMembers).hasSize(3)
    }

    // --- Repository: Grup mesaj kaydetme ---

    @Test
    fun `saveMessage to group updates group conversation unread count`() = runTest {
        val groupConv = createGroupConversation()
        coEvery { conversationDao.getById("group-1") } returns groupConv

        val message = createGroupMessage(isOutgoing = false)
        repository.saveMessage(message)

        coVerify {
            conversationDao.update(match { entity ->
                entity.id == "group-1" && entity.unreadCount == 1
            })
        }
    }

    @Test
    fun `saveMessage to group does not increment unread for outgoing`() = runTest {
        val groupConv = createGroupConversation(unreadCount = 3)
        coEvery { conversationDao.getById("group-1") } returns groupConv

        val message = createGroupMessage(isOutgoing = true)
        repository.saveMessage(message)

        coVerify {
            conversationDao.update(match { entity ->
                entity.unreadCount == 3
            })
        }
    }

    @Test
    fun `saveMessage to group sets correct conversationId on entity`() = runTest {
        val groupConv = createGroupConversation()
        coEvery { conversationDao.getById("group-1") } returns groupConv

        val message = createGroupMessage(isOutgoing = false)
        repository.saveMessage(message)

        coVerify {
            messageDao.insert(match { entity ->
                entity.conversationId == "group-1"
            })
        }
    }

    // --- Repository: Grup konusmalarini listeleme ---

    @Test
    fun `getConversations includes group conversations with correct fields`() = runTest {
        val entities = listOf(
            ConversationEntity(
                id = "peer-1",
                peerId = "peer-1",
                peerName = "Ali",
                peerPhone = "+905551234567",
                lastMessage = "Selam",
                lastMessageTimestamp = 1000L,
                unreadCount = 0,
                isGroup = false,
                groupMembers = null
            ),
            ConversationEntity(
                id = "group-1",
                peerId = "group-1",
                peerName = "Proje Grubu",
                peerPhone = "",
                lastMessage = "Toplanti saat 3",
                lastMessageTimestamp = 2000L,
                unreadCount = 5,
                isGroup = true,
                groupMembers = "user-1,user-2,user-3"
            )
        )
        every { conversationDao.getAll() } returns flowOf(entities)

        val result = repository.getConversations().first()

        assertThat(result).hasSize(2)

        val oneToOne = result.first { !it.isGroup }
        assertThat(oneToOne.peerName).isEqualTo("Ali")
        assertThat(oneToOne.groupMembers).isEmpty()

        val group = result.first { it.isGroup }
        assertThat(group.peerName).isEqualTo("Proje Grubu")
        assertThat(group.groupMembers).containsExactly("user-1", "user-2", "user-3")
        assertThat(group.unreadCount).isEqualTo(5)
    }

    @Test
    fun `getMessages returns messages for group conversation`() = runTest {
        val entities = listOf(
            MessageEntity(
                id = "msg-1",
                conversationId = "group-1",
                senderId = "user-1",
                content = "Merhaba grup",
                contentType = MessageContentType.TEXT,
                timestamp = 1000L,
                status = MessageStatus.DELIVERED,
                isOutgoing = false
            ),
            MessageEntity(
                id = "msg-2",
                conversationId = "group-1",
                senderId = "user-2",
                content = "Selam",
                contentType = MessageContentType.TEXT,
                timestamp = 2000L,
                status = MessageStatus.DELIVERED,
                isOutgoing = false
            )
        )
        every { messageDao.getMessages("group-1") } returns flowOf(entities)

        val result = repository.getMessages("group-1").first()

        assertThat(result).hasSize(2)
        assertThat(result[0].senderId).isEqualTo("user-1")
        assertThat(result[1].senderId).isEqualTo("user-2")
        assertThat(result[0].conversationId).isEqualTo("group-1")
    }

    // --- Repository: Grup konusmasi silme ---

    @Test
    fun `deleteConversation deletes group messages and conversation`() = runTest {
        repository.deleteConversation("group-1")

        coVerify { messageDao.deleteByConversation("group-1") }
        coVerify { conversationDao.delete("group-1") }
    }

    @Test
    fun `markConversationAsRead works for group conversations`() = runTest {
        repository.markConversationAsRead("group-1")

        coVerify { conversationDao.markAsRead("group-1") }
    }

    // --- Yardimci fonksiyonlar ---

    private fun createGroupConversation(unreadCount: Int = 0) = ConversationEntity(
        id = "group-1",
        peerId = "group-1",
        peerName = "Test Grup",
        peerPhone = "",
        lastMessage = null,
        lastMessageTimestamp = null,
        unreadCount = unreadCount,
        isGroup = true,
        groupMembers = "user-1,user-2,user-3"
    )

    private fun createGroupMessage(
        id: String = "msg-1",
        senderId: String = "user-2",
        isOutgoing: Boolean = false
    ) = LocalMessage(
        id = id,
        conversationId = "group-1",
        senderId = senderId,
        peerId = senderId,
        content = "Grup mesaji",
        contentType = MessageContentType.TEXT,
        timestamp = System.currentTimeMillis(),
        status = if (isOutgoing) MessageStatus.SENDING else MessageStatus.DELIVERED,
        isOutgoing = isOutgoing
    )
}
