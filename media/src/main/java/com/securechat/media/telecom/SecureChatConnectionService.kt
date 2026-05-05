package com.securechat.media.telecom

import android.telecom.Connection
import android.telecom.ConnectionRequest
import android.telecom.ConnectionService
import android.telecom.DisconnectCause
import android.telecom.PhoneAccountHandle
import android.util.Log

/**
 * Telecom Framework ConnectionService — sistemin SecureChat aramalarini
 * yonetmek icin instantiate ettigi servis.
 *
 * Manifest'te `BIND_TELECOM_CONNECTION_SERVICE` permission ile expose edilir.
 * Sistem `TelecomManager.placeCall()` veya `TelecomManager.addNewIncomingCall()`
 * cagrildiginda bu servisin `onCreateOutgoing/IncomingConnection` metodunu
 * tetikler.
 *
 * **Asama A:** Skeleton — donen Connection sadece state yonetir, henuz
 * CallManager ile baglanti kurmaz. Asama B'de TelecomBridge devreye girince
 * Connection.listener set edilecek ve CallManager <-> Connection cift yonlu
 * koprulenecek.
 *
 * **Extras Anahtarlari:** ([CallExtras] ile sarmalandi):
 *  - [CallExtras.KEY_CALL_ID] (String) — CallManager session ID
 *  - [CallExtras.KEY_PEER_NAME] (String) — gosterilecek isim
 *  - [CallExtras.KEY_IS_VIDEO] (Boolean) — video aramasi mi
 */
class SecureChatConnectionService : ConnectionService() {

    override fun onCreateOutgoingConnection(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest?
    ): Connection {
        val extras = request?.extras
        val outgoingExtras = extras?.getBundle(android.telecom.TelecomManager.EXTRA_OUTGOING_CALL_EXTRAS)
            ?: extras
        val callId = outgoingExtras?.getString(CallExtras.KEY_CALL_ID).orEmpty()
        val peerId = outgoingExtras?.getString(CallExtras.KEY_PEER_ID).orEmpty()
        val peerName = outgoingExtras?.getString(CallExtras.KEY_PEER_NAME).orEmpty()
        val isVideo = outgoingExtras?.getBoolean(CallExtras.KEY_IS_VIDEO, false) ?: false

        Log.d(TAG, "onCreateOutgoingConnection: callId=$callId peer=$peerName video=$isVideo")

        val connection = SecureChatConnection(
            callId = callId,
            peerId = peerId,
            peerName = peerName,
            isVideo = isVideo,
            isIncoming = false
        )
        connection.setDialing()
        registry.put(callId, connection)
        return connection
    }

    override fun onCreateOutgoingConnectionFailed(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest?
    ) {
        val outgoingExtras = request?.extras?.getBundle(android.telecom.TelecomManager.EXTRA_OUTGOING_CALL_EXTRAS)
            ?: request?.extras
        val callId = outgoingExtras?.getString(CallExtras.KEY_CALL_ID)
        val peerId = outgoingExtras?.getString(CallExtras.KEY_PEER_ID)
        Log.w(TAG, "onCreateOutgoingConnectionFailed: callId=$callId peer=$peerId")
        registry.remove(callId)
        registry.notifyFailure(callId, peerId)
    }

    override fun onCreateIncomingConnection(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest?
    ): Connection {
        val extras = request?.extras
        val callExtras = extras?.getBundle(android.telecom.TelecomManager.EXTRA_INCOMING_CALL_EXTRAS)
            ?: extras
        val callId = callExtras?.getString(CallExtras.KEY_CALL_ID).orEmpty()
        val peerId = callExtras?.getString(CallExtras.KEY_PEER_ID).orEmpty()
        val peerName = callExtras?.getString(CallExtras.KEY_PEER_NAME).orEmpty()
        val isVideo = callExtras?.getBoolean(CallExtras.KEY_IS_VIDEO, false) ?: false

        Log.d(TAG, "onCreateIncomingConnection: callId=$callId peer=$peerName video=$isVideo")

        val connection = SecureChatConnection(
            callId = callId,
            peerId = peerId,
            peerName = peerName,
            isVideo = isVideo,
            isIncoming = true
        )
        connection.setRinging()
        registry.put(callId, connection)
        return connection
    }

    override fun onCreateIncomingConnectionFailed(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest?
    ) {
        val extras = request?.extras
        val callExtras = extras?.getBundle(android.telecom.TelecomManager.EXTRA_INCOMING_CALL_EXTRAS)
            ?: extras
        val callId = callExtras?.getString(CallExtras.KEY_CALL_ID)
        val peerId = callExtras?.getString(CallExtras.KEY_PEER_ID)
        Log.w(TAG, "onCreateIncomingConnectionFailed: callId=$callId peer=$peerId")
        registry.remove(callId)
        registry.notifyFailure(callId, peerId)
    }

