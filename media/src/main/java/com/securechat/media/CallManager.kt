package com.securechat.media

import android.content.Context
import com.securechat.media.model.CallDirection
import com.securechat.media.model.CallSession
import com.securechat.media.model.CallState
import com.securechat.network.IceServerFetcher
import com.securechat.network.PeerConnectionManager
import com.securechat.network.SignalingClient
import com.securechat.network.SignalMessage
import com.securechat.network.model.CallAction
import com.securechat.network.model.CallType
import com.securechat.storage.dao.CallLogDao
import com.securechat.storage.entity.CallLogEntity
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.concurrent.ConcurrentHashMap
import org.webrtc.EglBase
import org.webrtc.IceCandidate
import org.webrtc.PeerConnection
import org.webrtc.SessionDescription
import org.webrtc.VideoTrack
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Arama yasam dongusunu yoneten ana sinif.
 *
 * Sorumluluklari:
 * - Giden arama baslatma (initiateCall) — WebRTC PeerConnection olusturur, SDP Offer uretir
 * - Gelen arama isleme (handleIncomingCall) — gelen SDP Offer'i saklar
 * - Arama kabul (acceptCall) — PeerConnection olusturur, remote SDP set eder, SDP Answer uretir
 * - Arama red/sonlandirma
 * - SDP Answer ve ICE candidate isleme (handleSdpAnswer, handleIceCandidate)
 * - Medya kontrolleri (mute, speaker, kamera)
 * - Arama durumu yonetimi (CallSession StateFlow)
 *
 * Ses ve video akisi WebRTC PeerConnection uzerinden P2P olarak iletilir.
 * Signaling kanali sadece SDP offer/answer ve ICE candidate degisimi icin kullanilir.
 */
