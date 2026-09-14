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

    // GUVENLIK: Production'da JANUS_API_SECRET ve JANUS_ADMIN_SECRET env zorunlu (H6 fix).
    // Default fallback artik yok — env yoksa uygulama start'ta crash eder.
    // Bu Janus admin API'sine yetkisiz erisimi tamamen onler.
    private val janusApiSecret = requireSecret("JANUS_API_SECRET")
    private val janusAdminSecret = requireSecret("JANUS_ADMIN_SECRET")

    private fun requireSecret(envName: String): String {
        val value = SecretSource.required(envName)
        check(value.length >= 16) {
            "$envName cok kisa (${value.length} char). En az 16, ideal 32+ char random secret kullan."
        }
        check(value != "janusoverlord" && value != "securechat_janus_api") {
            "$envName default/sample value kullaniyor. " +
            "Random secret ile degistir: openssl rand -base64 32"
        }
        return value
    }

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
     * Tek reconnect sahibi.
     *
     * Onceki kodda `onClose` ve `onError` ayri ayri reconnect baslatiyor,
     * catch blogu da ozyinelemeli olarak yeniden deniyordu; tek bir kopmada
     * birden fazla baglanti dongusu ureyebiliyordu.
     */
    private val reconnecting = java.util.concurrent.atomic.AtomicBoolean(false)

    /** Keepalive olmadan Janus oturumu kendiliginden zaman asimina ugrar. */
    private var keepAliveJob: kotlinx.coroutines.Job? = null
    private val keepAliveIntervalMillis = 30_000L

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
                    log.info("[Janus] WebSocket baglantisi kuruldu")
                    webSocket.request(1)
                }

                override fun onClose(webSocket: WebSocket, statusCode: Int, reason: String): CompletionStage<*>? {
                    connected = false
                    log.info("[Janus] WebSocket kapandi; status={}", statusCode)
                    scheduleReconnect()
                    return null
                }

                override fun onError(webSocket: WebSocket, error: Throwable) {
                    connected = false
                    log.warn("[!] Janus WebSocket hatasi: ${error.javaClass.simpleName}")
                    scheduleReconnect()
                }
            }).join()
            startKeepAlive()
        } catch (e: Exception) {
            log.warn("[!] Janus baglanti hatasi: ${e.javaClass.simpleName}")
            scheduleReconnect()
        }
    }

    /**
     * Kopan baglantiyi tek bir dongude yeniden kurar ve bekleyen istekleri
     * serbest birakir. Aksi halde `sendAndWait` cagrilari timeout'a kadar
     * asili kalirdi.
     */
    private fun scheduleReconnect() {
        failPendingRequests()
        if (!reconnecting.compareAndSet(false, true)) return
        scope.launch {
            try {
                delay(5000)
                connectToJanus()
            } finally {
                reconnecting.set(false)
            }
        }
    }

    /** Bekleyen istek sayisi — sizinti kontrolu icin gorunur. */
    internal fun pendingRequestCount(): Int = pendingRequests.size

    internal fun failPendingRequests() {
        val pending = pendingRequests.keys.toList()
        for (transaction in pending) {
            pendingRequests.remove(transaction)?.completeExceptionally(
                IllegalStateException("Janus connection lost"),
            )
        }
        if (pending.isNotEmpty()) {
            log.warn("[Janus] {} bekleyen istek baglanti kopmasiyla dusuruldu", pending.size)
        }
    }

    /** Janus oturumlari keepalive gelmezse kendiliginden kapanir. */
    private fun startKeepAlive() {
        keepAliveJob?.cancel()
        keepAliveJob = scope.launch {
            while (true) {
                delay(keepAliveIntervalMillis)
                if (!connected) continue
                for (sessionId in sessions.values.toList()) {
                    val message = buildJsonObject {
                        put("janus", "keepalive")
                        put("session_id", sessionId)
                        put("transaction", nextTransaction())
                        put("apisecret", janusApiSecret)
                    }
                    runCatching { ws?.sendText(message.toString(), true) }
                }
            }
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
            log.warn("[!] Janus mesaj parse hatasi: ${e.javaClass.simpleName}")
        }
    }

    /**
     * Janus'a mesaj gonderir ve yanit bekler.
     */
    internal suspend fun sendAndWait(message: JsonObject, timeoutMs: Long = 10_000): JsonObject {
        val transaction = message["transaction"]?.jsonPrimitive?.contentOrNull
            ?: throw IllegalArgumentException("transaction alani gerekli")

        val deferred = CompletableDeferred<JsonObject>()
        pendingRequests[transaction] = deferred
        try {
            val text = message.toString()
            ws?.sendText(text, true) ?: throw IllegalStateException("Janus WS bagli degil")
            return withTimeout(timeoutMs) { deferred.await() }
        } finally {
            // Timeout veya gonderim hatasinda kayit birakilirsa harita yalniz
            // buyur ve hicbir zaman temizlenmezdi.
            pendingRequests.remove(transaction)
        }
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
        log.info("[Janus] Session olusturuldu")
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
        log.info("[Janus] VideoRoom handle hazir")
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
    private const val ROOM_ID_ATTEMPTS = 16
    private val roomIdRandom = java.security.SecureRandom()

    /**
     * Oda kimligi tahmin edilemez olmalidir.
     *
     * Artan bir sayac, baska bir grubun odasina katilma girisimini onemsiz
     * hale getirirdi; kimlik 62 bit rastgeledir ve carpisma kontrol edilir.
     */
    internal fun nextRoomId(): Long {
        repeat(ROOM_ID_ATTEMPTS) {
            val candidate = roomIdRandom.nextLong() and 0x3FFF_FFFF_FFFF_FFFFL
            if (candidate != 0L && !activeRooms.containsValue(candidate)) return candidate
        }
        error("Janus room id could not be allocated without a collision")
    }

    suspend fun createVideoRoom(groupId: String, maxParticipants: Int = 50): Long {
        // Zaten varsa mevcut room'u don
        activeRooms[groupId]?.let { return it }

        val sessionId = createSession()
        sessions[groupId] = sessionId

        val handleId = attachVideoRoom(sessionId)
        handles[groupId] = handleId

        // Room ID grup kimliginden turetilmez: `groupId.hashCode()` 31 bitlik,
        // cakismaya acik ve grup routing tokenini bilen biri tarafindan
        // onceden hesaplanabilir bir degerdi. Bunun yerine aktif odalarla
        // cakismayan 62-bit rastgele bir deger uretilir.
        val roomId = nextRoomId()
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
                put("description", "SecureChat private group")
            }
        }

        val response = sendAndWait(request)
        val pluginData = response["plugindata"]?.jsonObject?.get("data")?.jsonObject
        val createdRoomId = pluginData?.get("room")?.jsonPrimitive?.long ?: roomId

        activeRooms[groupId] = createdRoomId
        log.info("[Janus] VideoRoom olusturuldu")
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
            log.info("[Janus] VideoRoom silindi")
        } catch (e: Exception) {
            log.warn("[!] Janus room destroy hatasi: ${e.javaClass.simpleName}")
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
        } catch (_: Exception) { /* best-effort teardown */ }
    }

    /**
     * Belirli bir grup icin SFU room bilgisini doner.
     * Client bu bilgiyi kullanarak Janus'a dogrudan baglanir.
     *
     * GUVENLIK: apiSecret client'a ASLA gonderilmez (C2 fix).
     * Janus public endpoint (Nginx reverse proxy) anonymous baglantiyi kabul etmeli
     * veya per-session token plugin'i ile authentication yapilmali. apiSecret server-internal.
     *
     * @return null ise room henuz olusturulmamis
     */
    fun getRoomInfo(groupId: String): SfuRoomInfo? {
        val roomId = activeRooms[groupId] ?: return null
        return SfuRoomInfo(
            roomId = roomId,
            janusWsUrl = System.getenv("JANUS_PUBLIC_WS_URL")
                ?: error("JANUS_PUBLIC_WS_URL env tanimlanmamis — production'da zorunlu (wss:// + reverse proxy)")
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
 *
 * GUVENLIK: apiSecret alani BURADAN KALDIRILDI (C2 fix).
 * Janus admin api_secret asla client'a sizdirilmaz. Authentication ya Nginx reverse proxy
 * katmaninda (JWT validation) ya da Janus token plugin'i ile yapilir.
 */
data class SfuRoomInfo(
    val roomId: Long,
    val janusWsUrl: String
)
