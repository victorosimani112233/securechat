package com.securechat.botapi.delivery

import com.securechat.botapi.BotApiConfig
import com.securechat.botapi.signal.BotIdentity
import com.securechat.botapi.signal.BotServiceTokenMinter
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
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

    /**
     * Mesaji WS'ye gönderir. WS up değilse OutboundQueue'ya yazar — yine de
     * true döner (delivery garanti edildi: ya doğrudan ya da queue'dan).
     */
    fun send(envelopeJson: String): Boolean {
        val ws = wsRef.get()
        if (connected && ws != null) {
            val ok = ws.send(envelopeJson)
            if (!ok) {
                log.warn("[WSClient] send() false donduy — OutboundQueue'ya yaziliyor")
                OutboundQueue.enqueue(BotIdentity.get().botUserId, envelopeJson)
            }
            return true
        }
        OutboundQueue.enqueue(BotIdentity.get().botUserId, envelopeJson)
        log.debug("[WSClient] WS down — queue'a yazildi")
        return true
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
                    OutboundQueue.drainAll(BotIdentity.get().botUserId) { msg ->
                        ws.send(msg)
                    }
                    // connected loop: WS lifecycle listener tarafindan yonetilir; burada
                    // sadece disconnect olana kadar uyu
                    while (connected && !stopping) {
                        delay(1000)
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

    private class BotWsListener : WebSocketListener() {
        override fun onOpen(webSocket: WebSocket, response: Response) {
            connected = true
            log.info("[WSClient] WS acildi (HTTP {})", response.code)
        }
        override fun onMessage(webSocket: WebSocket, text: String) {
            // Bot SEND-ONLY: gelen mesajlar yok sayilir. Sadece debug.
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