@Singleton
class CallManager @Inject constructor(
    @ApplicationContext private val context: Context,
    private val signalingClient: SignalingClient,
    private val iceServerFetcher: IceServerFetcher,
    private val peerConnectionManager: PeerConnectionManager,
    private val audioManager: CallAudioManager,
    private val ringtonePlayer: RingtonePlayer,
    private val incomingCallHandler: IncomingCallHandler,
    private val callLogDao: CallLogDao,
    private val messageRepository: com.securechat.storage.repository.MessageRepository,
    private val sharedOkHttpClient: okhttp3.OkHttpClient
) {
    private val _callSession = MutableStateFlow<CallSession?>(null)

    /** Aktif arama oturumunu izlemek icin StateFlow. */
    val callSession: StateFlow<CallSession?> = _callSession.asStateFlow()

    /** Aktif arama oturumuna dogrudan erisim. */
    val currentSession: CallSession? get() = _callSession.value

    /** Karsi tarafin video track'i — SurfaceViewRenderer'a baglanir. */
    val remoteVideoTrackFlow: StateFlow<VideoTrack?> get() = peerConnectionManager.remoteVideoTrackFlow

    /** Yerel kamera video track'i — PIP SurfaceViewRenderer icin. */
    val localVideoTrackFlow: StateFlow<VideoTrack?> get() = peerConnectionManager.localVideoTrackFlow

    /** EGL context — SurfaceViewRenderer.init() icin gerekli. */
    val eglBaseContext: EglBase.Context? get() = peerConnectionManager.eglBaseContext

    /** Coroutine scope — async islemler icin kullanilir. */
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /** Yerel kullanici ID'si — arama baslatma ve kabul sirasinda kaydedilir. */
    private var localUserId: String = ""

    /** Cleanup isleminin atomik olarak yapildigini garanti eder. */
    private val isCleaningUp = AtomicBoolean(false)

    // ---- F7 Background blur (goruntulu cagri) ----
    /**
     * Lazy: ML Kit Segmenter + executor maliyetli — kullanici toggle etmeden once
     * insantiate edilmez. Cagri bitince dispose() ile temizlenir.
     */
    private var backgroundBlurProcessor: BackgroundBlurProcessor? = null
    private val isBackgroundBlurEnabled = AtomicBoolean(false)

    /**
     * Arka plan bulaniklastir bayragini ayarlar. Aktif cagri yoksa state cached;
     * sonraki cagri baslayinca processor yine bu bayraga gore takilir.
     */
    fun setBackgroundBlurEnabled(enabled: Boolean) {
        isBackgroundBlurEnabled.set(enabled)
        applyBackgroundBlurState()
    }

    /** Aktif cagri varsa processor'i takar/cikarir; PCM video source initialize edilmis olmali. */
    private fun applyBackgroundBlurState() {
        val enabled = isBackgroundBlurEnabled.get()
        if (enabled) {
            val processor = backgroundBlurProcessor ?: BackgroundBlurProcessor().also {
                backgroundBlurProcessor = it
            }
            processor.isEnabled = true
            peerConnectionManager.setVideoProcessor(processor)
        } else {
            backgroundBlurProcessor?.isEnabled = false
            peerConnectionManager.setVideoProcessor(null)
        }
    }

    /** Cagri bittiginde dispose et — ML Kit + executor resource'larini serbest birak. */
    private fun disposeBackgroundBlur() {
        // Once source'tan unbind et — disposed processor'a frame gelmesin race'i kapatilir.
        runCatching { peerConnectionManager.setVideoProcessor(null) }
        backgroundBlurProcessor?.dispose()
        backgroundBlurProcessor = null
    }

    // ---- Konusma gostergesi (grup arama) ----
    /** Threshold: 0.05 altinda arka plan gurultusu sayilir. */
    private val speakingThreshold = 0.05f
    /** Hold suresi: kelime aralarinda titrememesi icin pulse 800ms yapisik kalir. */
    private val speakingHoldMs = 800L

    private val _speakingPeers = MutableStateFlow<Map<String, Boolean>>(emptyMap())
    /** Konusan peer'lerin durumu: peerId -> isSpeaking. UI pulse animasyonu icin. */
    val speakingPeers: StateFlow<Map<String, Boolean>> = _speakingPeers.asStateFlow()

    private val lastSpokeAt = ConcurrentHashMap<String, Long>()
    private var speakingCollectorJob: Job? = null

    /**
     * Gelen SDP Offer'i saklar. acceptCall() sirasinda remote description olarak kullanilir.
     * handleIncomingCall() ile set edilir, acceptCall() ile tuketilir.
     */
    private var pendingRemoteSdpOffer: String? = null

    /**
     * Gelen aramanin callType'ini saklar. handleIncomingCall() ile set edilir.
     */
    private var pendingCallType: CallType? = null

    /**
     * Calma (ringing) sirasinda gelen ICE candidate'leri burada tamponlanir.
     * acceptCall() sirasinda PeerConnection kurulduktan sonra replay edilir.
     * createPeerConnection() PeerConnectionManager'in kendi buffer'ini temizledigi
     * icin bu ayrı buffer gereklidir.
     */
    private val pendingRemoteIceCandidates = mutableListOf<SignalMessage.IceCandidate>()

    /**
     * Caller-side ringback timeout job. 60 saniye icinde peer ACCEPT/REJECT/BUSY
     * sinyali gondermezse session FAILED olarak kapatilir — boylece kayip sinyaller
     * yuzunden hayalet ringback (sonsuz dıt-dıt sesi) olusmaz.
     */
    private var callerRingbackTimeoutJob: kotlinx.coroutines.Job? = null
    private val CALLER_RINGBACK_TIMEOUT_MS = 60_000L

    // ---- Call waiting (ikinci gelen arama) state ----
    /**
     * Aktif bir cağrı varken gelen ikinci aramayı tutar. WhatsApp tarzı "call waiting" —
     * UI'da küçük banner gösterilir, kullanici Cevapla/Reddet seçebilir.
     * 3. arama gelirse otomatik BUSY donulur (max 2 paralel arama policy).
     */
    private val _secondaryIncomingCall = MutableStateFlow<CallSession?>(null)
    val secondaryIncomingCall: StateFlow<CallSession?> = _secondaryIncomingCall.asStateFlow()

    /** Secondary aramanin SDP offer'i — acceptSecondaryCall sirasinda kullanilir. */
    private var pendingSecondaryOffer: String? = null
    private var pendingSecondaryCallType: CallType? = null

    /** Secondary call icin 30 saniyelik missed-call timer. */
    private var secondaryMissedTimerJob: kotlinx.coroutines.Job? = null
    private val SECONDARY_MISSED_TIMEOUT_MS = 30_000L

    // --- Grup arama state ---
    /** Arayan (koordinator) mi? Yeni uye bildirimlerini bu kisi gonderir. */
    private var isGroupCallCoordinator = false
    /** Su an baglanmis grup uyeleri (mesh peers). */
    private val groupConnectedPeers = mutableSetOf<String>()
    /** Grup aramasi SDP Offer bekleyen peerler (ringing sirasinda). */
    private val pendingGroupSdpOffers = mutableMapOf<String, String>()

    // ---- Giden arama ----

    /**
     * Yeni bir giden arama baslatir.
     *
     * Islem sirasi:
     * 1. CallSession olusturulur (INITIATING)
     * 2. PeerConnectionManager ile PeerConnection olusturulur
     * 3. SDP Offer olusturulur (async, Main thread)
     * 4. SDP Offer signaling uzerinden gonderilir
     * 5. ICE candidate'ler uretildikce signaling uzerinden gonderilir
     * 6. Durum RINGING'e gecilir
     *
     * @param peerId Aranacak kisinin ID'si
     * @param callType Arama tipi (VOICE veya VIDEO)
     * @param userId Arayan kullanicinin ID'si
     */
    fun initiateCall(peerId: String, callType: CallType, userId: String) {
        // DIAGNOSTIC: stack trace ile cagri yolu logla — ghost call kaynak takibi.
        // Eger bu cagri kullanici eyleminden gelmedi ise stack hangi sinif/fonksiyon
        // oldugunu gosterir. Kalici tutmak guvenli, etkisi sadece log.
        android.util.Log.w("CallManager", "initiateCall ENTRY peer=$peerId type=$callType",
            Throwable("CALL_TRACE"))

        // GHOST CALL FIX (cool-down guard): Son 5sn icinde ayni peer'a terminal cleanup
        // tetiklendiyse OTOMATIK initiateCall'i bloklat. Bu Compose recomposition,
        // ViewModel re-create, intent replay gibi UNUSER-DRIVEN tetikleyicileri kapsar.
        // Kullanici 5sn icinde gercekten ayni kisiyi tekrar aramak istiyorsa beklemeli;
        // bu kabul edilebilir (en rare senaryo, ghost call katlanilmaz).
        val sinceTerminal = System.currentTimeMillis() - lastTerminalAtMs
        if (lastTerminalPeerId == peerId && sinceTerminal in 0..CALL_REINITIATE_COOLDOWN_MS) {
            android.util.Log.w("CallManager",
                "initiateCall BLOCKED (cool-down) — peer=$peerId, son terminal'den ${sinceTerminal}ms gecti " +
                "(limit=${CALL_REINITIATE_COOLDOWN_MS}ms). Olasi sebep: Compose re-create / intent replay.")
            return
        }

        // GÜÇLÜ GUARD: Eğer aktif call varsa, ignore et - ASLA duplicate call yapma
        val currentSession = _callSession.value
        if (currentSession != null && (
            currentSession.state == CallState.RINGING ||
            currentSession.state == CallState.ACTIVE ||
            currentSession.state == CallState.INITIATING
        )) {
            android.util.Log.w("CallManager", "initiateCall IGNORE edildi - zaten aktif call var: state=${currentSession.state}, direction=${currentSession.direction}")
            return
        }

        // Race condition önlemi: null yapmak yerine direkt yeni session set et
        localUserId = userId
        val isVideo = callType == CallType.VIDEO
        val session = CallSession(
            callId = UUID.randomUUID().toString(),
            peerId = peerId,
            callType = callType,
            direction = CallDirection.OUTGOING,
            state = CallState.INITIATING,
            startTime = null,
            isSpeakerOn = isVideo // Video aramada hoparlor varsayilan acik
        )
        _callSession.value = session

        // Video aramada hoparloru hemen ac
        if (isVideo) {
            audioManager.setSpeakerOn(true)
        }

        // PeerConnection olustur ve SDP Offer uret
        scope.launch(Dispatchers.Main) {
            try {
                refreshIceServers(userId)
                peerConnectionManager.initialize()
                attachSingleCallConnectionObserver()

                // ICE candidate callback'ini ayarla
                peerConnectionManager.onIceCandidateGenerated = { candidate ->
                    signalingClient.sendSignal(
                        SignalMessage.IceCandidate(
                            senderId = userId,
                            recipientId = peerId,
                            timestamp = System.currentTimeMillis(),
                            candidate = candidate.sdp,
                            sdpMid = candidate.sdpMid,
                            sdpMLineIndex = candidate.sdpMLineIndex
                        )
                    )
                }

                val enableVideo = callType == CallType.VIDEO
                val pc = peerConnectionManager.createPeerConnection(peerId, enableVideo)

                if (pc == null) {
                    android.util.Log.e("CallManager", "PeerConnection olusturulamadi")
                    onCallFailed()
                    return@launch
                }

                // F7: video source olustu — backgroundBlur cached state'i ise hemen tak.
                if (enableVideo) applyBackgroundBlurState()

                // HATA #1 FIX: Arayan tarafta ses modunu HEMEN ayarla.
                // onCallConnected() race condition'dan dolayi cok gec cagirilabilir,
                // bu yuzden PeerConnection kurulduktan hemen sonra set ediyoruz.
                audioManager.setCallMode()

                // SDP Offer olustur
                val offer = peerConnectionManager.createOffer()
                android.util.Log.d("CallManager", "SDP Offer olusturuldu, sdp uzunlugu=${offer.description.length}")

                // SDP Offer'i signaling uzerinden gonder
                signalingClient.sendSignal(
                    SignalMessage.SdpOffer(
                        senderId = userId,
                        recipientId = peerId,
                        timestamp = System.currentTimeMillis(),
                        sdp = offer.description,
                        callType = callType
                    )
                )

                android.util.Log.d("CallManager", "initiateCall gonderildi, peerId=$peerId")
                // Arayan taraf icin ringback tonu baslat
                ringtonePlayer.startRingbackTone()
                _callSession.value = session.copy(state = CallState.RINGING)

                // Caller-side timeout: 60sn icinde peer cevap vermezse hayalet ringback'i durdur
                callerRingbackTimeoutJob?.cancel()
                callerRingbackTimeoutJob = scope.launch {
                    kotlinx.coroutines.delay(CALLER_RINGBACK_TIMEOUT_MS)
                    val current = _callSession.value
                    if (current != null && current.callId == session.callId &&
                        current.state == CallState.RINGING &&
                        current.direction == CallDirection.OUTGOING) {
                        android.util.Log.w("CallManager",
                            "Caller ringback timeout (${CALLER_RINGBACK_TIMEOUT_MS}ms) — hayalet ringback temizleniyor: ${session.callId}")
                        // Karsi tarafa HANGUP gonder (varsa) ve session'i kapat
                        try {
                            signalingClient.sendSignal(
                                SignalMessage.CallControl(
                                    senderId = userId,
                                    recipientId = peerId,
                                    timestamp = System.currentTimeMillis(),
                                    action = CallAction.HANGUP
                                )
                            )
                        } catch (_: Exception) { /* sinyal gonderilemese de cleanup yap */ }
                        cleanupCall(CallState.FAILED)
                    }
                }
            } catch (e: Exception) {
                android.util.Log.e("CallManager", "initiateCall hatasi: ${e.message}")
                onCallFailed()
            }
        }
    }

    // ---- Gelen arama ----

    /**
     * Gelen bir arama sinyalini (SDP Offer) isler.
     *
     * CallSession olusturulur ve RINGING durumuna gecirilir.
     * SDP Offer, acceptCall() sirasinda kullanilmak uzere saklanir.
     * Kullanici acceptCall() cagirana kadar PeerConnection olusturulmaz.
     *
     * @param signal Gelen SDP Offer sinyali
     * @param localUserId Yerel kullanicinin ID'si
     */
    /** Idempotency: ayni SDP Offer'in 2 kez islenmesini engeller (offline queue + WS race). */
    @Volatile private var lastHandledOfferKey: String? = null
    @Volatile private var lastTerminalPeerId: String? = null
    @Volatile private var lastTerminalAtMs: Long = 0L
    private val TERMINAL_OFFER_SUPPRESS_MS = 5_000L
    /**
     * Outgoing call cool-down — terminal cleanup'tan sonra ayni peer'a otomatik
     * initiateCall tetiklenmesin (Compose re-create, intent replay, vs.). 5sn yeterli,
     * gercek kullanici tekrar aramak isterse bu sure sonunda normal calisir.
     */
    private val CALL_REINITIATE_COOLDOWN_MS = 5_000L

    /**
     * Reliable CallControl gondericisi — server'dan ACK alana kadar retry yapar.
     * Senaryo: kullanici HANGUP basti ama WebSocket frame paketi yolda kayboldu;
     * server purge tetiklenmedi → karsi tarafta hayalet call kaliyordu.
     * Cozum: her CallControl mesajina unique messageId koy; server ACK doner;
     * client ACK'i 1.5sn icinde almazsa 3 kez retry eder.
     */
    private val pendingAcks = java.util.concurrent.ConcurrentHashMap<String, kotlinx.coroutines.CompletableDeferred<Unit>>()

    init {
        // Server'dan gelen call_control_ack'lari dinle
        scope.launch {
            signalingClient.incomingSignals.collect { signal ->
                if (signal is SignalMessage.CallControlAck) {
                    pendingAcks.remove(signal.messageId)?.complete(Unit)
                }
            }
        }
    }

    private fun sendCallControlReliable(
        senderId: String,
        recipientId: String,
        action: CallAction
    ) {
        val messageId = UUID.randomUUID().toString()
        val control = SignalMessage.CallControl(
            senderId = senderId,
            recipientId = recipientId,
            timestamp = System.currentTimeMillis(),
            action = action,
            messageId = messageId
        )

        val ack = kotlinx.coroutines.CompletableDeferred<Unit>()
        pendingAcks[messageId] = ack

        scope.launch {
            var attempt = 0
            val maxAttempts = 3
            while (attempt < maxAttempts) {
                attempt++
                val sent = try {
                    signalingClient.sendSignal(control)
                } catch (e: Exception) {
                    android.util.Log.w("CallManager", "sendCallControl attempt $attempt hata: ${e.message}")
                    false
                }
                if (sent) {
                    try {
                        kotlinx.coroutines.withTimeout(1500) { ack.await() }
                        android.util.Log.d("CallManager", "$action ACK alindi (attempt $attempt)")
                        return@launch
                    } catch (_: kotlinx.coroutines.TimeoutCancellationException) {
                        android.util.Log.w("CallManager", "$action ACK timeout — retry $attempt/$maxAttempts")
                    }
                } else {
                    android.util.Log.w("CallManager", "$action sendSignal false — retry $attempt/$maxAttempts")
                }
                if (attempt < maxAttempts) kotlinx.coroutines.delay(1000)
            }
            // Tum denemeler basarisiz — temizle ve sessizce log
            pendingAcks.remove(messageId)
            android.util.Log.e("CallManager", "$action gonderilemedi (max retry, peer=$recipientId)")
        }
    }

    /**
     * Persistent offer keys — process kill sonrasinda da queue replay'i engeller.
     * SharedPreferences'a son 20 handled offer key + timestamp yazilir.
     * TTL: 1 saat (eski entry'ler temizlenir; gecek bir call'da gercek yeni offer
     * timestamp'i farkli oldugu icin engellenmez).
     */
    private val offerHistoryPrefs: android.content.SharedPreferences by lazy {
        context.getSharedPreferences("call_offer_history", android.content.Context.MODE_PRIVATE)
    }
    private val OFFER_HISTORY_KEY = "handled_offers"
    private val OFFER_HISTORY_MAX_SIZE = 20
    private val OFFER_HISTORY_TTL_MS = 3_600_000L // 1 saat

    /** Verilen offer key persistent gecmiste var mi (ve TTL gecmis degil mi)? */
    private fun isOfferAlreadyHandled(offerKey: String): Boolean {
        val now = System.currentTimeMillis()
        val raw = offerHistoryPrefs.getString(OFFER_HISTORY_KEY, "") ?: ""
        if (raw.isBlank()) return false
        // Format: "key1|ts1,key2|ts2,..."
        return raw.split(",")
            .asSequence()
            .mapNotNull {
                val parts = it.split("|", limit = 2)
                if (parts.size == 2) parts[0] to (parts[1].toLongOrNull() ?: 0L) else null
            }
            .filter { now - it.second < OFFER_HISTORY_TTL_MS }
            .any { it.first == offerKey }
    }

    /** Offer key'i persistent gecmise ekle (last-N FIFO + TTL filter). */
    private fun rememberOffer(offerKey: String) {
        val now = System.currentTimeMillis()
        val raw = offerHistoryPrefs.getString(OFFER_HISTORY_KEY, "") ?: ""
        val existing = raw.split(",")
            .mapNotNull {
                val parts = it.split("|", limit = 2)
                if (parts.size == 2) parts[0] to (parts[1].toLongOrNull() ?: 0L) else null
            }
            .filter { now - it.second < OFFER_HISTORY_TTL_MS && it.first != offerKey }
        val updated = (existing + (offerKey to now))
            .takeLast(OFFER_HISTORY_MAX_SIZE)
            .joinToString(",") { "${it.first}|${it.second}" }
        offerHistoryPrefs.edit().putString(OFFER_HISTORY_KEY, updated).apply()
    }

    fun handleIncomingCall(signal: SignalMessage.SdpOffer, localUserId: String) {
        // Idempotency: senderId + timestamp + sdp hash — ayni offer kac kez gelirse gelsin
        // sadece ilkinde session yarat. (FCM-WS double trigger ve queue replay onlemi.)
        val offerKey = "${signal.senderId}:${signal.timestamp}:${signal.sdp.hashCode()}"
        if (offerKey == lastHandledOfferKey) {
            android.util.Log.w("CallManager", "Ayni SDP Offer 2. kez geldi (in-memory) — IGNORE (key=$offerKey)")
            return
        }
        // Persistent check — process kill sonrasi queue replay'i engelle
        if (isOfferAlreadyHandled(offerKey)) {
            android.util.Log.w("CallManager", "Ayni SDP Offer 2. kez geldi (persistent) — IGNORE (key=$offerKey)")
            return
        }

        // Mevcut aktif/ringing call varsa: secondary slot mantigi (call waiting)
        // - Slot bossa: gelen aramayi "ikinci gelen arama" olarak tut, UI'da banner
        //   gosterilir; kullanici Cevapla (eskiyi kapat, yeniyi ac) / Reddet seçebilir.
        // - Slot doluysa (3. arama): otomatik BUSY + sohbet kaydi (mevcut davranis)
        // - Ayni peer ikinci kez offer gonderirse (kendi mevcut call'i): idempotent IGNORE
        val existingSession = _callSession.value
        if (existingSession != null && (
            existingSession.state == CallState.ACTIVE ||
            existingSession.state == CallState.RINGING ||
            existingSession.state == CallState.INITIATING
        )) {
            // Ayni peer'dan tekrar offer geldi → mevcut call zaten o peer ile
            if (existingSession.peerId == signal.senderId) {
                android.util.Log.w("CallManager", "Ayni peer'dan tekrar SDP Offer — IGNORE")
                lastHandledOfferKey = offerKey
                rememberOffer(offerKey)
                return
            }

            val secondarySlot = _secondaryIncomingCall.value
            // Ayni peer ikinci kez ariyorsa (secondary slot'taki ayni peer) ignore
            if (secondarySlot != null && secondarySlot.peerId == signal.senderId) {
                android.util.Log.w("CallManager", "Secondary slot'taki peer'dan tekrar offer — IGNORE")
                lastHandledOfferKey = offerKey
                rememberOffer(offerKey)
                return
            }

            if (secondarySlot == null) {
                // Slot bos — secondary olarak tut, banner UI'da gosterilecek
                android.util.Log.d("CallManager", "Call waiting: ${signal.senderId} aktif call sirasinda ariyor")
                lastHandledOfferKey = offerKey
                rememberOffer(offerKey)
                val secondarySession = CallSession(
                    callId = UUID.randomUUID().toString(),
                    peerId = signal.senderId,
                    callType = signal.callType,
                    direction = CallDirection.INCOMING,
                    state = CallState.RINGING,
                    startTime = null
                )
                _secondaryIncomingCall.value = secondarySession
                pendingSecondaryOffer = signal.sdp
                pendingSecondaryCallType = signal.callType
                // Kisa call-waiting tonu — kullaniciya isaret
                ringtonePlayer.playWaitingTone()
                // 30sn timeout — kullanici cevap vermezse caller'a BUSY don, missed call kaydet
                secondaryMissedTimerJob?.cancel()
                secondaryMissedTimerJob = scope.launch {
                    kotlinx.coroutines.delay(SECONDARY_MISSED_TIMEOUT_MS)
                    val current = _secondaryIncomingCall.value
                    if (current != null && current.callId == secondarySession.callId) {
                        android.util.Log.d("CallManager", "Secondary call timeout — missed olarak isaretleniyor")
                        // Caller'a BUSY don
                        try {
                            signalingClient.sendSignal(
                                SignalMessage.CallControl(
                                    senderId = localUserId,
                                    recipientId = signal.senderId,
                                    timestamp = System.currentTimeMillis(),
                                    action = CallAction.BUSY
                                )
                            )
                        } catch (_: Exception) {}
                        // Cevapsiz olarak kaydet
                        saveCallLog(secondarySession, duration = null, finalState = CallState.BUSY)
                        _secondaryIncomingCall.value = null
                        pendingSecondaryOffer = null
                        pendingSecondaryCallType = null
                    }
                }
                return
            } else {
                // Slot dolu (3. arama) — BUSY + sohbet kaydi
                android.util.Log.w("CallManager", "3. arama geldi (max 2 paralel) — BUSY donuluyor: ${signal.senderId}")
                saveBusyIncomingCallAttempt(signal)
                try {
                    signalingClient.sendSignal(
                        SignalMessage.CallControl(
                            senderId = localUserId,
                            recipientId = signal.senderId,
                            timestamp = System.currentTimeMillis(),
                            action = CallAction.BUSY
                        )
                    )
                } catch (e: Exception) {
                    android.util.Log.w("CallManager", "BUSY signal gonderilemedi: ${e.message}")
                }
                return
            }
        }
        if (existingSession != null &&
            existingSession.peerId == signal.senderId &&
            existingSession.state in setOf(CallState.ENDED, CallState.REJECTED, CallState.FAILED, CallState.BUSY)
        ) {
            val ageMs = System.currentTimeMillis() - lastTerminalAtMs
            if (lastTerminalPeerId == signal.senderId && ageMs in 0..TERMINAL_OFFER_SUPPRESS_MS) {
                lastHandledOfferKey = offerKey
                rememberOffer(offerKey)
                android.util.Log.w(
                    "CallManager",
                    "Terminal cleanup penceresinde SDP Offer geldi — IGNORE (peer=${signal.senderId}, ageMs=$ageMs, key=$offerKey)"
                )
                return
            }
        }
        // Terminal state'deki eski session'i temizle — yeni arama icin yer ac
        if (existingSession != null) {
            android.util.Log.d("CallManager", "Eski terminal session temizleniyor: state=${existingSession.state}")
            _callSession.value = null
            isCleaningUp.set(false)
        }

        // Idempotency anahtarini kaydet — bu offer iki kez islenmeyecek
        lastHandledOfferKey = offerKey

        // Race condition önlemi: null yapmak yerine direkt yeni session set et
        this.localUserId = localUserId

        // Gelen SDP Offer'i sakla — acceptCall() sirasinda remote description olarak kullanilacak
        pendingRemoteSdpOffer = signal.sdp
        pendingCallType = signal.callType

        val session = CallSession(
            callId = UUID.randomUUID().toString(),
            peerId = signal.senderId,
            callType = signal.callType,
            direction = CallDirection.INCOMING,
            state = CallState.RINGING,
            startTime = null
        )
        _callSession.value = session

        // Zil sesi ve titresimi baslat (RingtonePlayer @Synchronized — duplicate korumali)
        ringtonePlayer.startRinging()
    }

    // ---- Arama kabul ----

    /**
     * Gelen aramayi kabul eder.
     * Sadece RINGING durumunda ve INCOMING yonunde calisir.
     *
     * Islem sirasi:
     * 1. ACCEPT kontrol mesaji gonderilir
     * 2. PeerConnection olusturulur
     * 3. Remote SDP Offer set edilir
     * 4. SDP Answer olusturulur ve gonderilir
     * 5. ICE candidate'ler uretildikce gonderilir
     * 6. Ses modu arama moduna gecirilir
     * 7. Durum ACTIVE'e gecilir
     *
     * @param userId Kabul eden kullanicinin ID'si
     */
    fun acceptCall(userId: String) {
        val session = _callSession.value ?: return
        if (session.state != CallState.RINGING || session.direction != CallDirection.INCOMING) return

        // Grup aramasi ise farkli flow kullan
        if (session.isGroupCall) {
            acceptGroupCall(userId)
            return
        }

        val remoteSdp = pendingRemoteSdpOffer
        if (remoteSdp == null) {
            android.util.Log.e("CallManager", "acceptCall hatasi: pendingRemoteSdpOffer null")
            onCallFailed()
            return
        }

        localUserId = userId

        android.util.Log.d("CallManager", "Arama kabul edildi: ${session.callId}")

        // Gelen arama bildirimini kaldir ve zil sesi/titresimi durdur
        incomingCallHandler.dismissIncomingCall()
        ringtonePlayer.stopRinging()

        // ACCEPT kontrol mesajini gonder
        signalingClient.sendSignal(
            SignalMessage.CallControl(
                senderId = userId,
                recipientId = session.peerId,
                timestamp = System.currentTimeMillis(),
                action = CallAction.ACCEPT
            )
        )

        // PeerConnection olustur, remote SDP set et, answer uret
        scope.launch(Dispatchers.Main) {
            try {
                refreshIceServers(userId)
                peerConnectionManager.initialize()
                attachSingleCallConnectionObserver()

                // ICE candidate callback'ini ayarla
                peerConnectionManager.onIceCandidateGenerated = { candidate ->
                    signalingClient.sendSignal(
                        SignalMessage.IceCandidate(
                            senderId = userId,
                            recipientId = session.peerId,
                            timestamp = System.currentTimeMillis(),
                            candidate = candidate.sdp,
                            sdpMid = candidate.sdpMid,
                            sdpMLineIndex = candidate.sdpMLineIndex
                        )
                    )
                }

                val enableVideo = session.callType == CallType.VIDEO
                val pc = peerConnectionManager.createPeerConnection(session.peerId, enableVideo)

                if (pc == null) {
                    android.util.Log.e("CallManager", "PeerConnection olusturulamadi (acceptCall)")
                    onCallFailed()
                    return@launch
                }

                // F7: video source olustu — backgroundBlur cached state'i ise hemen tak.
                if (enableVideo) applyBackgroundBlurState()

                // Remote SDP Offer'i set et (suspend — tamamlanmasi beklenir)
                val remoteDescription = SessionDescription(
                    SessionDescription.Type.OFFER,
                    remoteSdp
                )
                peerConnectionManager.setRemoteDescription(remoteDescription)

                // Calma sirasinda tamponlanan ICE candidate'leri replay et
                val buffered = synchronized(pendingRemoteIceCandidates) {
                    pendingRemoteIceCandidates.toList().also { pendingRemoteIceCandidates.clear() }
                }
                if (buffered.isNotEmpty()) {
                    android.util.Log.d("CallManager", "${buffered.size} tamponlanmis ICE candidate ekleniyor")
                    for (sig in buffered) {
                        peerConnectionManager.addIceCandidate(
                            IceCandidate(sig.sdpMid, sig.sdpMLineIndex, sig.candidate)
                        )
                    }
                }

                // SDP Answer olustur
                val answer = peerConnectionManager.createAnswer()
                android.util.Log.d("CallManager", "SDP Answer olusturuldu, sdp uzunlugu=${answer.description.length}")

                // SDP Answer'i signaling uzerinden gonder
                signalingClient.sendSignal(
                    SignalMessage.SdpAnswer(
                        senderId = userId,
                        recipientId = session.peerId,
                        timestamp = System.currentTimeMillis(),
                        sdp = answer.description
                    )
                )

                // Saklanan SDP'yi temizle
                pendingRemoteSdpOffer = null
                pendingCallType = null

                audioManager.setCallMode()

                // Baglanti kuruldugunu belirten kisa sinyal sesi
                ringtonePlayer.playConnectedTone()

                android.util.Log.d("CallManager", "acceptCall BASARILI, PeerConnection kuruldu")
                _callSession.value = session.copy(
                    state = CallState.ACTIVE,
                    startTime = System.currentTimeMillis()
                )
            } catch (e: Exception) {
                android.util.Log.e("CallManager", "acceptCall PeerConnection hatasi: ${e.message}")
                onCallFailed()
            }
        }
    }

    // ---- SDP ve ICE islemleri ----

    /**
     * Karsi taraftan gelen SDP Answer'i isler (arayan taraf icin).
     * Remote description olarak PeerConnection'a ayarlanir.
     * Bu, ICE baglanti surecini baslatir.
     *
     * @param signal Gelen SDP Answer sinyali
     */
    fun handleSdpAnswer(signal: SignalMessage.SdpAnswer) {
        val session = _callSession.value ?: return

        // Sadece arayan taraf (OUTGOING) SDP Answer alabilir
        if (session.direction != CallDirection.OUTGOING) {
            android.util.Log.w("CallManager", "handleSdpAnswer IGNORE edildi - direction=${session.direction}")
            return
        }

        android.util.Log.d("CallManager", "SDP Answer alindi, peerId=${signal.senderId}")

        scope.launch(Dispatchers.Main) {
            try {
                val remoteDescription = SessionDescription(
                    SessionDescription.Type.ANSWER,
                    signal.sdp
                )
                peerConnectionManager.setRemoteDescription(remoteDescription)
                android.util.Log.d("CallManager", "Remote SDP Answer set edildi")

                // KRITIK: SDP Answer geldigi an pratikte peer accept etti demektir.
                // Bagımsız ACCEPT signal'ine GUVENMEK YERINE burada da onCallConnected'i
                // tetikle — boylece ACCEPT kaybolur/gecikirse de UI "Araniyor..." takilmaz.
                // onCallConnected idempotent: state RINGING+OUTGOING degilse no-op.
                onCallConnected()
            } catch (e: Exception) {
                android.util.Log.e("CallManager", "handleSdpAnswer hatasi: ${e.message}")
            }
        }
    }

    /**
     * Karsi taraftan gelen ICE Candidate'i isler.
     * PeerConnection'a eklenir ve NAT traversal surecine katki saglar.
     *
     * @param signal Gelen ICE Candidate sinyali
     */
    fun handleIceCandidate(signal: SignalMessage.IceCandidate) {
        val session = _callSession.value ?: return

        android.util.Log.d("CallManager", "ICE Candidate alindi, peerId=${signal.senderId}")

        // PeerConnection henuz kurulmadiysa (calma sirasinda) CallManager'da tamponla.
        // createPeerConnection() PeerConnectionManager'in buffer'ini temizler,
        // bu yuzden candidate'leri burada saklamak gerekir.
        if (session.state == CallState.RINGING && session.direction == CallDirection.INCOMING) {
            synchronized(pendingRemoteIceCandidates) {
                pendingRemoteIceCandidates.add(signal)
            }
            android.util.Log.d("CallManager", "ICE Candidate tamponlandi (ringing), toplam=${pendingRemoteIceCandidates.size}")
            return
        }

        scope.launch(Dispatchers.Main) {
            try {
                val candidate = IceCandidate(
                    signal.sdpMid,
                    signal.sdpMLineIndex,
                    signal.candidate
                )
                peerConnectionManager.addIceCandidate(candidate)
            } catch (e: Exception) {
                android.util.Log.e("CallManager", "handleIceCandidate hatasi: ${e.message}")
            }
        }
    }

    // ---- Callback'ler ----

    /**
     * Arama basariyla baglandi callback'i.
     * Karsi taraf ACCEPT sinyali gonderdiginde cagirilir (arayan taraf icin).
     * Ringback tonu durdurulur, ses modu ayarlanir ve durum ACTIVE'e gecirilir.
     * Not: Gercek medya akisi SDP Answer alindiginda (handleSdpAnswer) PeerConnection
     * uzerinden otomatik baslar.
     */
    fun onCallConnected() {
        val session = _callSession.value ?: return

        // Guard clause: sadece OUTGOING/RINGING aramalar icin isle
        // INCOMING aramalar zaten acceptCall() ile handle ediliyor
        if (session.direction != CallDirection.OUTGOING || session.state != CallState.RINGING) {
            android.util.Log.d("CallManager", "onCallConnected islenmedi - direction=${session.direction}, state=${session.state}")
            return
        }

        // Ringback tonunu durdur (arayan tarafta caliyordu)
        ringtonePlayer.stopRingbackTone()
        // Caller timeout iptal — peer cevap verdi
        callerRingbackTimeoutJob?.cancel()
        callerRingbackTimeoutJob = null
        audioManager.setCallMode()

        // Baglanti kuruldugunu belirten kisa sinyal sesi
        ringtonePlayer.playConnectedTone()

        android.util.Log.d("CallManager", "onCallConnected, PeerConnection aktif")

        val newSession = session.copy(
            state = CallState.ACTIVE,
            startTime = System.currentTimeMillis()
        )
        _callSession.value = newSession

        android.util.Log.d("CallManager", "STATE UPDATE: ${session.state} -> ${newSession.state}")
    }

    /**
     * Arama basarisiz oldu callback'i.
     * Temizlik yapar ve durumu FAILED'e gecirir.
     */
    fun onCallFailed() {
        cleanupCall(CallState.FAILED)
    }

    /**
     * Karsi taraf aramayi kapatti callback'i.
     */
    fun onRemoteHangup() {
        // Zil sesi ve titresimi durdur (henuz cevaplanmamis aramada olabilir)
        ringtonePlayer.stopRinging()
        cleanupCall(CallState.ENDED)
    }

    /**
     * Karsi taraf aramayi reddetti callback'i.
     */
    fun onRemoteReject() {
        cleanupCall(CallState.REJECTED)
    }

    /**
     * Karsi taraf mesgul callback'i.
     */
    fun onRemoteBusy() {
        cleanupCall(CallState.BUSY)
    }

    // ---- Grup Arama ----

    /**
     * Grup aramasi baslatir. Tum uyelere GroupCallInvite gonderir.
     * Arayan kisi koordinator olur — yeni uye katildiginda mevcut uyeleri bilgilendirir.
     *
     * Mesh WebRTC modeli:
     * - Her katilimci birbiriyle dogrudan PeerConnection kurar
     * - Arayan koordinator olarak gorev yapar (katilim sinyallerini yonetir)
     * - N katilimci icin her birine N-1 PeerConnection gerekir
     *
     * @param groupId Grup konusma ID'si
     * @param peerIds Grup uyeleri (arayan haric)
     * @param callType Arama tipi (VOICE veya VIDEO)
     * @param userId Arayan kullanicinin ID'si
     */
    fun initiateGroupCall(groupId: String, peerIds: List<String>, callType: CallType, userId: String) {
        val currentSession = _callSession.value
        if (currentSession != null && (
            currentSession.state == CallState.RINGING ||
            currentSession.state == CallState.ACTIVE ||
            currentSession.state == CallState.INITIATING
        )) {
            android.util.Log.w("CallManager", "initiateGroupCall IGNORE — zaten aktif call var")
            return
        }

        localUserId = userId
        isGroupCallCoordinator = true
        groupConnectedPeers.clear()

        val callId = UUID.randomUUID().toString()
        val session = CallSession(
            callId = callId,
            peerId = groupId,
            callType = callType,
            direction = CallDirection.OUTGOING,
            state = CallState.ACTIVE,
            startTime = System.currentTimeMillis(),
            isSpeakerOn = true, // Grup aramalarda hoparlor varsayilan acik
            isGroupCall = true,
            groupId = groupId,
            peerIds = peerIds,
            connectedPeerIds = emptyList()
        )
        _callSession.value = session

        audioManager.setSpeakerOn(true)
        audioManager.setCallMode()

        // Konusma gostergesi polling baslat (idempotent)
        startGroupSpeakingDetection()

        // PeerConnectionManager'i baslat ve ICE callback'ini ayarla
        scope.launch(Dispatchers.Main) {
            try {
                refreshIceServers(userId)
                peerConnectionManager.initialize()

                peerConnectionManager.onGroupIceCandidateGenerated = { peerId, candidate ->
                    signalingClient.sendSignal(
                        SignalMessage.IceCandidate(
                            senderId = userId,
                            recipientId = peerId,
                            timestamp = System.currentTimeMillis(),
                            candidate = candidate.sdp,
                            sdpMid = candidate.sdpMid,
                            sdpMLineIndex = candidate.sdpMLineIndex
                        )
                    )
                }

                peerConnectionManager.onGroupConnectionStateChanged = { peerId, state ->
                    if (state == org.webrtc.PeerConnection.IceConnectionState.CONNECTED ||
                        state == org.webrtc.PeerConnection.IceConnectionState.COMPLETED) {
                        synchronized(groupConnectedPeers) {
                            groupConnectedPeers.add(peerId)
                        }
                        updateGroupConnectedPeers()
                        android.util.Log.d("CallManager", "Grup peer baglandi: $peerId (toplam: ${groupConnectedPeers.size})")
                    } else if (state == org.webrtc.PeerConnection.IceConnectionState.DISCONNECTED ||
                        state == org.webrtc.PeerConnection.IceConnectionState.FAILED) {
                        synchronized(groupConnectedPeers) {
                            groupConnectedPeers.remove(peerId)
                        }
                        updateGroupConnectedPeers()
                    }
                }

                // Tum uyelere davet gonder
                val allParticipants = peerIds + userId
                for (peerId in peerIds) {
                    signalingClient.sendSignal(
                        SignalMessage.GroupCallInvite(
                            senderId = userId,
                            recipientId = peerId,
                            timestamp = System.currentTimeMillis(),
                            groupId = groupId,
                            callType = callType,
                            callId = callId,
                            participants = allParticipants
                        )
                    )
                }

                android.util.Log.d("CallManager", "Grup aramasi baslatildi: $groupId, ${peerIds.size} uye davet edildi")
            } catch (e: Exception) {
                android.util.Log.e("CallManager", "initiateGroupCall hatasi: ${e.message}")
                onCallFailed()
            }
        }

        // Sohbete "Grup araması başladı" sistem mesaji kaydet
        saveGroupCallStartMessage(session)
    }

    /**
     * Gelen grup arama davetiyesini isler.
     * CallSession olusturulur ve RINGING durumuna gecirilir.
     */
    fun handleGroupCallInvite(signal: SignalMessage.GroupCallInvite, localUserId: String) {
        val existingSession = _callSession.value
        if (existingSession != null && (
            existingSession.state == CallState.ACTIVE ||
            existingSession.state == CallState.RINGING ||
            existingSession.state == CallState.INITIATING
        )) {
            android.util.Log.w("CallManager", "handleGroupCallInvite IGNORE — mevcut call var")
            return
        }

        this.localUserId = localUserId
        isGroupCallCoordinator = false
        groupConnectedPeers.clear()

        // Diger katilimcilar (kendisi ve arayan haric)
        val otherPeers = signal.participants.filter { it != localUserId }

        val session = CallSession(
            callId = signal.callId,
            peerId = signal.senderId, // Arayanin ID'si (goruntuleme icin)
            callType = signal.callType,
            direction = CallDirection.INCOMING,
            state = CallState.RINGING,
            startTime = null,
            isGroupCall = true,
            groupId = signal.groupId,
            peerIds = otherPeers,
            connectedPeerIds = emptyList()
        )
        _callSession.value = session

        ringtonePlayer.startRinging()
        android.util.Log.d("CallManager", "Gelen grup aramasi: ${signal.groupId} from ${signal.senderId}")
    }

    /**
     * Grup aramasini kabul eder.
     * Arayan (koordinator) a ACCEPT sinyali gonderir.
     * Koordinator daha sonra mevcut uyelere GroupCallMemberJoined gonderir,
     * ve mevcut uyeler yeni uyeye SDP Offer gonderir.
     */
    fun acceptGroupCall(userId: String) {
        val session = _callSession.value ?: return
        if (!session.isGroupCall || session.state != CallState.RINGING || session.direction != CallDirection.INCOMING) return

        localUserId = userId

        incomingCallHandler.dismissIncomingCall()
        ringtonePlayer.stopRinging()

        // Arayan (koordinator) a ACCEPT gonder
        signalingClient.sendSignal(
            SignalMessage.CallControl(
                senderId = userId,
                recipientId = session.peerId, // Arayan (koordinator)
                timestamp = System.currentTimeMillis(),
                action = CallAction.ACCEPT
            )
        )

        audioManager.setSpeakerOn(true)
        audioManager.setCallMode()

        // PeerConnectionManager'i baslat ve ICE callback'ini ayarla
        scope.launch(Dispatchers.Main) {
            try {
                refreshIceServers(userId)
                peerConnectionManager.initialize()

                peerConnectionManager.onGroupIceCandidateGenerated = { peerId, candidate ->
                    signalingClient.sendSignal(
                        SignalMessage.IceCandidate(
                            senderId = userId,
                            recipientId = peerId,
                            timestamp = System.currentTimeMillis(),
                            candidate = candidate.sdp,
                            sdpMid = candidate.sdpMid,
                            sdpMLineIndex = candidate.sdpMLineIndex
                        )
                    )
                }

                peerConnectionManager.onGroupConnectionStateChanged = { peerId, state ->
                    if (state == org.webrtc.PeerConnection.IceConnectionState.CONNECTED ||
                        state == org.webrtc.PeerConnection.IceConnectionState.COMPLETED) {
                        synchronized(groupConnectedPeers) {
                            groupConnectedPeers.add(peerId)
                        }
                        updateGroupConnectedPeers()
                        android.util.Log.d("CallManager", "Grup peer baglandi: $peerId")
                    } else if (state == org.webrtc.PeerConnection.IceConnectionState.DISCONNECTED ||
                        state == org.webrtc.PeerConnection.IceConnectionState.FAILED) {
                        synchronized(groupConnectedPeers) {
                            groupConnectedPeers.remove(peerId)
                        }
                        updateGroupConnectedPeers()
                    }
                }

                // Bekleyen SDP Offer'leri isle (ringing sirasinda gelen)
                val pendingOffers = synchronized(pendingGroupSdpOffers) {
                    pendingGroupSdpOffers.toMap().also { pendingGroupSdpOffers.clear() }
                }
                for ((peerId, sdp) in pendingOffers) {
                    connectToGroupPeer(peerId, sdp, session.callType)
                }

                android.util.Log.d("CallManager", "Grup aramasi kabul edildi, ${pendingOffers.size} bekleyen offer islendi")
            } catch (e: Exception) {
                android.util.Log.e("CallManager", "acceptGroupCall hatasi: ${e.message}")
                onCallFailed()
            }
        }

        ringtonePlayer.playConnectedTone()
        val activeSession = session.copy(
            state = CallState.ACTIVE,
            startTime = System.currentTimeMillis()
        )
        _callSession.value = activeSession

        // Konusma gostergesi polling baslat (idempotent)
        startGroupSpeakingDetection()

        // Sohbete "Grup araması başladı" sistem mesaji kaydet (her katilan kendi local kopyasi)
        saveGroupCallStartMessage(activeSession)
    }

    /**
     * Grup aramasinda bir uyeye PeerConnection kurar ve SDP Answer gonderir.
     * Mevcut uye SDP Offer gonderdiginde cagirilir.
     */
    private fun connectToGroupPeer(peerId: String, remoteSdp: String, callType: CallType) {
        scope.launch(Dispatchers.Main) {
            try {
                val enableVideo = callType == CallType.VIDEO
                val pc = peerConnectionManager.createGroupPeerConnection(peerId, enableVideo)
                if (pc == null) {
                    android.util.Log.e("CallManager", "Group PeerConnection olusturulamadi: $peerId")
                    return@launch
                }

                val remoteDescription = SessionDescription(SessionDescription.Type.OFFER, remoteSdp)
                peerConnectionManager.setRemoteDescriptionForPeer(peerId, remoteDescription)

                val answer = peerConnectionManager.createAnswerForPeer(peerId)
                signalingClient.sendSignal(
                    SignalMessage.SdpAnswer(
                        senderId = localUserId,
                        recipientId = peerId,
                        timestamp = System.currentTimeMillis(),
                        sdp = answer.description
                    )
                )

                android.util.Log.d("CallManager", "Grup peer'e baglandi (answer): $peerId")
            } catch (e: Exception) {
                android.util.Log.e("CallManager", "connectToGroupPeer hatasi ($peerId): ${e.message}")
            }
        }
    }

    /**
     * Aktif bir grup aramasina sonradan katilim (late-join).
     * Sohbet ekranindaki "Grup araması devam ediyor • Katıl" banner'i tetikler.
     *
     * Mesh modunda: koordinatore GroupCallJoinRequest gonderir, koordinator
     * onGroupCallJoinRequest cevabini verir (mevcut peer'lara haber + yeni
     * uyeye SDP Offer akisi = onGroupMemberAccepted yolu).
     *
     * SFU modunda: bindSfuRoom akisi (Adim 3'te eklenecek) ile dogrudan Janus'a
     * publisher olarak baglanir.
     *
     * @param userId Katilan kullanicinin ID'si
     * @param groupId Grup ID'si
     * @param callId Aktif arama ID'si (status query ile alindi)
     * @param coordinatorId Koordinator kullanici ID'si
     * @param callType VOICE veya VIDEO
     * @param sfuRoomInfo SFU modu icin Janus baglanti bilgisi, mesh modunda null
     */
    fun joinGroupCall(
        userId: String,
        groupId: String,
        callId: String,
        coordinatorId: String,
        callType: CallType,
        sfuRoomInfo: SfuRoomBindInfo? = null
    ) {
        val currentSession = _callSession.value
        if (currentSession != null && (
            currentSession.state == CallState.RINGING ||
            currentSession.state == CallState.ACTIVE ||
            currentSession.state == CallState.INITIATING
        )) {
            android.util.Log.w("CallManager", "joinGroupCall IGNORE — zaten aktif call var")
            return
        }

        localUserId = userId
        isGroupCallCoordinator = false
        groupConnectedPeers.clear()

        val session = CallSession(
            callId = callId,
            peerId = coordinatorId, // koordinator referans icin
            callType = callType,
            direction = CallDirection.OUTGOING, // kullanici aktif olarak katildi
            state = CallState.ACTIVE,
            startTime = System.currentTimeMillis(),
            isSpeakerOn = true,
            isGroupCall = true,
            groupId = groupId,
            peerIds = listOf(coordinatorId),
            connectedPeerIds = emptyList()
        )
        _callSession.value = session

        audioManager.setSpeakerOn(true)
        audioManager.setCallMode()

        // Konusma gostergesi polling baslat (idempotent) — mesh ve SFU her ikisinde de calisir
        startGroupSpeakingDetection()

        if (sfuRoomInfo != null) {
            // SFU modu — bindSfuRoom Adim 3'te eklenecek; simdilik hook
            bindSfuRoom(userId, session, sfuRoomInfo)
        } else {
            // Mesh modu — koordinatore katilim istegi gonder; koordinator mevcut
            // peer listesini bilir ve onGroupMemberAccepted akisini tetikler.
            scope.launch(Dispatchers.Main) {
                try {
                    refreshIceServers(userId)
                    peerConnectionManager.initialize()

                    peerConnectionManager.onGroupIceCandidateGenerated = { peerId, candidate ->
                        signalingClient.sendSignal(
                            SignalMessage.IceCandidate(
                                senderId = userId,
                                recipientId = peerId,
                                timestamp = System.currentTimeMillis(),
                                candidate = candidate.sdp,
                                sdpMid = candidate.sdpMid,
                                sdpMLineIndex = candidate.sdpMLineIndex
                            )
                        )
                    }

                    peerConnectionManager.onGroupConnectionStateChanged = { peerId, state ->
                        if (state == org.webrtc.PeerConnection.IceConnectionState.CONNECTED ||
                            state == org.webrtc.PeerConnection.IceConnectionState.COMPLETED) {
                            synchronized(groupConnectedPeers) { groupConnectedPeers.add(peerId) }
                            updateGroupConnectedPeers()
                        } else if (state == org.webrtc.PeerConnection.IceConnectionState.DISCONNECTED ||
                                   state == org.webrtc.PeerConnection.IceConnectionState.FAILED) {
                            synchronized(groupConnectedPeers) { groupConnectedPeers.remove(peerId) }
                            updateGroupConnectedPeers()
                        }
                    }

                    // Koordinatore katilim istegi
                    signalingClient.sendSignal(
                        SignalMessage.GroupCallJoinRequest(
                            senderId = userId,
                            recipientId = coordinatorId,
                            timestamp = System.currentTimeMillis(),
                            groupId = groupId,
                            callId = callId,
                            callType = callType
                        )
                    )

                    android.util.Log.d("CallManager", "Grup aramasina katilim istegi gonderildi: $groupId -> coord=$coordinatorId")
                } catch (e: Exception) {
                    // Grup arama icin onCallFailed() yanlis cleanup yolu (1-1 cleanupCall)
                    // — grup state'i temiz birakmaz, late-join bagligi sonra yarim kalir.
                    android.util.Log.e("CallManager", "joinGroupCall hatasi: ${e.message}", e)
                    cleanupGroupCall(CallState.FAILED)
                }
            }
        }

        // Sohbete "Grup araması başladı" sistem mesaji kaydet (kendi local kopyasi)
        saveGroupCallStartMessage(session)
    }

    /**
     * Koordinator: bir uye sonradan katilim istedi.
     * onGroupMemberAccepted ile ayni akis — mevcut peer'lara bildir + yeni uyeye PC kur + SDP Offer.
     */
    fun handleGroupCallJoinRequest(signal: SignalMessage.GroupCallJoinRequest) {
        val session = _callSession.value ?: return
        if (!session.isGroupCall || !isGroupCallCoordinator) {
            android.util.Log.w("CallManager", "handleGroupCallJoinRequest IGNORE — koordinator degil")
            return
        }
        if (session.groupId != signal.groupId || session.callId != signal.callId) {
            android.util.Log.w("CallManager", "handleGroupCallJoinRequest IGNORE — groupId/callId uyumsuz")
            return
        }
        // SFU modundayken mesh join istegi gelmemeli — yine de geldiyse sessizce ignore et,
        // dogru akis: joiner sunucudan GroupCallStatusResponse alip SFU bilgisi ile bindSfuRoom yapar.
        if (janusClient != null) {
            android.util.Log.w("CallManager", "handleGroupCallJoinRequest IGNORE — SFU modunda mesh join istegi")
            return
        }
        // peerIds listesine ekle (idempotent)
        val newPeerIds = (session.peerIds + signal.senderId).distinct()
        _callSession.value = session.copy(peerIds = newPeerIds)

        // Mevcut akis: onGroupMemberAccepted ile ayni
        onGroupMemberAccepted(signal.senderId)
    }

    /**
     * SFU bind bilgisi — joinGroupCall ve handleSfuRoomCreated kullanir.
     *
     * GUVENLIK: apiSecret alani BURADAN KALDIRILDI (C2 fix).
     * Janus auth Nginx reverse proxy (JWT) veya token plugin uzerinden saglanir.
     */
    data class SfuRoomBindInfo(
        val roomId: Long,
        val janusWsUrl: String
    )

    /** Aktif Janus istemcisi — sadece SFU modunda dolu. */
    private var janusClient: com.securechat.network.JanusClient? = null

    /**
     * IncomingMessageHandler.handleSfuRoomCreated tarafindan cagirilir.
     * Aktif grup arama mesh modundayken sunucu SFU room actiginda buraya yonlendirilir.
     */
    fun bindSfuRoomFromInvite(userId: String, info: SfuRoomBindInfo) {
        val session = _callSession.value ?: return
        if (!session.isGroupCall) return
        bindSfuRoom(userId, session, info)
    }

    /**
     * SFU moduna baglan: Janus'a publisher olarak katil, mevcut yayincilara abone ol,
     * yerel media'yi yayinla. onPublisherJoined/Left callback'leri ile dinamik yonetilir.
     *
     * Akis:
     * 1. JanusClient.connect → createSession → attachVideoRoom → joinAsPublisher
     * 2. PeerConnectionManager.createSfuPublisherPeerConnection → createOffer → publishSdp → setAnswer
     * 3. Mevcut publisher listesi icin subscribeToFeed → setSubscriberRemoteAndCreateAnswer → answerSubscription
     * 4. ICE candidate'lar trickle gonderilir (Janus'a)
     */
    private fun bindSfuRoom(userId: String, session: CallSession, info: SfuRoomBindInfo) {
        scope.launch(Dispatchers.IO) {
            try {
                android.util.Log.d("CallManager", "bindSfuRoom basliyor: room=${info.roomId} ws=${info.janusWsUrl}")
                refreshIceServers(userId)

                val client = com.securechat.network.JanusClient(sharedOkHttpClient).also { janusClient = it }
                // Janus auth artik Nginx reverse proxy katmaninda (JWT) yapilir — client apiSecret tasimaz.
                val connected = client.connect(info.janusWsUrl)
                if (!connected) {
                    android.util.Log.e("CallManager", "Janus baglantisi kurulamadi")
                    onCallFailed()
                    return@launch
                }
                client.createSession()
                client.attachVideoRoom()
                val existingPublishers = client.joinAsPublisher(info.roomId, userId)
                android.util.Log.d("CallManager", "Janus'a publisher olarak katildi, mevcut=${existingPublishers.size}")

                // Mevcut PC'leri kapatabilir miyiz? bindSfuRoom mesh ile cakisirsa cikar
                // (4. uye katildiginda sunucu room acti — mesh hala calisiyor olabilir).
                // En guvenli: mesh group PC'lerini kapat, SFU'ya gec.
                withContext(Dispatchers.Main) {
                    peerConnectionManager.closeGroupPeerConnectionsOnly()
                }

                // Publisher PC + offer
                val enableVideo = session.callType == CallType.VIDEO
                withContext(Dispatchers.Main) {
                    peerConnectionManager.onSfuPublisherIce = { candidate ->
                        try {
                            client.trickleIce(
                                handleId = client.getPublisherHandleId(),
                                sdpMid = candidate.sdpMid,
                                sdpMLineIndex = candidate.sdpMLineIndex,
                                candidate = candidate.sdp
                            )
                        } catch (_: Exception) { }
                    }
                    peerConnectionManager.onSfuPublisherIceComplete = {
                        try { client.trickleIceCompleted(client.getPublisherHandleId()) } catch (_: Exception) { }
                    }
                    peerConnectionManager.onSfuSubscriberIce = subIce@{ feedId, candidate ->
                        try {
                            val handleId = client.getSubscriberHandleId(feedId) ?: return@subIce
                            client.trickleIce(
                                handleId = handleId,
                                sdpMid = candidate.sdpMid,
                                sdpMLineIndex = candidate.sdpMLineIndex,
                                candidate = candidate.sdp
                            )
                        } catch (_: Exception) { }
                    }
                    peerConnectionManager.onSfuPublisherConnectionStateChanged = { state ->
                        if (state == org.webrtc.PeerConnection.IceConnectionState.CONNECTED ||
                            state == org.webrtc.PeerConnection.IceConnectionState.COMPLETED) {
                            synchronized(groupConnectedPeers) {
                                groupConnectedPeers.add("sfu_self")
                            }
                            updateGroupConnectedPeers()
                        }
                    }
                    peerConnectionManager.createSfuPublisherConnection(enableVideo)
                }

                val publisherOffer = withContext(Dispatchers.Main) {
                    peerConnectionManager.createSfuPublisherOffer()
                }
                val publisherAnswer = client.publishSdp(publisherOffer.description)
                withContext(Dispatchers.Main) {
                    peerConnectionManager.setSfuPublisherRemoteAnswer(
                        SessionDescription(SessionDescription.Type.ANSWER, publisherAnswer)
                    )
                }

                // Mevcut publisher'lara abone ol
                for ((feedId, display) in existingPublishers) {
                    subscribeToSfuFeed(client, info.roomId, feedId, display)
                }

                // Yeni publisher'lar icin callback
                client.onPublisherJoined = { feedId, display ->
                    scope.launch(Dispatchers.IO) {
                        try {
                            subscribeToSfuFeed(client, info.roomId, feedId, display)
                        } catch (e: Exception) {
                            android.util.Log.e("CallManager", "SFU yeni publisher abone hatasi: ${e.message}")
                        }
                    }
                }
                client.onPublisherLeft = { feedId ->
                    scope.launch(Dispatchers.Main) {
                        peerConnectionManager.disposeSfuSubscriber(feedId)
                        synchronized(groupConnectedPeers) {
                            groupConnectedPeers.remove("sfu_$feedId")
                        }
                        updateGroupConnectedPeers()
                    }
                }

                android.util.Log.d("CallManager", "bindSfuRoom tamamlandi: room=${info.roomId} subs=${existingPublishers.size}")
            } catch (e: Exception) {
                android.util.Log.e("CallManager", "bindSfuRoom hatasi: ${e.message}", e)
                onCallFailed()
            }
        }
    }

    /** Tek bir uzak feed'e SFU abone ol — bindSfuRoom ve onPublisherJoined kullanir. */
    private suspend fun subscribeToSfuFeed(
        client: com.securechat.network.JanusClient,
        roomId: Long,
        feedId: Long,
        display: String?
    ) {
        try {
            val subscriberOffer = client.subscribeToFeed(roomId, feedId)
            withContext(Dispatchers.Main) {
                peerConnectionManager.createSfuSubscriberConnection(feedId)
            }
            // Konusma gostergesi: feedId -> peerId eslesmesini kaydet.
            // Janus 'display' alani peerId tasir; null durumda fallback uretiriz.
            peerConnectionManager.registerSfuFeed(feedId, display ?: "feed_$feedId")

            val answer = withContext(Dispatchers.Main) {
                peerConnectionManager.handleSfuSubscriberOffer(
                    feedId,
                    SessionDescription(SessionDescription.Type.OFFER, subscriberOffer)
                )
            }
            client.answerSubscription(feedId, answer.description)
            synchronized(groupConnectedPeers) {
                groupConnectedPeers.add("sfu_$feedId")
            }
            updateGroupConnectedPeers()
            android.util.Log.d("CallManager", "SFU feed abone tamamlandi: feedId=$feedId display=$display")
        } catch (e: Exception) {
            android.util.Log.e("CallManager", "SFU subscribe hatasi feedId=$feedId: ${e.message}")
        }
    }

    /**
     * Grup aramasinda koordinator: Bir uye ACCEPT gonderdiginde cagirilir.
     * Yeni uyeye PeerConnection kurar ve mevcut uyelere bildirir.
     */
    fun onGroupMemberAccepted(memberId: String) {
        val session = _callSession.value ?: return
        if (!session.isGroupCall || !isGroupCallCoordinator) return

        android.util.Log.d("CallManager", "Grup uyesi kabul etti: $memberId")

        // Mevcut bagli uyelere yeni uye bildir — onlar da PeerConnection kuracak
        synchronized(groupConnectedPeers) {
            for (existingPeerId in groupConnectedPeers) {
                signalingClient.sendSignal(
                    SignalMessage.GroupCallMemberJoined(
                        senderId = localUserId,
                        recipientId = existingPeerId,
                        timestamp = System.currentTimeMillis(),
                        groupCallId = session.callId,
                        joinedMemberId = memberId
                    )
                )
            }
        }

        // Koordinator olarak yeni uyeye PeerConnection kur ve SDP Offer gonder
        scope.launch(Dispatchers.Main) {
            try {
                val enableVideo = session.callType == CallType.VIDEO
                val pc = peerConnectionManager.createGroupPeerConnection(memberId, enableVideo)
                if (pc == null) {
                    android.util.Log.e("CallManager", "Group PeerConnection olusturulamadi: $memberId")
                    return@launch
                }

                val offer = peerConnectionManager.createOfferForPeer(memberId)
                signalingClient.sendSignal(
                    SignalMessage.SdpOffer(
                        senderId = localUserId,
                        recipientId = memberId,
                        timestamp = System.currentTimeMillis(),
                        sdp = offer.description,
                        callType = session.callType
                    )
                )

                android.util.Log.d("CallManager", "Koordinator -> yeni uye SDP Offer gonderildi: $memberId")
            } catch (e: Exception) {
                android.util.Log.e("CallManager", "onGroupMemberAccepted PeerConnection hatasi ($memberId): ${e.message}")
            }
        }
    }

    /**
     * Grup aramasinda: Yeni bir uye katildi bildirimi alindi.
     * Yeni uyeye PeerConnection kurar ve SDP Offer gonderir.
     */
    fun handleGroupCallMemberJoined(signal: SignalMessage.GroupCallMemberJoined) {
        val session = _callSession.value ?: return
        if (!session.isGroupCall || session.state != CallState.ACTIVE) return

        val newMemberId = signal.joinedMemberId
        android.util.Log.d("CallManager", "Grup uyesi katildi bildirimi: $newMemberId")

        scope.launch(Dispatchers.Main) {
            try {
                val enableVideo = session.callType == CallType.VIDEO
                val pc = peerConnectionManager.createGroupPeerConnection(newMemberId, enableVideo)
                if (pc == null) {
                    android.util.Log.e("CallManager", "Group PeerConnection olusturulamadi: $newMemberId")
                    return@launch
                }

                val offer = peerConnectionManager.createOfferForPeer(newMemberId)
                signalingClient.sendSignal(
                    SignalMessage.SdpOffer(
                        senderId = localUserId,
                        recipientId = newMemberId,
                        timestamp = System.currentTimeMillis(),
                        sdp = offer.description,
                        callType = session.callType
                    )
                )

                android.util.Log.d("CallManager", "Mevcut uye -> yeni uye SDP Offer gonderildi: $newMemberId")
            } catch (e: Exception) {
                android.util.Log.e("CallManager", "handleGroupCallMemberJoined PeerConnection hatasi: ${e.message}")
            }
        }
    }

    /**
     * Grup aramasindan uye ayrildi bildirimi (sunucu WebSocket disconnect tespitiyle).
     * - Mesh: ilgili PeerConnection dispose edilir
     * - SFU: feedId tutuluyorsa subscriber dispose (Janus onPublisherLeft ayri yoldan da gelir)
     * - peerIds + connectedPeerIds guncellenir; kimse kalmazsa cleanup
     */
    fun handleGroupCallMemberLeft(signal: SignalMessage.GroupCallMemberLeft) {
        val session = _callSession.value ?: return
        if (!session.isGroupCall) return

        val leftId = signal.leftMemberId
        if (leftId == localUserId) return // kendimizi ignore

        android.util.Log.d("CallManager", "Grup uyesi ayrildi (server disconnect): $leftId")

        // Mesh PC dispose (varsa)
        scope.launch(Dispatchers.Main) {
            try {
                peerConnectionManager.disposeGroupPeerConnection(leftId)
            } catch (e: Exception) {
                android.util.Log.w("CallManager", "disposeGroupPeerConnection hatasi ($leftId): ${e.message}")
            }
        }

        // Connected/invited listelerini guncelle
        synchronized(groupConnectedPeers) { groupConnectedPeers.remove(leftId) }
        val newPeerIds = session.peerIds.filterNot { it == leftId }
        val newConnected = session.connectedPeerIds.filterNot { it == leftId }
        _callSession.value = session.copy(peerIds = newPeerIds, connectedPeerIds = newConnected)
        updateGroupConnectedPeers()

        // Kimse kalmadiysa aramayi bitir
        if (groupConnectedPeers.isEmpty() && newPeerIds.isEmpty()) {
            android.util.Log.d("CallManager", "Grup aramasinda kimse kalmadi (server signal), sonlandiriliyor")
            cleanupGroupCall(CallState.ENDED)
        }
    }

    /**
     * Sunucudan koordinator devri bildirimi.
     * Eski koordinator disconnect/HANGUP yaptiginda sunucu kalan uyelerden birini
     * yeni koordinator olarak secer; arama kesilmeden devam eder.
     *
     * - Yerel kullanici yeni koordinator ise: isGroupCallCoordinator=true,
     *   onGroupConnectionStateChanged callback'i ayarlanir (yeni katilimcilari handle)
     * - CallSession.peerId koordinator referansi olarak guncellenir (late-join akisi)
     */
    fun handleGroupCallCoordinatorChanged(signal: SignalMessage.GroupCallCoordinatorChanged) {
        val session = _callSession.value ?: return
        if (!session.isGroupCall) return

        val newCoord = signal.newCoordinatorId
        val prevCoord = signal.previousCoordinatorId
        android.util.Log.d(
            "CallManager",
            "Koordinator devir: $prevCoord → $newCoord (yerel=$localUserId)"
        )

        // Session referansini guncelle (peerId, koordinator UUID'sini tasir)
        _callSession.value = session.copy(peerId = newCoord)

        // Yerel kullanici yeni koordinator mu?
        if (newCoord == localUserId && !isGroupCallCoordinator) {
            isGroupCallCoordinator = true
            android.util.Log.d("CallManager", "Yerel kullanici artik koordinator")

            // Yeni gelen uyeleri kabul edebilmek icin connection-state callback'ini
            // yeniden ayarla — initiateGroupCall'daki ayni mantik (idempotent).
            peerConnectionManager.onGroupConnectionStateChanged = { peerId, state ->
                if (state == org.webrtc.PeerConnection.IceConnectionState.CONNECTED ||
                    state == org.webrtc.PeerConnection.IceConnectionState.COMPLETED) {
                    synchronized(groupConnectedPeers) { groupConnectedPeers.add(peerId) }
                    updateGroupConnectedPeers()
                } else if (state == org.webrtc.PeerConnection.IceConnectionState.DISCONNECTED ||
                    state == org.webrtc.PeerConnection.IceConnectionState.FAILED) {
                    synchronized(groupConnectedPeers) { groupConnectedPeers.remove(peerId) }
                    updateGroupConnectedPeers()
                }
            }
        } else if (newCoord != localUserId && isGroupCallCoordinator) {
            // Defansif: server farkli birini koordinator yaptiysa yerel flag'i sustur
            isGroupCallCoordinator = false
        }
    }

    /**
     * Grup aramasinda SDP Offer alindi.
     * Eger grup aramasi ringing durumundaysa tamponlar,
     * aktifse direkt PeerConnection kurar.
     */
    fun handleGroupSdpOffer(signal: SignalMessage.SdpOffer) {
        val session = _callSession.value ?: return
        if (!session.isGroupCall) return

        if (session.state == CallState.RINGING) {
            // Ringing — henuz kabul edilmedi, tamponla
            synchronized(pendingGroupSdpOffers) {
                pendingGroupSdpOffers[signal.senderId] = signal.sdp
            }
            android.util.Log.d("CallManager", "Grup SDP Offer tamponlandi (ringing): ${signal.senderId}")
        } else if (session.state == CallState.ACTIVE) {
            connectToGroupPeer(signal.senderId, signal.sdp, signal.callType)
        }
    }

    /**
     * Grup aramasinda SDP Answer alindi.
     * Ilgili PeerConnection'a remote description olarak ayarlar.
     */
    fun handleGroupSdpAnswer(signal: SignalMessage.SdpAnswer) {
        val session = _callSession.value ?: return
        if (!session.isGroupCall) return

        scope.launch(Dispatchers.Main) {
            try {
                val remoteDescription = SessionDescription(SessionDescription.Type.ANSWER, signal.sdp)
                peerConnectionManager.setRemoteDescriptionForPeer(signal.senderId, remoteDescription)
                android.util.Log.d("CallManager", "Grup SDP Answer islendi: ${signal.senderId}")
            } catch (e: Exception) {
                android.util.Log.e("CallManager", "handleGroupSdpAnswer hatasi (${signal.senderId}): ${e.message}")
            }
        }
    }

    /**
     * Grup aramasinda ICE Candidate alindi.
     * Ilgili PeerConnection'a eklenir.
     */
    fun handleGroupIceCandidate(signal: SignalMessage.IceCandidate) {
        val session = _callSession.value ?: return
        if (!session.isGroupCall) return

        scope.launch(Dispatchers.Main) {
            try {
                val candidate = org.webrtc.IceCandidate(
                    signal.sdpMid,
                    signal.sdpMLineIndex,
                    signal.candidate
                )
                peerConnectionManager.addIceCandidateForPeer(signal.senderId, candidate)
            } catch (e: Exception) {
                android.util.Log.e("CallManager", "handleGroupIceCandidate hatasi: ${e.message}")
            }
        }
    }

    /** connectedPeerIds listesini gunceller. */
    private fun updateGroupConnectedPeers() {
        val session = _callSession.value ?: return
        if (!session.isGroupCall) return
        val connected = synchronized(groupConnectedPeers) { groupConnectedPeers.toList() }
        _callSession.value = session.copy(connectedPeerIds = connected)
    }

    /**
     * Grup aramasini sonlandirir.
     * Tum peer'lere HANGUP gonderir ve tum PeerConnection'lari temizler.
     */
    fun endGroupCall(userId: String) {
        val session = _callSession.value ?: return
        if (!session.isGroupCall) return

        val sessionGroupId = session.groupId

        // Eski client compat: peer-peer HANGUP fan-out. Yeni server bu HANGUP'lari
        // sadece routing icin gorur (recipientId="server" degil → devir/broadcast yok).
        // Eski client'lar bu mesajla ilgili peer'in PC'sini dispose eder.
        for (peerId in session.peerIds) {
            signalingClient.sendSignal(
                SignalMessage.CallControl(
                    senderId = userId,
                    recipientId = peerId,
                    timestamp = System.currentTimeMillis(),
                    action = CallAction.HANGUP,
                    groupId = sessionGroupId
                )
            )
        }

        // Server'a tek HANGUP — koordinator olsun veya olmasin, devir/temizlik logic'ini
        // tetikler: participant cikarilir, koordinatorse devredilir, herkese member_left
        // (gerekirse coordinator_changed) broadcast edilir.
        if (sessionGroupId != null) {
            signalingClient.sendSignal(
                SignalMessage.CallControl(
                    senderId = userId,
                    recipientId = "server",
                    timestamp = System.currentTimeMillis(),
                    action = CallAction.HANGUP,
                    groupId = sessionGroupId
                )
            )
        }

        cleanupGroupCall(CallState.ENDED)
    }

    /**
     * Grup aramasinda bir uye ayrildi.
     * Ilgili PeerConnection'i temizler.
     */
    fun onGroupMemberHangup(memberId: String) {
        val session = _callSession.value ?: return
        if (!session.isGroupCall) return

        peerConnectionManager.disposeGroupPeerConnection(memberId)
        synchronized(groupConnectedPeers) {
            groupConnectedPeers.remove(memberId)
        }
        updateGroupConnectedPeers()
        android.util.Log.d("CallManager", "Grup uyesi ayrildi: $memberId")

        // Kimse kalmadiysa aramayi sonlandir
        if (groupConnectedPeers.isEmpty()) {
            android.util.Log.d("CallManager", "Grup aramasinda kimse kalmadi, sonlandiriliyor")
            cleanupGroupCall(CallState.ENDED)
        }
    }

    /**
     * Grup arama konusma gostergesi icin polling + collector baslat.
     * Idempotent: 3 grup arama girisinde (initiate/accept/join) cagirilabilir.
     */
    private fun startGroupSpeakingDetection() {
        peerConnectionManager.startAudioLevelPolling()

        // Collector idempotency: onceki job iptal et, yenisini baslat
        speakingCollectorJob?.cancel()
        speakingCollectorJob = scope.launch {
            peerConnectionManager.audioLevelsFlow.collect { levels ->
                val now = System.currentTimeMillis()
                // Konusma threshold'unu gecen peer'ler icin son konusma zamanini guncelle
                for ((peerId, level) in levels) {
                    if (level > speakingThreshold) lastSpokeAt[peerId] = now
                }
                // Artik aktif PC'lerde olmayan eski peer'leri temizle
                val activePeers = levels.keys
                (lastSpokeAt.keys - activePeers).forEach { lastSpokeAt.remove(it) }

                // Hold penceresi icindeki peer'ler "konusuyor" sayilir
                _speakingPeers.value = levels.mapValues { (peerId, _) ->
                    (now - (lastSpokeAt[peerId] ?: 0L)) < speakingHoldMs
                }
            }
        }
    }

    /** Polling ve collector'i durdurur, state'i sifirlar. */
    private fun stopGroupSpeakingDetection() {
        peerConnectionManager.stopAudioLevelPolling()
        speakingCollectorJob?.cancel()
        speakingCollectorJob = null
        lastSpokeAt.clear()
        _speakingPeers.value = emptyMap()
    }

    /** Grup aramasi kaynaklarini temizler. */
    private fun cleanupGroupCall(finalState: CallState) {
        if (!isCleaningUp.compareAndSet(false, true)) return

        try {
            val session = _callSession.value ?: return
            val duration = session.startTime?.let { System.currentTimeMillis() - it }

            saveCallLog(session, duration, finalState)

            // Grup aramasi bitti — sohbete sistem mesaji kaydet (her uye kendi local kopyasi)
            if (finalState == CallState.ENDED || finalState == CallState.FAILED) {
                saveGroupCallEndMessage(session, duration)
            }

            incomingCallHandler.dismissIncomingCall()
            ringtonePlayer.stopRinging()
            ringtonePlayer.stopRingbackTone()

            // Konusma gostergesi: PCM dispose'larindan ONCE (cancelAndJoin ile in-flight tick biter)
            stopGroupSpeakingDetection()

            peerConnectionManager.disposeAllGroupPeerConnections()
            peerConnectionManager.disposeAllSfuConnections()

            // SFU janus baglantisini kapat
            janusClient?.let { jc ->
                scope.launch(Dispatchers.IO) {
                    try { jc.leaveRoom() } catch (_: Exception) { }
                    try { jc.disconnect() } catch (_: Exception) { }
                }
            }
            janusClient = null

            audioManager.resetAudioMode()

            isGroupCallCoordinator = false
            groupConnectedPeers.clear()
            synchronized(pendingGroupSdpOffers) { pendingGroupSdpOffers.clear() }

            _callSession.value = session.copy(
                state = finalState,
                duration = duration
            )

            scheduleTerminalStateCleanup(finalState, session.callId)
        } catch (e: Exception) {
            android.util.Log.e("CallManager", "cleanupGroupCall hatasi: ${e.message}")
            isCleaningUp.set(false)
        }
    }

    /** Remote video track'leri (grup arama icin). */
    val remoteVideoTracksFlow get() = peerConnectionManager.remoteVideoTracksFlow

    /** SFU subscriber'lardan gelen remote video track'leri (feedId -> VideoTrack). */
    val sfuRemoteVideoTracksFlow get() = peerConnectionManager.sfuRemoteVideoTracksFlow

    /** Aktif oturumun grup aramasi olup olmadigini kontrol eder. */
    val isCurrentCallGroup: Boolean get() = _callSession.value?.isGroupCall == true

    // ---- Arama sonlandirma ----

    /**
     * Gelen aramayi reddeder.
     *
     * @param userId Reddeden kullanicinin ID'si
     */
    fun rejectCall(userId: String) {
        val session = _callSession.value ?: return

        android.util.Log.d("CallManager", "Arama reddedildi: ${session.callId}")

        ringtonePlayer.stopRinging()

        if (session.isGroupCall) {
            // Grup aramasinda sadece arayan (peerId) a REJECT gonder — reliable retry
            sendCallControlReliable(userId, session.peerId, CallAction.REJECT)
            cleanupGroupCall(CallState.REJECTED)
        } else {
            sendCallControlReliable(userId, session.peerId, CallAction.REJECT)
            cleanupCall(CallState.REJECTED)
        }
    }

    /**
     * Aktif aramayi sonlandirir.
     *
     * @param userId Sonlandiran kullanicinin ID'si
     */
    fun endCall(userId: String) {
        val session = _callSession.value
        if (session == null) {
            android.util.Log.w("CallManager", "endCall: session zaten null — bos hangup gonderilmiyor")
            return
        }
        if (session.isGroupCall) {
            endGroupCall(userId)
            return
        }
        // HANGUP reliable — retry + ACK ile gonder. Hayalet call kritik onlemi:
        // network drop ile HANGUP kaybi yasanmasin diye server'dan ack bekler.
        sendCallControlReliable(userId, session.peerId, CallAction.HANGUP)
        cleanupCall(CallState.ENDED)
    }

    // ---- Call waiting kontrolleri ----

    /**
     * Bekleyen ikinci aramayi kabul eder: mevcut aktif arama kapatilir, ardindan
     * ikinci arama kabul edilir. WhatsApp tarzi "ya/ya" davranisi — hold yok.
     *
     * Sira:
     * 1. Aktif arama varsa HANGUP gonder + cleanupCall(ENDED)
     * 2. ~300ms audio mode reset icin bekle
     * 3. Secondary call'i primary slot'a tasi
     * 4. acceptCall(userId) cagir
     */
    fun acceptSecondaryCall(userId: String) {
        val secondary = _secondaryIncomingCall.value ?: run {
            android.util.Log.w("CallManager", "acceptSecondaryCall: secondary slot bos")
            return
        }
        val secondaryOffer = pendingSecondaryOffer ?: run {
            android.util.Log.e("CallManager", "acceptSecondaryCall: pendingSecondaryOffer null")
            _secondaryIncomingCall.value = null
            return
        }
        val secondaryCT = pendingSecondaryCallType ?: secondary.callType

        secondaryMissedTimerJob?.cancel()
        secondaryMissedTimerJob = null

        scope.launch {
            // 1. Mevcut aktif aramaya HANGUP gonder + temizle
            val primary = _callSession.value
            if (primary != null) {
                try {
                    signalingClient.sendSignal(
                        SignalMessage.CallControl(
                            senderId = userId,
                            recipientId = primary.peerId,
                            timestamp = System.currentTimeMillis(),
                            action = CallAction.HANGUP
                        )
                    )
                } catch (e: Exception) {
                    android.util.Log.w("CallManager", "Primary HANGUP gonderilemedi: ${e.message}")
                }
                cleanupCall(CallState.ENDED)
            }

            // 2. Audio mode reset icin kisa bekleme
            kotlinx.coroutines.delay(300)

            // 3. Secondary'i primary slot'a tasi
            _callSession.value = secondary
            pendingRemoteSdpOffer = secondaryOffer
            pendingCallType = secondaryCT
            _secondaryIncomingCall.value = null
            pendingSecondaryOffer = null
            pendingSecondaryCallType = null

            // 4. Normal accept akisi
            acceptCall(userId)
        }
    }

    /**
     * Bekleyen ikinci aramayi reddeder: caller'a REJECT gonderilir, secondary state
     * temizlenir, B'nin sohbetinde "Kacirilan ..." kaydi olusur. Aktif arama dokunulmaz.
     */
    fun rejectSecondaryCall(userId: String) {
        val secondary = _secondaryIncomingCall.value ?: return

        secondaryMissedTimerJob?.cancel()
        secondaryMissedTimerJob = null

        try {
            signalingClient.sendSignal(
                SignalMessage.CallControl(
                    senderId = userId,
                    recipientId = secondary.peerId,
                    timestamp = System.currentTimeMillis(),
                    action = CallAction.REJECT
                )
            )
        } catch (e: Exception) {
            android.util.Log.w("CallManager", "Secondary REJECT gonderilemedi: ${e.message}")
        }

        // Sohbete "Kacirilan / Reddedildi" kaydi at
        saveCallLog(secondary, duration = null, finalState = CallState.REJECTED)

        _secondaryIncomingCall.value = null
        pendingSecondaryOffer = null
        pendingSecondaryCallType = null
    }

    // ---- Medya kontrolleri ----

    /**
     * Mikrofon sessiz/acik durumunu degistirir.
     * PeerConnectionManager uzerinden audio track'in enabled durumunu ayarlar.
     */
    fun toggleMute() {
        val session = _callSession.value ?: return
        val newMuted = !session.isMuted
        peerConnectionManager.setMicEnabled(!newMuted)
        _callSession.value = session.copy(isMuted = newMuted)
    }

    /**
     * Hoparlor acik/kapali durumunu degistirir.
     */
    fun toggleSpeaker() {
        val session = _callSession.value ?: return
        val newSpeakerOn = !session.isSpeakerOn
        audioManager.setSpeakerOn(newSpeakerOn)
        _callSession.value = session.copy(isSpeakerOn = newSpeakerOn)
    }

    /**
     * Kamera acik/kapali durumunu degistirir.
     * PeerConnectionManager uzerinden video track'i enable/disable eder.
     */
    fun toggleCamera() {
        val session = _callSession.value ?: return
        val newEnabled = !session.isCameraEnabled
        if (newEnabled) {
            peerConnectionManager.enableVideo()
        } else {
            peerConnectionManager.disableVideo()
        }
        _callSession.value = session.copy(isCameraEnabled = newEnabled)

        // Karsi tarafa kamera durumunu bildir
        signalingClient.sendSignal(
            SignalMessage.CallControl(
                senderId = localUserId,
                recipientId = session.peerId,
                timestamp = System.currentTimeMillis(),
                action = if (newEnabled) CallAction.CAMERA_ON else CallAction.CAMERA_OFF
            )
        )
    }

    /**
     * Telecom Framework audio routing degisikligi bildirimi.
     *
     * SELF_MANAGED ConnectionService aktif olduğunda sistem ses yönlendirmesini
     * (BT/SPEAKER/EARPIECE/WIRED_HEADSET) kendisi uygular — biz yalnız UI durumunu
     * senkronize ederiz. Hoparlor durumu sistem route'una göre güncellenir, böylece
     * kullanıcı sistem volume HUD'unda hoparloru kapatınca CallScreen butonunu da
     * doğru gösteririz.
     *
     * @param isSpeaker Sistem hoparlore yonlendirdi mi?
     */
    fun notifyAudioRouteChanged(isSpeaker: Boolean) {
        val session = _callSession.value ?: return
        if (session.isSpeakerOn == isSpeaker) return
        _callSession.value = session.copy(isSpeakerOn = isSpeaker)
    }

    /**
     * On/arka kamera arasinda gecis yapar.
     * PeerConnectionManager uzerinden kamera degistirilir.
     */
    fun switchCamera() {
        val session = _callSession.value ?: return
        peerConnectionManager.switchCamera()
        _callSession.value = session.copy(isUsingFrontCamera = !session.isUsingFrontCamera)
    }

    /**
     * Aktif aramanin suresini hesaplar.
     *
     * @return Arama suresi (ms), aktif arama yoksa veya henuz baglanilmadiysa null
     */
    fun getCallDuration(): Long? {
        val start = _callSession.value?.startTime ?: return null
        return System.currentTimeMillis() - start
    }

    /**
     * Arama kaynaklarini temizler.
     * PeerConnection'i kapatir, ses ayarlarini sifirlar ve durumu ENDED'e gecirir.
     * Gelen arama bildirimini de kaldirir.
     * Race condition'lari onlemek icin atomik olarak calisir.
     */
    private fun cleanupCall(finalState: CallState) {
        // Bu stop'lar cleanup guard'inin disinda olmali: ikinci cleanup cagrisi
        // kaynak temizligini atlayabilir ama hayalet sesleri mutlaka susturmali.
        incomingCallHandler.dismissIncomingCall()
        ringtonePlayer.stopRinging()
        ringtonePlayer.stopRingbackTone()

        // Ayni anda birden fazla cleanupCall cagrisini onle
        if (!isCleaningUp.compareAndSet(false, true)) {
            return // Zaten cleanup yapiliyor
        }

        try {
            val session = _callSession.value
            if (session == null) {
                isCleaningUp.set(false)
                return
            }
            val duration = session.startTime?.let { System.currentTimeMillis() - it }

            // Arama gecmisine kaydet
            saveCallLog(session, duration, finalState)

            // F7 Background blur processor — dispose et (ML Kit + executor cleanup)
            disposeBackgroundBlur()

            // WebRTC PeerConnection'i kapat
            peerConnectionManager.disposePeerConnection()

            audioManager.resetAudioMode()

            // Caller-side ringback timeout timer'i iptal et — session sona erdi
            callerRingbackTimeoutJob?.cancel()
            callerRingbackTimeoutJob = null

            // Saklanan SDP ve ICE bilgilerini temizle
            pendingRemoteSdpOffer = null
            pendingCallType = null
            synchronized(pendingRemoteIceCandidates) { pendingRemoteIceCandidates.clear() }
            // NOT: lastHandledOfferKey BURADA SIFIRLANMAZ.
            // Hangup sonrasi FCM/queue replay ile ayni SDP Offer tekrar gelirse
            // yeni bir hayalet aramayi tetiklemesin diye anahtar islem boyu korunur.
            // Yeni gelen gercek arama farkli senderId/timestamp/sdp uretir, otomatik
            // olarak yeni anahtar olarak isenir.

            _callSession.value = session.copy(
                state = finalState,
                duration = duration
            )
            lastTerminalPeerId = session.peerId
            lastTerminalAtMs = System.currentTimeMillis()

            scheduleTerminalStateCleanup(finalState, session.callId)
        } catch (e: Exception) {
            android.util.Log.e("CallManager", "cleanupCall hatasi: ${e.message}")
            // Cleanup flag'ini sifirla
            isCleaningUp.set(false)
        }
    }

    private fun saveCallLog(session: CallSession, duration: Long?, finalState: CallState) {
        val status = when (finalState) {
            CallState.REJECTED -> "REJECTED"
            CallState.FAILED -> "FAILED"
            CallState.BUSY -> "BUSY"
            CallState.ENDED -> if (duration != null && duration > 0) "ANSWERED" else "MISSED"
            CallState.RINGING -> if (session.direction == CallDirection.INCOMING) "MISSED" else "FAILED"
            else -> if (duration != null && duration > 0) "ANSWERED" else "MISSED"
        }
        scope.launch(Dispatchers.IO) {
            try {
                callLogDao.insert(
                    CallLogEntity(
                        id = session.callId,
                        peerId = session.peerId,
                        peerName = session.peerId, // Gercek isim UI katmaninda cozumlenir
                        callType = session.callType.name,
                        direction = session.direction.name,
                        status = status,
                        timestamp = session.startTime ?: System.currentTimeMillis(),
                        duration = duration ?: 0
                    )
                )

                // WhatsApp tarzi: arama bilgisini sohbette SYSTEM mesaji olarak da kaydet
                // boylece kullanici sohbet icinde "Sesli arama · 01:48" gibi gorebilir.
                if (session.isGroupCall) {
                    // Grup aramasinda saveCallLog ENDED state icin yazilir — GROUP_ENDED sistem mesaji
                    // saveGroupCallEndMessage tarafindan ayrica yazildigi icin burada tekrar yazma.
                } else {
                    saveCallSystemMessage(session, status, duration)
                }
            } catch (e: Exception) {
                android.util.Log.e("CallManager", "Call log kayit hatasi: ${e.message}")
            }
        }
    }

    private fun saveBusyIncomingCallAttempt(signal: SignalMessage.SdpOffer) {
        val busySession = CallSession(
            callId = UUID.randomUUID().toString(),
            peerId = signal.senderId,
            callType = signal.callType,
            direction = CallDirection.INCOMING,
            state = CallState.BUSY,
            startTime = signal.timestamp
        )
        saveCallLog(busySession, duration = null, finalState = CallState.BUSY)
    }

    /**
     * Arama bilgisini sohbette SYSTEM mesaji olarak kaydeder — WhatsApp tarzi.
     * Format: "CALL|direction|callType|status|durationMs|displayText"
     * ChatScreen.SystemMessageBanner bu formati parse edip okunabilir gosterir.
     */
    private suspend fun saveCallSystemMessage(session: CallSession, status: String, duration: Long?) {
        try {
            val callTypeLabel = if (session.callType == CallType.VOICE) "Sesli arama" else "Görüntülü arama"
            val isOutgoing = session.direction == CallDirection.OUTGOING

            val content = when (status) {
                "ANSWERED" -> {
                    val durationStr = formatCallDuration(duration ?: 0)
                    "$callTypeLabel · $durationStr"
                }
                "MISSED" -> if (isOutgoing) "$callTypeLabel · Cevap verilmedi" else "Kaçırılan $callTypeLabel"
                "REJECTED" -> if (isOutgoing) "$callTypeLabel · Reddedildi" else "Kaçırılan $callTypeLabel"
                "BUSY" -> if (isOutgoing) "$callTypeLabel · Meşgul" else "Meşgulken kaçırılan $callTypeLabel"
                "FAILED" -> "$callTypeLabel · Bağlanılamadı"
                else -> callTypeLabel
            }

            val systemContent = "CALL|${session.direction.name}|${session.callType.name}|$status|${duration ?: 0}|$content"

            val conversationId = session.peerId // 1-on-1 icin peerId = conversationId
            val message = com.securechat.storage.domain.LocalMessage(
                id = UUID.randomUUID().toString(),
                conversationId = conversationId,
                senderId = if (isOutgoing) localUserId else session.peerId,
                peerId = session.peerId,
                content = systemContent,
                contentType = com.securechat.storage.model.MessageContentType.SYSTEM,
                timestamp = System.currentTimeMillis(),
                status = com.securechat.storage.model.MessageStatus.DELIVERED,
                isOutgoing = isOutgoing
            )
            messageRepository.saveMessage(message)
        } catch (e: Exception) {
            android.util.Log.e("CallManager", "Call system message kayit hatasi: ${e.message}")
        }
    }

    /**
     * Grup aramasi basladiginda sohbete SYSTEM mesaji kaydeder.
     * Format: "CALL|GROUP_STARTED|VOICE|ACTIVE|0|📞 Grup araması başladı"
     */
    private fun saveGroupCallStartMessage(session: CallSession) {
        val groupId = session.groupId ?: return
        scope.launch(Dispatchers.IO) {
            try {
                val callTypeName = session.callType.name
                val displayText = "📞 Grup araması başladı"
                val systemContent = "CALL|GROUP_STARTED|$callTypeName|ACTIVE|0|$displayText"
                val message = com.securechat.storage.domain.LocalMessage(
                    id = UUID.randomUUID().toString(),
                    conversationId = groupId,
                    senderId = localUserId,
                    peerId = groupId,
                    content = systemContent,
                    contentType = com.securechat.storage.model.MessageContentType.SYSTEM,
                    timestamp = System.currentTimeMillis(),
                    status = com.securechat.storage.model.MessageStatus.DELIVERED,
                    isOutgoing = false
                )
                messageRepository.saveMessage(message)
            } catch (e: Exception) {
                android.util.Log.e("CallManager", "Grup arama baslangic mesaji hatasi: ${e.message}")
            }
        }
    }

    /**
     * Grup aramasi bittiginde sohbete SYSTEM mesaji kaydeder.
     * Format: "CALL|GROUP_ENDED|VOICE|ENDED|<durationMs>|Grup araması · mm:ss sürdü"
     */
    private fun saveGroupCallEndMessage(session: CallSession, duration: Long?) {
        val groupId = session.groupId ?: return
        scope.launch(Dispatchers.IO) {
            try {
                val callTypeName = session.callType.name
                val dur = duration ?: 0
                val displayText = if (dur > 0) "Grup araması · ${formatCallDuration(dur)} sürdü"
                                  else "Grup araması sonlandırıldı"
                val systemContent = "CALL|GROUP_ENDED|$callTypeName|ENDED|$dur|$displayText"
                val message = com.securechat.storage.domain.LocalMessage(
                    id = UUID.randomUUID().toString(),
                    conversationId = groupId,
                    senderId = localUserId,
                    peerId = groupId,
                    content = systemContent,
                    contentType = com.securechat.storage.model.MessageContentType.SYSTEM,
                    timestamp = System.currentTimeMillis(),
                    status = com.securechat.storage.model.MessageStatus.DELIVERED,
                    isOutgoing = false
                )
                messageRepository.saveMessage(message)
            } catch (e: Exception) {
                android.util.Log.e("CallManager", "Grup arama bitis mesaji hatasi: ${e.message}")
            }
        }
    }

    private fun formatCallDuration(durationMs: Long): String {
        val totalSeconds = durationMs / 1000
        val minutes = totalSeconds / 60
        val seconds = totalSeconds % 60
        return if (minutes > 0) String.format("%02d:%02d", minutes, seconds)
               else String.format("00:%02d", seconds)
    }

    /**
     * Terminal state'deki call'i 2sn sonra null'a temizler.
     * KRITIK FIX (2026-05-11): callId-based check — bu 2sn'lik pencerede YENI bir call
     * baslarsa (initiateCall / handleIncomingCall) o yeni session'i yok ETMEZ.
     * Eski davranis: state RINGING bile olsa null yapardi → ghost call'un tetikleyicisiydi.
     */
    private fun scheduleTerminalStateCleanup(@Suppress("UNUSED_PARAMETER") finalState: CallState, cleanupCallId: String) {
        scope.launch {
            kotlinx.coroutines.delay(2000)
            val current = _callSession.value
            when {
                current == null -> {
                    // Zaten temiz, hicbir sey yapma
                }
                current.callId == cleanupCallId && current.state in setOf(
                        CallState.ENDED, CallState.REJECTED, CallState.FAILED, CallState.BUSY) -> {
                    // Eski session hala terminal state'de — temizle
                    android.util.Log.d("CallManager",
                        "Terminal cleanup: ayni callId=$cleanupCallId, temizleniyor (state=${current.state})")
                    _callSession.value = null
                }
                current.callId != cleanupCallId -> {
                    // YENI session basladi (farkli callId) — DOKUNMA
                    android.util.Log.w("CallManager",
                        "Terminal cleanup ATLANDI: yeni session aktif (oldCallId=$cleanupCallId, newCallId=${current.callId}, state=${current.state})")
                }
                else -> {
                    // Ayni callId ama terminal degil → garip, log ve dokunma
                    android.util.Log.w("CallManager",
                        "Terminal cleanup ATLANDI: ayni callId ama state=${current.state} (terminal degil)")
                }
            }
            isCleaningUp.set(false)
        }
    }

    private suspend fun refreshIceServers(userId: String) {
        val servers = withContext(Dispatchers.IO) {
            iceServerFetcher.fetch(userId)
        }
        peerConnectionManager.updateIceServers(servers)
    }

    /** 30sn DISCONNECTED kalan reconnecting session'lari hangup eder. */
    private var disconnectTimeoutJob: kotlinx.coroutines.Job? = null

    private fun attachSingleCallConnectionObserver() {
        peerConnectionManager.onConnectionStateChanged = observer@{ state ->
            when (state) {
                PeerConnection.IceConnectionState.DISCONNECTED -> {
                    val session = _callSession.value ?: return@observer
                    if (!session.isGroupCall && session.state == CallState.ACTIVE) {
                        _callSession.value = session.copy(state = CallState.RECONNECTING)
                        // 30sn icinde reconnect olmazsa hangup
                        disconnectTimeoutJob?.cancel()
                        disconnectTimeoutJob = scope.launch {
                            kotlinx.coroutines.delay(30_000)
                            val s = _callSession.value
                            if (s != null && s.state == CallState.RECONNECTING && !isCleaningUp.get()) {
                                android.util.Log.w("CallManager", "DISCONNECTED 30sn — hangup tetikleniyor")
                                onRemoteHangup()
                            }
                        }
                    }
                }
                PeerConnection.IceConnectionState.CONNECTED,
                PeerConnection.IceConnectionState.COMPLETED -> {
                    disconnectTimeoutJob?.cancel()
                    val session = _callSession.value ?: return@observer
                    if (!session.isGroupCall && session.state == CallState.RECONNECTING) {
                        _callSession.value = session.copy(state = CallState.ACTIVE)
                    }
                }
                PeerConnection.IceConnectionState.FAILED,
                PeerConnection.IceConnectionState.CLOSED -> {
                    disconnectTimeoutJob?.cancel()
                    val session = _callSession.value ?: return@observer
                    val terminal = session.state in setOf(
                        CallState.ENDED, CallState.REJECTED, CallState.FAILED, CallState.BUSY
                    )
                    // Sadece ACTIVE/RECONNECTING state'de cleanup tetikle.
                    // onRemoteHangup yerine cleanupCall: lokal WebRTC failed iken uzaktan
                    // HANGUP gelmis gibi davranma (ringtone'u durdurma yan etkisi var ama
                    // ACTIVE'da zaten ringtone calmiyor).
                    if (!session.isGroupCall && !isCleaningUp.get() && !terminal &&
                        session.state in setOf(CallState.ACTIVE, CallState.RECONNECTING)) {
                        cleanupCall(CallState.ENDED)
                    }
                }
                else -> Unit
            }
        }
    }
}
