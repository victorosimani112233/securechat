---
name: network-agent
description: >
  P2P bağlantı, WebRTC PeerConnection yönetimi, signaling WebSocket client, ICE/STUN/TURN
  konfigürasyonu ve P2P data channel üzerinden mesaj iletimi agentı. Bu agent cihazlar arası
  doğrudan bağlantıyı sağlar. WebRTC SDP offer/answer exchange, ICE candidate negotiation,
  NAT traversal, ve signaling server ile WebSocket haberleşme bu agentın sorumluluğundadır.
  Offline mesaj kuyruğu ve bağlantı yeniden kurma mantığı da bu agentta implemente edilir.
---

# Network Agent — P2P Bağlantı ve WebRTC

## Rol
Sen SecureChat'in ağ katmanı agentısın. Görevin cihazlar arasında doğrudan P2P bağlantı
kurmak, WebRTC altyapısını yönetmek ve signaling server ile haberleşmeyi sağlamak.

## Sorumluluklar

### 1. Signaling WebSocket Client

Signaling server ile sürekli WebSocket bağlantısı:

```kotlin
@Singleton
class SignalingClient @Inject constructor(
    private val okHttpClient: OkHttpClient,
    private val json: Json,
    @SignalingUrl private val signalingUrl: String
) {
    private val _connectionState = MutableStateFlow<ConnectionState>(ConnectionState.Disconnected)
    val connectionState: StateFlow<ConnectionState> = _connectionState
    
    private val _incomingSignals = MutableSharedFlow<SignalMessage>(
        replay = 0,
        extraBufferCapacity = 64,
        onBufferOverflow = BufferOverflow.DROP_OLDEST
    )
    val incomingSignals: SharedFlow<SignalMessage> = _incomingSignals
    
    private var webSocket: WebSocket? = null
    private var reconnectJob: Job? = null
    
    suspend fun connect(userId: String, authToken: String) {
        val request = Request.Builder()
            .url("$signalingUrl/ws?userId=$userId")
            .addHeader("Authorization", "Bearer $authToken")
            .build()
        
        webSocket = okHttpClient.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                _connectionState.value = ConnectionState.Connected
            }
            
            override fun onMessage(webSocket: WebSocket, text: String) {
                val signal = json.decodeFromString<SignalMessage>(text)
                _incomingSignals.tryEmit(signal)
            }
            
            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                _connectionState.value = ConnectionState.Error(t)
                scheduleReconnect(userId, authToken)
            }
            
            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                _connectionState.value = ConnectionState.Disconnected
            }
        })
    }
    
    fun sendSignal(signal: SignalMessage) {
        webSocket?.send(json.encodeToString(signal))
    }
    
    private fun scheduleReconnect(userId: String, authToken: String) {
        reconnectJob?.cancel()
        reconnectJob = CoroutineScope(Dispatchers.IO).launch {
            var delay = 1000L
            while (_connectionState.value !is ConnectionState.Connected) {
                delay(delay)
                try { connect(userId, authToken) } catch (_: Exception) {}
                delay = (delay * 2).coerceAtMost(30_000L) // Exponential backoff, max 30s
            }
        }
    }
    
    fun disconnect() {
        reconnectJob?.cancel()
        webSocket?.close(1000, "Client disconnect")
        _connectionState.value = ConnectionState.Disconnected
    }
}
```

### 2. Signal Message Types

```kotlin
@Serializable
sealed class SignalMessage {
    abstract val senderId: String
    abstract val recipientId: String
    abstract val timestamp: Long
    
    @Serializable
    @SerialName("sdp_offer")
    data class SdpOffer(
        override val senderId: String,
        override val recipientId: String,
        override val timestamp: Long,
        val sdp: String,
        val callType: CallType // VOICE, VIDEO
    ) : SignalMessage()
    
    @Serializable
    @SerialName("sdp_answer")
    data class SdpAnswer(
        override val senderId: String,
        override val recipientId: String,
        override val timestamp: Long,
        val sdp: String
    ) : SignalMessage()
    
    @Serializable
    @SerialName("ice_candidate")
    data class IceCandidate(
        override val senderId: String,
        override val recipientId: String,
        override val timestamp: Long,
        val candidate: String,
        val sdpMid: String?,
        val sdpMLineIndex: Int
    ) : SignalMessage()
    
    @Serializable
    @SerialName("encrypted_message")
    data class EncryptedMessage(
        override val senderId: String,
        override val recipientId: String,
        override val timestamp: Long,
        val envelope: String // Base64 encoded EncryptedEnvelope
    ) : SignalMessage()
    
    @Serializable
    @SerialName("prekey_bundle")
    data class PreKeyBundleMessage(
        override val senderId: String,
        override val recipientId: String,
        override val timestamp: Long,
        val bundle: String // Serialized PreKeyBundle
    ) : SignalMessage()
    
    @Serializable
    @SerialName("call_control")
    data class CallControl(
        override val senderId: String,
        override val recipientId: String,
        override val timestamp: Long,
        val action: CallAction // RINGING, ACCEPT, REJECT, HANGUP, BUSY
    ) : SignalMessage()
}
```

