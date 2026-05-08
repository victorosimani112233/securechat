package com.securechat.app.ui.viewmodel

import androidx.lifecycle.SavedStateHandle
import com.securechat.app.data.UserSession
import com.securechat.media.CallManager
import com.securechat.media.model.CallDirection
import com.securechat.media.model.CallSession
import com.securechat.media.model.CallState
import com.securechat.network.model.CallType
import com.securechat.storage.dao.ConversationDao
import com.securechat.storage.resolver.ContactNameResolver
import com.securechat.telecom.PhoneAccountRegistrar
import io.mockk.every
import io.mockk.mockk
import io.mockk.verify
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test

/**
 * CallViewModel birim testleri.
 *
 * CallManager'a delege edilen fonksiyonlarin
 * dogru cagrildigini dogrular.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class CallViewModelTest {

    private val testDispatcher = StandardTestDispatcher()
    private lateinit var callManager: CallManager
    private lateinit var userSession: UserSession
    private lateinit var savedStateHandle: SavedStateHandle
    private lateinit var conversationDao: ConversationDao
    private lateinit var contactNameResolver: ContactNameResolver
    private lateinit var phoneAccountRegistrar: dagger.Lazy<PhoneAccountRegistrar>
    private val callSessionFlow = MutableStateFlow<CallSession?>(null)

    @Before
    fun setup() {
        Dispatchers.setMain(testDispatcher)
        callManager = mockk(relaxed = true)
        userSession = mockk(relaxed = true)
        conversationDao = mockk(relaxed = true)
        contactNameResolver = mockk(relaxed = true)
        phoneAccountRegistrar = mockk(relaxed = true)
        every { callManager.callSession } returns callSessionFlow
        every { callManager.currentSession } returns null
        every { callManager.getCallDuration() } returns null
        every { userSession.userId } returns "test-user"

        // Bos peerId ile SavedStateHandle — mevcut session olmadigi durumda
        // initiateCall cagrilmaz cunku peerId bos
        savedStateHandle = SavedStateHandle(mapOf("peerId" to "", "callType" to "VOICE"))
    }

    private fun newViewModel() = CallViewModel(
        savedStateHandle, callManager, userSession, conversationDao,
        contactNameResolver, phoneAccountRegistrar
    )

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    @Test
    fun `toggleMute delegates to callManager`() {
        val viewModel = newViewModel()
        viewModel.toggleMute()
        verify { callManager.toggleMute() }
    }

    @Test
    fun `toggleSpeaker delegates to callManager`() {
        val viewModel = newViewModel()
        viewModel.toggleSpeaker()
        verify { callManager.toggleSpeaker() }
    }

    @Test
    fun `toggleCamera delegates to callManager`() {
        val viewModel = newViewModel()
        viewModel.toggleCamera()
        verify { callManager.toggleCamera() }
    }

    @Test
    fun `switchCamera delegates to callManager`() {
        val viewModel = newViewModel()
        viewModel.switchCamera()
        verify { callManager.switchCamera() }
    }

    @Test
    fun `endCall delegates to callManager with userId`() {
        val viewModel = newViewModel()
        viewModel.endCall()
        verify { callManager.endCall("test-user") }
    }

    @Test
    fun `callState initially null`() {
        val viewModel = newViewModel()
        assertNull(viewModel.callState.value)
    }

    @Test
    fun `callDuration defaults to zero`() {
        val viewModel = newViewModel()
        assertEquals(0L, viewModel.callDuration.value)
    }

    @Test
    fun `initiateCall called when peerId is set and no current session`() {
        savedStateHandle = SavedStateHandle(mapOf("peerId" to "peer-123", "callType" to "VOICE"))

        newViewModel()

        verify { callManager.initiateCall("peer-123", CallType.VOICE, "test-user") }
    }

    @Test
    fun `initiateCall not called when current session exists`() {
        every { callManager.currentSession } returns mockk(relaxed = true) {
            every { state } returns CallState.ACTIVE
            every { direction } returns CallDirection.INCOMING
        }
        savedStateHandle = SavedStateHandle(mapOf("peerId" to "peer-123", "callType" to "VOICE"))

        newViewModel()

        verify(exactly = 0) { callManager.initiateCall(any(), any(), any()) }
    }

    @Test
    fun `acceptCall delegates with correct userId`() {
        val viewModel = newViewModel()
        viewModel.acceptCall()
        verify { callManager.acceptCall("test-user") }
    }
}
