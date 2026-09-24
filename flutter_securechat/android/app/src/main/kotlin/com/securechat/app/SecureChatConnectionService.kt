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
        val callId = remembered?.callId ?: extras.getString(EXTRA_CALL_ID).orEmpty()
        val peerId = remembered?.peerId
            ?: extras.getString(EXTRA_PEER_ID)
            ?: request.address?.schemeSpecificPart.orEmpty()
        val peerName = remembered?.peerName ?: extras.getString(EXTRA_PEER_NAME) ?: peerId
        val hasVideo = remembered?.hasVideo
            ?: extras.getBoolean(EXTRA_HAS_VIDEO, false)
        val redactIdentity = remembered?.redactIdentity
            ?: extras.getBoolean(EXTRA_REDACT_IDENTITY, true)
        if (callId.isBlank()) {
            return Connection.createFailedConnection(
                DisconnectCause(DisconnectCause.ERROR, "Missing SecureChat call id")
            )
        }
        val info = NativeCallInfo(callId, peerId, peerName, hasVideo, redactIdentity)
        NativeCallRegistry.remember(callId, peerId, peerName, hasVideo, redactIdentity)
        val connection = SecureChatConnection(info, callNotifications).apply {
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
    initialInfo: NativeCallInfo,
    private val notifications: SecureChatCallNotificationManager
) : Connection() {
    private var info = initialInfo
    private var availableEndpoints: List<CallEndpoint> = emptyList()

    init {
        setAudioModeIsVoip(true)
    }

    override fun onAnswer(videoState: Int) {
        setActive()
        notifications.showConnecting(info)
        NativeCallRegistry.emit("answer", info.callId)
    }

    override fun onAnswer() = onAnswer(VideoProfile.STATE_AUDIO_ONLY)

    override fun onReject() {
        NativeCallRegistry.emit("end", info.callId)
        disconnect(DisconnectCause.REJECTED)
    }

    override fun onDisconnect() {
        NativeCallRegistry.emit("end", info.callId)
        disconnect(DisconnectCause.LOCAL)
    }

    override fun onAbort() = onDisconnect()

    override fun onCallAudioStateChanged(state: android.telecom.CallAudioState?) {
        if (state != null) {
            NativeCallRegistry.emit(if (state.isMuted) "mute" else "unmute", info.callId)
            NativeCallRegistry.emit(
                if (state.route and CallAudioState.ROUTE_SPEAKER != 0) "speakerOn"
                else "speakerOff",
                info.callId
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
            info.callId
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

    fun promote(replacement: NativeCallInfo) {
        info = replacement
        setAddress(
            Uri.fromParts(
                "securechat",
                if (replacement.redactIdentity) "private" else replacement.peerId,
                null
            ),
            if (replacement.redactIdentity) TelecomManager.PRESENTATION_RESTRICTED
            else TelecomManager.PRESENTATION_ALLOWED
        )
        setCallerDisplayName(
            if (replacement.redactIdentity) "Elçim araması" else replacement.peerName,
            if (replacement.redactIdentity) TelecomManager.PRESENTATION_RESTRICTED
            else TelecomManager.PRESENTATION_ALLOWED
        )
        videoState = if (replacement.hasVideo) {
            VideoProfile.STATE_BIDIRECTIONAL
        } else {
            VideoProfile.STATE_AUDIO_ONLY
        }
    }

    fun disconnect(cause: Int) {
        notifications.cancel()
        setDisconnected(DisconnectCause(cause))
        destroy()
        NativeCallRegistry.remove(info.callId)
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
    private val pendingAnswers = ConcurrentHashMap.newKeySet<String>()
    data class HintPromotion(val action: String?)

    private data class PendingHint(val callId: String, val createdAt: Long)

    private val calls = ConcurrentHashMap<String, NativeCallInfo>()
    private val connections = ConcurrentHashMap<String, SecureChatConnection>()
    private val aliases = ConcurrentHashMap<String, String>()
    private val hintActions = ConcurrentHashMap<String, String>()
    private val pendingActions = ArrayDeque<Pair<String, String>>()
    @Volatile private var pendingHint: PendingHint? = null
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
        if (pendingHint?.callId == callId) {
            if (action == "answer" || action == "end") hintActions[callId] = action
            return
        }
        emitResolved(action, resolve(callId))
    }

    fun emitResolved(action: String, callId: String) {
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

    @Synchronized
    fun rememberHint(info: NativeCallInfo): Boolean {
        val current = pendingHint
        if (current?.callId == info.callId) return false
        if (current != null) {
            calls.remove(current.callId)
            connections.remove(current.callId)?.disconnect(DisconnectCause.CANCELED)
            hintActions.remove(current.callId)
        }
        pendingHint = PendingHint(info.callId, System.currentTimeMillis())
        calls[info.callId] = info
        return true
    }

    @Synchronized
    fun promoteHint(info: NativeCallInfo): HintPromotion? {
        val hint = pendingHint ?: return null
        if (System.currentTimeMillis() - hint.createdAt > HINT_LIFETIME_MS) {
            pendingHint = null
            calls.remove(hint.callId)
            hintActions.remove(hint.callId)
            connections.remove(hint.callId)?.disconnect(DisconnectCause.CANCELED)
            return null
        }
        pendingHint = null
        calls.remove(hint.callId)
        calls[info.callId] = info
        aliases[hint.callId] = info.callId
        connections.remove(hint.callId)?.let { connection ->
            connection.promote(info)
            connections[info.callId] = connection
        }
        return HintPromotion(hintActions.remove(hint.callId))
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
    fun findByCallId(callId: String?): NativeCallInfo? = callId?.let {
        calls[resolve(it)]
    }
    fun findByPeer(peerId: String?): NativeCallInfo? =
        calls.values.firstOrNull { it.peerId == peerId }
    fun bind(callId: String, connection: SecureChatConnection) {
        connections[resolve(callId)] = connection
        if (pendingAnswers.remove(resolve(callId))) connection.onAnswer()
    }
    fun setActive(callId: String) { connections[resolve(callId)]?.setActive() }
    fun answer(callId: String) {
        val id = resolve(callId)
        if (!calls.containsKey(id)) return
        val connection = connections[id]
        if (connection != null) connection.onAnswer() else pendingAnswers.add(id)
    }
    fun setSpeaker(
        callId: String,
        enabled: Boolean,
        executor: Executor,
        completion: (Boolean) -> Unit
    ) {
        val connection = connections[resolve(callId)]
        if (connection == null) {
            completion(false)
            return
        }
        connection.requestSpeaker(enabled, executor, completion)
    }
    fun end(callId: String) { connections[resolve(callId)]?.disconnect(DisconnectCause.LOCAL) }
    fun remove(callId: String) {
        val resolved = resolve(callId)
        pendingAnswers.remove(resolved)
        connections.remove(resolved)
        if (pendingHint?.callId != callId) calls.remove(resolved)
        aliases.entries.removeIf { it.key == callId || it.value == resolved }
    }

    private fun resolve(callId: String): String = aliases[callId] ?: callId

    private const val HINT_LIFETIME_MS = 60_000L
}
