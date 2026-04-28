package com.securechat.app.ui.viewmodel

import app.cash.turbine.test
import com.securechat.app.usecase.UpdateContactNamesUseCase
import com.securechat.network.SignalingClient
import com.securechat.network.model.ConnectionState
import com.securechat.storage.domain.Conversation
import com.securechat.storage.repository.MessageRepository
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * ConversationsViewModel birim testleri.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class ConversationsViewModelTest {

    private val testDispatcher = UnconfinedTestDispatcher()
    private lateinit var messageRepository: MessageRepository
    private lateinit var signalingClient: SignalingClient
    private lateinit var updateContactNamesUseCase: UpdateContactNamesUseCase
    private val connectionStateFlow = MutableStateFlow<ConnectionState>(ConnectionState.Disconnected)

    @Before
    fun setup() {
        Dispatchers.setMain(testDispatcher)
        messageRepository = mockk(relaxed = true)
        signalingClient = mockk(relaxed = true)
        updateContactNamesUseCase = mockk(relaxed = true)
        every { signalingClient.connectionState } returns connectionStateFlow
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    @Test
    fun `conversations emits conversations from repository`() = runTest {
        val testConversations = listOf(
            createTestConversation("conv_1", "Ali"),
            createTestConversation("conv_2", "Veli")
        )
        every { messageRepository.getConversations() } returns flowOf(testConversations)

        val viewModel = ConversationsViewModel(messageRepository, signalingClient, updateContactNamesUseCase)

        viewModel.conversations.test {
            val first = awaitItem()
            if (first.isEmpty()) {
                val second = awaitItem()
                assertEquals(2, second.size)
                assertEquals("Ali", second[0].peerName)
            } else {
                assertEquals(2, first.size)
                assertEquals("Ali", first[0].peerName)
            }
            cancelAndConsumeRemainingEvents()
        }
    }

    @Test
    fun `conversations defaults to empty list`() = runTest {
        every { messageRepository.getConversations() } returns flowOf(emptyList())

        val viewModel = ConversationsViewModel(messageRepository, signalingClient, updateContactNamesUseCase)

        assertEquals(emptyList<Conversation>(), viewModel.conversations.value)
    }

    @Test
    fun `connectionState reflects signalingClient state`() = runTest {
        every { messageRepository.getConversations() } returns flowOf(emptyList())
        connectionStateFlow.value = ConnectionState.Connected

        val viewModel = ConversationsViewModel(messageRepository, signalingClient, updateContactNamesUseCase)

        viewModel.connectionState.test {
            val first = awaitItem()
            if (first is ConnectionState.Disconnected) {
                val second = awaitItem()
                assertTrue(second is ConnectionState.Connected)
            } else {
                assertTrue(first is ConnectionState.Connected)
            }
            cancelAndConsumeRemainingEvents()
        }
    }

    @Test
    fun `connectionState defaults to Disconnected`() = runTest {
        every { messageRepository.getConversations() } returns flowOf(emptyList())
        connectionStateFlow.value = ConnectionState.Disconnected

        val viewModel = ConversationsViewModel(messageRepository, signalingClient, updateContactNamesUseCase)

        assertTrue(viewModel.connectionState.value is ConnectionState.Disconnected)
    }

    private fun createTestConversation(id: String, peerName: String): Conversation {
        return Conversation(
            id = id,
            peerId = "peer_$id",
            peerName = peerName,
            peerPhone = "+905551234567",
            lastMessage = "Son mesaj",
            lastMessageTimestamp = System.currentTimeMillis(),
            unreadCount = 0,
            isMuted = false,
            isPinned = false
        )
    }
}
