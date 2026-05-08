package com.securechat.telecom

import android.os.Build
import android.telecom.Connection
import android.telecom.ConnectionRequest
import android.telecom.ConnectionService
import android.telecom.PhoneAccountHandle
import android.util.Log
import androidx.annotation.RequiresApi
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject

/**
 * Android Telecom Framework ConnectionService implementasyonu.
 *
 * Sistem bu service'i [PhoneAccountRegistrar] tarafından kayıtlı PhoneAccountHandle ile
 * binder eder. Gelen ve giden aramalarda Connection nesnesi üretmek için sistem
 * [onCreateIncomingConnection] / [onCreateOutgoingConnection] callback'lerini çağırır.
 *
 * Manifest: `<service android:name="...SecureChatConnectionService"
 *   android:permission="android.permission.BIND_TELECOM_CONNECTION_SERVICE">
 *   <intent-filter><action android:name="android.telecom.ConnectionService"/></intent-filter>
 * </service>`
 *
 * Bridge: [ConnectionBridge] uygulamanın CallManager'ına bağlanır (Hilt inject).
 */
@RequiresApi(Build.VERSION_CODES.O)
@AndroidEntryPoint
class SecureChatConnectionService : ConnectionService() {

    @Inject lateinit var bridge: ConnectionBridge

    override fun onCreateIncomingConnection(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest?
    ): Connection {
        val extras = request?.extras
        val callId = extras?.getString(EXTRA_CALL_ID) ?: "unknown_${System.currentTimeMillis()}"
        val peerId = extras?.getString(EXTRA_PEER_ID) ?: "unknown"
        Log.d(TAG, "onCreateIncomingConnection call=$callId peer=$peerId")

        val conn = SecureChatConnection(
            callId = callId, peerId = peerId, isIncoming = true, bridge = bridge
        )
        // Bridge'e bilgi ver — CallManager bu Connection'ı state machine'iyle senkronize eder
        bridge.onConnectionCreated(callId, conn)
        // Sistem UI'sının "Gelen Arama" göstermesi için ringing state
        conn.startRinging()
        return conn
    }

    override fun onCreateOutgoingConnection(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest?
    ): Connection {
        val extras = request?.extras
        val callId = extras?.getString(EXTRA_CALL_ID) ?: "out_${System.currentTimeMillis()}"
        val peerId = extras?.getString(EXTRA_PEER_ID) ?: "unknown"
        Log.d(TAG, "onCreateOutgoingConnection call=$callId peer=$peerId")

        val conn = SecureChatConnection(
            callId = callId, peerId = peerId, isIncoming = false, bridge = bridge
        )
        bridge.onConnectionCreated(callId, conn)
        conn.startDialing()
        return conn
    }

    override fun onCreateIncomingConnectionFailed(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest?
    ) {
        Log.w(TAG, "onCreateIncomingConnectionFailed: ${request?.extras?.getString(EXTRA_CALL_ID)}")
    }

    override fun onCreateOutgoingConnectionFailed(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest?
    ) {
        Log.w(TAG, "onCreateOutgoingConnectionFailed: ${request?.extras?.getString(EXTRA_CALL_ID)}")
    }

    companion object {
        const val EXTRA_CALL_ID = "com.securechat.telecom.CALL_ID"
        const val EXTRA_PEER_ID = "com.securechat.telecom.PEER_ID"
        const val EXTRA_PEER_NAME = "com.securechat.telecom.PEER_NAME"
        const val EXTRA_IS_VIDEO = "com.securechat.telecom.IS_VIDEO"
        private const val TAG = "SCConnectionService"
    }
}
