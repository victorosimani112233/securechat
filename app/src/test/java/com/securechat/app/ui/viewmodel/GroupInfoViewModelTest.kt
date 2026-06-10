package com.securechat.app.ui.viewmodel

import com.securechat.app.data.UserSession
import com.securechat.app.domain.usecase.AddGroupMemberUseCase
import com.securechat.app.domain.usecase.PromoteToAdminUseCase
import com.securechat.app.domain.usecase.RemoveGroupMemberUseCase
import com.securechat.app.domain.usecase.UpdateGroupNameUseCase
import com.securechat.network.SignalingClient
import com.securechat.storage.dao.ContactDao
import com.securechat.storage.dao.ConversationDao
import com.securechat.storage.dao.MessageDao
import com.securechat.storage.entity.ConversationEntity
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class GroupInfoViewModelTest {

    private lateinit var viewModel: GroupInfoViewModel
    private val conversationDao = mockk<ConversationDao>(relaxed = true)
    private val messageDao = mockk<MessageDao>(relaxed = true)
    private val contactDao = mockk<ContactDao>(relaxed = true)
    private val userSession = mockk<UserSession>()
    private val signalingClient = mockk<SignalingClient>(relaxed = true)
    private val addGroupMemberUseCase = mockk<AddGroupMemberUseCase>()
    private val promoteToAdminUseCase = mockk<PromoteToAdminUseCase>()
    private val removeGroupMemberUseCase = mockk<RemoveGroupMemberUseCase>()
    private val updateGroupNameUseCase = mockk<UpdateGroupNameUseCase>()

    private val testDispatcher = UnconfinedTestDispatcher()

    @Before
    fun setup() {
        Dispatchers.setMain(testDispatcher)
        every { userSession.userId } returns "user1"
        every { userSession.displayName } returns "Test User"
        every { userSession.phoneNumber } returns "+905551234567"

        // Default media/doc/starred flows
        every { messageDao.getMediaMessages(any()) } returns flowOf(emptyList())
        every { messageDao.getDocumentMessages(any()) } returns flowOf(emptyList())
        every { messageDao.getStarredMessages(any()) } returns flowOf(emptyList())

        viewModel = GroupInfoViewModel(
            conversationDao = conversationDao,
            messageDao = messageDao,
            contactDao = contactDao,
            userSession = userSession,
            signalingClient = signalingClient,
            addGroupMemberUseCase = addGroupMemberUseCase,
            promoteToAdminUseCase = promoteToAdminUseCase,
            removeGroupMemberUseCase = removeGroupMemberUseCase,
            updateGroupNameUseCase = updateGroupNameUseCase,
            contactNameResolver = contactNameResolver,
            pendingTimerFlusher = mockk(relaxed = true),
            toggleExportPolicyUseCase = mockk(relaxed = true),
            setGroupReadOnlyUseCase = mockk(relaxed = true)
        )
    }

    private val contactNameResolver: com.securechat.storage.resolver.ContactNameResolver = mockk(relaxed = true) {
        // ViewModel cogu yerde contactNameResolver'a fallback dusebilir; pre-existing test
        // user2 icin Conversation.peerName "John Doe" bekler. Resolver de bunu donsun
        // (gercekte resolver Conversation'i ilk source kabul eder, mock symmetric davranisi saglar).
        coEvery { resolveDisplayName("user2") } returns "John Doe"
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    @Test
    fun `loadGroupInfo loads group information correctly`() = runTest {
        val groupId = "group123"
        val groupConversation = ConversationEntity(
            id = groupId,
            peerId = groupId,
            peerName = "Test Group",
            peerPhone = "",
            lastMessage = null,
            lastMessageTimestamp = null,
            isGroup = true,
            groupMembers = "user1,user2,user3",
            groupAdmins = "user1"
        )

        val user2Conversation = ConversationEntity(
            id = "conv_user2",
            peerId = "user2",
            peerName = "John Doe",
            peerPhone = "+1234567890",
            lastMessage = null,
            lastMessageTimestamp = null,
            isGroup = false
        )

        coEvery { conversationDao.getById(groupId) } returns groupConversation
        coEvery { conversationDao.getByPeerId("user2") } returns user2Conversation
        coEvery { conversationDao.getByPeerId("user3") } returns null
        coEvery { contactDao.getById(any()) } returns null

        viewModel.loadGroupInfo(groupId)

        val groupInfo = viewModel.groupInfo.value
        assertNotNull(groupInfo)
        assertEquals("Test Group", groupInfo?.name)
        assertEquals(3, groupInfo?.members?.size)

        val members = groupInfo?.members ?: emptyList()
        val user1Member = members.find { it.userId == "user1" }

        assertNotNull(user1Member)
        assertTrue(user1Member?.isAdmin ?: false)
        assertTrue(user1Member?.isCurrentUser ?: false)

        assertEquals("John Doe", groupInfo?.memberNames?.get("user2"))
        assertTrue(viewModel.isAdmin.value)
    }

    @Test
    fun `loadGroupInfo handles non-group conversation`() = runTest {
        val conversationId = "user2"
        val directConversation = ConversationEntity(
            id = conversationId,
            peerId = conversationId,
            peerName = "John Doe",
            peerPhone = "+1234567890",
            lastMessage = null,
            lastMessageTimestamp = null,
            isGroup = false
        )

        coEvery { conversationDao.getById(conversationId) } returns directConversation

        viewModel.loadGroupInfo(conversationId)

        assertNotNull(viewModel.error.value)
        assertTrue(viewModel.error.value?.contains("Grup bulunamadi") ?: false)
    }

    @Test
    fun `updateGroupName calls use case and updates UI`() = runTest {
        val groupId = "group123"
        val newName = "Updated Group Name"
        coEvery { updateGroupNameUseCase(groupId, newName) } returns true

        val groupConversation = ConversationEntity(
            id = groupId,
            peerId = groupId,
            peerName = "Old Name",
            peerPhone = "",
            lastMessage = null,
            lastMessageTimestamp = null,
            isGroup = true,
            groupMembers = "user1",
            groupAdmins = "user1"
        )
        coEvery { conversationDao.getById(groupId) } returns groupConversation
        coEvery { conversationDao.getByPeerId(any()) } returns null
        coEvery { contactDao.getById(any()) } returns null
        viewModel.loadGroupInfo(groupId)

        viewModel.updateGroupName(groupId, newName)

        coVerify { updateGroupNameUseCase(groupId, newName) }
        assertEquals(newName, viewModel.groupInfo.value?.name)
    }

    @Test
    fun `addMember calls use case and reloads group info`() = runTest {
        val groupId = "group123"
        val newMemberId = "user4"
        val groupConversation = ConversationEntity(
            id = groupId,
            peerId = groupId,
            peerName = "Test Group",
            peerPhone = "",
            lastMessage = null,
            lastMessageTimestamp = null,
            isGroup = true,
            groupMembers = "user1,user2,user3,user4",
            groupAdmins = "user1"
        )

        coEvery { addGroupMemberUseCase(groupId, newMemberId) } returns true
        coEvery { conversationDao.getById(groupId) } returns groupConversation
        coEvery { conversationDao.getByPeerId(any()) } returns null
        coEvery { contactDao.getById(any()) } returns null

        viewModel.addMember(groupId, newMemberId)

        coVerify { addGroupMemberUseCase(groupId, newMemberId) }
        coVerify { conversationDao.getById(groupId) }
    }

    @Test
    fun `removeMember calls use case and reloads group info`() = runTest {
        val groupId = "group123"
        val memberId = "user3"
        val groupConversation = ConversationEntity(
            id = groupId,
            peerId = groupId,
            peerName = "Test Group",
            peerPhone = "",
            lastMessage = null,
            lastMessageTimestamp = null,
            isGroup = true,
            groupMembers = "user1,user2",
            groupAdmins = "user1"
        )

        coEvery { removeGroupMemberUseCase(groupId, memberId) } returns true
        coEvery { conversationDao.getById(groupId) } returns groupConversation
        coEvery { conversationDao.getByPeerId(any()) } returns null
        coEvery { contactDao.getById(any()) } returns null

        viewModel.removeMember(groupId, memberId)

        coVerify { removeGroupMemberUseCase(groupId, memberId) }
        coVerify { conversationDao.getById(groupId) }
    }

    @Test
    fun `clearError clears error state`() = runTest {
        coEvery { conversationDao.getById(any()) } returns null
        viewModel.loadGroupInfo("invalid_id")

        viewModel.clearError()

        assertNull(viewModel.error.value)
    }
}
