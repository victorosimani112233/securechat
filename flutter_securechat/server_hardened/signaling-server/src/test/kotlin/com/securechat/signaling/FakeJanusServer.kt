package com.securechat.signaling

import io.ktor.server.application.install
import io.ktor.server.engine.embeddedServer
import io.ktor.server.netty.Netty
import io.ktor.server.netty.NettyApplicationEngine
import io.ktor.server.routing.routing
import io.ktor.server.websocket.WebSockets
import io.ktor.server.websocket.webSocket
import io.ktor.websocket.Frame
import io.ktor.websocket.readText
import java.io.IOException
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.ConcurrentLinkedQueue
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * Test icin Janus gateway taklidi.
 *
 * Gercek bir WebSocket konusur: `create`, `attach`, `message` ve
 * `keepalive` isteklerine Janus'un dondurdugu bicimde yanit verir. Boylece
 * SFU kontrol duzlemi — oturum kurma, oda olusturma, sir gonderimi ve
 * baglanti kopmasi — uretim kodunun kendisi uzerinden surulebilir.
 *
 * Gelen her istek kaydedilir; testler api/admin sirlarinin gercekten
 * gonderildigini burada dogrular.
 */
class FakeJanusServer(private val port: Int = 18188) {

    private val json = Json { ignoreUnknownKeys = true }
    private val sessionIds = AtomicLong(1_000)
    private val handleIds = AtomicLong(5_000)
    private var engine: NettyApplicationEngine? = null

    /** Gelen istekler; sirasiyla. */
    val received = ConcurrentLinkedQueue<JsonObject>()

    /** true iken sunucu hicbir istege yanit vermez (timeout senaryosu). */
    @Volatile
    var silent: Boolean = false

    /** `message` isteklerinde dondurulecek oda kimligi; null ise istekteki deger. */
    @Volatile
    var roomIdOverride: Long? = null
    @Volatile var rejectRoomCreation = false
    @Volatile var rejectRoomDestruction = false
    @Volatile var acknowledgeBeforeReply = false

    fun start() {
        engine = embeddedServer(Netty, host = "127.0.0.1", port = port) {
            install(WebSockets)
            routing {
                webSocket("/janus", protocol = "janus-protocol") {
                    for (frame in incoming) {
                        val text = (frame as? Frame.Text)?.readText() ?: continue
                        val request = runCatching {
                            json.parseToJsonElement(text).jsonObject
                        }.getOrNull() ?: continue
                        received += request
                        if (silent) continue
                        if (acknowledgeBeforeReply && request["janus"]?.jsonPrimitive?.content == "message") {
                            send(Frame.Text("""{"janus":"ack","transaction":${request["transaction"]}}"""))
                        }
                        reply(request)?.let { send(Frame.Text(it)) }
                    }
                }
            }
        }.start(wait = false)
    }

    fun stop() {
        val running = engine
        engine = null
        try {
            running?.stop(500, 1_000)
        } catch (error: IOException) {
            // Ktor lazily creates its reload watcher while stopping an already
            // terminated Netty engine. Desktop CI can exhaust the per-user
            // inotify instance quota even though every server assertion ran.
            val message = error.message.orEmpty().lowercase()
            if ("inotify" !in message && "too many open files" !in message) {
                throw error
            }
        }
    }

    fun clear() {
        received.clear()
    }

    private suspend fun io.ktor.websocket.WebSocketSession.reply(request: JsonObject): String? {
        val transaction = request["transaction"]?.jsonPrimitive?.content ?: return null
        return when (request["janus"]?.jsonPrimitive?.content) {
            "create" -> """{"janus":"success","transaction":"$transaction","data":{"id":${sessionIds.incrementAndGet()}}}"""
            "attach" -> """{"janus":"success","transaction":"$transaction","data":{"id":${handleIds.incrementAndGet()}}}"""
            "message" -> {
                val body = request["body"]?.jsonObject
                if (rejectRoomCreation && body?.get("request")?.jsonPrimitive?.content == "create") {
                    return """{"janus":"success","transaction":"$transaction","plugindata":{"data":{"error_code":499,"error":"test refusal"}}}"""
                }
                if (rejectRoomDestruction && body?.get("request")?.jsonPrimitive?.content == "destroy") {
                    return """{"janus":"success","transaction":"$transaction","plugindata":{"data":{"error_code":499,"error":"test refusal"}}}"""
                }
                val event = if (body?.get("request")?.jsonPrimitive?.content == "destroy") "destroyed" else "created"
                val room = roomIdOverride
                    ?: body?.get("room")?.jsonPrimitive?.content?.toLongOrNull()
                    ?: 0L
                """{"janus":"success","transaction":"$transaction",""" +
                    """"plugindata":{"plugin":"janus.plugin.videoroom","data":{"videoroom":"$event","room":$room}}}"""
            }
            "keepalive" -> """{"janus":"ack","transaction":"$transaction"}"""
            "destroy" -> """{"janus":"success","transaction":"$transaction"}"""
            else -> """{"janus":"ack","transaction":"$transaction"}"""
        }
    }
}
