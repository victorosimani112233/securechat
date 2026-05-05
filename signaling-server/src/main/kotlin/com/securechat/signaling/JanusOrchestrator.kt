package com.securechat.signaling

import kotlinx.coroutines.*
import kotlinx.serialization.json.*
import java.net.URI
import java.net.http.HttpClient
import java.net.http.WebSocket
import java.net.http.WebSocket.Listener
import java.util.concurrent.CompletionStage
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong
import org.slf4j.LoggerFactory

private val log = LoggerFactory.getLogger("JanusOrchestrator")

/**
 * Janus Gateway ile WebSocket uzerinden iletisim kurar.
 * Grup aramalari icin VideoRoom olusturma/silme ve katilimci yonetimi.
 *
 * Akis:
 * 1. Grup aramasi basladiginda → createVideoRoom(groupId)
 * 2. Katilimci geldiginde → attachPlugin() + joinRoom()
 * 3. Arama bittiginde → destroyVideoRoom(groupId)
 *
 * SFU threshold: >=4 katilimci → SFU mode, <4 → mesh mode (client tarafinda karar verilir)
 */
object JanusOrchestrator {

    private val janusWsUrl = System.getenv("JANUS_WS_URL") ?: "ws://localhost:8188"
    private val janusApiSecret = System.getenv("JANUS_API_SECRET") ?: "securechat_janus_api"
    private val janusAdminSecret = System.getenv("JANUS_ADMIN_SECRET") ?: "janusoverlord"

    private val transactionCounter = AtomicLong(0)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    // groupId -> Janus room ID
    private val activeRooms = ConcurrentHashMap<String, Long>()
    // groupId -> Janus session ID
    private val sessions = ConcurrentHashMap<String, Long>()
    // groupId -> Janus plugin handle ID
    private val handles = ConcurrentHashMap<String, Long>()

    // Janus WebSocket baglantisi
    @Volatile
    private var ws: WebSocket? = null
    @Volatile
    private var connected = false

    // Bekleyen yanit callback'leri: transaction -> CompletableDeferred
    private val pendingRequests = ConcurrentHashMap<String, CompletableDeferred<JsonObject>>()

    /**
     * Janus Gateway'e WebSocket baglantisi kurar.
     * Sunucu baslatildiginda cagrilir.
     */
    fun init() {
        scope.launch {
            connectToJanus()
        }
    }

    private suspend fun connectToJanus() {
        try {
            val client = HttpClient.newHttpClient()
            val wsBuilder = client.newWebSocketBuilder()
                .subprotocols("janus-protocol")

            ws = wsBuilder.buildAsync(URI.create(janusWsUrl), object : Listener {
                private val buffer = StringBuilder()

                override fun onText(webSocket: WebSocket, data: CharSequence, last: Boolean): CompletionStage<*>? {
                    buffer.append(data)
                    if (last) {
                        val text = buffer.toString()
                        buffer.clear()
                        handleJanusMessage(text)
                    }
                    webSocket.request(1)
                    return null
                }

                override fun onOpen(webSocket: WebSocket) {
                    connected = true
                    log.info("[Janus] WebSocket baglantisi kuruldu: $janusWsUrl")
                    webSocket.request(1)
                }

                override fun onClose(webSocket: WebSocket, statusCode: Int, reason: String): CompletionStage<*>? {
                    connected = false
                    log.info("[Janus] WebSocket kapandi: $statusCode $reason")
                    // Yeniden baglan
                    scope.launch {
                        delay(5000)
                        connectToJanus()
                    }
                    return null
                }

                override fun onError(webSocket: WebSocket, error: Throwable) {
                    connected = false
                    log.warn("[!] Janus WebSocket hatasi: ${error.message}")
                    scope.launch {
                        delay(5000)
                        connectToJanus()
                    }
                }
            }).join()
        } catch (e: Exception) {
            log.warn("[!] Janus baglanti hatasi: ${e.message}")
            delay(5000)
            connectToJanus()
        }
    }

    private fun handleJanusMessage(text: String) {
        try {
            val json = Json.parseToJsonElement(text).jsonObject
            val transaction = json["transaction"]?.jsonPrimitive?.contentOrNull

            // Transaction'a bagli yanit varsa callback'e ilet
            if (transaction != null) {
                val deferred = pendingRequests.remove(transaction)
                deferred?.complete(json)
            }
        } catch (e: Exception) {
            log.warn("[!] Janus mesaj parse hatasi: ${e.message}")
        }
    }

    /**
     * Janus'a mesaj gonderir ve yanit bekler.
     */
    private suspend fun sendAndWait(message: JsonObject, timeoutMs: Long = 10_000): JsonObject {
        val transaction = message["transaction"]?.jsonPrimitive?.contentOrNull
            ?: throw IllegalArgumentException("transaction alani gerekli")

        val deferred = CompletableDeferred<JsonObject>()
        pendingRequests[transaction] = deferred

        val text = message.toString()
        ws?.sendText(text, true) ?: throw IllegalStateException("Janus WS bagli degil")

        return withTimeout(timeoutMs) { deferred.await() }
    }

    private fun nextTransaction(): String = "txn_${transactionCounter.incrementAndGet()}"

