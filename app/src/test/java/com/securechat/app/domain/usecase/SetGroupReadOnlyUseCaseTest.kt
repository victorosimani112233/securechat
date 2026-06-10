package com.securechat.app.domain.usecase

import com.google.common.truth.Truth.assertThat
import com.securechat.app.data.UserSession
import com.securechat.network.SignalMessage
import com.securechat.network.SignalingClient
import com.securechat.network.model.GroupAction
import com.securechat.storage.dao.ConversationDao
import com.securechat.storage.entity.ConversationEntity
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import io.mockk.slot
import kotlinx.coroutines.test.runTest
import org.junit.Before
import org.junit.Test

class SetGroupReadOnlyUseCaseTest {

    private lateinit var conversationDao: ConversationDao
    private lateinit var userSession: UserSession
    private lateinit var signalingClient: SignalingClient
    private lateinit var useCase: SetGroupReadOnlyUseCase

    private val localUserId = "user-admin"
    private val groupId = "group-1"

    @Before
    fun setup() {
        conversationDao = mockk(relaxed = true)
        userSession = mockk(relaxed = true)
        signalingClient = mockk(relaxed = true)
        every { userSession.userId } returns localUserId
        useCase = SetGroupReadOnlyUseCase(conversationDao, userSession, signalingClient)
    }

    @Test
    fun `admin grup read-only acabilir`() = runTest {
        coEvery { conversationDao.getById(groupId) } returns groupConversation(
            admins = listOf(localUserId),
            members = listOf(localUserId, "u2", "u3")
        )

        useCase(groupId, isReadOnly = true)

        coVerify { conversationDao.updateReadOnly(groupId, true) }
        coVerify(exactly = 2) { signalingClient.sendSignal(any()) }
    }

    @Test
    fun `signal payload SET_READ_ONLY action ve true targetMemberId tasir`() = runTest {
        coEvery { conversationDao.getById(groupId) } returns groupConversation(
            admins = listOf(localUserId),
            members = listOf(localUserId, "u2")
        )

        useCase(groupId, isReadOnly = true)

        val captured = slot<SignalMessage>()
        coVerify { signalingClient.sendSignal(capture(captured)) }
        val notif = captured.captured as SignalMessage.GroupNotification
        assertThat(notif.action).isEqualTo(GroupAction.SET_READ_ONLY)
        assertThat(notif.targetMemberId).isEqualTo("true")
        assertThat(notif.groupId).isEqualTo(groupId)
    }

    @Test(expected = IllegalAccessException::class)
    fun `non-admin denemesi exception`() = runTest {
        coEvery { conversationDao.getById(groupId) } returns groupConversation(
            admins = listOf("other-admin"),
            members = listOf(localUserId, "other-admin")
        )

        useCase(groupId, isReadOnly = true)
    }

    @Test(expected = IllegalArgumentException::class)
    fun `1to1 sohbette exception`() = runTest {
        coEvery { conversationDao.getById(groupId) } returns ConversationEntity(
            id = groupId,
            peerId = groupId,
            peerName = "Direct",
            peerPhone = "",
            lastMessage = null,
            lastMessageTimestamp = null,
            isGroup = false
        )

        useCase(groupId, isReadOnly = true)
    }

    private fun groupConversation(admins: List<String>, members: List<String>) = ConversationEntity(
        id = groupId,
        peerId = groupId,
        peerName = "Grup",
        peerPhone = "",
        lastMessage = null,
        lastMessageTimestamp = null,
        isGroup = true,
        groupMembers = members.joinToString(","),
        groupAdmins = admins.joinToString(",")
    )
}
