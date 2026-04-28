package com.securechat.app.ui.viewmodel

import android.content.SharedPreferences
import androidx.lifecycle.SavedStateHandle
import app.cash.turbine.test
import com.securechat.app.data.UserSession
import com.securechat.app.domain.usecase.MarkAsReadUseCase
import com.securechat.app.domain.usecase.ObserveMessagesUseCase
import com.securechat.app.domain.usecase.SendMessageUseCase
import com.securechat.media.FileTransferManager
import com.securechat.network.SignalingClient
import com.securechat.network.model.ConnectionState
import com.securechat.storage.dao.ConversationDao
import com.securechat.storage.domain.LocalMessage
import com.securechat.storage.model.MessageContentType
import com.securechat.storage.model.MessageStatus
import com.securechat.storage.resolver.ContactNameResolver
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test

/**
 * ChatViewModel birim testleri.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class ChatViewModelTest {

    private val testDispatcher = UnconfinedTestDispatcher()
    private lateinit var sendMessageUseCase: SendMessageUseCase
    private lateinit var observeMessagesUseCase: ObserveMessagesUseCase
    private lateinit var markAsReadUseCase: MarkAsReadUseCase
    private lateinit var messageRepository: com.securechat.storage.repository.MessageRepository
    private lateinit var conversationDao: ConversationDao
    private lateinit var fileTransferManager: FileTransferManager
    private lateinit var userSession: UserSession
    private lateinit var signalingClient: SignalingClient
    private lateinit var contactNameResolver: ContactNameResolver
    private lateinit var sharedPreferences: SharedPreferences
    private lateinit var savedStateHandle: SavedStateHandle

    @Before
    fun setup() {
        Dispatchers.setMain(testDispatcher)
        sendMessageUseCase = mockk(relaxed = true)
        observeMessagesUseCase = mockk()
        markAsReadUseCase = mockk(relaxed = true)
        messageRepository = mockk(relaxed = true)
        conversationDao = mockk(relaxed = true)
        fileTransferManager = mockk(relaxed = true)
        userSession = mockk(relaxed = true)
        signalingClient = mockk(relaxed = true)
        contactNameResolver = mockk(relaxed = true)
        sharedPreferences = mockk(relaxed = true)
        savedStateHandle = SavedStateHandle(mapOf("conversationId" to "conv_123"))

        every { userSession.userId } returns "local_user"
        every { signalingClient.connectionState } returns MutableStateFlow(ConnectionState.Disconnected)
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private fun createViewModel(): ChatViewModel {
        return ChatViewModel(
            savedStateHandle = savedStateHandle,
            sendMessageUseCase = sendMessageUseCase,
            observeMessagesUseCase = observeMessagesUseCase,
            markAsReadUseCase = markAsReadUseCase,
            messageRepository = messageRepository,
            conversationDao = conversationDao,
            fileTransferManager = fileTransferManager,
            userSession = userSession,
            signalingClient = signalingClient,
            contactNameResolver = contactNameResolver,
            sharedPreferences = sharedPreferences
        )
    }

    @Test
    fun `conversationId is read from savedStateHandle`() = runTest {
        every { observeMessagesUseCase("conv_123") } returns flowOf(emptyList())

        val viewModel = createViewModel()

        assertEquals("conv_123", viewModel.conversationId)
    }

    @Test
    fun `messages flow emits messages from use case`() = runTest {
        val testMessages = listOf(createTestMessage("msg_1"))
        every { observeMessagesUseCase("conv_123") } returns flowOf(testMessages)
        every { messageRepository.getRecentMessages("conv_123", any()) } returns flowOf(testMessages)

        val viewModel = createViewModel()

        viewModel.messages.test {
            val first = awaitItem()
            if (first.isEmpty()) {
                val second = awaitItem()
                assertEquals(1, second.size)
                assertEquals("msg_1", second[0].id)
            } else {
                assertEquals(1, first.size)
                assertEquals("msg_1", first[0].id)
            }
            cancelAndConsumeRemainingEvents()
        }
    }

    @Test
    fun `sendMessage delegates to sendMessageUseCase`() = runTest {
        every { observeMessagesUseCase("conv_123") } returns flowOf(emptyList())

        val viewModel = createViewModel()
        viewModel.sendMessage("Merhaba")
        advanceUntilIdle()

        coVerify { sendMessageUseCase("conv_123", "Merhaba") }
    }

    @Test
    fun `init marks conversation as read`() = runTest {
        every { observeMessagesUseCase("conv_123") } returns flowOf(emptyList())

        createViewModel()
        advanceUntilIdle()

        coVerify { markAsReadUseCase("conv_123") }
    }

    @Test
    fun `messages defaults to empty list`() = runTest {
        every { observeMessagesUseCase("conv_123") } returns flowOf(emptyList())

        val viewModel = createViewModel()

        assertEquals(emptyList<LocalMessage>(), viewModel.messages.value)
    }

    private fun createTestMessage(id: String): LocalMessage {
        return LocalMessage(
            id = id,
            conversationId = "conv_123",
            senderId = "local_user",
            peerId = "peer_1",
            content = "Test",
            contentType = MessageContentType.TEXT,
            timestamp = System.currentTimeMillis(),
            status = MessageStatus.SENT,
            isOutgoing = true
        )
    }
}
