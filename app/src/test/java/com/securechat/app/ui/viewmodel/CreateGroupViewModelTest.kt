package com.securechat.app.ui.viewmodel

import com.google.common.truth.Truth.assertThat
import com.securechat.app.data.UserSession
import com.securechat.contacts.ContactSearchManager
import com.securechat.contacts.DiscoveryApiService
import com.securechat.contacts.UserDiscoveryService
import com.securechat.contacts.model.RegisteredContact
import com.securechat.network.SignalingClient
import com.securechat.network.SignalMessage
import com.securechat.network.model.GroupAction
import com.securechat.storage.dao.ConversationDao
import com.securechat.storage.entity.ConversationEntity
import io.mockk.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Before
import org.junit.Test

/**
 * CreateGroupViewModel unit testleri.
 * Grup oluşturma mantığını, creator otomatik ekleme ve üye yönetimi
 * davranışlarını test eder.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class CreateGroupViewModelTest {

    private lateinit var conversationDao: ConversationDao
    private lateinit var userSession: UserSession
    private lateinit var signalingClient: SignalingClient
    private lateinit var contactSearchManager: ContactSearchManager
    private lateinit var userDiscoveryService: UserDiscoveryService
    private lateinit var discoveryApiService: DiscoveryApiService
    private lateinit var viewModel: CreateGroupViewModel

    private val testDispatcher = UnconfinedTestDispatcher()

    @Before
    fun setup() {
        Dispatchers.setMain(testDispatcher)
        conversationDao = mockk(relaxed = true)
        userSession = mockk {
            every { userId } returns "creator-123"
        }
        signalingClient = mockk(relaxed = true)
        contactSearchManager = mockk(relaxed = true)
        userDiscoveryService = mockk(relaxed = true)
        discoveryApiService = mockk(relaxed = true)

        val contacts = listOf(
            RegisteredContact(userId = "user1", displayName = "Ali", phoneNumber = "+905551111111", phoneHash = "hash1", avatarUri = null),
            RegisteredContact(userId = "user2", displayName = "Veli", phoneNumber = "+905552222222", phoneHash = "hash2", avatarUri = null),
            RegisteredContact(userId = "creator-123", displayName = "Ben", phoneNumber = "+905550000000", phoneHash = "hash3", avatarUri = null)
        )
        every { contactSearchManager.getRegisteredContacts() } returns flowOf(contacts)
        coEvery { userDiscoveryService.discoverRegisteredUsers() } returns emptyList()

        viewModel = CreateGroupViewModel(
            conversationDao, userSession, signalingClient,
            contactSearchManager, userDiscoveryService, discoveryApiService
        )
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    @Test
    fun `createGroup automatically adds creator as first member`() = runTest {
        // selectedMembers WhileSubscribed oldugu icin aktif subscriber gerekli
        val collectJob = launch(UnconfinedTestDispatcher()) {
            viewModel.selectedMembers.collect {}
        }

        viewModel.onGroupNameChanged("Test Grup")
        viewModel.toggleContactSelection("user1")
        viewModel.toggleContactSelection("user2")

        viewModel.createGroup()

        val capturedConversation = slot<ConversationEntity>()
        coVerify { conversationDao.insert(capture(capturedConversation)) }

        val conversation = capturedConversation.captured
        assertThat(conversation.isGroup).isTrue()
        assertThat(conversation.peerName).isEqualTo("Test Grup")

        val members = conversation.groupMembers!!.split(",")
        assertThat(members[0]).isEqualTo("creator-123")
        assertThat(members).containsExactly("creator-123", "user1", "user2")

        collectJob.cancel()
    }

    @Test
    fun `createGroup prevents duplicate creator in member list`() = runTest {
        val collectJob = launch(UnconfinedTestDispatcher()) {
            viewModel.selectedMembers.collect {}
        }

        viewModel.onGroupNameChanged("Test Grup")
        viewModel.toggleContactSelection("creator-123")
        viewModel.toggleContactSelection("user1")

        viewModel.createGroup()

        val capturedConversation = slot<ConversationEntity>()
        coVerify { conversationDao.insert(capture(capturedConversation)) }

        val conversation = capturedConversation.captured
        val members = conversation.groupMembers!!.split(",")
        assertThat(members.count { it == "creator-123" }).isEqualTo(1)

        collectJob.cancel()
    }

    @Test
    fun `createGroup sends notifications only to other members`() = runTest {
        val collectJob = launch(UnconfinedTestDispatcher()) {
            viewModel.selectedMembers.collect {}
        }

        viewModel.onGroupNameChanged("Test Grup")
        viewModel.toggleContactSelection("user1")
        viewModel.toggleContactSelection("user2")

        viewModel.createGroup()

        val capturedSignals = mutableListOf<SignalMessage.GroupNotification>()
        verify { signalingClient.sendSignal(capture(capturedSignals)) }

        assertThat(capturedSignals).hasSize(2)
        assertThat(capturedSignals.map { it.recipientId }).containsExactly("user1", "user2")
        assertThat(capturedSignals.all { it.senderId == "creator-123" }).isTrue()
        assertThat(capturedSignals.all { it.action == GroupAction.CREATE }).isTrue()

        collectJob.cancel()
    }

    @Test
    fun `createGroup with single member still works`() = runTest {
        val collectJob = launch(UnconfinedTestDispatcher()) {
            viewModel.selectedMembers.collect {}
        }

        viewModel.onGroupNameChanged("Test Grup")
        viewModel.toggleContactSelection("user1")

        viewModel.createGroup()

        val capturedConversation = slot<ConversationEntity>()
        coVerify { conversationDao.insert(capture(capturedConversation)) }

        val conversation = capturedConversation.captured
        val members = conversation.groupMembers!!.split(",")
        assertThat(members).hasSize(2)
        assertThat(members).containsExactly("creator-123", "user1")

        collectJob.cancel()
    }

    @Test
    fun `createGroup fails with empty member list`() = runTest {
        viewModel.onGroupNameChanged("Test Grup")

        viewModel.createGroup()

        assertThat(viewModel.error.value).isNotNull()
        coVerify(exactly = 0) { conversationDao.insert(any()) }
    }

    @Test
    fun `createGroup fails with blank name`() = runTest {
        val collectJob = launch(UnconfinedTestDispatcher()) {
            viewModel.selectedMembers.collect {}
        }

        viewModel.onGroupNameChanged("   ")
        viewModel.toggleContactSelection("user1")

        viewModel.createGroup()

        assertThat(viewModel.error.value).isNotNull()
        coVerify(exactly = 0) { conversationDao.insert(any()) }

        collectJob.cancel()
    }
}
