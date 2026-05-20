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
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
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
 * - Yeniden baglanti kuruldugunda offline kuyrugu otomatik flush eder (Bug 001)
 * - SENDING durumunda takili kalan mesajlari kurtarir (Bug 003)
 *
 * GUVENLIK: Authorization token WebSocket handshake'inde Bearer token olarak gonderilir.
 */
@Singleton
class SignalingClient @Inject constructor(
    private val okHttpClient: OkHttpClient,
    @Named("signalingUrl") private val signalingUrl: String = ""
) {
    private val json = Json {
        ignoreUnknownKeys = true
        classDiscriminator = "type"
    }

    private val _connectionState = MutableStateFlow<ConnectionState>(ConnectionState.Disconnected)
    val connectionState: StateFlow<ConnectionState> = _connectionState.asStateFlow()

    private val _incomingSignals = MutableSharedFlow<SignalMessage>(
        replay = 0,
        extraBufferCapacity = 512,
        onBufferOverflow = BufferOverflow.DROP_OLDEST
    )
    val incomingSignals: SharedFlow<SignalMessage> = _incomingSignals.asSharedFlow()

    private var webSocket: WebSocket? = null
    private var reconnectJob: Job? = null
    private val reconnectScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var currentUserId: String? = null
    private var currentAuthToken: String? = null
    /** Yeniden baglanti sirasinda ayni anda birden fazla connect() cagrilmasini onler */
    private var isConnecting = false
    /** Server shutdown bildirimi alindi — reconnect oncesi ek bekleme */
    @Volatile
    private var serverShutdownDelay = false

    /** Baglanti kopunca cagirilir — presence state'lerini sifirlamak icin */
    var onConnectionLostListener: (() -> Unit)? = null

    /** Baglanti (yeniden) kurulunca cagirilir — foreground durumuna gore presence gondermek icin */
    var onConnectedListener: (() -> Unit)? = null

    /**
     * Yeniden baglanti kuruldugunda cagirilir — SENDING durumunda takili kalan
     * mesajlari kurtarmak ve offline kuyrugu flush etmek icin (Bug 001, Bug 003).
     * IncomingMessageHandler veya AppLifecycleObserver bu callback'i set eder.
     */
    var onReconnectedCallback: (() -> Unit)? = null

    /**
     * Offline mesaj kuyrugu referansi.
     * Yeniden baglanti kuruldugunda otomatik flush icin kullanilir (Bug 001).
     * Setter ile atanir cunku constructor injection dongusel bagimlilik yaratir.
     */
    var offlineMessageQueue: OfflineMessageQueue? = null

    /**
     * Signaling sunucusuna WebSocket baglantisi kurar.
     * Mevcut baglanti varsa once kapatir (duplicate baglanti onlemi).
     *
     * @param userId Baglanan kullanicinin ID'si
     * @param authToken Yetkilendirme token'i (Bearer)
     * @param customUrl Opsiyonel custom URL, null ise injected URL kullanılır
     */
    @Synchronized
    fun connect(userId: String, authToken: String, customUrl: String? = null) {
        // Zaten baglaniyorsak veya bagliyysak tekrar deneme
        if (isConnecting) {
            Log.d("SecureChat", "connect() skipped — already connecting")
            return
        }
        if (_connectionState.value is ConnectionState.Connected && webSocket != null) {
            Log.d("SecureChat", "connect() skipped — already connected")
            return
        }

        isConnecting = true
        Log.d("SecureChat", "=== SignalingClient.connect() ===")
        Log.d("SecureChat", "  userId=$userId, url=${customUrl ?: signalingUrl}")

        val url = customUrl ?: signalingUrl

        // Onceki WebSocket'i temizle (duplicate baglanti onlemi)
        webSocket?.cancel()
        webSocket = null

        currentUserId = userId
        currentAuthToken = authToken
        _connectionState.value = ConnectionState.Connecting

        val finalUrl = "$url/ws?userId=$userId"

        val request = Request.Builder()
            .url(finalUrl)
            .addHeader("Authorization", "Bearer $authToken")
            .build()

        webSocket = okHttpClient.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                Log.d("SecureChat", "WebSocket CONNECTED (code=${response.code})")
                isConnecting = false
                _connectionState.value = ConnectionState.Connected
                reconnectJob?.cancel()
                onConnectedListener?.invoke()

                // Bug 001: Yeniden baglanti kuruldugunda offline kuyrugu otomatik flush et
                val uid = currentUserId
                if (uid != null) {
                    offlineMessageQueue?.let { queue ->
                        val pendingCount = queue.getPendingCount()
                        if (pendingCount > 0) {
                            Log.d("SecureChat", "Reconnected: flushing $pendingCount offline messages")
                            queue.flushQueue(uid)
                        }
                    }
                }

                // Bug 003: Takili kalan SENDING mesajlarini kurtarmak icin callback
                onReconnectedCallback?.invoke()
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                try {
                    val signal = json.decodeFromString<SignalMessage>(text)
                    // Server shutdown: reconnect oncesi bekleme suresi ayarla
                    if (signal is SignalMessage.ServerShutdown) {
                        Log.w("SecureChat", "Server shutdown bildirimi alindi — 5sn sonra reconnect")
                        serverShutdownDelay = true
                    }
                    _incomingSignals.tryEmit(signal)
                } catch (e: Exception) {
                    Log.w("SecureChat", "Failed to parse WebSocket message: ${e.message}")
                }
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                Log.e("SecureChat", "❌ WebSocket FAILED: ${t.javaClass.simpleName} — ${t.message}")
                isConnecting = false
                _connectionState.value = ConnectionState.Error(t)
                onConnectionLostListener?.invoke()
                scheduleReconnect(url)
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                Log.w("SecureChat", "❌ WebSocket closed (code=$code, reason=$reason)")
                isConnecting = false
                _connectionState.value = ConnectionState.Disconnected
                onConnectionLostListener?.invoke()
                // Kullanici disconnect() cagirmadiysa yeniden baglan
                if (currentUserId != null) {
                    scheduleReconnect(url)
                }
            }

            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                Log.w("SecureChat", "⚠️ WebSocket closing (code=$code)")
            }
        })
    }

    /**
     * Bağlantı yoksa açar ve `Connected` durumunu bekler. Reconnect backoff dongusuyle
     * yarismaz — direkt `connect()` cagrir; zaten bagliysa anında doner.
     *
     * Planli mesaj receiver'lari ve diger arka plan tetikleyicileri icin idealdir:
     * "her ne olursa olsun, yeni bir bağlantı açıp gönder" semantigi saglar.
     *
     * @return timeout icinde Connected'a ulasildiysa true
     */
    suspend fun ensureConnected(
        userId: String,
        authToken: String,
        customUrl: String? = null,
        timeoutMs: Long = 8_000L
    ): Boolean {
        if (_connectionState.value is ConnectionState.Connected && webSocket != null) return true
        connect(userId, authToken, customUrl)
        val result = withTimeoutOrNull(timeoutMs) {
            connectionState.first { it is ConnectionState.Connected }
        }
        return result != null
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
     * Baglanti koptuğunda exponential backoff + jitter ile yeniden baglanti dener.
     * Baslangic gecikmesi 2 saniye, maksimum 30 saniye.
     * Tek scope kullanir — her cagride onceki job iptal edilir (scope leak onlemi).
     */
    private fun scheduleReconnect(url: String) {
        reconnectJob?.cancel()
        val userId = currentUserId ?: return
        val authToken = currentAuthToken ?: return
        reconnectJob = reconnectScope.launch {
            var currentDelay = INITIAL_RECONNECT_DELAY_MS
            // Server shutdown bildirimi alindiysa ilk denemede 5sn ekle
            if (serverShutdownDelay) {
                delay(SERVER_SHUTDOWN_WAIT_MS)
                serverShutdownDelay = false
            }
            while (isActive && _connectionState.value !is ConnectionState.Connected) {
                // Jitter ekle — ayni anda birden fazla client'in reconnect etmesini onle
                val jitter = (currentDelay * 0.2 * Math.random()).toLong()
                delay(currentDelay + jitter)
                // Baglanti zaten kurulduysa (baska bir yerden) cik
                if (_connectionState.value is ConnectionState.Connected) break
                try {
                    connect(userId, authToken, url)
                } catch (_: Exception) { }
                // Baglanti basariliysa dongu zaten sonlanir (Connected check)
                // Degilse backoff artir
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
        isConnecting = false
        // Kapanmadan once offline presence gonder
        currentUserId?.let { uid ->
            sendPresenceUpdate(uid, false)
        }
        webSocket?.close(NORMAL_CLOSURE_CODE, "Client disconnect")
        webSocket = null
        _connectionState.value = ConnectionState.Disconnected
        onConnectionLostListener?.invoke()
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
            reconnectJob?.cancel()
            isConnecting = false
            webSocket?.cancel()
            webSocket = null
            _connectionState.value = ConnectionState.Disconnected
            connect(userId, authToken, signalingUrl)
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

    fun sendPresenceUpdate(userId: String, isOnline: Boolean, hideLastSeen: Boolean = false) {
        val signal = SignalMessage.PresenceUpdate(
            senderId = userId,
            recipientId = "server",
            timestamp = System.currentTimeMillis(),
            isOnline = isOnline,
            lastSeen = System.currentTimeMillis(),
            hideLastSeen = hideLastSeen
        )
        sendSignal(signal)
    }

    /**
     * Belirli bir kullanicinin presence durumuna abone olur.
     * Sunucu aninda mevcut durumu doner ve degisiklikleri push eder.
     */
    fun subscribePresence(targetUserId: String) {
        val uid = currentUserId ?: return
        sendSignal(SignalMessage.PresenceSubscribe(
            senderId = uid,
            recipientId = targetUserId,
            timestamp = System.currentTimeMillis()
        ))
    }

    /**
     * Presence aboneligini iptal eder.
     */
    fun unsubscribePresence(targetUserId: String) {
        val uid = currentUserId ?: return
        sendSignal(SignalMessage.PresenceUnsubscribe(
            senderId = uid,
            recipientId = targetUserId,
            timestamp = System.currentTimeMillis()
        ))
    }

    /**
     * Mevcut kullanici ID'sini dondurur.
     * Offline kuyruk flush ve stuck message recovery icin gereklidir.
     */
    fun getCurrentUserId(): String? = currentUserId

    companion object {
        private const val NORMAL_CLOSURE_CODE = 1000
        private const val INITIAL_RECONNECT_DELAY_MS = 2000L
        private const val MAX_RECONNECT_DELAY_MS = 30_000L
        /** SENDING durumunda takili kalan mesajlar icin timeout suresi (milisaniye) */
        const val STUCK_MESSAGE_TIMEOUT_MS = 30_000L
        /** Server shutdown sonrasi reconnect oncesi bekleme suresi */
        private const val SERVER_SHUTDOWN_WAIT_MS = 5_000L
    }
}
