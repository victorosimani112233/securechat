package com.securechat.botapi.delivery

import com.securechat.botapi.BotApiConfig
import com.securechat.botapi.signal.BotIdentity
import com.securechat.botapi.signal.BotServiceTokenMinter
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.slf4j.LoggerFactory
import java.util.concurrent.atomic.AtomicReference
import java.time.Duration

private val log = LoggerFactory.getLogger("SignalingWsClient")

/**
 * Bot'un signaling-server'a kurdugu WebSocket baglantisi.
 *
 *  - URL: ${SIGNALING_WS_URL}?userId=<botUserId>; servis assertion'i
 *    yalniz Authorization header'inda tasinir
 *  - Exponential backoff reconnect: 1s, 2s, 4s ... cap 30s
 *  - Connect sonrasinda OutboundQueue.drainAll cagrilir
 *  - send() WS down ise OutboundQueue'ya yazar, true doner (caller 202 verebilir)
 *
 * Thread-safety: WebSocket OkHttp tarafindan thread-safe; ref AtomicReference.
 */
object SignalingWsClient {

    private val scope = CoroutineScope(Dispatchers.IO)
    private var loopJob: Job? = null

    private val client = OkHttpClient.Builder()
        .readTimeout(Duration.ofSeconds(0))     // WS icin idle disabled
        .pingInterval(Duration.ofSeconds(30))
        .build()

    private val wsRef = AtomicReference<WebSocket>()
    private val drainLock = Any()
    private val json = Json { ignoreUnknownKeys = true }
    @Volatile private var connected: Boolean = false
    @Volatile private var stopping: Boolean = false

    fun start() {
        if (loopJob != null) return
        stopping = false
        loopJob = scope.launch { reconnectLoop() }
        log.info("[WSClient] Reconnect loop baslatildi")
    }

    fun stop() {
        stopping = true
        loopJob?.cancel()
        loopJob = null
        runCatching { wsRef.get()?.close(1000, "shutdown") }
    }

    fun isConnected(): Boolean = connected

    /** Mesaji once durable queue'ya alir, sonra baglanti varsa drain eder. */
    fun send(envelopeJson: String): Boolean {
        val botUserId = BotIdentity.get().botUserId
        try {
            OutboundQueue.enqueue(botUserId, envelopeJson)
        } catch (e: Exception) {
            log.error("[WSClient] Durable queue yazimi basarisiz: {}", e.javaClass.simpleName)
            return false
        }
        val ws = wsRef.get()
        if (connected && ws != null) {
            runCatching { drainQueued(botUserId, ws) }
                .onFailure {
                    // Queue yazimi tamamlandi; API teslim sorumlulugunu kabul
                    // edebilir. Reconnect/visibility timeout yeniden dener.
                    log.warn("[WSClient] Anlik drain hatasi: {}", it.javaClass.simpleName)
                }
        } else {
            log.debug("[WSClient] WS down — queue'a yazildi")
        }
        return true
    }

    private fun drainQueued(botUserId: String, webSocket: WebSocket) {
        synchronized(drainLock) {
            if (!connected || wsRef.get() !== webSocket) return
            OutboundQueue.drainAll(botUserId) { message ->
                connected && wsRef.get() === webSocket && webSocket.send(message)
            }
        }
    }

    private suspend fun reconnectLoop() {
        var backoffSec = 1L
        while (!stopping) {
            try {
                val token = BotServiceTokenMinter.issue(
                    BotIdentity.get().botUserId,
                    BotServiceTokenMinter.Scope.WS_CONNECT,
                )
                // Token URL'de tasinmaz: query string proxy/WAF/APM loglarina
                // girer ve orada saatlerce gecerli bir credential birakir.
                val url = "${BotApiConfig.signalingWsUrl}?userId=${BotIdentity.get().botUserId}"
                log.info("[WSClient] Baglaniliyor")
                val req = Request.Builder()
                    .url(url)
                    .header("Authorization", "Bearer $token")
                    .build()

                val ws = client.newWebSocket(req, BotWsListener())
                wsRef.set(ws)

                // Connected oluncaya kadar listener'in onOpen'i bekle (basit: kisa delay + flag check)
                var waited = 0
                while (!connected && !stopping && waited < 50) {
                    delay(100)
                    waited++
                }
                if (connected) {
                    backoffSec = 1L  // reset
                    val botUserId = BotIdentity.get().botUserId
                    drainQueued(botUserId, ws)
                    // connected loop: WS lifecycle listener tarafindan yonetilir; burada
                    // ACK kaybi icin visibility timeout'u periyodik uzlastir.
                    while (connected && !stopping) {
                        delay(1000)
                        runCatching { drainQueued(botUserId, ws) }
                            .onFailure {
                                log.warn("[WSClient] Periyodik drain hatasi: {}", it.javaClass.simpleName)
                            }
                    }
                }
            } catch (e: Exception) {
                log.warn("[WSClient] Baglanti hatasi: {}", e.javaClass.simpleName)
            }

            if (stopping) break

            log.info("[WSClient] {} saniye sonra yeniden denenecek", backoffSec)
            delay(backoffSec * 1000)
            backoffSec = (backoffSec * 2).coerceAtMost(30)
        }
        log.info("[WSClient] reconnect loop durdu")
    }

    internal fun parseMessageAck(text: String): String? =
        runCatching {
            val frame = json.parseToJsonElement(text).jsonObject
            if (frame["type"]?.jsonPrimitive?.contentOrNull != "message_ack") {
                return@runCatching null
            }
            frame["messageId"]?.jsonPrimitive?.contentOrNull
        }
            .getOrNull()
            ?.takeIf { it.isNotBlank() && it.length <= 128 }

    private class BotWsListener : WebSocketListener() {
        override fun onOpen(webSocket: WebSocket, response: Response) {
            connected = true
            log.info("[WSClient] WS acildi (HTTP {})", response.code)
        }
        override fun onMessage(webSocket: WebSocket, text: String) {
            // Bot SEND-ONLY. Tek istisna: sunucunun mesaji gercekten kabul
            // ettigini bildiren ACK. Kuyruk ancak bununla bosalir; soket
            // tamponuna yazmak teslim degildir.
            val ackedId = parseMessageAck(text)
            if (ackedId != null) {
                runCatching { OutboundQueue.acknowledge(BotIdentity.get().botUserId, ackedId) }
                return
            }
            log.debug("[WSClient] Inbound mesaj (gormezden geliniyor): {} byte", text.length)
        }
        override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
            log.warn("[WSClient] WS kapanmak uzere: code={}", code)
            connected = false
            try { webSocket.close(code, reason) } catch (_: Exception) {}
        }
        override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
            log.warn("[WSClient] WS kapali: code={}", code)
            connected = false
        }
        override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
            log.warn("[WSClient] WS hata: {}", t.javaClass.simpleName)
            connected = false
        }
    }
}
