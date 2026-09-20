package com.securechat.app

import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.OutcomeReceiver
import android.telecom.CallAudioState
import android.telecom.CallEndpoint
import android.telecom.CallEndpointException
import android.telecom.Connection
import android.telecom.ConnectionRequest
import android.telecom.ConnectionService
import android.telecom.DisconnectCause
import android.telecom.TelecomManager
import android.telecom.VideoProfile
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executor

class SecureChatConnectionService : ConnectionService() {
    companion object {
        const val EXTRA_CALL_ID = "securechat.call_id"
        const val EXTRA_PEER_ID = "securechat.peer_id"
        const val EXTRA_PEER_NAME = "securechat.peer_name"
        const val EXTRA_HAS_VIDEO = "securechat.has_video"
        const val EXTRA_REDACT_IDENTITY = "securechat.redact_identity"
    }

    private val callNotifications by lazy {
        SecureChatCallNotificationManager(applicationContext)
    }

    override fun onCreate() {
        super.onCreate()
        callNotifications.ensureChannels()
    }

    override fun onCreateIncomingConnection(
        connectionManagerPhoneAccount: android.telecom.PhoneAccountHandle?,
        request: ConnectionRequest
    ): Connection = createConnection(request, incoming = true)

    override fun onCreateOutgoingConnection(
        connectionManagerPhoneAccount: android.telecom.PhoneAccountHandle?,
        request: ConnectionRequest
    ): Connection = createConnection(request, incoming = false)

    private fun createConnection(request: ConnectionRequest, incoming: Boolean): Connection {
        val extras = request.extras ?: Bundle.EMPTY
        val remembered = NativeCallRegistry.findByCallId(request.address?.schemeSpecificPart)
            ?: NativeCallRegistry.findByPeer(request.address?.schemeSpecificPart)
        val callId = extras.getString(EXTRA_CALL_ID) ?: remembered?.callId.orEmpty()
        val peerId = extras.getString(EXTRA_PEER_ID)
            ?: request.address?.schemeSpecificPart
            ?: remembered?.peerId.orEmpty()
        val peerName = extras.getString(EXTRA_PEER_NAME) ?: remembered?.peerName ?: peerId
        val hasVideo = extras.getBoolean(EXTRA_HAS_VIDEO, remembered?.hasVideo ?: false)
        val redactIdentity = extras.getBoolean(
            EXTRA_REDACT_IDENTITY,
            remembered?.redactIdentity ?: true
        )
        if (callId.isBlank()) {
            return Connection.createFailedConnection(
                DisconnectCause(DisconnectCause.ERROR, "Missing SecureChat call id")
            )
        }
        val info = NativeCallInfo(callId, peerId, peerName, hasVideo, redactIdentity)
        NativeCallRegistry.remember(callId, peerId, peerName, hasVideo, redactIdentity)
        val connection = SecureChatConnection(
            callId = callId,
            onConnecting = { callNotifications.showConnecting(info) },
            onEnded = callNotifications::cancel
        ).apply {
            connectionProperties = Connection.PROPERTY_SELF_MANAGED
            connectionCapabilities = Connection.CAPABILITY_MUTE
            setAddress(
                Uri.fromParts("securechat", if (redactIdentity) "private" else peerId, null),
                if (redactIdentity) TelecomManager.PRESENTATION_RESTRICTED
                else TelecomManager.PRESENTATION_ALLOWED
            )
            setCallerDisplayName(
                if (redactIdentity) "Elçim araması" else peerName,
                if (redactIdentity) TelecomManager.PRESENTATION_RESTRICTED
                else TelecomManager.PRESENTATION_ALLOWED
            )
            videoState = if (hasVideo) {
                VideoProfile.STATE_BIDIRECTIONAL
            } else {
                VideoProfile.STATE_AUDIO_ONLY
            }
            if (incoming) setRinging() else setDialing()
        }
        NativeCallRegistry.bind(callId, connection)
        return connection
    }
}

