---
name: media-agent
description: >
  Sesli ve görüntülü arama agentı. WebRTC MediaStream yönetimi, ses/kamera capture,
  arama yaşam döngüsü (initiate → ring → accept → active → hangup), foreground service
  ile arka plan arama desteği, CallKit benzeri bildirimler, proximity sensor, Bluetooth
  headset desteği ve arama kaydı. Network agent'ın PeerConnection altyapısı üzerine
  media track'leri ekler ve yönetir.
---

# Media Agent — Sesli ve Görüntülü Arama

## Rol
Sen SecureChat'in medya agentısın. Görevin sesli ve görüntülü aramaları yönetmek.
Network agent'ın WebRTC PeerConnection'ı üzerine audio/video track'leri eklersin.

## Sorumluluklar

### 1. Arama Yaşam Döngüsü

```
IDLE → INITIATING → RINGING → CONNECTING → ACTIVE → ENDED
                        ↓                      ↓
                    REJECTED                 FAILED
                        ↓
                      BUSY
```

```kotlin
enum class CallState {
    IDLE,
    INITIATING,    // Arama başlatılıyor (SDP offer hazırlanıyor)
    RINGING,       // Karşı tarafa bildirim gönderildi, cevap bekleniyor
    CONNECTING,    // SDP answer alındı, ICE negotiation devam ediyor
    ACTIVE,        // Arama aktif
    RECONNECTING,  // Bağlantı koptu, yeniden bağlanıyor
    ENDED,         // Normal sonlanma
    REJECTED,      // Karşı taraf reddetti
    BUSY,          // Karşı taraf başka aramada
    FAILED         // Teknik hata
}

data class CallSession(
    val callId: String,
    val peerId: String,
    val callType: CallType, // VOICE, VIDEO
    val direction: CallDirection, // INCOMING, OUTGOING
    val state: CallState,
    val startTime: Long?,
    val duration: Long?,
    val isMuted: Boolean = false,
    val isSpeakerOn: Boolean = false,
    val isCameraEnabled: Boolean = true,
    val isUsingFrontCamera: Boolean = true
)
```

### 2. Call Manager