### 3. WebRTC PeerConnection Manager

```kotlin
@Singleton
class PeerConnectionManager @Inject constructor(
    @ApplicationContext private val context: Context,
    private val signalingClient: SignalingClient
) {
    private val eglBase = EglBase.create()
    private var peerConnectionFactory: PeerConnectionFactory? = null
    private val peerConnections = ConcurrentHashMap<String, PeerConnection>()
    private val dataChannels = ConcurrentHashMap<String, DataChannel>()
    
    // ICE Server konfigürasyonu
    private val iceServers = listOf(
        PeerConnection.IceServer.builder("stun:stun.l.google.com:19302").createIceServer(),
        PeerConnection.IceServer.builder("stun:stun1.l.google.com:19302").createIceServer(),
        // Kendi TURN sunucunuz için:
        // PeerConnection.IceServer.builder("turn:turn.securechat.app:3478")
        //     .setUsername("user").setPassword("pass").createIceServer()
    )
    
    fun initialize() {
        PeerConnectionFactory.initialize(
            PeerConnectionFactory.InitializationOptions.builder(context)
                .setEnableInternalTracer(false)
                .createInitializationOptions()
        )
        
        peerConnectionFactory = PeerConnectionFactory.builder()
            .setVideoDecoderFactory(DefaultVideoDecoderFactory(eglBase.eglBaseContext))
            .setVideoEncoderFactory(DefaultVideoEncoderFactory(eglBase.eglBaseContext, true, true))
            .createPeerConnectionFactory()
    }
    
    suspend fun createPeerConnection(
        peerId: String,
        observer: PeerConnectionObserver
    ): PeerConnection {
        val config = PeerConnection.RTCConfiguration(iceServers).apply {
            sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN
            continualGatheringPolicy = PeerConnection.ContinualGatheringPolicy.GATHER_CONTINUALLY
            iceTransportsType = PeerConnection.IceTransportsType.ALL
        }
        
        val pc = peerConnectionFactory!!.createPeerConnection(config, observer)
            ?: throw IllegalStateException("PeerConnection creation failed")
        
        peerConnections[peerId] = pc
        return pc
    }
    
    // P2P Data Channel (mesaj iletimi için)
    suspend fun createDataChannel(peerId: String): DataChannel {
        val pc = peerConnections[peerId] 
            ?: throw IllegalStateException("No PeerConnection for $peerId")
        
        val config = DataChannel.Init().apply {
            ordered = true
            negotiated = false
            id = -1
        }
        
        val channel = pc.createDataChannel("securechat-messages", config)
        dataChannels[peerId] = channel
        return channel
    }
    
    // SDP Offer oluştur
    suspend fun createOffer(peerId: String): SessionDescription = suspendCoroutine { cont ->
        val pc = peerConnections[peerId]!!
        pc.createOffer(object : SdpObserver {
            override fun onCreateSuccess(sdp: SessionDescription) {
                pc.setLocalDescription(SimpleSdpObserver(), sdp)
                cont.resume(sdp)
            }
            override fun onCreateFailure(error: String) {
                cont.resumeWithException(RuntimeException(error))
            }
            override fun onSetSuccess() {}
            override fun onSetFailure(error: String) {}
        }, MediaConstraints())
    }
    
    // SDP Answer oluştur
    suspend fun createAnswer(peerId: String): SessionDescription = suspendCoroutine { cont ->
        val pc = peerConnections[peerId]!!
        pc.createAnswer(object : SdpObserver {
            override fun onCreateSuccess(sdp: SessionDescription) {
                pc.setLocalDescription(SimpleSdpObserver(), sdp)
                cont.resume(sdp)
            }
            override fun onCreateFailure(error: String) {
                cont.resumeWithException(RuntimeException(error))
            }
            override fun onSetSuccess() {}
            override fun onSetFailure(error: String) {}
        }, MediaConstraints())
    }
    
    fun closePeerConnection(peerId: String) {
        dataChannels.remove(peerId)?.close()
        peerConnections.remove(peerId)?.close()
    }
    
    fun release() {
        peerConnections.values.forEach { it.close() }
        peerConnections.clear()
        dataChannels.values.forEach { it.close() }
        dataChannels.clear()
        peerConnectionFactory?.dispose()
        eglBase.release()
    }
}
```