internal class SecureChatConnection(
    private val callId: String,
    private val onConnecting: () -> Unit,
    private val onEnded: () -> Unit
) : Connection() {
    private var availableEndpoints: List<CallEndpoint> = emptyList()

    init {
        setAudioModeIsVoip(true)
    }

    override fun onAnswer(videoState: Int) {
        setActive()
        onConnecting()
        NativeCallRegistry.emit("answer", callId)
    }

    override fun onAnswer() = onAnswer(VideoProfile.STATE_AUDIO_ONLY)

    override fun onReject() {
        NativeCallRegistry.emit("end", callId)
        disconnect(DisconnectCause.REJECTED)
    }

    override fun onDisconnect() {
        NativeCallRegistry.emit("end", callId)
        disconnect(DisconnectCause.LOCAL)
    }

    override fun onAbort() = onDisconnect()

    override fun onCallAudioStateChanged(state: android.telecom.CallAudioState?) {
        if (state != null) {
            NativeCallRegistry.emit(if (state.isMuted) "mute" else "unmute", callId)
            NativeCallRegistry.emit(
                if (state.route and CallAudioState.ROUTE_SPEAKER != 0) "speakerOn"
                else "speakerOff",
                callId
            )
        }
    }

    override fun onAvailableCallEndpointsChanged(endpoints: List<CallEndpoint>) {
        availableEndpoints = endpoints.toList()
    }

    override fun onCallEndpointChanged(endpoint: CallEndpoint) {
        NativeCallRegistry.emit(
            if (endpoint.endpointType == CallEndpoint.TYPE_SPEAKER) "speakerOn"
            else "speakerOff",
            callId
        )
    }

    fun requestSpeaker(
        enabled: Boolean,
        executor: Executor,
        completion: (Boolean) -> Unit
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val endpoint = preferredEndpoint(enabled)
            if (endpoint != null) {
                requestCallEndpointChange(
                    endpoint,
                    executor,
                    object : OutcomeReceiver<Void, CallEndpointException> {
                        override fun onResult(result: Void?) = completion(true)
                        override fun onError(error: CallEndpointException) = completion(false)
                    }
                )
                return
            }
        }
        completion(requestLegacyAudioRoute(enabled))
    }

    private fun requestLegacyAudioRoute(enabled: Boolean): Boolean {
        val supported = callAudioState?.supportedRouteMask ?: return false
        val candidates = if (enabled) {
            intArrayOf(CallAudioState.ROUTE_SPEAKER)
        } else {
            intArrayOf(
                CallAudioState.ROUTE_BLUETOOTH,
                CallAudioState.ROUTE_WIRED_HEADSET,
                CallAudioState.ROUTE_EARPIECE
            )
        }
        val route = candidates.firstOrNull { supported and it != 0 } ?: return false
        @Suppress("DEPRECATION")
        setAudioRoute(route)
        return true
    }

    private fun preferredEndpoint(speaker: Boolean): CallEndpoint? {
        val types = if (speaker) {
            intArrayOf(CallEndpoint.TYPE_SPEAKER)
        } else {
            intArrayOf(
                CallEndpoint.TYPE_BLUETOOTH,
                CallEndpoint.TYPE_WIRED_HEADSET,
                CallEndpoint.TYPE_EARPIECE
            )
        }
        for (type in types) {
            val endpoint = availableEndpoints.firstOrNull { it.endpointType == type }
            if (endpoint != null) return endpoint
        }
        return null
    }

    fun disconnect(cause: Int) {
        onEnded()
        setDisconnected(DisconnectCause(cause))
        destroy()
        NativeCallRegistry.remove(callId)
    }
}

internal data class NativeCallInfo(
    val callId: String,
    val peerId: String,
    val peerName: String,
    val hasVideo: Boolean,
    val redactIdentity: Boolean
)

internal object NativeCallRegistry {
    private val calls = ConcurrentHashMap<String, NativeCallInfo>()
    private val connections = ConcurrentHashMap<String, SecureChatConnection>()
    private val pendingActions = ArrayDeque<Pair<String, String>>()
    @Volatile private var emitter: ((String, String) -> Unit)? = null

    fun attach(value: (String, String) -> Unit) {
        val pending = synchronized(this) {
            emitter = value
            pendingActions.toList().also { pendingActions.clear() }
        }
        for ((action, callId) in pending) value(action, callId)
    }

    fun detach() {
        synchronized(this) { emitter = null }
    }

    fun emit(action: String, callId: String) {
        val current = synchronized(this) {
            emitter.also {
                if (it == null) {
                    if (pendingActions.size == 8) pendingActions.removeFirst()
                    pendingActions.addLast(action to callId)
                }
            }
        }
        current?.invoke(action, callId)
    }
    fun remember(
        callId: String,
        peerId: String,
        peerName: String,
        hasVideo: Boolean,
        redactIdentity: Boolean
    ) {
        calls[callId] = NativeCallInfo(callId, peerId, peerName, hasVideo, redactIdentity)
    }
    fun findByCallId(callId: String?): NativeCallInfo? = callId?.let(calls::get)
    fun findByPeer(peerId: String?): NativeCallInfo? =
        calls.values.firstOrNull { it.peerId == peerId }
    fun bind(callId: String, connection: SecureChatConnection) {
        connections[callId] = connection
    }
    fun setActive(callId: String) { connections[callId]?.setActive() }
    fun setSpeaker(
        callId: String,
        enabled: Boolean,
        executor: Executor,
        completion: (Boolean) -> Unit
    ) {
        val connection = connections[callId]
        if (connection == null) {
            completion(false)
            return
        }
        connection.requestSpeaker(enabled, executor, completion)
    }
    fun end(callId: String) { connections[callId]?.disconnect(DisconnectCause.LOCAL) }
    fun remove(callId: String) {
        connections.remove(callId)
        calls.remove(callId)
    }
}
