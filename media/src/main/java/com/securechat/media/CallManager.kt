package com.securechat.media

import android.content.Context
import com.securechat.media.model.CallDirection
import com.securechat.media.model.CallSession
import com.securechat.media.model.CallState
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
    private val audioManager: CallAudioManager,
    private val ringtonePlayer: RingtonePlayer,
    private val incomingCallHandler: IncomingCallHandler,
    private val callLogDao: CallLogDao
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

        // PeerConnection olustur ve SDP Offer uret
        scope.launch(Dispatchers.Main) {
            try {
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

    // ---- Arama sonlandirma ----

    /**
     * Gelen aramayi reddeder.
     *
     * @param userId Reddeden kullanicinin ID'si
     */
    fun rejectCall(userId: String) {
        val session = _callSession.value ?: return

        android.util.Log.d("CallManager", "Arama reddedildi: ${session.callId}")

        // Zil sesi ve titresimi durdur
        ringtonePlayer.stopRinging()
        signalingClient.sendSignal(
            SignalMessage.CallControl(
                senderId = userId,
                recipientId = session.peerId,
                timestamp = System.currentTimeMillis(),
                action = CallAction.REJECT
            )
        )
        cleanupCall()
        _callSession.value = _callSession.value?.copy(state = CallState.REJECTED)
    }

    /**
     * Aktif aramayi sonlandirir.
     *
     * @param userId Sonlandiran kullanicinin ID'si
     */
    fun endCall(userId: String) {
        val session = _callSession.value ?: return
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
            } catch (e: Exception) {
                android.util.Log.e("CallManager", "Call log kayit hatasi: ${e.message}")
            }
        }
    }
}
