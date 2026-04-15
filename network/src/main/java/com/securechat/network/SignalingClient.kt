package com.securechat.network

import com.securechat.network.model.ConnectionState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import android.util.Log
import javax.inject.Inject
import javax.inject.Named
import javax.inject.Singleton

/**
 * Signaling sunucusu ile WebSocket baglantisini yoneten istemci.
 *
 * Bu sinif:
 * - WebSocket baglantisi kurar ve yonetir
 * - Gelen signaling mesajlarini SharedFlow olarak yayar
 * - Baglanti koptuğunda exponential backoff ile yeniden baglanti dener
 * - Baglanti durumunu StateFlow olarak izlemeye sunar
 *
 * GUVENLIK: Authorization token WebSocket handshake'inde Bearer token olarak gonderilir.
 */
@Singleton
class SignalingClient @Inject constructor(
    private val okHttpClient: OkHttpClient,
    @Named("signalingUrl") private val signalingUrl: String
) {
    private val json = Json {
        ignoreUnknownKeys = true
        classDiscriminator = "type"
    }

    private val _connectionState = MutableStateFlow<ConnectionState>(ConnectionState.Disconnected)
    val connectionState: StateFlow<ConnectionState> = _connectionState.asStateFlow()

    private val _incomingSignals = MutableSharedFlow<SignalMessage>(
        replay = 0,
        extraBufferCapacity = 64,
        onBufferOverflow = BufferOverflow.DROP_OLDEST
    )
    val incomingSignals: SharedFlow<SignalMessage> = _incomingSignals.asSharedFlow()

    private var webSocket: WebSocket? = null
    private var reconnectJob: Job? = null
    private var currentUserId: String? = null
    private var currentAuthToken: String? = null

    /**
     * Signaling sunucusuna WebSocket baglantisi kurar.
     *
     * @param userId Baglanan kullanicinin ID'si
     * @param authToken Yetkilendirme token'i (Bearer)
     * @param customUrl Opsiyonel custom URL, null ise injected URL kullanılır
     */
    fun connect(userId: String, authToken: String, customUrl: String? = null) {
        Log.d("SecureChat", "=== SignalingClient.connect() CALLED ===")
        Log.d("SecureChat", "  - userId: $userId")
        Log.d("SecureChat", "  - authToken: $authToken")
        Log.d("SecureChat", "  - customUrl: $customUrl")
        Log.d("SecureChat", "  - injected signalingUrl: $signalingUrl")

        val url = customUrl ?: signalingUrl
        Log.d("SecureChat", "  - final URL (base): $url")

        currentUserId = userId
        currentAuthToken = authToken
        _connectionState.value = ConnectionState.Connecting
        Log.d("SecureChat", "Connection state set to: Connecting")

        val finalUrl = "$url/ws?userId=$userId"
        Log.d("SecureChat", "  - finalUrl (with path): $finalUrl")

        val request = Request.Builder()
            .url(finalUrl)
            .addHeader("Authorization", "Bearer $authToken")
            .build()

        Log.d("SecureChat", "Creating WebSocket connection to: $finalUrl")
        Log.d("SecureChat", "Request headers:")
        for ((name, value) in request.headers) {
            Log.d("SecureChat", "  - $name: $value")
        }

        webSocket = okHttpClient.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                Log.d("SecureChat", "✅ WebSocket CONNECTED successfully!")
                Log.d("SecureChat", "  - Response code: ${response.code}")
                Log.d("SecureChat", "  - Response message: ${response.message}")
                Log.d("SecureChat", "Response headers:")
                for ((name, value) in response.headers) {
                    Log.d("SecureChat", "  - $name: $value")
                }
                _connectionState.value = ConnectionState.Connected
                reconnectJob?.cancel()
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                Log.d("SecureChat", "📨 WebSocket message received: ${text.take(100)}...")
                try {
                    val signal = json.decodeFromString<SignalMessage>(text)
                    _incomingSignals.tryEmit(signal)
                } catch (e: Exception) {
                    Log.w("SecureChat", "Failed to parse WebSocket message: ${e.message}")
                }
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                Log.e("SecureChat", "❌ WebSocket CONNECTION FAILED!")
                Log.e("SecureChat", "  - Error type: ${t.javaClass.simpleName}")
                Log.e("SecureChat", "  - Error message: ${t.message}")
                Log.e("SecureChat", "  - Stack trace: ${t.stackTraceToString()}")
                if (response != null) {
                    Log.e("SecureChat", "  - Response code: ${response.code}")
                    Log.e("SecureChat", "  - Response message: ${response.message}")
                    Log.e("SecureChat", "Response headers:")
                    for ((name, value) in response.headers) {
                        Log.e("SecureChat", "  - $name: $value")
                    }
                } else {
                    Log.e("SecureChat", "  - No HTTP response received (connection failed before HTTP handshake)")
                }
                _connectionState.value = ConnectionState.Error(t)
                scheduleReconnect(url)
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                Log.w("SecureChat", "❌ WebSocket connection closed")
                Log.w("SecureChat", "  - Code: $code, Reason: $reason")
                _connectionState.value = ConnectionState.Disconnected
                // Kullanici disconnect() cagirmadiysa yeniden baglan
                if (currentUserId != null) {
                    scheduleReconnect(url)
                }
            }

            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                Log.w("SecureChat", "⚠️ WebSocket connection closing...")
                Log.w("SecureChat", "  - Code: $code, Reason: $reason")
            }
        })
    }

    /**
     * Signaling mesajini WebSocket uzerinden gonderir.
     *
     * @param signal Gonderilecek signaling mesaji
     * @return Mesaj basariyla kuyruga alindiysa true
     */
    fun sendSignal(signal: SignalMessage): Boolean {
        val text = json.encodeToString(signal)
        return webSocket?.send(text) ?: false
    }

    /**
     * Baglanti koptuğunda exponential backoff ile yeniden baglanti dener.
     * Baslangic gecikmesi 1 saniye, maksimum 30 saniye.
     */
    private fun scheduleReconnect(url: String) {
        reconnectJob?.cancel()
        val userId = currentUserId ?: return
        val authToken = currentAuthToken ?: return
        reconnectJob = CoroutineScope(Dispatchers.IO + SupervisorJob()).launch {
            var currentDelay = INITIAL_RECONNECT_DELAY_MS
            while (isActive && _connectionState.value !is ConnectionState.Connected) {
                delay(currentDelay)
                try {
                    connect(userId, authToken, url)
                } catch (_: Exception) {
                    // Baglanti denemesi basarisiz — bir sonraki denemede tekrar dene
                }
                currentDelay = (currentDelay * 2).coerceAtMost(MAX_RECONNECT_DELAY_MS)
            }
        }
    }

    /**
     * WebSocket baglantisini kapatir ve tum kaynaklari temizler.
     */
    fun disconnect() {
        reconnectJob?.cancel()
        reconnectJob = null
        webSocket?.close(NORMAL_CLOSURE_CODE, "Client disconnect")
        webSocket = null
        _connectionState.value = ConnectionState.Disconnected
        currentUserId = null
        currentAuthToken = null
    }

    /**
     * WebSocket bağlantı sorunlarını debug etmek için test fonksiyonu.
     * Bu fonksiyon geliştirilme aşamasında connectivity sorunlarını
     * analiz etmek için kullanılır.
     */
    fun debugWebSocketConnection(userId: String, authToken: String, customUrl: String? = null) {
        val url = customUrl ?: signalingUrl
        Log.w("SecureChat", "🔍 Starting WebSocket debug session for: $url")

        val debugger = WebSocketDebugger()

        // Önce HTTP endpoint'ini test et
        debugger.testHttpEndpoint(url)

        // Sonra WebSocket bağlantısını test et
        debugger.testWebSocketConnection(url, userId, authToken)
    }

    /**
     * Manuel olarak yeniden bağlantı dener.
     * Bu fonksiyon kullanıcı trigger'ı ile çağrılabilir.
     */
    fun retryConnection() {
        val userId = currentUserId
        val authToken = currentAuthToken

        if (userId != null && authToken != null) {
            Log.w("SecureChat", "🔄 Manual connection retry initiated")
            disconnect() // Mevcut bağlantıyı temizle
            connect(userId, authToken, signalingUrl) // Yeniden bağlan
        } else {
            Log.w("SecureChat", "❌ Cannot retry connection: missing credentials")
        }
    }

    /**
     * Alternatif WebSocket URL'leri ile bağlantı dener.
     * Eğer primary URL başarısız olursa fallback URL'ler denenir.
     */
    fun connectWithFallback(
        userId: String,
        authToken: String,
        primaryUrl: String,
        fallbackUrls: List<String> = emptyList()
    ) {
        val allUrls = listOf(primaryUrl) + fallbackUrls

        for ((index, url) in allUrls.withIndex()) {
            Log.w("SecureChat", "🔄 Trying connection ${index + 1}/${allUrls.size}: $url")

            try {
                connect(userId, authToken, url)

                // Bağlantı başarılı olup olmadığını kontrol etmek için kısa bir süre bekle
                Thread.sleep(2000)

                if (_connectionState.value is ConnectionState.Connected) {
                    Log.d("SecureChat", "✅ Connection successful with: $url")
                    return
                }
            } catch (e: Exception) {
                Log.e("SecureChat", "❌ Connection failed with $url: ${e.message}")
            }
        }

        Log.e("SecureChat", "❌ All connection attempts failed")
    }

    companion object {
        private const val NORMAL_CLOSURE_CODE = 1000
        private const val INITIAL_RECONNECT_DELAY_MS = 1000L
        private const val MAX_RECONNECT_DELAY_MS = 30_000L
    }
}
