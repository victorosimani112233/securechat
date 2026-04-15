package com.securechat.app.ui.viewmodel

import com.google.common.truth.Truth.assertThat
import com.securechat.app.data.UserSession
import com.securechat.network.SignalingClient
import com.securechat.network.SignalMessage
import com.securechat.network.model.GroupAction
import com.securechat.storage.dao.ConversationDao
import com.securechat.storage.entity.ConversationEntity
import io.mockk.*
import kotlinx.coroutines.test.runTest
import org.junit.Before
import org.junit.Test

/**
 * CreateGroupViewModel unit testleri.
 * Grup oluşturma mantığını, creator otomatik ekleme ve üye yönetimi
 * davranışlarını test eder.
 */
class CreateGroupViewModelTest {

    private lateinit var conversationDao: ConversationDao
    private lateinit var userSession: UserSession
    private lateinit var signalingClient: SignalingClient
    private lateinit var viewModel: CreateGroupViewModel

    @Before
    fun setup() {
        conversationDao = mockk(relaxed = true)
        userSession = mockk {
            every { userId } returns "creator-123"
        }
        signalingClient = mockk(relaxed = true)

        viewModel = CreateGroupViewModel(conversationDao, userSession, signalingClient)
    }

    @Test
    fun `createGroup automatically adds creator as first member`() = runTest {
        // Given
        viewModel.onGroupNameChanged("Test Grup")
        viewModel.onMemberInputChanged("user1")
        viewModel.addMember()
        viewModel.onMemberInputChanged("user2")
        viewModel.addMember()

        // When
        viewModel.createGroup()

        // Then
        val capturedConversation = slot<ConversationEntity>()
        coVerify { conversationDao.insert(capture(capturedConversation)) }

        val conversation = capturedConversation.captured
        assertThat(conversation.isGroup).isTrue()
        assertThat(conversation.peerName).isEqualTo("Test Grup")

        // Creator'ın ilk sırada olduğunu kontrol et
        val members = conversation.groupMembers!!.split(",")
        assertThat(members).hasSize(3)
        assertThat(members[0]).isEqualTo("creator-123") // Creator ilk sırada
        assertThat(members).containsExactly("creator-123", "user1", "user2")
    }

    @Test
    fun `createGroup prevents duplicate creator in member list`() = runTest {
        // Given - Creator'ı manuel olarak üye listesine ekle
        viewModel.onGroupNameChanged("Test Grup")
        viewModel.onMemberInputChanged("creator-123")
        viewModel.addMember()
        viewModel.onMemberInputChanged("user1")
        viewModel.addMember()

        // When
        viewModel.createGroup()

        // Then
        val capturedConversation = slot<ConversationEntity>()
        coVerify { conversationDao.insert(capture(capturedConversation)) }

        val conversation = capturedConversation.captured
        val members = conversation.groupMembers!!.split(",")
        assertThat(members).hasSize(2)
        assertThat(members).containsExactly("creator-123", "user1")
        assertThat(members.count { it == "creator-123" }).isEqualTo(1) // Sadece bir kere
    }

    @Test
    fun `createGroup sends notifications only to other members`() = runTest {
        // Given
        viewModel.onGroupNameChanged("Test Grup")
        viewModel.onMemberInputChanged("user1")
        viewModel.addMember()
        viewModel.onMemberInputChanged("user2")
        viewModel.addMember()

        // When
        viewModel.createGroup()

        // Then - Sadece diğer üyelere bildirim gönderildi (creator'a değil)
        verify(exactly = 2) {
            signalingClient.sendSignal(any<SignalMessage.GroupNotification>())
        }

        // Gönderilen bildirimlerin doğru olduğunu kontrol et
        val capturedSignals = mutableListOf<SignalMessage.GroupNotification>()
        verify { signalingClient.sendSignal(capture(capturedSignals)) }

        assertThat(capturedSignals).hasSize(2)
        assertThat(capturedSignals.map { it.recipientId }).containsExactly("user1", "user2")
        assertThat(capturedSignals.all { it.senderId == "creator-123" }).isTrue()
        assertThat(capturedSignals.all { it.action == GroupAction.CREATE }).isTrue()
    }

    @Test
    fun `createGroup with single member still works`() = runTest {
        // Given
        viewModel.onGroupNameChanged("Test Grup")
        viewModel.onMemberInputChanged("user1")
        viewModel.addMember()

        // When
        viewModel.createGroup()

        // Then
        val capturedConversation = slot<ConversationEntity>()
        coVerify { conversationDao.insert(capture(capturedConversation)) }

        val conversation = capturedConversation.captured
        val members = conversation.groupMembers!!.split(",")
        assertThat(members).hasSize(2)
        assertThat(members).containsExactly("creator-123", "user1")
    }

    @Test
    fun `createGroup fails with empty member list`() = runTest {
        // Given
        viewModel.onGroupNameChanged("Test Grup")
        // Üye ekleme

        // When
        viewModel.createGroup()

        // Then
        assertThat(viewModel.error.value).isEqualTo("En az 1 uye eklenmeli (siz otomatik dahil edileceksiniz)")
        coVerify(exactly = 0) { conversationDao.insert(any()) }
    }

    @Test
    fun `createGroup fails with blank name`() = runTest {
        // Given
        viewModel.onGroupNameChanged("   ")
        viewModel.onMemberInputChanged("user1")
        viewModel.addMember()

        // When
        viewModel.createGroup()

        // Then
        assertThat(viewModel.error.value).isEqualTo("Grup adi bos olamaz")
        coVerify(exactly = 0) { conversationDao.insert(any()) }
    }

    @Test
    fun `createGroup sets last message correctly`() = runTest {
        // Given
        viewModel.onGroupNameChanged("Test Grup")
        viewModel.onMemberInputChanged("user1")
        viewModel.addMember()

        // When
        viewModel.createGroup()

        // Then
        val capturedConversation = slot<ConversationEntity>()
        coVerify { conversationDao.insert(capture(capturedConversation)) }

        val conversation = capturedConversation.captured
        assertThat(conversation.lastMessage).isEqualTo("creator-123 grubu oluşturdu")
        assertThat(conversation.lastMessageTimestamp).isNotNull()
        assertThat(conversation.unreadCount).isEqualTo(0) // Creator için unread count 0
    }
}