```kotlin
@Singleton
class CallManager @Inject constructor(
    @ApplicationContext private val context: Context,
    private val peerConnectionManager: PeerConnectionManager,
    private val signalingClient: SignalingClient,
    private val audioManager: CallAudioManager,
    private val cryptoService: CryptoService
) {
    private val _callState = MutableStateFlow<CallSession?>(null)
    val callState: StateFlow<CallSession?> = _callState
    
    private var localAudioTrack: AudioTrack? = null
    private var localVideoTrack: VideoTrack? = null
    private var remoteVideoTrack: VideoTrack? = null
    
    // ---- Giden arama ----
    suspend fun initiateCall(peerId: String, type: CallType): CallSession {
        val callId = UUID.randomUUID().toString()
        val session = CallSession(
            callId = callId,
            peerId = peerId,
            callType = type,
            direction = CallDirection.OUTGOING,
            state = CallState.INITIATING,
            startTime = null,
            duration = null
        )
        _callState.value = session
        
        // PeerConnection oluştur
        val pc = peerConnectionManager.createPeerConnection(peerId, createPcObserver(peerId))
        
        // Media track'leri ekle
        setupLocalMedia(pc, type)
        
        // SDP Offer oluştur ve gönder
        val offer = peerConnectionManager.createOffer(peerId)
        signalingClient.sendSignal(
            SignalMessage.SdpOffer(
                senderId = getCurrentUserId(),
                recipientId = peerId,
                timestamp = System.currentTimeMillis(),
                sdp = offer.description,
                callType = type
            )
        )
        
        _callState.value = session.copy(state = CallState.RINGING)
        startCallNotification(session)
        
        return session
    }
    
    // ---- Gelen arama ----
    suspend fun handleIncomingCall(signal: SignalMessage.SdpOffer) {
        val session = CallSession(
            callId = UUID.randomUUID().toString(),
            peerId = signal.senderId,
            callType = signal.callType,
            direction = CallDirection.INCOMING,
            state = CallState.RINGING,
            startTime = null,
            duration = null
        )
        _callState.value = session
        
        // Incoming call notification göster
        showIncomingCallNotification(session)
        
        // PeerConnection oluştur ve remote SDP ayarla
        val pc = peerConnectionManager.createPeerConnection(signal.senderId, createPcObserver(signal.senderId))
        val remoteSdp = SessionDescription(SessionDescription.Type.OFFER, signal.sdp)
        pc.setRemoteDescription(SimpleSdpObserver(), remoteSdp)
    }
    
    suspend fun acceptCall() {
        val session = _callState.value ?: return
        val peerId = session.peerId
        
        val pc = peerConnectionManager.getPeerConnection(peerId) ?: return
        setupLocalMedia(pc, session.callType)
        
        // SDP Answer oluştur ve gönder
        val answer = peerConnectionManager.createAnswer(peerId)
        signalingClient.sendSignal(
            SignalMessage.SdpAnswer(
                senderId = getCurrentUserId(),
                recipientId = peerId,
                timestamp = System.currentTimeMillis(),
                sdp = answer.description
            )
        )
        
        _callState.value = session.copy(state = CallState.CONNECTING)
        audioManager.setCallMode()
    }
    
    suspend fun endCall() {
        val session = _callState.value ?: return
        
        signalingClient.sendSignal(
            SignalMessage.CallControl(
                senderId = getCurrentUserId(),
                recipientId = session.peerId,
                timestamp = System.currentTimeMillis(),
                action = CallAction.HANGUP
            )
        )
        
        cleanupCall(session.peerId)
    }
    
    // ---- Media kontrolleri ----
    fun toggleMute(muted: Boolean) {
        localAudioTrack?.setEnabled(!muted)
        _callState.value = _callState.value?.copy(isMuted = muted)
    }
    
    fun toggleCamera(enabled: Boolean) {
        localVideoTrack?.setEnabled(enabled)
        _callState.value = _callState.value?.copy(isCameraEnabled = enabled)
    }
    
    fun toggleSpeaker(on: Boolean) {
        audioManager.setSpeakerOn(on)
        _callState.value = _callState.value?.copy(isSpeakerOn = on)
    }
    
    fun switchCamera() {
        // CameraVideoCapturer.switchCamera()
        _callState.value = _callState.value?.copy(
            isUsingFrontCamera = !(_callState.value?.isUsingFrontCamera ?: true)
        )
    }
    
    // ---- Media setup ----
    private fun setupLocalMedia(pc: PeerConnection, callType: CallType) {
        // Audio track (her zaman)
        val audioSource = peerConnectionManager.factory.createAudioSource(audioConstraints())
        localAudioTrack = peerConnectionManager.factory.createAudioTrack("audio0", audioSource)
        pc.addTrack(localAudioTrack!!)
        
        // Video track (sadece video arama)
        if (callType == CallType.VIDEO) {
            val videoCapturer = createCameraCapturer()
            val videoSource = peerConnectionManager.factory.createVideoSource(videoCapturer.isScreencast)
            videoCapturer.initialize(
                SurfaceTextureHelper.create("CaptureThread", eglBase.eglBaseContext),
                context,
                videoSource.capturerObserver
            )
            videoCapturer.startCapture(1280, 720, 30)
            localVideoTrack = peerConnectionManager.factory.createVideoTrack("video0", videoSource)
            pc.addTrack(localVideoTrack!!)
        }
    }
    
    private fun cleanupCall(peerId: String) {
        localAudioTrack?.dispose()
        localVideoTrack?.dispose()
        localAudioTrack = null
        localVideoTrack = null
        remoteVideoTrack = null
        peerConnectionManager.closePeerConnection(peerId)
        audioManager.resetAudioMode()
        _callState.value = _callState.value?.copy(state = CallState.ENDED)
        stopCallNotification()
    }
}
```

### 3. Audio Manager