    companion object {
        private const val TAG = "SecureChatConnSvc"

        /**
         * Aktif Connection'lari callId -> Connection olarak tutar.
         * TelecomBridge (Asama B) callId ile Connection'a erisip listener set
         * eder ve state push/disconnect yapar.
         */
        internal val registry = ConnectionRegistry()
    }
}

/**
 * Aktif SecureChatConnection'lari callId uzerinden tutar. Thread-safe.
 *
 * `placeCall()` sonrasi sistem `onCreateOutgoingConnection`'i tetikler ve
 * Connection'i olusturur — bu cagri arka planda happen ediyor olabilir.
 * TelecomBridge "onceden" listener kaydetmek istedigi icin
 * [whenAvailable] ile bekleyen callback kayit edilir; Connection
 * registry'ye [put] edildigi anda callback senkron tetiklenir.
 *
 * Bridge soyle kullanir:
 *   1. `whenAvailable(callId) { conn -> conn.listener = ... }`
 *   2. `telecomManager.placeCall(...)`
 *   3. Sistem ConnectionService.onCreateOutgoingConnection cagrir → Connection
 *      olusur ve put edilir → kayitli callback tetiklenir → listener bagli.
 *
 * Tum metotlar tek bir lock altinda atomik — `put` + pending callback
 * tetiklemesi senkron, race condition yok.
 */
internal class ConnectionRegistry {
    private val map = HashMap<String, SecureChatConnection>()
    private val pending = HashMap<String, (SecureChatConnection) -> Unit>()
    private val lock = Any()
    /** TelecomBridge tarafindan kayit edilir; sistem onCreateXxxConnectionFailed
     *  cagirdiginda Bridge'in activeCallIds'i temizleyebilmesi icin. */
    @Volatile var failureListener: ((callId: String?, peerId: String?) -> Unit)? = null

    fun put(callId: String, connection: SecureChatConnection) {
        if (callId.isEmpty()) return
        val pendingListener = synchronized(lock) {
            map[callId] = connection
            pending.remove(callId)
        }
        // Lock disinda invoke — listener uzun is yapacak olabilir
        pendingListener?.invoke(connection)
    }

    fun get(callId: String?): SecureChatConnection? {
        if (callId.isNullOrEmpty()) return null
        return synchronized(lock) { map[callId] }
    }

    fun remove(callId: String?): SecureChatConnection? {
        if (callId.isNullOrEmpty()) return null
        return synchronized(lock) {
            pending.remove(callId)
            map.remove(callId)
        }
    }

    /**
     * [callId] icin Connection olustugunda (veya zaten varsa hemen) verilen
     * action'i bir kez calistirir. Birden fazla cagri ayni callId icin son
     * kayitliyi tutar (TelecomBridge'in tek noktasi olmasi beklenir).
     */
    fun whenAvailable(callId: String, action: (SecureChatConnection) -> Unit) {
        if (callId.isEmpty()) return
        val immediate = synchronized(lock) {
            val existing = map[callId]
            if (existing == null) {
                pending[callId] = action
                null
            } else existing
        }
        immediate?.let { action(it) }
    }

    /**
     * placeCall() basarisiz olursa pending listener'i temizler.
     */
    fun cancelPending(callId: String) {
        if (callId.isEmpty()) return
        synchronized(lock) { pending.remove(callId) }
    }

    fun forEach(action: (SecureChatConnection) -> Unit) {
        val snapshot = synchronized(lock) { map.values.toList() }
        snapshot.forEach(action)
    }

    fun clear() {
        synchronized(lock) {
            map.clear()
            pending.clear()
        }
    }

    /** ConnectionService onCreateXxxConnectionFailed cagrildiginda tetiklenir. */
    fun notifyFailure(callId: String?, peerId: String?) {
        try {
            failureListener?.invoke(callId, peerId)
        } catch (_: Throwable) {
            // listener exception'lari Bridge sebep olmasin
        }
    }
}

/**
 * ConnectionRequest extras icin Bundle anahtarlari — kod-genelinde tek noktada.
 */
object CallExtras {
    const val KEY_CALL_ID = "com.securechat.media.telecom.CALL_ID"
    const val KEY_PEER_ID = "com.securechat.media.telecom.PEER_ID"
    const val KEY_PEER_NAME = "com.securechat.media.telecom.PEER_NAME"
    const val KEY_IS_VIDEO = "com.securechat.media.telecom.IS_VIDEO"
}
