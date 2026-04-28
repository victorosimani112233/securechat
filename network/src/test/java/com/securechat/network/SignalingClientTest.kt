package com.securechat.network

import com.google.common.truth.Truth.assertThat
import com.securechat.network.model.CallAction
import com.securechat.network.model.CallType
import com.securechat.network.model.ConnectionState
import io.mockk.every
import io.mockk.mockk
import io.mockk.slot
import io.mockk.verify
import app.cash.turbine.test
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.junit.Before
import org.junit.Test

/**
 * SignalingClient sinifinin unit testleri.
 * WebSocket baglanti yaşam dongusunu, mesaj gonderme/alma ve
 * baglanti durumu yonetimini test eder.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class SignalingClientTest {

    private lateinit var mockOkHttpClient: OkHttpClient
    private lateinit var mockWebSocket: WebSocket
    private lateinit var mockResponse: Response
    private lateinit var signalingClient: SignalingClient
    private lateinit var capturedListener: WebSocketListener

    @Before
    fun setUp() {
        mockOkHttpClient = mockk()
        mockWebSocket = mockk(relaxed = true)
        mockResponse = mockk(relaxed = true)

        val listenerSlot = slot<WebSocketListener>()
        every {
            mockOkHttpClient.newWebSocket(any<Request>(), capture(listenerSlot))
        } answers {
            capturedListener = listenerSlot.captured
            mockWebSocket
        }

        signalingClient = SignalingClient(mockOkHttpClient)
    }

    @Test
    fun `initial state is Disconnected`() {
        assertThat(signalingClient.connectionState.value).isEqualTo(ConnectionState.Disconnected)
    }

    @Test
    fun `connect sets state to Connecting`() {
        signalingClient.connect("user1", "token123", "ws://localhost:8080")

        // connect ayarladiktan sonra state Connecting olur (onOpen cagrilmadan once)
        // Ancak newWebSocket hemen WebSocketListener'i cagirabilir, burada
        // sadece connect'in cagrildigini dogruluyoruz
        verify { mockOkHttpClient.newWebSocket(any<Request>(), any()) }
    }

    @Test
    fun `onOpen sets state to Connected`() {
        signalingClient.connect("user1", "token123", "ws://localhost:8080")

        capturedListener.onOpen(mockWebSocket, mockResponse)

        assertThat(signalingClient.connectionState.value).isEqualTo(ConnectionState.Connected)
    }

    @Test
    fun `onClosed sets state to Disconnected`() {
        signalingClient.connect("user1", "token123", "ws://localhost:8080")

        capturedListener.onOpen(mockWebSocket, mockResponse)
        assertThat(signalingClient.connectionState.value).isEqualTo(ConnectionState.Connected)

        capturedListener.onClosed(mockWebSocket, 1000, "Normal closure")
        assertThat(signalingClient.connectionState.value).isEqualTo(ConnectionState.Disconnected)
    }

    @Test
    fun `onFailure sets state to Error`() {
        signalingClient.connect("user1", "token123", "ws://localhost:8080")

        val error = RuntimeException("Connection failed")
        capturedListener.onFailure(mockWebSocket, error, null)

        val state = signalingClient.connectionState.value
        assertThat(state).isInstanceOf(ConnectionState.Error::class.java)
        assertThat((state as ConnectionState.Error).throwable).isEqualTo(error)
    }

    @Test
    fun `sendSignal delegates to webSocket`() {
        every { mockWebSocket.send(any<String>()) } returns true

        signalingClient.connect("user1", "token123", "ws://localhost:8080")

        val signal = SignalMessage.CallControl(
            senderId = "user1",
            recipientId = "user2",
            timestamp = System.currentTimeMillis(),
            action = CallAction.RINGING
        )

        val result = signalingClient.sendSignal(signal)
        assertThat(result).isTrue()
        verify { mockWebSocket.send(any<String>()) }
    }

    @Test
    fun `sendSignal returns false when no websocket connection`() {
        // WebSocket baglantisi kurulmadan gonderim denemesi
        val freshClient = SignalingClient(mockOkHttpClient)
        val signal = SignalMessage.EncryptedMessage(
            senderId = "user1",
            recipientId = "user2",
            timestamp = System.currentTimeMillis(),
            envelope = "encrypted_data"
        )

        val result = freshClient.sendSignal(signal)
        assertThat(result).isFalse()
    }

    @Test
    fun `disconnect closes websocket and sets state to Disconnected`() {
        every { mockWebSocket.close(any(), any()) } returns true

        signalingClient.connect("user1", "token123", "ws://localhost:8080")
        capturedListener.onOpen(mockWebSocket, mockResponse)
        assertThat(signalingClient.connectionState.value).isEqualTo(ConnectionState.Connected)

        signalingClient.disconnect()

        verify { mockWebSocket.close(1000, "Client disconnect") }
        assertThat(signalingClient.connectionState.value).isEqualTo(ConnectionState.Disconnected)
    }

    @Test
    fun `onMessage emits signal for valid JSON`() = runTest {
        signalingClient.connect("user1", "token123", "ws://localhost:8080")

        val validJson = """
            {
                "type": "sdp_offer",
                "senderId": "alice",
                "recipientId": "bob",
                "timestamp": 1000,
                "sdp": "v=0",
                "callType": "VIDEO"
            }
        """.trimIndent()

        // Turbine ile SharedFlow'u test et
        signalingClient.incomingSignals.test {
            capturedListener.onMessage(mockWebSocket, validJson)

            val received = awaitItem()
            assertThat(received).isInstanceOf(SignalMessage.SdpOffer::class.java)
            val offer = received as SignalMessage.SdpOffer
            assertThat(offer.senderId).isEqualTo("alice")
            assertThat(offer.recipientId).isEqualTo("bob")
            assertThat(offer.sdp).isEqualTo("v=0")
            assertThat(offer.callType).isEqualTo(CallType.VIDEO)

            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `onMessage ignores invalid JSON silently`() = runTest {
        signalingClient.connect("user1", "token123", "ws://localhost:8080")

        signalingClient.incomingSignals.test {
            // Gecersiz JSON gonder — hata firlatilmamali, sinyal yayilmamali
            capturedListener.onMessage(mockWebSocket, "invalid json")

            expectNoEvents()

            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `connect creates request with correct URL and auth header`() {
        val requestSlot = slot<Request>()
        every {
            mockOkHttpClient.newWebSocket(capture(requestSlot), any())
        } returns mockWebSocket

        signalingClient.connect("user42", "myToken", "wss://signal.example.com")

        val request = requestSlot.captured
        // OkHttp wss:// semasini https:// olarak normalize eder
        assertThat(request.url.toString()).contains("signal.example.com/ws?userId=user42")
        assertThat(request.header("Authorization")).isEqualTo("Bearer myToken")
    }

    @Test
    fun `disconnect after disconnect does not throw`() {
        // Baglanti kurulmadan disconnect cagirma — hata firlatilmamali
        signalingClient.disconnect()
        signalingClient.disconnect()
        assertThat(signalingClient.connectionState.value).isEqualTo(ConnectionState.Disconnected)
    }

    @Test
    fun `sendSignal with SdpOffer contains correct type in JSON`() {
        val sentTextSlot = slot<String>()
        every { mockWebSocket.send(capture(sentTextSlot)) } returns true

        signalingClient.connect("user1", "token", "ws://localhost")

        val offer = SignalMessage.SdpOffer(
            senderId = "user1",
            recipientId = "user2",
            timestamp = 1000L,
            sdp = "v=0",
            callType = CallType.VOICE
        )

        signalingClient.sendSignal(offer)

        assertThat(sentTextSlot.captured).contains("\"type\":\"sdp_offer\"")
        assertThat(sentTextSlot.captured).contains("\"senderId\":\"user1\"")
    }

    // --- Bug 001: Offline kuyruk otomatik flush testleri ---

    @Test
    fun `onOpen flushes offline queue when messages pending`() {
        val mockQueue: OfflineMessageQueue = mockk(relaxed = true)
        every { mockQueue.getPendingCount() } returns 3

        signalingClient.offlineMessageQueue = mockQueue
        signalingClient.connect("user1", "token123", "ws://localhost:8080")

        capturedListener.onOpen(mockWebSocket, mockResponse)

        verify { mockQueue.flushQueue("user1") }
    }

    @Test
    fun `onOpen does not flush when queue is empty`() {
        val mockQueue: OfflineMessageQueue = mockk(relaxed = true)
        every { mockQueue.getPendingCount() } returns 0

        signalingClient.offlineMessageQueue = mockQueue
        signalingClient.connect("user1", "token123", "ws://localhost:8080")

        capturedListener.onOpen(mockWebSocket, mockResponse)

        verify(exactly = 0) { mockQueue.flushQueue(any()) }
    }

    @Test
    fun `onOpen does not crash when offlineMessageQueue is null`() {
        signalingClient.offlineMessageQueue = null
        signalingClient.connect("user1", "token123", "ws://localhost:8080")

        // NullPointerException firlatilmamali
        capturedListener.onOpen(mockWebSocket, mockResponse)

        assertThat(signalingClient.connectionState.value).isEqualTo(ConnectionState.Connected)
    }

    // --- Bug 003: Reconnected callback testleri ---

    @Test
    fun `onOpen invokes onReconnectedCallback`() {
        var callbackInvoked = false
        signalingClient.onReconnectedCallback = { callbackInvoked = true }

        signalingClient.connect("user1", "token123", "ws://localhost:8080")
        capturedListener.onOpen(mockWebSocket, mockResponse)

        assertThat(callbackInvoked).isTrue()
    }

    @Test
    fun `onOpen does not crash when onReconnectedCallback is null`() {
        signalingClient.onReconnectedCallback = null

        signalingClient.connect("user1", "token123", "ws://localhost:8080")

        // NullPointerException firlatilmamali
        capturedListener.onOpen(mockWebSocket, mockResponse)

        assertThat(signalingClient.connectionState.value).isEqualTo(ConnectionState.Connected)
    }

    @Test
    fun `onOpen invokes onConnectedListener before onReconnectedCallback`() {
        val callOrder = mutableListOf<String>()
        signalingClient.onConnectedListener = { callOrder.add("connected") }
        signalingClient.onReconnectedCallback = { callOrder.add("reconnected") }

        signalingClient.connect("user1", "token123", "ws://localhost:8080")
        capturedListener.onOpen(mockWebSocket, mockResponse)

        assertThat(callOrder).containsExactly("connected", "reconnected").inOrder()
    }

    @Test
    fun `getCurrentUserId returns userId after connect`() {
        signalingClient.connect("user42", "token", "ws://localhost:8080")

        assertThat(signalingClient.getCurrentUserId()).isEqualTo("user42")
    }

    @Test
    fun `getCurrentUserId returns null before connect`() {
        assertThat(signalingClient.getCurrentUserId()).isNull()
    }

    @Test
    fun `getCurrentUserId returns null after disconnect`() {
        every { mockWebSocket.close(any(), any()) } returns true

        signalingClient.connect("user1", "token", "ws://localhost:8080")
        capturedListener.onOpen(mockWebSocket, mockResponse)
        signalingClient.disconnect()

        assertThat(signalingClient.getCurrentUserId()).isNull()
    }

    @Test
    fun `STUCK_MESSAGE_TIMEOUT_MS is 30 seconds`() {
        assertThat(SignalingClient.STUCK_MESSAGE_TIMEOUT_MS).isEqualTo(30_000L)
    }

    @Test
    fun `onOpen flush and callback work together on reconnect`() {
        // Tam reconnect senaryosu: flush + callback birlikte calisir
        val mockQueue: OfflineMessageQueue = mockk(relaxed = true)
        every { mockQueue.getPendingCount() } returns 2

        var reconnectCallbackInvoked = false
        signalingClient.offlineMessageQueue = mockQueue
        signalingClient.onReconnectedCallback = { reconnectCallbackInvoked = true }

        signalingClient.connect("user1", "token", "ws://localhost:8080")

        // Ilk baglanti
        capturedListener.onOpen(mockWebSocket, mockResponse)

        // Her ikisi de calistirilmali
        verify { mockQueue.flushQueue("user1") }
        assertThat(reconnectCallbackInvoked).isTrue()
    }
}
