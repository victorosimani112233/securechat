package com.securechat.media.telecom

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.telecom.CallAudioState
import android.telecom.DisconnectCause
import android.telecom.TelecomManager
import android.telecom.VideoProfile
import android.util.Log
import androidx.core.content.ContextCompat
import com.securechat.common.UserIdentityProvider
import com.securechat.media.CallManager
import com.securechat.media.model.CallDirection
import com.securechat.media.model.CallSession
import com.securechat.media.model.CallState
import com.securechat.network.model.CallType
import dagger.Lazy
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.launch
import java.util.Collections
import java.util.concurrent.ConcurrentHashMap
import javax.inject.Inject
import javax.inject.Singleton

/**
 * CallManager ile Android Telecom Framework arasinda cift yonlu kopru.
 *
 * **Asama B:** Sadece outgoing yonu aktif. [attemptOutgoing] cagrildiginda
 * `TelecomManager.placeCall()` tetiklenir, sistem `SecureChatConnection`
 * olusturur, Bridge listener atayip [CallManager.callSession] flow'unu
 * Connection state'ine yansitir.
 *
 * **Cycle:** CallManager -> Bridge (initiateCall icinde attemptOutgoing) ve
 * Bridge -> CallManager (Connection callback'leri delegate). [Lazy] ile
 * kirilir; observer ilk attemptOutgoing'da [ensureObserverStarted] tarafindan
 * baslatilir.
 *
 * **Fallback:** [PhoneAccountRegistrar.isAvailable] false donerse
 * [attemptOutgoing] no-op + false doner. CallManager mevcut Telecom-disi
 * akisi koruyacak sekilde tasarlandi (degisiklik yok — sadece "ekstra"
 * Telecom kaydi yapilmiyor).
 *
 * **Observer:** [CallManager.callSession] StateFlow'u dinler; sadece
 * [activeCallIds] icindeki callId'lere dokunur — Bridge'in attempt etmedigi
 * cagrilarla (eski akis veya henuz Asama C'siz incoming) etkilesmez.
 */