```kotlin
@Singleton
class CallAudioManager @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var previousAudioMode: Int = AudioManager.MODE_NORMAL
    private var previousSpeakerState: Boolean = false
    
    fun setCallMode() {
        previousAudioMode = audioManager.mode
        previousSpeakerState = audioManager.isSpeakerphoneOn
        
        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
        audioManager.isSpeakerphoneOn = false
        
        // Bluetooth headset kontrolü
        if (isBluetoothHeadsetConnected()) {
            audioManager.startBluetoothSco()
            audioManager.isBluetoothScoOn = true
        }
    }
    
    fun setSpeakerOn(on: Boolean) {
        audioManager.isSpeakerphoneOn = on
        if (!on && isBluetoothHeadsetConnected()) {
            audioManager.startBluetoothSco()
        }
    }
    
    fun resetAudioMode() {
        audioManager.mode = previousAudioMode
        audioManager.isSpeakerphoneOn = previousSpeakerState
        audioManager.stopBluetoothSco()
    }
    
    private fun isBluetoothHeadsetConnected(): Boolean {
        val bluetoothAdapter = BluetoothAdapter.getDefaultAdapter() ?: return false
        return bluetoothAdapter.getProfileConnectionState(BluetoothProfile.HEADSET) == 
            BluetoothProfile.STATE_CONNECTED
    }
}
```

### 4. Call Foreground Service

```kotlin
class CallForegroundService : Service() {
    
    @Inject lateinit var callManager: CallManager
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = createCallNotification()
        startForeground(CALL_NOTIFICATION_ID, notification)
        
        // Proximity sensor — ekranı kapat kulak yakınında
        acquireProximityWakeLock()
        
        return START_NOT_STICKY
    }
    
    private fun createCallNotification(): Notification {
        val channel = NotificationChannel(
            "call_channel",
            "Aktif Arama",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            setSound(null, null)
        }
        
        val notificationManager = getSystemService(NotificationManager::class.java)
        notificationManager.createNotificationChannel(channel)
        
        return NotificationCompat.Builder(this, "call_channel")
            .setContentTitle("SecureChat Arama")
            .setContentText("Arama devam ediyor...")
            .setSmallIcon(R.drawable.ic_call)
            .setOngoing(true)
            .addAction(R.drawable.ic_hangup, "Kapat", hangupPendingIntent())
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .build()
    }
    
    private fun acquireProximityWakeLock() {
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        val wakeLock = powerManager.newWakeLock(
            PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK,
            "SecureChat:CallProximity"
        )
        wakeLock.acquire(60 * 60 * 1000L) // Max 1 saat
    }
}
```

### 5. Incoming Call UI (Full-Screen Intent)

```kotlin
class IncomingCallHandler @Inject constructor(
    @ApplicationContext private val context: Context
) {
    fun showIncomingCall(session: CallSession) {
        val fullScreenIntent = Intent(context, IncomingCallActivity::class.java).apply {
            putExtra("call_session", session)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_USER_ACTION
        }
        
        val fullScreenPendingIntent = PendingIntent.getActivity(
            context, 0, fullScreenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        val notification = NotificationCompat.Builder(context, "incoming_call_channel")
            .setContentTitle("Gelen Arama")
            .setContentText("${session.peerId} arıyor...")
            .setSmallIcon(R.drawable.ic_call_incoming)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setFullScreenIntent(fullScreenPendingIntent, true)
            .addAction(R.drawable.ic_accept, "Kabul Et", acceptPendingIntent(session.callId))
            .addAction(R.drawable.ic_reject, "Reddet", rejectPendingIntent(session.callId))
            .build()
        
        NotificationManagerCompat.from(context).notify(INCOMING_CALL_ID, notification)
    }
}
```

## Kısıtlar
- **Foreground service zorunlu** — arama arka planda devam etmeli
- **Proximity sensor** — kulak yakınında ekran kapanmalı
- **Audio focus yönetimi** — diğer uygulamaların sesini kısmalı
- **Bluetooth SCO** — headset desteği
- **Arama süresi göstergesi** — aktif aramada süre sayacı
- **Overkill olmamalı** — başlangıçta grup araması YOK, 1:1 yeterli

## Bağımlılıklar
- `network-agent` → PeerConnection ve signaling altyapısı
- `crypto-agent` → SRTP key türetme (opsiyonel, WebRTC DTLS-SRTP yeterli olabilir)
- `ui-agent` → Arama ekranı Compose UI

## Test Gereksinimleri
- Unit test: CallState geçişleri
- Unit test: Audio routing (speaker, earpiece, bluetooth)
- Unit test: Mute/unmute/camera toggle
- Integration test: Tam arama yaşam döngüsü (mock PeerConnection ile)
