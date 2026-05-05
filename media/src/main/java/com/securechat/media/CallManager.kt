package com.securechat.media

import android.content.Context
import com.securechat.media.model.CallDirection
import com.securechat.media.model.CallSession
import com.securechat.media.model.CallState
import com.securechat.network.JanusClient
import com.securechat.network.PeerConnectionManager
import com.securechat.network.SignalingClient
import com.securechat.network.SignalMessage
import com.securechat.network.model.CallAction
import com.securechat.network.model.CallType
import com.securechat.storage.dao.CallLogDao
import com.securechat.storage.domain.LocalMessage
import com.securechat.storage.entity.CallLogEntity
import com.securechat.storage.model.MessageContentType
import com.securechat.storage.model.MessageStatus
import com.securechat.storage.repository.MessageRepository
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.webrtc.EglBase
import org.webrtc.IceCandidate
import org.webrtc.SessionDescription
import org.webrtc.VideoTrack
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
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
    private val peerConnectionManager: PeerConnectionManager,
    private val iceServerFetcher: com.securechat.network.IceServerFetcher,
    private val audioManager: CallAudioManager,
    private val ringtonePlayer: RingtonePlayer,
    private val incomingCallHandler: IncomingCallHandler,
    private val callLogDao: CallLogDao,
    private val messageRepository: MessageRepository,
    private val telecomBridge: com.securechat.media.telecom.TelecomBridge
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

    // --- Grup arama state ---
    /** Arayan (koordinator) mi? Yeni uye bildirimlerini bu kisi gonderir. */
    private var isGroupCallCoordinator = false
    /** Su an baglanmis grup uyeleri (mesh peers). */
    private val groupConnectedPeers = mutableSetOf<String>()
    /** Grup aramasi SDP Offer bekleyen peerler (ringing sirasinda). */
    private val pendingGroupSdpOffers = mutableMapOf<String, String>()

    // --- SFU (Janus VideoRoom) state ---
    /** SFU modu esik degeri — bu ve ustundeki katilimci sayisinda SFU aktif olur. */
    companion object {
        const val SFU_THRESHOLD = 4
    }

    /** Janus client — SFU modunda VideoRoom ile iletisim kurar. */
    private var janusClient: JanusClient? = null

    /** SFU modunda bekleyen room bilgisi (henuz arama aktif degilse). */
    @Volatile
    private var pendingSfuRoomInfo: SignalMessage.SfuRoomCreated? = null

    /** Janus publisher feedId'leri: displayName (userId) -> feedId eslemesi. */
    private val sfuFeedMap = ConcurrentHashMap<String, Long>()

    /**
     * FCM push'tan gelen aramayi kullanici kabul ettiyse (SDP henuz gelmeden),
     * SDP geldiginde otomatik kabul icin userId saklanir.
     * 90sn icinde SDP gelmezse otomatik temizlenir — eski pending state
     * sonraki gercek aramayi yanlislikla kabul etmesin diye.
     */
    @Volatile
    var pendingFcmAccept: String? = null
        set(value) {
            field = value
            if (value != null) schedulePendingFcmCleanup()
        }

    /**
     * FCM push'tan gelen aramayi kullanici reddettiyse (SDP henuz gelmeden),
     * SDP geldiginde otomatik reddet icin userId saklanir.
     * 90sn icinde SDP gelmezse otomatik temizlenir.
     */
    @Volatile
    var pendingFcmReject: String? = null
        set(value) {
            field = value
            if (value != null) schedulePendingFcmCleanup()
        }

    private var pendingFcmCleanupJob: kotlinx.coroutines.Job? = null

    private fun schedulePendingFcmCleanup() {
        pendingFcmCleanupJob?.cancel()
        pendingFcmCleanupJob = scope.launch {
            kotlinx.coroutines.delay(90_000L)
            if (pendingFcmAccept != null || pendingFcmReject != null) {
                android.util.Log.w("CallManager", "pendingFcm timeout — temizleniyor")
                pendingFcmAccept = null
                pendingFcmReject = null
            }
        }
    }

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

        // Telecom Framework (SELF_MANAGED) outgoing kayit denemesi.
        // Basarisiz olursa (PhoneAccount yok / izin yok / placeCall hatasi) sadece
        // log atilir; mevcut WebRTC akisi etkilenmez. Bridge attemptOutgoing()
        // sirasinda CallManager.callSession StateFlow'unu collect etmeye baslar
        // ve sonraki state'leri (ACTIVE/ENDED/...) Connection'a push eder.
        try {
            telecomBridge.attemptOutgoing(session)
        } catch (t: Throwable) {
            android.util.Log.w("CallManager", "telecomBridge.attemptOutgoing hatasi", t)
        }

        // PeerConnection olustur ve SDP Offer uret
        scope.launch(Dispatchers.Main) {
            try {
                // Sunucudan dinamik TURN credential al
                val iceServers = kotlinx.coroutines.withContext(Dispatchers.IO) {
                    iceServerFetcher.fetch(userId)
                }
                peerConnectionManager.updateIceServers(iceServers)

                peerConnectionManager.initialize()

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
    fun handleIncomingCall(signal: SignalMessage.SdpOffer, localUserId: String) {
        // CRITICAL FIX: Mevcut aktif/ringing call varsa yeni SdpOffer'i ignore et
        val existingSession = _callSession.value
        if (existingSession != null && (
            existingSession.state == CallState.ACTIVE ||
            existingSession.state == CallState.RINGING ||
            existingSession.state == CallState.INITIATING
        )) {
            android.util.Log.w("CallManager", "handleIncomingCall IGNORE edildi - mevcut call var: state=${existingSession.state}, direction=${existingSession.direction}")
            return
        }

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

        // Zil sesi ve titresimi baslat
        ringtonePlayer.startRinging()

        // FCM pending aksiyonlarini kontrol et
        val rejectUserId = pendingFcmReject
        val acceptUserId = pendingFcmAccept
        pendingFcmReject = null
        pendingFcmAccept = null

        if (rejectUserId != null) {
            android.util.Log.d("CallManager", "FCM pending reject uygulanıyor: $rejectUserId")
            rejectCall(rejectUserId)
            return
        }
        if (acceptUserId != null) {
            android.util.Log.d("CallManager", "FCM pending accept uygulanıyor: $acceptUserId")
            acceptCall(acceptUserId)
            return
        }
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
                // Sunucudan dinamik TURN credential al
                val iceServers = kotlinx.coroutines.withContext(Dispatchers.IO) {
                    iceServerFetcher.fetch(userId)
                }
                peerConnectionManager.updateIceServers(iceServers)

                peerConnectionManager.initialize()

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
        cleanupCall()
        _callSession.value = _callSession.value?.copy(state = CallState.FAILED)
    }

    /**
     * Karsi taraf aramayi kapatti callback'i.
     */
    fun onRemoteHangup() {
        // Zil sesi ve titresimi durdur (henuz cevaplanmamis aramada olabilir)
        ringtonePlayer.stopRinging()
        cleanupCall()
    }

    /**
     * Karsi taraf aramayi reddetti callback'i.
     */
    fun onRemoteReject() {
        cleanupCall()
        _callSession.value = _callSession.value?.copy(state = CallState.REJECTED)
    }

    /**
     * Karsi taraf mesgul callback'i.
     */
    fun onRemoteBusy() {
        cleanupCall()
        _callSession.value = _callSession.value?.copy(state = CallState.BUSY)
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

        // Toplam katilimci sayisi (arayan dahil)
        val totalParticipants = peerIds.size + 1
        val willUseSfu = totalParticipants >= SFU_THRESHOLD

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
            connectedPeerIds = emptyList(),
            isSfuMode = willUseSfu // Sunucu ≥4 katilimcida SFU room olusturacak
        )
        _callSession.value = session

        if (willUseSfu) {
            android.util.Log.d("CallManager", "SFU modu aktif: $totalParticipants katilimci (esik: $SFU_THRESHOLD)")
        }

        audioManager.setSpeakerOn(true)
        audioManager.setCallMode()

        // PeerConnectionManager'i baslat ve ICE callback'ini ayarla
        scope.launch(Dispatchers.Main) {
            try {
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

        // FCM pending aksiyonlarini kontrol et
        val rejectUserId = pendingFcmReject
        val acceptUserId = pendingFcmAccept
        pendingFcmReject = null
        pendingFcmAccept = null

        if (rejectUserId != null) {
            android.util.Log.d("CallManager", "FCM pending reject (grup) uygulanıyor")
            rejectCall(rejectUserId)
            return
        }
        if (acceptUserId != null) {
            android.util.Log.d("CallManager", "FCM pending accept (grup) uygulanıyor")
            acceptGroupCall(acceptUserId)
            return
        }
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

                // Bekleyen SFU room bilgisi varsa simdi isle
                val pendingSfu = pendingSfuRoomInfo
                if (pendingSfu != null) {
                    pendingSfuRoomInfo = null
                    kotlinx.coroutines.withContext(Dispatchers.IO) {
                        handleSfuRoomCreated(pendingSfu)
                    }
                }
            } catch (e: Exception) {
                android.util.Log.e("CallManager", "acceptGroupCall hatasi: ${e.message}")
                onCallFailed()
            }
        }

        ringtonePlayer.playConnectedTone()
        _callSession.value = session.copy(
            state = CallState.ACTIVE,
            startTime = System.currentTimeMillis()
        )
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

    // ---- SFU Mode ----

    /**
     * Sunucudan gelen SFU room bilgisini isler.
     * Grup aramasi SFU esigini (≥4 katilimci) astiysa sunucu Janus VideoRoom olusturur
     * ve tum katilimcilara bu bilgiyi gonderir.
     *
     * Akis:
     * 1. Janus WS'ye baglan
     * 2. Session olustur + VideoRoom plugin'ine attach
     * 3. Odaya publisher olarak katil
     * 4. Yerel medyayi publish et (SDP offer -> Janus -> SDP answer)
     * 5. Mevcut publisher'lara subscribe ol
     * 6. Yeni publisher event'lerini dinle
     */
    fun handleSfuRoomCreated(signal: SignalMessage.SfuRoomCreated) {
        val session = _callSession.value
        if (session == null || !session.isGroupCall) {
            // Henuz session yoksa (ringing sirasinda gelebilir) — sakla
            pendingSfuRoomInfo = signal
            android.util.Log.d("CallManager", "SFU room info saklandi (session henuz yok): ${signal.groupId}")
            return
        }

        // Session'i SFU moduna gecir
        _callSession.value = session.copy(isSfuMode = true, sfuRoomId = signal.roomId)

        android.util.Log.d("CallManager", "SFU room alindi: groupId=${signal.groupId}, roomId=${signal.roomId}")

        scope.launch {
            try {
                connectToSfuRoom(signal.janusWsUrl, signal.roomId)
            } catch (e: Exception) {
                android.util.Log.e("CallManager", "SFU baglanti hatasi: ${e.message}")
                // SFU basarisiz olursa mesh'e fallback — mevcut mesh baglantilari korunur
                _callSession.value = _callSession.value?.copy(isSfuMode = false, sfuRoomId = 0)
            }
        }
    }

    /**
     * Janus VideoRoom'a baglanir, publisher olarak katilir ve mevcut publisher'lara subscribe olur.
     */
    private suspend fun connectToSfuRoom(janusWsUrl: String, roomId: Long) {
        val client = JanusClient()
        janusClient = client

        // 1. Janus WS'ye baglan
        val connected = client.connect(janusWsUrl)
        if (!connected) throw RuntimeException("Janus WS baglantisi basarisiz")

        // 2. Session olustur
        client.createSession()

        // 3. VideoRoom plugin'ine attach
        client.attachVideoRoom()

        // 4. Odaya publisher olarak katil
        val existingPublishers = client.joinAsPublisher(roomId, localUserId)

        // 5. Publisher PeerConnection olustur ve SDP offer ile publish et
        kotlinx.coroutines.withContext(Dispatchers.Main) {
            peerConnectionManager.initialize()
            val session = _callSession.value ?: return@withContext
            val enableVideo = session.callType == CallType.VIDEO
            peerConnectionManager.createSfuPublisherConnection(enableVideo)
            val offer = peerConnectionManager.createSfuPublisherOffer()

            // Janus'a SDP offer gonder, answer al
            val answerSdp = client.publishSdp(offer.description)
            val answer = org.webrtc.SessionDescription(
                org.webrtc.SessionDescription.Type.ANSWER, answerSdp
            )
            peerConnectionManager.setSfuPublisherRemoteAnswer(answer)
        }

        android.util.Log.d("CallManager", "SFU publisher olarak yayina basladi")

        // 6. Mevcut publisher'lara subscribe ol
        for ((feedId, display) in existingPublishers) {
            subscribeToSfuFeed(client, roomId, feedId, display)
        }

        // 7. Yeni publisher event callback'lerini ayarla
        client.onPublisherJoined = { feedId, display ->
            scope.launch {
                subscribeToSfuFeed(client, roomId, feedId, display)
            }
        }

        client.onPublisherLeft = { feedId ->
            scope.launch(Dispatchers.Main) {
                peerConnectionManager.disposeSfuSubscriber(feedId)
                val displayName = sfuFeedMap.entries.find { it.value == feedId }?.key
                if (displayName != null) sfuFeedMap.remove(displayName)
                android.util.Log.d("CallManager", "SFU publisher ayrildi: feedId=$feedId")
            }
        }

        // Mesh PeerConnection'lari artik gereksiz — SFU aktif
        // ONEMLI: closeGroupPeerConnectionsOnly() kullan — paylasimli medya track'lerine DOKUNMA
        // SFU publisher ayni localAudioTrack/localVideoTrack'i kullaniyor
        peerConnectionManager.closeGroupPeerConnectionsOnly()
        android.util.Log.d("CallManager", "Mesh PeerConnection'lar kapatildi (medya korundu), SFU aktif")
    }

    /**
     * Belirli bir SFU publisher'a subscribe olur.
     * Janus'tan SDP offer alir, subscriber PeerConnection olusturur, SDP answer gonderir.
     */
    private suspend fun subscribeToSfuFeed(
        client: JanusClient,
        roomId: Long,
        feedId: Long,
        displayName: String?
    ) {
        try {
            if (displayName != null) sfuFeedMap[displayName] = feedId

            // Janus'tan subscriber SDP offer al
            val offerSdp = client.subscribeToFeed(roomId, feedId)

            // Subscriber PeerConnection olustur ve answer uret
            kotlinx.coroutines.withContext(Dispatchers.Main) {
                peerConnectionManager.createSfuSubscriberConnection(feedId)
                val remoteSdp = org.webrtc.SessionDescription(
                    org.webrtc.SessionDescription.Type.OFFER, offerSdp
                )
                val answer = peerConnectionManager.handleSfuSubscriberOffer(feedId, remoteSdp)

                // Answer'i Janus'a gonder
                client.answerSubscription(feedId, answer.description)
            }

            android.util.Log.d("CallManager", "SFU subscriber baglandi: feedId=$feedId, display=$displayName")
        } catch (e: Exception) {
            android.util.Log.e("CallManager", "SFU subscribe hatasi (feedId=$feedId): ${e.message}")
        }
    }

    /** SFU kaynaklarini temizler. */
    private fun cleanupSfu() {
        janusClient?.disconnect()
        janusClient = null
        peerConnectionManager.disposeAllSfuConnections()
        sfuFeedMap.clear()
        pendingSfuRoomInfo = null
    }

    /** SFU remote video track'leri. */
    val sfuRemoteVideoTracksFlow get() = peerConnectionManager.sfuRemoteVideoTracksFlow

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

        // Tum peer'lere HANGUP gonder
        for (peerId in session.peerIds) {
            signalingClient.sendSignal(
                SignalMessage.CallControl(
                    senderId = userId,
                    recipientId = peerId,
                    timestamp = System.currentTimeMillis(),
                    action = CallAction.HANGUP
                )
            )
        }

        cleanupGroupCall()
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
            cleanupGroupCall()
        }
    }

    /** Grup aramasi kaynaklarini temizler. */
    private fun cleanupGroupCall() {
        if (!isCleaningUp.compareAndSet(false, true)) return

        try {
            val session = _callSession.value ?: return
            val duration = session.startTime?.let { System.currentTimeMillis() - it }

            saveCallLog(session, duration)

            incomingCallHandler.dismissIncomingCall()
            // "Arama devam ediyor" foreground bildirimini de kaldir
            CallForegroundService.stop(context)
            ringtonePlayer.stopRinging()
            ringtonePlayer.stopRingbackTone()

            // SFU modundaysa Janus + SFU PC'lerini temizle (medya dahil)
            // Mesh modundaysa mesh PC'lerini temizle (medya dahil)
            // Ikisi birden cagirilmaz — double-dispose onlenir
            if (session.isSfuMode) {
                cleanupSfu()
                // Mesh PC'ler SFU gecisinde zaten kapatildi (medyasiz)
                // Ama hala referanslari varsa temizle (sadece PC, medya zaten SFU tarafindan temizlendi)
                peerConnectionManager.closeGroupPeerConnectionsOnly()
            } else {
                peerConnectionManager.disposeAllGroupPeerConnections()
            }
            audioManager.resetAudioMode()

            isGroupCallCoordinator = false
            groupConnectedPeers.clear()
            synchronized(pendingGroupSdpOffers) { pendingGroupSdpOffers.clear() }

            _callSession.value = session.copy(
                state = CallState.ENDED,
                duration = duration
            )

            scope.launch {
                kotlinx.coroutines.delay(2000)
                if (_callSession.value?.state == CallState.ENDED) {
                    _callSession.value = null
                }
                isCleaningUp.set(false)
            }
        } catch (e: Exception) {
            android.util.Log.e("CallManager", "cleanupGroupCall hatasi: ${e.message}")
            isCleaningUp.set(false)
        }
    }

    /** Remote video track'leri (grup arama icin). */
    val remoteVideoTracksFlow get() = peerConnectionManager.remoteVideoTracksFlow

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
            // Grup aramasinda sadece arayan (peerId) a REJECT gonder
            signalingClient.sendSignal(
                SignalMessage.CallControl(
                    senderId = userId,
                    recipientId = session.peerId,
                    timestamp = System.currentTimeMillis(),
                    action = CallAction.REJECT
                )
            )
            cleanupGroupCall()
        } else {
            signalingClient.sendSignal(
                SignalMessage.CallControl(
                    senderId = userId,
                    recipientId = session.peerId,
                    timestamp = System.currentTimeMillis(),
                    action = CallAction.REJECT
                )
            )
            cleanupCall()
        }
        _callSession.value = _callSession.value?.copy(state = CallState.REJECTED)
    }

    /**
     * Aktif aramayi sonlandirir.
     *
     * @param userId Sonlandiran kullanicinin ID'si
     */
    fun endCall(userId: String) {
        val session = _callSession.value ?: return
        if (session.isGroupCall) {
            endGroupCall(userId)
            return
        }
        signalingClient.sendSignal(
            SignalMessage.CallControl(
                senderId = userId,
                recipientId = session.peerId,
                timestamp = System.currentTimeMillis(),
                action = CallAction.HANGUP
            )
        )
        cleanupCall()
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
    private fun cleanupCall() {
        // Ayni anda birden fazla cleanupCall cagrisini onle
        if (!isCleaningUp.compareAndSet(false, true)) {
            return // Zaten cleanup yapiliyor
        }

        try {
            val session = _callSession.value ?: return
            val duration = session.startTime?.let { System.currentTimeMillis() - it }

            // Arama gecmisine kaydet
            saveCallLog(session, duration)

            // Gelen arama bildirimini kaldir
            incomingCallHandler.dismissIncomingCall()

            // Aktif arama foreground service'ini durdur — "Arama devam ediyor"
            // bildirimi calisma bittikten sonra ekranda kalmasin. stopService
            // idempotent: service zaten durmussa no-op.
            CallForegroundService.stop(context)

            // Guvenlik icin tum sesleri durdur (idempotent)
            ringtonePlayer.stopRinging()
            ringtonePlayer.stopRingbackTone()

            // WebRTC PeerConnection'i kapat
            peerConnectionManager.disposePeerConnection()

            audioManager.resetAudioMode()

            // Saklanan SDP ve ICE bilgilerini temizle
            pendingRemoteSdpOffer = null
            pendingCallType = null
            synchronized(pendingRemoteIceCandidates) { pendingRemoteIceCandidates.clear() }

            _callSession.value = session.copy(
                state = CallState.ENDED,
                duration = duration
            )

            // 2 saniye sonra session'i temizle ki yeni arama yapilabilsin
            scope.launch {
                kotlinx.coroutines.delay(2000)
                if (_callSession.value?.state == CallState.ENDED) {
                    _callSession.value = null
                }
                // Cleanup flag'ini sifirla
                isCleaningUp.set(false)
            }
        } catch (e: Exception) {
            android.util.Log.e("CallManager", "cleanupCall hatasi: ${e.message}")
            // Cleanup flag'ini sifirla
            isCleaningUp.set(false)
        }
    }

    private fun saveCallLog(session: CallSession, duration: Long?) {
        val status = when (session.state) {
            CallState.REJECTED -> "REJECTED"
            CallState.FAILED -> "FAILED"
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

                // Arama bilgisini sohbette SYSTEM mesaji olarak kaydet
                saveCallSystemMessage(session, status, duration)
            } catch (e: Exception) {
                android.util.Log.e("CallManager", "Call log kayit hatasi: ${e.message}")
            }
        }
    }

    /**
     * Arama bilgisini sohbette sistem mesaji olarak kaydeder.
     * WhatsApp'taki gibi arama bilgileri sohbet icinde gorunur.
     */
    private suspend fun saveCallSystemMessage(session: CallSession, status: String, duration: Long?) {
        try {
            val callTypeLabel = if (session.callType == CallType.VOICE) "Sesli arama" else "Görüntülü arama"
            val isOutgoing = session.direction == CallDirection.OUTGOING

            val content = when (status) {
                "ANSWERED" -> {
                    val durationStr = formatCallDuration(duration ?: 0)
                    if (isOutgoing) "$callTypeLabel · $durationStr"
                    else "$callTypeLabel · $durationStr"
                }
                "MISSED" -> "Kaçırılan $callTypeLabel"
                "REJECTED" -> if (isOutgoing) "$callTypeLabel · Reddedildi" else "Kaçırılan $callTypeLabel"
                "FAILED" -> "$callTypeLabel · Bağlanılamadı"
                else -> callTypeLabel
            }

            // Arama bilgisi: "CALL|direction|callType|status|duration"
            // Bu formati ChatScreen'de parse ederek ikon ve stil belirleriz
            val systemContent = "CALL|${session.direction.name}|${session.callType.name}|$status|${duration ?: 0}|$content"

            val conversationId = session.peerId // 1-on-1 icin peerId = conversationId
            val message = LocalMessage(
                id = UUID.randomUUID().toString(),
                conversationId = conversationId,
                senderId = if (isOutgoing) localUserId else session.peerId,
                peerId = session.peerId,
                content = systemContent,
                contentType = MessageContentType.SYSTEM,
                timestamp = System.currentTimeMillis(),
                status = MessageStatus.DELIVERED,
                isOutgoing = isOutgoing
            )
            messageRepository.saveMessage(message)
        } catch (e: Exception) {
            android.util.Log.e("CallManager", "Call system message kayit hatasi: ${e.message}")
        }
    }

    private fun formatCallDuration(durationMs: Long): String {
        val totalSeconds = durationMs / 1000
        val minutes = totalSeconds / 60
        val seconds = totalSeconds % 60
        return if (minutes > 0) "${minutes}dk ${seconds}sn" else "${seconds}sn"
    }
}