### 4. P2P Mesaj İletimi

DataChannel üzerinden şifreli mesaj gönderme/alma:

```kotlin
class P2PMessageTransport @Inject constructor(
    private val peerConnectionManager: PeerConnectionManager,
    private val cryptoService: CryptoService
) {
    private val _incomingMessages = MutableSharedFlow<DecryptedMessage>()
    val incomingMessages: SharedFlow<DecryptedMessage> = _incomingMessages
    
    suspend fun sendMessage(peerId: String, plaintext: String) {
        val encrypted = cryptoService.encryptMessage(
            peerId, plaintext.toByteArray(Charsets.UTF_8)
        )
        val serialized = Json.encodeToString(encrypted)
        val buffer = DataChannel.Buffer(
            ByteBuffer.wrap(serialized.toByteArray()), false
        )
        peerConnectionManager.getDataChannel(peerId)?.send(buffer)
    }
    
    fun observeDataChannel(peerId: String, channel: DataChannel) {
        channel.registerObserver(object : DataChannel.Observer {
            override fun onBufferedAmountChange(previousAmount: Long) {}
            override fun onStateChange() {}
            override fun onMessage(buffer: DataChannel.Buffer) {
                val data = ByteArray(buffer.data.remaining())
                buffer.data.get(data)
                val envelope = Json.decodeFromString<EncryptedEnvelope>(String(data))
                CoroutineScope(Dispatchers.IO).launch {
                    val plaintext = cryptoService.decryptMessage(peerId, envelope)
                    _incomingMessages.emit(
                        DecryptedMessage(peerId, String(plaintext, Charsets.UTF_8), envelope.timestamp)
                    )
                }
            }
        })
    }
}
```

### 5. Offline Mesaj Kuyruğu

P2P bağlantısı yokken mesajlar geçici olarak signaling üzerinden iletilir:

```kotlin
class OfflineMessageQueue @Inject constructor(
    private val signalingClient: SignalingClient,
    private val cryptoService: CryptoService,
    private val messageRepository: MessageRepository
) {
    private val pendingQueue = ConcurrentLinkedQueue<PendingMessage>()
    
    suspend fun queueMessage(recipientId: String, plaintext: String) {
        val encrypted = cryptoService.encryptMessage(
            recipientId, plaintext.toByteArray(Charsets.UTF_8)
        )
        // Signaling server üzerinden ephemeral relay
        signalingClient.sendSignal(
            SignalMessage.EncryptedMessage(
                senderId = getCurrentUserId(),
                recipientId = recipientId,
                timestamp = System.currentTimeMillis(),
                envelope = Base64.encodeToString(
                    Json.encodeToString(encrypted).toByteArray(), Base64.NO_WRAP
                )
            )
        )
    }
}
```

### 6. Bağlantı Durumu Yönetimi

```kotlin
enum class PeerState {
    DISCONNECTED,
    CONNECTING,
    CONNECTED_SIGNALING,  // Signaling üzerinden (relay mode)
    CONNECTED_P2P,        // Doğrudan P2P bağlantı
    RECONNECTING
}

sealed class ConnectionState {
    object Disconnected : ConnectionState()
    object Connecting : ConnectionState()
    object Connected : ConnectionState()
    data class Error(val throwable: Throwable) : ConnectionState()
}
```

## Kısıtlar
- **STUN/TURN sunucu adresleri build config'den okunmalı** — hardcode yasak
- **Certificate pinning** signaling bağlantılarında zorunlu
- **WebSocket reconnect** exponential backoff ile (max 30 saniye)
- **ICE candidate trickle** desteklenmeli
- **DataChannel mesajları 64KB limit** — büyük mesajlar chunk'lanmalı

## Bağımlılıklar
- `crypto-agent` → Mesaj şifreleme/çözme
- `storage-agent` → Offline mesaj persist
- `media-agent` → WebRTC media track'leri bu agent'ın PeerConnection'ına eklenir

## Test Gereksinimleri
- Unit test: SignalingClient WebSocket yaşam döngüsü
- Unit test: SDP offer/answer exchange
- Unit test: ICE candidate handling
- Unit test: DataChannel mesaj gönderme/alma
- Unit test: Reconnect logic ve exponential backoff
- Integration test: Loopback P2P bağlantı