@Singleton
class TelecomBridge @Inject constructor(
    @ApplicationContext private val context: Context,
    private val registrar: PhoneAccountRegistrar,
    private val callManagerLazy: Lazy<CallManager>,
    private val userIdentityProvider: UserIdentityProvider
) {
    private val telecomManager: TelecomManager? by lazy {
        context.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    /** Bridge'in olusturdugu cagrilarin callId'leri — gozlem filtresi. */
    private val activeCallIds: MutableSet<String> =
        Collections.newSetFromMap(ConcurrentHashMap())

    @Volatile private var observerStarted = false

    /**
     * Incoming UI tetiklendiginde launch edilecek Activity sinifi.
     * Media modulunden app modulundeki [com.securechat.app.IncomingCallActivity]
     * referansina ulasamadigimiz icin Application.onCreate'de
     * [setIncomingActivityClass] ile kayit edilir.
     */
    @Volatile private var incomingActivityClass: Class<*>? = null

    /** Sistemden gelen son audio state — debug ve gelecekte UI sync icin cache. */
    @Volatile var lastAudioState: CallAudioState? = null
        private set

    fun setIncomingActivityClass(cls: Class<*>?) {
        incomingActivityClass = cls
        Log.d(TAG, "incomingActivityClass set: ${cls?.name}")
    }

    init {
        // Sistem onCreateXxxConnectionFailed dondugunde Bridge tracking'inden
        // de cikar. Aksi halde activeCallIds'de orphan callId kalir → sonraki
        // upgradeIncomingCallId yanlis match yapar veya peer-orphan close edilemez.
        SecureChatConnectionService.registry.failureListener = { callId, peerId ->
            Log.d(TAG, "ConnectionService failure -> cleanup: callId=$callId peer=$peerId")
            if (!callId.isNullOrEmpty()) {
                activeCallIds.remove(callId)
            }
            // callId null geldigi vakalar (sistem fcm_pending'i bilemiyor): peerId
            // uzerinden ayni peer'a ait fcm_pending kayitlarini da temizle.
            if (!peerId.isNullOrEmpty()) {
                val matching = activeCallIds.filter { id ->
                    id.startsWith(FCM_PENDING_PREFIX) &&
                        SecureChatConnectionService.registry.get(id) == null
                }
                for (id in matching) {
                    activeCallIds.remove(id)
                    Log.d(TAG, "Bridge orphan fcm_pending temizlendi: $id")
                }
            }
        }
    }

    private val connectionListener = object : SecureChatConnection.Listener {
        override fun onShowIncomingCallUi(connection: SecureChatConnection) {
            val cls = incomingActivityClass
            if (cls == null) {
                Log.w(TAG, "onShowIncomingCallUi ama incomingActivityClass null — UI gosterilmedi")
                return
            }
            try {
                val intent = Intent(context, cls).apply {
                    putExtra("peer_id", connection.peerId)
                    putExtra("peer_name", connection.peerName)
                    putExtra("call_type", if (connection.isVideo) "VIDEO" else "VOICE")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    addFlags(Intent.FLAG_ACTIVITY_NO_USER_ACTION)
                    addFlags(Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS)
                }
                context.startActivity(intent)
                Log.d(TAG, "IncomingCallActivity Telecom uzerinden launch: ${connection.callId}")
            } catch (t: Throwable) {
                Log.e(TAG, "IncomingCallActivity launch hatasi", t)
            }
        }

        override fun onAnswer(connection: SecureChatConnection, videoState: Int) {
            val userId = userIdentityProvider.currentUserId
            if (userId == null) {
                Log.w(TAG, "onAnswer ama currentUserId null — atlandi")
                return
            }
            val cm = callManagerLazy.get()
            val current = cm.currentSession
            if (current != null &&
                current.state == CallState.RINGING &&
                current.direction == CallDirection.INCOMING
            ) {
                // Normal: SDP zaten gelmis, dogrudan kabul et.
                Log.d(TAG, "onAnswer -> acceptCall: callId=${connection.callId}")
                cm.acceptCall(userId)
            } else {
                // FCM-pending mode: SDP henuz gelmedi, accept'i kuyruga al.
                // CallManager.handleIncomingCall icindeki pendingFcm guard
                // SDP gelir gelmez otomatik acceptCall yapacak.
                Log.d(TAG, "onAnswer FCM-pending: pendingFcmAccept set, callId=${connection.callId}")
                cm.pendingFcmAccept = userId
            }
        }

        override fun onReject(connection: SecureChatConnection) {
            val userId = userIdentityProvider.currentUserId
            if (userId == null) {
                Log.w(TAG, "onReject ama currentUserId null — atlandi")
                return
            }
            val cm = callManagerLazy.get()
            val current = cm.currentSession
            if (current != null &&
                current.state == CallState.RINGING &&
                current.direction == CallDirection.INCOMING
            ) {
                Log.d(TAG, "onReject -> rejectCall: callId=${connection.callId}")
                cm.rejectCall(userId)
            } else {
                // FCM-pending mode: SDP henuz gelmedi, reject'i kuyruga al.
                Log.d(TAG, "onReject FCM-pending: pendingFcmReject set, callId=${connection.callId}")
                cm.pendingFcmReject = userId
                // Connection'i hemen kapat (kullanici reddetti) — Bridge cleanup
                // CallManager state'i de gunceller, ama kullanici icin annik kapanis garanti.
                connection.closeWith(android.telecom.DisconnectCause(android.telecom.DisconnectCause.REJECTED))
            }
        }

        override fun onDisconnect(connection: SecureChatConnection) {
            Log.d(TAG, "onDisconnect -> CallManager.endCall: callId=${connection.callId}")
            // Defansif: Bridge tracking'inden de cikar — CallManager.endCall
            // session yoksa return ediyor (FCM-pending sonrasi state lost), o
            // zaman cleanup tetiklenmez ve activeCallIds'de orphan kalir.
            // Sistem max-1 SELF_MANAGED Connection limiti yuzunden sonraki
            // cagrilar reddediliyor — onun icin burada da temizliyoruz.
            activeCallIds.remove(connection.callId)
            SecureChatConnectionService.registry.remove(connection.callId)
            val userId = userIdentityProvider.currentUserId
            if (userId != null) {
                callManagerLazy.get().endCall(userId)
            } else {
                Log.w(TAG, "onDisconnect ama currentUserId null — endCall atlandi")
            }
        }

        override fun onAbort(connection: SecureChatConnection) {
            Log.d(TAG, "onAbort -> CallManager.endCall: callId=${connection.callId}")
            activeCallIds.remove(connection.callId)
            SecureChatConnectionService.registry.remove(connection.callId)
            val userId = userIdentityProvider.currentUserId
            if (userId != null) {
                callManagerLazy.get().endCall(userId)
            }
        }

        override fun onHold(connection: SecureChatConnection) {
            // SecureChat su an HOLD desteklemiyor; capability ileride genisletilebilir.
            // Gecici olarak system isteyince accept edilir (Connection.setOnHold zaten
            // SecureChatConnection.onHold icinde cagrilir).
            Log.d(TAG, "onHold (no-op): callId=${connection.callId}")
        }

        override fun onUnhold(connection: SecureChatConnection) {
            Log.d(TAG, "onUnhold (no-op): callId=${connection.callId}")
        }

        override fun onCallAudioStateChanged(
            connection: SecureChatConnection,
            state: CallAudioState
        ) {
            // Asama D minimum: state cache + log. Mevcut CallAudioManager (manual
            // setSpeakerOn vb.) kendi yolundan calismaya devam ediyor; SELF_MANAGED
            // Connection setActive olunca sistem audio focus zaten aliyor. Cakisma yok.
            // Connection.setAudioRoute() entegrasyonu ileri optimizasyon icin sakli.
            lastAudioState = state
            Log.d(TAG, "audio state route=${state.route} muted=${state.isMuted} supported=${state.supportedRouteMask}")
        }
    }

    /**
     * Outgoing aramayi Telecom Framework uzerine de kaydetmeye calisir.
     *
     * @return true = placeCall basarili, Connection beklenir.
     *         false = PhoneAccount kayitli degil, izin yok, veya placeCall
     *                 exception firlatti — CallManager mevcut akisi tek basina
     *                 calismaya devam eder.
     */
    fun attemptOutgoing(session: CallSession): Boolean {
        if (!registrar.isAvailable()) {
            Log.d(TAG, "PhoneAccount yok — outgoing Telecom kayitsiz devam")
            return false
        }
        if (!hasManageOwnCallsPermission()) {
            Log.w(TAG, "MANAGE_OWN_CALLS izni yok — outgoing Telecom kayitsiz")
            return false
        }
        val tm = telecomManager ?: return false
        if (session.callId.isEmpty()) {
            Log.w(TAG, "callId bos — outgoing kaydi atlandi")
            return false
        }

        ensureObserverStarted()

        val isVideo = session.callType == CallType.VIDEO

        val outgoingExtras = Bundle().apply {
            putString(CallExtras.KEY_CALL_ID, session.callId)
            putString(CallExtras.KEY_PEER_ID, session.peerId)
            // peerName resolution media modulunde yapilamaz (contacts modulu reach edilmez).
            // SELF_MANAGED'da Telecom UI gorunmedigi icin peerId fallback'i kullanici
            // deneyimini etkilemez (CallScreen kendi peerName'ini cozer).
            putString(CallExtras.KEY_PEER_NAME, session.peerId)
            putBoolean(CallExtras.KEY_IS_VIDEO, isVideo)
        }
        val callExtras = Bundle().apply {
            putParcelable(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, registrar.handle)
            putBundle(TelecomManager.EXTRA_OUTGOING_CALL_EXTRAS, outgoingExtras)
            // Outgoing video icin VideoProfile state'i de iletilebilir
            if (isVideo) {
                putInt(
                    TelecomManager.EXTRA_START_CALL_WITH_VIDEO_STATE,
                    VideoProfile.STATE_BIDIRECTIONAL
                )
            }
        }

        // Connection olustugunda listener bagla — placeCall'dan ONCE kayit ediyoruz
        // ki Connection put edildigi an callback senkron tetiklensin.
        activeCallIds.add(session.callId)
        SecureChatConnectionService.registry.whenAvailable(session.callId) { conn ->
            conn.listener = connectionListener
            Log.d(TAG, "Connection ortaya cikti, listener bagli: callId=${session.callId}")
        }

        val address = registrar.addressFor(session.peerId)
        return try {
            tm.placeCall(address, callExtras)
            Log.i(TAG, "placeCall iletildi: callId=${session.callId} peer=${session.peerId}")
            true
        } catch (t: Throwable) {
            // SecurityException, IllegalArgumentException, vs. — sistem reddetti
            Log.e(TAG, "placeCall hatasi", t)
            SecureChatConnectionService.registry.cancelPending(session.callId)
            activeCallIds.remove(session.callId)
            false
        }
    }

    /**
     * Incoming aramayi Telecom Framework uzerine de kaydetmeye calisir.
     *
     * Cagiran (genelde IncomingMessageHandler) `CallManager.handleIncomingCall`
     * cagrildiktan sonra session olustugunda bu metodu cagirir. Sistem
     * `onCreateIncomingConnection`'i tetikler, Connection RINGING state'de
     * olusur ve sistem `onShowIncomingCallUi`'yi cagirir — Bridge listener
     * IncomingCallActivity'i launch eder.
     *
     * Sadece `RINGING + INCOMING` session icin geceri; FCM-pending accept/reject
     * dolayisiyla cagri zaten ACCEPTED veya REJECTED'a dustuyse no-op + false
     * doner. Caller bu durumda da Telecom-disi yedek bildirim gostermemelidir
     * cunku zaten karar verilmis.
     *
     * @return true = addNewIncomingCall basarili, Connection beklenir; caller
     *               kendi notification + Activity launch yapmamali.
     *         false = registrar yok / izin yok / addNewIncomingCall hatasi /
     *               session uygun degil — caller mevcut yedek akisi (CallStyle
     *               notification + IncomingCallActivity startActivity) calistirmali.
     */
    fun attemptIncoming(session: CallSession, peerName: String): Boolean {
        if (!registrar.isAvailable()) {
            Log.d(TAG, "PhoneAccount yok — incoming Telecom kayitsiz")
            return false
        }
        if (!hasManageOwnCallsPermission()) {
            Log.w(TAG, "MANAGE_OWN_CALLS izni yok — incoming Telecom kayitsiz")
            return false
        }
        if (session.callId.isEmpty()) {
            Log.w(TAG, "callId bos — incoming kaydi atlandi")
            return false
        }
        if (session.direction != CallDirection.INCOMING || session.state != CallState.RINGING) {
            // FCM-pending accept/reject yuzunden zaten karar verilmis — Telecom'a
            // duplicate ringing girisi yapmiyoruz. Caller da yedek bildirim
            // gostermesin (true donmuyoruz ama state degismedi anlam tasimak icin
            // false donuyoruz; caller current state'i kontrol ederek davranis
            // ayarlayabilir).
            Log.d(TAG, "incoming session uygun degil: state=${session.state} dir=${session.direction}")
            return false
        }
        val tm = telecomManager ?: return false

        ensureObserverStarted()

        // KRITIK: SELF_MANAGED PhoneAccount tek anda tek aktif Connection
        // tutabilir. Onceki cagrilardan stuck kalmis (ENDED'a hic dusmemis)
        // Connection'lar sistem'in yeni addNewIncomingCall'unu sessizce
        // (onCreateIncomingConnectionFailed callId=null) reddetmesine yol acar.
        // Yeni cagri oncesinde ayni peer'a ait orphan'lari kapat.
        closeOrphansForPeer(session.peerId)

        val isVideo = session.callType == CallType.VIDEO

        val callDetails = Bundle().apply {
            putString(CallExtras.KEY_CALL_ID, session.callId)
            putString(CallExtras.KEY_PEER_ID, session.peerId)
            putString(CallExtras.KEY_PEER_NAME, peerName)
            putBoolean(CallExtras.KEY_IS_VIDEO, isVideo)
        }

        val incomingExtras = Bundle().apply {
            putBundle(TelecomManager.EXTRA_INCOMING_CALL_EXTRAS, callDetails)
            putParcelable(
                TelecomManager.EXTRA_INCOMING_CALL_ADDRESS,
                registrar.addressFor(session.peerId)
            )
            if (isVideo) {
                putInt(
                    TelecomManager.EXTRA_INCOMING_VIDEO_STATE,
                    VideoProfile.STATE_BIDIRECTIONAL
                )
            }
        }

        // Connection olustugunda listener bagla — addNewIncomingCall'dan ONCE.
        activeCallIds.add(session.callId)
        SecureChatConnectionService.registry.whenAvailable(session.callId) { conn ->
            conn.listener = connectionListener
            Log.d(TAG, "Incoming Connection ortaya cikti, listener bagli: ${session.callId}")
        }

        return try {
            tm.addNewIncomingCall(registrar.handle, incomingExtras)
            Log.i(TAG, "addNewIncomingCall iletildi: callId=${session.callId} peer=${session.peerId}")
            true
        } catch (t: Throwable) {
            Log.e(TAG, "addNewIncomingCall hatasi", t)
            SecureChatConnectionService.registry.cancelPending(session.callId)
            activeCallIds.remove(session.callId)
            false
        }
    }

    /**
     * Verilen peerId icin tracking edilmis kapanmamis Connection'lari kapatir.
     * Sistemin onceki cagridan stuck kalmis self-managed Connection ile
     * cakismasini onler.
     */
    private fun closeOrphansForPeer(peerId: String) {
        val orphans = activeCallIds.filter { id ->
            val conn = SecureChatConnectionService.registry.get(id)
            conn != null && conn.peerId == peerId
        }
        for (id in orphans) {
            val conn = SecureChatConnectionService.registry.remove(id)
            try {
                conn?.closeWith(android.telecom.DisconnectCause(android.telecom.DisconnectCause.LOCAL))
            } catch (t: Throwable) {
                Log.w(TAG, "Orphan Connection kapatma hatasi: $id", t)
            }
            activeCallIds.remove(id)
            Log.d(TAG, "Orphan Connection kapatildi: $id (peer=$peerId)")
        }
    }

    /**
     * FCM pre-call asamasinda acilmis "fcm_pending_*" callId'li Connection'i
     * SDP geldiginde gercek session.callId'sine remap eder. Boylece duplicate
     * Connection acilmaz; ayni sistem ringing tek bir akista yasar.
     *
     * Eslesme peerId uzerinden yapilir (peerId fcm-pending Connection'a
     * SecureChatFcmService tarafindan KEY_PEER_ID extras'i ile yazilmisti).
     *
     * @return true = upgrade basarili, [attemptIncoming] tekrar cagirilmamali.
     *         false = uyumlu fcm-pending Connection bulunamadi, caller normal
     *                 [attemptIncoming] yolunu kullanmali.
     */
    fun upgradeIncomingCallId(realSession: CallSession): Boolean {
        if (realSession.callId.isEmpty() || realSession.peerId.isEmpty()) return false

        // Aktif fcm-pending kayitlari icinde peerId eslesen Connection'i bul.
        val pendingId = activeCallIds.firstOrNull { id ->
            id.startsWith(FCM_PENDING_PREFIX) && run {
                val conn = SecureChatConnectionService.registry.get(id)
                conn != null && conn.peerId == realSession.peerId
            }
        } ?: return false

        val conn = SecureChatConnectionService.registry.get(pendingId) ?: return false

        // Re-key: registry'de eski callId'yi kaldir, gercek callId ile ayni
        // Connection'a yeni mapping ekle. activeCallIds tracking'ini de guncelle.
        SecureChatConnectionService.registry.remove(pendingId)
        activeCallIds.remove(pendingId)
        SecureChatConnectionService.registry.put(realSession.callId, conn)
        activeCallIds.add(realSession.callId)

        Log.i(TAG, "upgradeIncomingCallId: $pendingId -> ${realSession.callId} (peer=${realSession.peerId})")
        return true
    }

    private fun ensureObserverStarted() {
        if (observerStarted) return
        synchronized(this) {
            if (observerStarted) return
            observerStarted = true
        }
        scope.launch {
            // CallManager flow'u bridge ilk kullanildigi anda construct olur.
            // filterNotNull KRITIK: StateFlow'un ilk emit'i mevcut deger (null).
            // Eger null'i alirsak "orphan cleanup" branch'i activeCallIds'i temizler
            // — ama bu sirada baska thread'de attemptIncoming yeni callId eklemis
            // olabilir. RACE: pending listener silinir, Connection.listener bagli
            // kalmaz, onShowIncomingCallUi no-op olur, sistem UI cikmaz.
            // ENDED -> null gecisi zaten ENDED branch'inde temizleniyor;
            // ekstra null guard'a gerek yok.
            callManagerLazy.get().callSession.filterNotNull().collect { session ->
                handleStateChange(session)
            }
        }
    }

    private fun handleStateChange(session: CallSession) {
        if (session.callId !in activeCallIds) return  // Bridge'in attempt etmedigi cagri
        val conn = SecureChatConnectionService.registry.get(session.callId) ?: return

        when (session.state) {
            CallState.ACTIVE -> {
                if (conn.state != android.telecom.Connection.STATE_ACTIVE) {
                    conn.setActive()
                    Log.d(TAG, "Connection ACTIVE: callId=${session.callId}")
                }
            }
            CallState.ENDED -> {
                conn.closeWith(DisconnectCause(DisconnectCause.LOCAL))
                SecureChatConnectionService.registry.remove(session.callId)
                activeCallIds.remove(session.callId)
            }
            CallState.REJECTED -> {
                conn.closeWith(DisconnectCause(DisconnectCause.REJECTED))
                SecureChatConnectionService.registry.remove(session.callId)
                activeCallIds.remove(session.callId)
            }
            CallState.FAILED -> {
                conn.closeWith(DisconnectCause(DisconnectCause.ERROR))
                SecureChatConnectionService.registry.remove(session.callId)
                activeCallIds.remove(session.callId)
            }
            CallState.BUSY -> {
                conn.closeWith(DisconnectCause(DisconnectCause.BUSY))
                SecureChatConnectionService.registry.remove(session.callId)
                activeCallIds.remove(session.callId)
            }
            CallState.INITIATING, CallState.RINGING -> {
                // Outgoing icin: Connection STATE_DIALING'de kalir; karsi taraf
                // kabul edene kadar setActive cagirmiyoruz.
                // Incoming icin (Asama C): STATE_RINGING zaten ConnectionService'te set edildi.
            }
            else -> {
                // IDLE / CONNECTING / RECONNECTING — Connection state'inde
                // ek transition yapmiyoruz; ACTIVE veya bitis state'leri yakalanir.
            }
        }
    }

    private fun hasManageOwnCallsPermission(): Boolean =
        ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.MANAGE_OWN_CALLS
        ) == PackageManager.PERMISSION_GRANTED

    companion object {
        private const val TAG = "TelecomBridge"
        /** SecureChatFcmService.handleIncomingCallPush tarafindan uretilen callId prefix'i. */
        const val FCM_PENDING_PREFIX = "fcm_pending_"
    }
}