    /**
     * Janus session olusturur.
     */
    private suspend fun createSession(): Long {
        val txn = nextTransaction()
        val request = buildJsonObject {
            put("janus", "create")
            put("transaction", txn)
            put("apisecret", janusApiSecret)
        }
        val response = sendAndWait(request)
        val sessionId = response["data"]?.jsonObject?.get("id")?.jsonPrimitive?.long
            ?: throw RuntimeException("Janus session olusturulamadi: $response")
        log.info("[Janus] Session olusturuldu: $sessionId")
        return sessionId
    }

    /**
     * VideoRoom plugin'ine attach olur.
     */
    private suspend fun attachVideoRoom(sessionId: Long): Long {
        val txn = nextTransaction()
        val request = buildJsonObject {
            put("janus", "attach")
            put("session_id", sessionId)
            put("plugin", "janus.plugin.videoroom")
            put("transaction", txn)
            put("apisecret", janusApiSecret)
        }
        val response = sendAndWait(request)
        val handleId = response["data"]?.jsonObject?.get("id")?.jsonPrimitive?.long
            ?: throw RuntimeException("VideoRoom attach basarisiz: $response")
        log.info("[Janus] VideoRoom handle: $handleId (session: $sessionId)")
        return handleId
    }

    /**
     * Yeni VideoRoom olusturur.
     * Grup aramasi basladiginda cagrilir.
     *
     * @param groupId Grup kimlik numarasi
     * @param maxParticipants Maksimum katilimci sayisi
     * @return Janus room ID
     */
    suspend fun createVideoRoom(groupId: String, maxParticipants: Int = 50): Long {
        // Zaten varsa mevcut room'u don
        activeRooms[groupId]?.let { return it }

        val sessionId = createSession()
        sessions[groupId] = sessionId

        val handleId = attachVideoRoom(sessionId)
        handles[groupId] = handleId

        val roomId = groupId.hashCode().toLong().and(0x7FFFFFFF) // pozitif int
        val txn = nextTransaction()

        val request = buildJsonObject {
            put("janus", "message")
            put("session_id", sessionId)
            put("handle_id", handleId)
            put("transaction", txn)
            put("apisecret", janusApiSecret)
            putJsonObject("body") {
                put("request", "create")
                put("room", roomId)
                put("publishers", maxParticipants)
                put("bitrate", 512000) // 512kbps max per publisher
                put("fir_freq", 10)
                put("videocodec", "vp8")
                put("audiocodec", "opus")
                put("record", false)
                put("admin_key", janusAdminSecret)
                put("description", "SecureChat group: $groupId")
            }
        }

        val response = sendAndWait(request)
        val pluginData = response["plugindata"]?.jsonObject?.get("data")?.jsonObject
        val createdRoomId = pluginData?.get("room")?.jsonPrimitive?.long ?: roomId

        activeRooms[groupId] = createdRoomId
        log.info("[Janus] VideoRoom olusturuldu: $groupId -> room=$createdRoomId")
        return createdRoomId
    }

    /**
     * VideoRoom'u siler.
     * Grup aramasi bittiginde cagrilir.
     */
    suspend fun destroyVideoRoom(groupId: String) {
        val roomId = activeRooms.remove(groupId) ?: return
        val sessionId = sessions.remove(groupId) ?: return
        val handleId = handles.remove(groupId) ?: return

        try {
            val txn = nextTransaction()
            val request = buildJsonObject {
                put("janus", "message")
                put("session_id", sessionId)
                put("handle_id", handleId)
                put("transaction", txn)
                put("apisecret", janusApiSecret)
                putJsonObject("body") {
                    put("request", "destroy")
                    put("room", roomId)
                }
            }
            sendAndWait(request, 5000)
            log.info("[Janus] VideoRoom silindi: $groupId (room=$roomId)")
        } catch (e: Exception) {
            log.warn("[!] Janus room destroy hatasi: ${e.message}")
        }

        // Session'i da kapat
        try {
            val txn = nextTransaction()
            val destroySession = buildJsonObject {
                put("janus", "destroy")
                put("session_id", sessionId)
                put("transaction", txn)
                put("apisecret", janusApiSecret)
            }
            sendAndWait(destroySession, 5000)
        } catch (_: Exception) { }
    }

    /**
     * Belirli bir grup icin SFU room bilgisini doner.
     * Client bu bilgiyi kullanarak Janus'a dogrudan baglanir.
     *
     * @return null ise room henuz olusturulmamis
     */
    fun getRoomInfo(groupId: String): SfuRoomInfo? {
        val roomId = activeRooms[groupId] ?: return null
        return SfuRoomInfo(
            roomId = roomId,
            janusWsUrl = System.getenv("JANUS_PUBLIC_WS_URL") ?: "ws://185.48.182.124:8188",
            apiSecret = janusApiSecret
        )
    }

    /**
     * Aktif room var mi kontrol eder.
     */
    fun hasActiveRoom(groupId: String): Boolean = activeRooms.containsKey(groupId)

    /**
     * Tum aktif room'lari kapatir (graceful shutdown icin).
     */
    suspend fun destroyAllRooms() {
        val groups = activeRooms.keys.toList()
        for (groupId in groups) {
            destroyVideoRoom(groupId)
        }
        log.info("[Janus] Tum room'lar kapatildi (${groups.size})")
    }

    fun isConnected(): Boolean = connected
}

/**
 * SFU room bilgisi — client'a gonderilir.
 */
data class SfuRoomInfo(
    val roomId: Long,
    val janusWsUrl: String,
    val apiSecret: String
)
