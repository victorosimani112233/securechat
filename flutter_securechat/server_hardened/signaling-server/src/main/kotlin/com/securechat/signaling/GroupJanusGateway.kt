package com.securechat.signaling

import io.ktor.server.application.*
import io.ktor.server.routing.*
import io.ktor.server.websocket.*
import io.ktor.websocket.*
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import kotlinx.serialization.json.*
import java.net.URI
import java.net.http.HttpClient
import java.net.http.WebSocket as UpstreamSocket
import java.util.concurrent.CompletionStage
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit

/** A restricted adapter for Flutter's Bearer-authenticated Janus contract.
 * No admin operations, arbitrary plugins, foreign sessions or room discovery.
 */
internal fun Application.configureGroupJanusGateway(
    enabled: () -> Boolean = { SfuPolicy.isEnabled() },
    verifyToken: (String) -> String? = AuthService::verifyToken,
    upstreamUrl: () -> String = { System.getenv("JANUS_WS_URL") },
    apiSecret: () -> String = { SecretSource.required("JANUS_API_SECRET") },
    allowRequest: (String, String) -> Boolean = RateLimiter::allow,
) {
    val clients = ConcurrentHashMap<String, Any>()
    val feeds = GroupJanusFeeds()
    val httpClient = HttpClient.newHttpClient()
    routing {
        webSocket("/janus", protocol = "janus-protocol") {
            val credentials = WebSocketCredentials.extract(
                call.request.headers["Authorization"], call.request.queryParameters["token"],
            ) as? WebSocketCredentials.Result.Accepted
            val user = credentials?.let { verifyToken(it.token) }
            val active = user?.let { id -> GroupCallSessionStore.findActiveCallsForUser(id)
                .singleOrNull { it.mode == "SFU" && id in it.joinedParticipants && it.mediaEndToEndEncrypted } }
            val owner = Any()
            if (!enabled() || user == null || active == null ||
                !allowRequest("ws_connect", call.clientAddress()) || clients.putIfAbsent(user, owner) != null) {
                close(CloseReason(CloseReason.Codes.VIOLATED_POLICY, "Group SFU access denied"))
                return@webSocket
            }
            val contract = GroupJanusContract(user, active, feeds)
            val responses = Channel<String>(32)
            var upstream: UpstreamSocket? = null
            try {
                val secret = apiSecret()
                val connected = withContext(Dispatchers.IO) {
                    httpClient.newWebSocketBuilder()
                        .connectTimeout(java.time.Duration.ofSeconds(8))
                        .subprotocols("janus-protocol")
                        .buildAsync(URI.create(upstreamUrl()), object : UpstreamSocket.Listener {
                            private val buffer = StringBuilder()
                            override fun onOpen(socket: UpstreamSocket) { socket.request(1) }
                            override fun onText(socket: UpstreamSocket, data: CharSequence, last: Boolean): CompletionStage<*>? {
                                buffer.append(data)
                                if (buffer.length > 256 * 1024) {
                                    responses.close(); socket.abort(); return null
                                }
                                if (last) {
                                    val accepted = responses.trySend(buffer.toString()).isSuccess
                                    buffer.clear()
                                    if (!accepted) { responses.close(); socket.abort(); return null }
                                }
                                socket.request(1)
                                return null
                            }
                            override fun onClose(socket: UpstreamSocket, status: Int, reason: String): CompletionStage<*>? {
                                responses.close(); return null
                            }
                            override fun onError(socket: UpstreamSocket, error: Throwable) { responses.close() }
                        }).get(10, TimeUnit.SECONDS)
                }
                upstream = connected
                coroutineScope {
                    val reader = launch {
                        try {
                            for (text in responses) {
                                require(contract.authorized() && verifyToken(credentials.token) == user)
                                require(text.toByteArray(Charsets.UTF_8).size <= 256 * 1024)
                                val response = Json.parseToJsonElement(text).jsonObject
                                contract.response(response)
                                send(Frame.Text(sanitizeJanusResponse(response).toString()))
                            }
                        } finally {
                            close(CloseReason(CloseReason.Codes.NORMAL, "Janus connection ended"))
                        }
                    }
                    val membership = launch {
                        while (isActive) {
                            delay(1_000)
                            if (!contract.authorized() || verifyToken(credentials.token) != user) {
                                close(CloseReason(CloseReason.Codes.VIOLATED_POLICY, "Group membership ended"))
                                break
                            }
                        }
                    }
                    try {
                        for (frame in incoming) {
                            val text = (frame as? Frame.Text)?.readText() ?: continue
                            require(text.toByteArray(Charsets.UTF_8).size <= 256 * 1024)
                            require(allowRequest("ws_message", user))
                            require(verifyToken(credentials.token) == user)
                            val approved = contract.request(Json.parseToJsonElement(text).jsonObject)
                            val internal = JsonObject(approved + ("apisecret" to JsonPrimitive(secret)))
                            withContext(Dispatchers.IO) { connected.sendText(internal.toString(), true).get(8, TimeUnit.SECONDS) }
                        }
                    } finally {
                        membership.cancel()
                        reader.cancel()
                    }
                }
            } catch (_: Exception) {
                // No tokens, SDP, upstream errors or request bodies enter logs.
                close(CloseReason(CloseReason.Codes.VIOLATED_POLICY, "Group Janus request failed"))
            } finally {
                withContext(NonCancellable + Dispatchers.IO) {
                    runCatching {
                        contract.destroyRequest()?.let { request ->
                            val internal = JsonObject(request + ("apisecret" to JsonPrimitive(apiSecret())))
                            upstream?.sendText(internal.toString(), true)?.get(2, TimeUnit.SECONDS)
                        }
                    }
                    upstream?.abort()
                }
                responses.close()
                clients.remove(user, owner)
                feeds.removeOwner(active.instanceId, user)
            }
        }
    }
}

