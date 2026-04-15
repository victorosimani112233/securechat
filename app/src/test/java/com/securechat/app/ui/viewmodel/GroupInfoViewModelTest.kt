package com.securechat.app.ui.viewmodel

import com.securechat.app.data.UserSession
import com.securechat.app.domain.usecase.AddGroupMemberUseCase
import com.securechat.app.domain.usecase.RemoveGroupMemberUseCase
import com.securechat.app.domain.usecase.UpdateGroupNameUseCase
import com.securechat.app.ui.screen.GroupMember
import com.securechat.storage.dao.ConversationDao
import com.securechat.storage.entity.ConversationEntity
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

@ExperimentalCoroutinesApi
class GroupInfoViewModelTest {

    private lateinit var viewModel: GroupInfoViewModel
    private val conversationDao = mockk<ConversationDao>()
    private val userSession = mockk<UserSession>()
    private val addGroupMemberUseCase = mockk<AddGroupMemberUseCase>()
    private val removeGroupMemberUseCase = mockk<RemoveGroupMemberUseCase>()
    private val updateGroupNameUseCase = mockk<UpdateGroupNameUseCase>()

    private val testScope = TestScope(UnconfinedTestDispatcher())

    @Before
    fun setup() {
        every { userSession.userId } returns "user1"

        viewModel = GroupInfoViewModel(
            conversationDao = conversationDao,
            userSession = userSession,
            addGroupMemberUseCase = addGroupMemberUseCase,
            removeGroupMemberUseCase = removeGroupMemberUseCase,
            updateGroupNameUseCase = updateGroupNameUseCase
        )
    }

    @Test
    fun `loadGroupInfo loads group information correctly`() = testScope.runTest {
        // Given
        val groupId = "group123"
        val groupConversation = ConversationEntity(
            id = groupId,
            peerId = groupId,
            peerName = "Test Group",
            peerPhone = "",
            lastMessage = null,
            lastMessageTimestamp = null,
            isGroup = true,
            groupMembers = "user1,user2,user3"
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

        // When
        viewModel.loadGroupInfo(groupId)

        // Then
        val groupInfo = viewModel.groupInfo.value
        assertNotNull(groupInfo)
        assertEquals("Test Group", groupInfo?.name)
        assertEquals(3, groupInfo?.members?.size)

        val members = groupInfo?.members ?: emptyList()
        val user1Member = members.find { it.userId == "user1" }
        val user2Member = members.find { it.userId == "user2" }

        assertNotNull(user1Member)
        assertTrue(user1Member?.isAdmin ?: false)
        assertTrue(user1Member?.isCurrentUser ?: false)

        assertNotNull(user2Member)
        assertFalse(user2Member?.isAdmin ?: true)
        assertFalse(user2Member?.isCurrentUser ?: true)

        assertEquals("John Doe", groupInfo?.memberNames?.get("user2"))
        assertTrue(viewModel.isAdmin.value)
    }

    @Test
    fun `loadGroupInfo handles non-group conversation`() = testScope.runTest {
        // Given
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

        // When
        viewModel.loadGroupInfo(conversationId)

        // Then
        assertNotNull(viewModel.error.value)
        assertTrue(viewModel.error.value?.contains("Grup bulunamadi") ?: false)
    }

    @Test
    fun `updateGroupName calls use case and updates UI`() = testScope.runTest {
        // Given
        val groupId = "group123"
        val newName = "Updated Group Name"
        coEvery { updateGroupNameUseCase(groupId, newName) } returns true

        // Set up initial state - simulate loaded group info with admin status
        val groupConversation = ConversationEntity(
            id = groupId,
            peerId = groupId,
            peerName = "Old Name",
            peerPhone = "",
            lastMessage = null,
            lastMessageTimestamp = null,
            isGroup = true,
            groupMembers = "user1"
        )
        coEvery { conversationDao.getById(groupId) } returns groupConversation
        coEvery { conversationDao.getByPeerId(any()) } returns null
        viewModel.loadGroupInfo(groupId) // This will set up admin status

        // When
        viewModel.updateGroupName(groupId, newName)

        // Then
        coVerify { updateGroupNameUseCase(groupId, newName) }
        assertEquals(newName, viewModel.groupInfo.value?.name)
    }

    @Test
    fun `addMember calls use case and reloads group info`() = testScope.runTest {
        // Given
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
            groupMembers = "user1,user2,user3,user4" // Updated after add
        )

        coEvery { addGroupMemberUseCase(groupId, newMemberId) } returns true
        coEvery { conversationDao.getById(groupId) } returns groupConversation
        coEvery { conversationDao.getByPeerId(any()) } returns null

        // When
        viewModel.addMember(groupId, newMemberId)

        // Then
        coVerify { addGroupMemberUseCase(groupId, newMemberId) }
        coVerify { conversationDao.getById(groupId) }
    }

    @Test
    fun `removeMember calls use case and reloads group info`() = testScope.runTest {
        // Given
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
            groupMembers = "user1,user2" // Updated after removal
        )

        coEvery { removeGroupMemberUseCase(groupId, memberId) } returns true
        coEvery { conversationDao.getById(groupId) } returns groupConversation
        coEvery { conversationDao.getByPeerId(any()) } returns null

        // When
        viewModel.removeMember(groupId, memberId)

        // Then
        coVerify { removeGroupMemberUseCase(groupId, memberId) }
        coVerify { conversationDao.getById(groupId) }
    }

    @Test
    fun `clearError clears error state`() = testScope.runTest {
        // Given - simulate an error by calling a use case that will fail
        coEvery { conversationDao.getById(any()) } returns null
        viewModel.loadGroupInfo("invalid_id") // This should set an error

        // When
        viewModel.clearError()

        // Then
        assertNull(viewModel.error.value)
    }
}