internal class GroupJanusFeeds {
    private val owners = ConcurrentHashMap<Pair<String, Long>, String>()
    fun register(call: GroupCallSessionStore.ActiveCall, feed: Long, owner: String) {
        if (owner in call.joinedParticipants && owner in call.mediaE2eeParticipants && feed > 0) {
            owners[call.instanceId to feed] = owner
        }
    }
    fun allowed(call: GroupCallSessionStore.ActiveCall, feed: Long): Boolean =
        owners[call.instanceId to feed]?.let { it in call.joinedParticipants && it in call.mediaE2eeParticipants } == true
    fun remove(instance: String, feed: Long) { owners.remove(instance to feed) }
    fun removeOwner(instance: String, owner: String) {
        owners.entries.removeIf { it.key.first == instance && it.value == owner }
    }
}

internal class GroupJanusContract(
    private val user: String,
    private val call: GroupCallSessionStore.ActiveCall,
    private val feeds: GroupJanusFeeds = GroupJanusFeeds(),
) {
    private data class Pending(val kind: String, val handle: Long?, val role: String?)
    private val pending = mutableMapOf<String, Pending>()
    private val handles = mutableMapOf<Long, String?>()
    private var session: Long? = null
    private var created = false

    fun authorized(): Boolean {
        val current = GroupCallSessionStore.get(call.groupId) ?: return false
        return current.instanceId == call.instanceId && current.sfuRoomId == call.sfuRoomId &&
            current.mode == "SFU" && current.mediaEndToEndEncrypted && user in current.joinedParticipants &&
            user in current.mediaE2eeParticipants
    }

    @Synchronized
    fun request(frame: JsonObject): JsonObject {
        require(authorized())
        require(frame.keys.all { it in setOf("janus", "transaction", "session_id", "handle_id", "plugin", "body", "jsep", "candidate") })
        val transaction = frame.text("transaction")
        require(transaction.isNotBlank() && transaction.length <= 128 && transaction !in pending && pending.size < 32)
        val kind = frame.text("janus")
        val handle = frame["handle_id"]?.jsonPrimitive?.longOrNull
        var role: String? = null
        var body: JsonObject? = null
        var jsep: JsonObject? = null
        if (kind != "create") require(session != null && frame["session_id"]?.jsonPrimitive?.longOrNull == session)
        when (kind) {
            "create" -> { require(!created && frame.keys == setOf("janus", "transaction")); created = true }
            "attach" -> {
                require(frame.text("plugin") == "janus.plugin.videoroom")
                require(handles.size + pending.values.count { it.kind == "attach" } < 16)
            }
            "keepalive", "destroy" -> require(handle == null && frame["body"] == null && frame["jsep"] == null)
            "detach" -> require(handle in handles)
            "trickle" -> { require(handle in handles); require(frame["candidate"] is JsonObject) }
            "message" -> {
                require(handle in handles)
                val supplied = frame["body"]!!.jsonObject
                val command = supplied.text("request")
                body = when (command) {
                    "join" -> {
                        require(handles[handle] == null && pending.values.none { it.handle == handle && it.role != null })
                        require(supplied["room"]?.jsonPrimitive?.longOrNull == call.sfuRoomId)
                        role = supplied.text("ptype")
                        when (role) {
                            "publisher" -> {
                                require(handles.values.none { it == "publisher" } && pending.values.none { it.role == "publisher" })
                                require(supplied.keys.all { it in setOf("request", "room", "ptype", "display") })
                                JsonObject(supplied + ("display" to JsonPrimitive(user)))
                            }
                            "subscriber" -> {
                                require(supplied.keys.all { it in setOf("request", "room", "ptype", "feed") })
                                val feed = supplied["feed"]?.jsonPrimitive?.longOrNull ?: 0
                                require(feeds.allowed(requireNotNull(GroupCallSessionStore.get(call.groupId)), feed))
                                supplied
                            }
                            else -> throw IllegalArgumentException("Unsupported group role")
                        }
                    }
                    "configure" -> {
                        require(handles[handle] == "publisher")
                        require(supplied.keys.all { it in setOf("request", "audio", "video") })
                        supplied
                    }
                    "start" -> {
                        require(handles[handle] == "subscriber")
                        require(supplied.keys == setOf("request", "room") && supplied["room"]?.jsonPrimitive?.longOrNull == call.sfuRoomId)
                        supplied
                    }
                    "leave" -> { require(supplied.keys == setOf("request")); supplied }
                    else -> throw IllegalArgumentException("Unsupported group operation")
                }
                if (command in setOf("configure", "start")) {
                    val suppliedJsep = frame["jsep"]!!.jsonObject
                    require(suppliedJsep.keys.all { it in setOf("type", "sdp", "e2ee") })
                    require(suppliedJsep.text("type") == if (command == "configure") "offer" else "answer")
                    require(suppliedJsep.text("sdp").isNotBlank())
                    require(suppliedJsep["e2ee"]?.jsonPrimitive?.booleanOrNull != false)
                    // Capability was authenticated at join; no plaintext fallback.
                    jsep = JsonObject(suppliedJsep + ("e2ee" to JsonPrimitive(true)))
                } else require(frame["jsep"] == null)
            }
            else -> throw IllegalArgumentException("Unsupported Janus operation")
        }
        pending[transaction] = Pending(kind, handle, role)
        return buildJsonObject {
            put("janus", kind); put("transaction", transaction)
            if (kind != "create") put("session_id", session!!)
            if (handle != null) put("handle_id", handle)
            if (kind == "attach") put("plugin", "janus.plugin.videoroom")
            if (kind == "trickle") put("candidate", frame.getValue("candidate"))
            body?.let { put("body", it) }; jsep?.let { put("jsep", it) }
        }
    }

    @Synchronized
    fun response(frame: JsonObject) {
        val responseSession = frame["session_id"]?.jsonPrimitive?.longOrNull
        require(responseSession == null || responseSession == session)
        val sender = frame["sender"]?.jsonPrimitive?.longOrNull
        require(sender == null || sender in handles)
        val data = frame["plugindata"]?.jsonObject?.get("data")?.jsonObject
        val room = data?.get("room")?.jsonPrimitive?.longOrNull
        require(room == null || room == call.sfuRoomId)
        val current = requireNotNull(GroupCallSessionStore.get(call.groupId))
        require(authorized())
        data?.get("publishers")?.jsonArray?.forEach { publisher ->
            val info = publisher.jsonObject
            val feed = info["id"]?.jsonPrimitive?.longOrNull
            val owner = info["display"]?.jsonPrimitive?.contentOrNull
            if (feed != null && owner != null) feeds.register(current, feed, owner)
        }
        (data?.get("unpublished") ?: data?.get("leaving"))?.jsonPrimitive?.longOrNull?.let {
            feeds.remove(call.instanceId, it)
        }
        val transaction = frame["transaction"]?.jsonPrimitive?.contentOrNull ?: return
        val request = pending[transaction] ?: return
        val kind = frame.text("janus")
        if (kind == "ack" && request.kind !in setOf("trickle", "keepalive")) return
        pending.remove(transaction)
        if (kind == "error" || frame["plugindata"]?.jsonObject?.get("data")?.jsonObject?.get("error_code") != null) return
        when (request.kind) {
            "create" -> session = frame["data"]!!.jsonObject["id"]!!.jsonPrimitive.long
            "attach" -> handles[frame["data"]!!.jsonObject["id"]!!.jsonPrimitive.long] = null
            "detach" -> handles.remove(request.handle)
            "message" -> if (request.role != null) {
                handles[request.handle!!] = request.role
                if (request.role == "publisher") {
                    data?.get("id")?.jsonPrimitive?.longOrNull?.let { feeds.register(current, it, user) }
                }
            }
        }
    }

    @Synchronized
    fun destroyRequest(): JsonObject? = session?.let { id -> buildJsonObject {
        put("janus", "destroy"); put("session_id", id); put("transaction", "gateway-close")
    } }
}

private fun JsonObject.text(key: String) = get(key)?.jsonPrimitive?.contentOrNull.orEmpty()

private fun sanitizeJanusResponse(value: JsonElement): JsonElement = when (value) {
    is JsonObject -> JsonObject(value.filterKeys { it !in setOf("apisecret", "admin_secret", "admin_key", "secret", "token") }
        .mapValues { (key, child) -> if (key in setOf("reason", "error") && child is JsonPrimitive) JsonPrimitive("Janus request failed")
            else sanitizeJanusResponse(child) })
    is JsonArray -> JsonArray(value.map(::sanitizeJanusResponse))
    else -> value
}
