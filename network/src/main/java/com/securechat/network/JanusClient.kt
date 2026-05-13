package com.securechat.network

import android.util.Log
import kotlinx.coroutines.*
import kotlinx.serialization.json.*
import okhttp3.*
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit

/**
 * Janus Gateway WebSocket istemcisi.
 * VideoRoom plugin uzerinden SFU modunda grup arama yonetimi saglar.
 *
 * Akis:
 * 1. connect() → Janus WS bagla
 * 2. createSession() → Janus session al
 * 3. attachVideoRoom() → VideoRoom plugin'ine baglan (handle al)
 * 4. joinAsPublisher() → Odaya publisher olarak katil, mevcut publisher listesi al
 * 5. publishSdp() → Yerel SDP offer'i gonder, Janus'tan answer al
 * 6. subscribeToFeed() → Uzak publisher'a abone ol, Janus'tan offer al
 * 7. answerSubscription() → Subscriber SDP answer'i gonder
 */
class JanusClient(
    /**
     * Shared OkHttpClient — NetworkModule'den inject edilir (certificate pinning + interceptors).
     * JanusClient kendi OkHttp instance'ini olusturmaz, aksi takdirde MITM korumasi atlanir.
     */
    private val sharedClient: OkHttpClient
) {

    companion object {
        private const val TAG = "JanusClient"
        private const val JANUS_TIMEOUT_MS = 10_000L

        /**
         * SDP icindeki private/local IP candidate'lari ve mDNS host'lari kaldirir (M6 fix).
         * RFC 1918 araliklar:  10.0.0.0/8, 172.16-31.x.x, 192.168.0.0/16,
         * Link-local: 169.254.0.0/16, IPv6 fe80::/10
         * mDNS host candidate'lari (.local hostname) — gercek IP'yi gizler ama bilgi sizdirir.
         *
         * Sonuc: sadece public/STUN/TURN relay candidate'lari Janus'a iletilir → LAN topology leak yok.
         */
        internal fun stripPrivateCandidates(sdp: String): String {
            val privateCandidateRegex = Regex(
                """^a=candidate:.*\s(?:10\.\d+\.\d+\.\d+|172\.(?:1[6-9]|2\d|3[01])\.\d+\.\d+|192\.168\.\d+\.\d+|169\.254\.\d+\.\d+|fe80:[0-9a-fA-F:]+|[A-Fa-f0-9.-]+\.local)\s.*$""",
                RegexOption.IGNORE_CASE
            )
            return sdp.lineSequence()
                .filterNot { privateCandidateRegex.matches(it) }
                .joinToString("\r\n")
        }
    }

    private var webSocket: WebSocket? = null
    // Janus icin daha uzun read/write timeout — uzun suren VideoRoom operasyonlari icin.
    // newBuilder() shared client'in pinner+interceptor'larini KORUR.
    private val client = sharedClient.newBuilder()
        .readTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .build()

    private var sessionId: Long = 0
    private var publisherHandleId: Long = 0
    private var roomId: Long = 0

    // Subscriber handle'lari: feedId -> handleId
    private val subscriberHandles = ConcurrentHashMap<Long, Long>()

    // Transaction ID -> CompletableDeferred response
    private val pendingRequests = ConcurrentHashMap<String, CompletableDeferred<JsonObject>>()

    // Event callback'leri
    var onPublisherJoined: ((feedId: Long, displayName: String?) -> Unit)? = null
    var onPublisherLeft: ((feedId: Long) -> Unit)? = null
    var onRemoteSdpOffer: ((feedId: Long, sdp: String) -> Unit)? = null
    var onRemoteSdpAnswer: ((sdp: String) -> Unit)? = null

    @Volatile
    var isConnected = false
        private set

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /**
     * Janus WebSocket sunucusuna baglanir.
     *
     * GUVENLIK: api_secret tabanli auth KALDIRILDI (C2 fix).
     * Janus authentication artik Nginx reverse proxy katmaninda yapilir
     * (Authorization: Bearer JWT). Client mesajlarinda apisecret alani gonderilmez.
     */
    /** Eski apiSecret auth no-op — backward compat icin korundu, hicbir sey yapmaz. */
    @Deprecated("Janus auth Nginx reverse proxy katmaninda yapilir; apiSecret kullanmayin.")
    fun setApiSecret(@Suppress("UNUSED_PARAMETER") secret: String?) {
        // No-op: apisecret artik kullanilmiyor.
    }

    /** JsonObjectBuilder auth — Nginx katmani Authorization header'i set eder, body'de degisiklik yok. */
    private fun JsonObjectBuilder.withAuth() {
        // apisecret artik gonderilmez.
    }

    suspend fun connect(janusWsUrl: String): Boolean {
        val connectDeferred = CompletableDeferred<Boolean>()

        val request = Request.Builder()
            .url(janusWsUrl)
            .addHeader("Sec-WebSocket-Protocol", "janus-protocol")
            .build()

        webSocket = client.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                Log.d(TAG, "Janus WS baglandi: $janusWsUrl")
                isConnected = true
                connectDeferred.complete(true)
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                handleJanusMessage(text)
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                Log.e(TAG, "Janus WS hatasi: ${t.message}")
                isConnected = false
                connectDeferred.complete(false)
                // Bekleyen tum request'leri iptal et
                pendingRequests.forEach { (_, deferred) ->
                    deferred.completeExceptionally(t)
                }
                pendingRequests.clear()
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                Log.d(TAG, "Janus WS kapandi: $reason")
                isConnected = false
            }
        })

        return withTimeout(JANUS_TIMEOUT_MS) { connectDeferred.await() }
    }

    /**
     * Janus session olusturur.
     */
    suspend fun createSession(): Long {
        val txId = newTransaction()
        val msg = buildJsonObject {
            put("janus", "create")
            put("transaction", txId)
            withAuth()
        }
        val response = sendAndWait(txId, msg)
        sessionId = response["data"]?.jsonObject?.get("id")?.jsonPrimitive?.long
            ?: throw RuntimeException("Janus session ID alinamadi")
        Log.d(TAG, "Janus session olusturuldu: $sessionId")

        // Keepalive basalt
        startKeepalive()

        return sessionId
    }

    /**
     * VideoRoom plugin'ine baglanir (attach).
     */
    suspend fun attachVideoRoom(): Long {
        val txId = newTransaction()
        val msg = buildJsonObject {
            put("janus", "attach")
            put("session_id", sessionId)
            put("plugin", "janus.plugin.videoroom")
            put("transaction", txId)
            withAuth()
        }
        val response = sendAndWait(txId, msg)
        publisherHandleId = response["data"]?.jsonObject?.get("id")?.jsonPrimitive?.long
            ?: throw RuntimeException("Janus handle ID alinamadi")
        Log.d(TAG, "VideoRoom plugin baglandi: handle=$publisherHandleId")
        return publisherHandleId
    }

    /**
     * Odaya publisher olarak katilir.
     * @return Mevcut publisher listesi (feedId, displayName)
     */
    suspend fun joinAsPublisher(roomId: Long, displayName: String): List<Pair<Long, String?>> {
        this.roomId = roomId
        val txId = newTransaction()
        val body = buildJsonObject {
            put("request", "join")
            put("room", roomId)
            put("ptype", "publisher")
            put("display", displayName)
        }
        val msg = buildJsonObject {
            put("janus", "message")
            put("session_id", sessionId)
            put("handle_id", publisherHandleId)
            put("transaction", txId)
            put("body", body)
            withAuth()
        }
        val response = sendAndWait(txId, msg)

        // Mevcut publisher listesini parse et
        val pluginData = response["plugindata"]?.jsonObject?.get("data")?.jsonObject
        val publishers = pluginData?.get("publishers")?.jsonArray ?: return emptyList()
        return publishers.map { pub ->
            val obj = pub.jsonObject
            val feedId = obj["id"]?.jsonPrimitive?.long ?: 0
            val display = obj["display"]?.jsonPrimitive?.contentOrNull
            feedId to display
        }.also {
            Log.d(TAG, "Odaya katildi, ${it.size} mevcut publisher")
        }
    }

    /**
     * Yerel SDP offer'i Janus'a gonderir ve SDP answer alir.
     * Publisher olarak medya yayinlamak icin kullanilir.
     */
    suspend fun publishSdp(sdpOffer: String): String {
        val txId = newTransaction()
        // GUVENLIK (M6 fix): SDP'den private/local IP candidate'lari kaldir.
        val sanitizedOffer = stripPrivateCandidates(sdpOffer)
        val body = buildJsonObject {
            put("request", "configure")
            put("audio", true)
            put("video", true)
        }
        val jsep = buildJsonObject {
            put("type", "offer")
            put("sdp", sanitizedOffer)
        }
        val msg = buildJsonObject {
            put("janus", "message")
            put("session_id", sessionId)
            put("handle_id", publisherHandleId)
            put("transaction", txId)
            put("body", body)
            put("jsep", jsep)
            withAuth()
        }
        val response = sendAndWait(txId, msg)
        val answerSdp = response["jsep"]?.jsonObject?.get("sdp")?.jsonPrimitive?.content
            ?: throw RuntimeException("Janus SDP answer alinamadi")
        Log.d(TAG, "Publish SDP answer alindi (${answerSdp.length} byte)")
        return answerSdp
    }

    /**
     * Uzak bir publisher'a abone olur (subscriber).
     * Janus SDP offer gonderir — client answer ile yanit verir.
     *
     * @return SDP offer from Janus
     */
    suspend fun subscribeToFeed(roomId: Long, feedId: Long): String {
        // Yeni subscriber handle attach et
        val handleId = attachSubscriberHandle()
        subscriberHandles[feedId] = handleId

        val txId = newTransaction()
        val body = buildJsonObject {
            put("request", "join")
            put("room", roomId)
            put("ptype", "subscriber")
            put("feed", feedId)
        }
        val msg = buildJsonObject {
            put("janus", "message")
            put("session_id", sessionId)
            put("handle_id", handleId)
            put("transaction", txId)
            put("body", body)
            withAuth()
        }
        val response = sendAndWait(txId, msg)
        val offerSdp = response["jsep"]?.jsonObject?.get("sdp")?.jsonPrimitive?.content
            ?: throw RuntimeException("Janus subscriber SDP offer alinamadi")
        Log.d(TAG, "Subscriber SDP offer alindi: feedId=$feedId (${offerSdp.length} byte)")
        return offerSdp
    }

    /**
     * Subscriber SDP answer'i Janus'a gonderir.
     */
    suspend fun answerSubscription(feedId: Long, sdpAnswer: String) {
        val handleId = subscriberHandles[feedId]
            ?: throw RuntimeException("Subscriber handle bulunamadi: feedId=$feedId")

        val txId = newTransaction()
        // GUVENLIK (M6 fix): SDP'den private/local IP candidate'lari kaldir.
        val sanitizedAnswer = stripPrivateCandidates(sdpAnswer)
        val body = buildJsonObject {
            put("request", "start")
            put("room", roomId)
        }
        val jsep = buildJsonObject {
            put("type", "answer")
            put("sdp", sanitizedAnswer)
        }
        val msg = buildJsonObject {
            put("janus", "message")
            put("session_id", sessionId)
            put("handle_id", handleId)
            put("transaction", txId)
            put("body", body)
            put("jsep", jsep)
            withAuth()
        }
        sendAndWait(txId, msg)
        Log.d(TAG, "Subscriber answer gonderildi: feedId=$feedId")
    }

    /**
     * Janus'a ICE candidate trickle gonderir.
     * handleType: "publisher" -> publisherHandleId; "subscriber:<feedId>" -> subscriberHandles[feedId]
     */
    fun trickleIce(handleId: Long, sdpMid: String?, sdpMLineIndex: Int, candidate: String) {
        // GUVENLIK (M6 fix): Private/local IP candidate'i Janus'a iletme.
        // Tek satirlik candidate string'i regex ile dogrula.
        val privateCandidateRegex = Regex(
            """.*\s(?:10\.\d+\.\d+\.\d+|172\.(?:1[6-9]|2\d|3[01])\.\d+\.\d+|192\.168\.\d+\.\d+|169\.254\.\d+\.\d+|fe80:[0-9a-fA-F:]+|[A-Fa-f0-9.-]+\.local)\s.*""",
            RegexOption.IGNORE_CASE
        )
        if (privateCandidateRegex.matches(candidate)) {
            Log.d(TAG, "Private candidate filtrelendi (M6 fix)")
            return
        }
        val txId = newTransaction()
        val candObj = buildJsonObject {
            put("candidate", candidate)
            sdpMid?.let { put("sdpMid", it) }
            put("sdpMLineIndex", sdpMLineIndex)
        }
        val msg = buildJsonObject {
            put("janus", "trickle")
            put("session_id", sessionId)
            put("handle_id", handleId)
            put("transaction", txId)
            put("candidate", candObj)
            withAuth()
        }
        // Trickle async — yanit beklenmez
        webSocket?.send(msg.toString())
    }

    fun trickleIceCompleted(handleId: Long) {
        val txId = newTransaction()
        val msg = buildJsonObject {
            put("janus", "trickle")
            put("session_id", sessionId)
            put("handle_id", handleId)
            put("transaction", txId)
            put("candidate", buildJsonObject { put("completed", true) })
            withAuth()
        }
        webSocket?.send(msg.toString())
    }

    /** Publisher handle ID'sini doner — trickle ICE icin. */
    fun getPublisherHandleId(): Long = publisherHandleId

    /** Subscriber handle ID'sini doner — trickle ICE icin. */
    fun getSubscriberHandleId(feedId: Long): Long? = subscriberHandles[feedId]

    /** VideoRoom'dan ayrilma — best-effort. */
    suspend fun leaveRoom() {
        if (publisherHandleId == 0L || sessionId == 0L) return
        val txId = newTransaction()
        val body = buildJsonObject {
            put("request", "leave")
        }
        val msg = buildJsonObject {
            put("janus", "message")
            put("session_id", sessionId)
            put("handle_id", publisherHandleId)
            put("transaction", txId)
            put("body", body)
            withAuth()
        }
        try { sendAndWait(txId, msg) } catch (_: Exception) { /* best-effort */ }
    }

    /**
     * Subscriber icin yeni handle attach eder.
     */
    private suspend fun attachSubscriberHandle(): Long {
        val txId = newTransaction()
        val msg = buildJsonObject {
            put("janus", "attach")
            put("session_id", sessionId)
            put("plugin", "janus.plugin.videoroom")
            put("transaction", txId)
            withAuth()
        }
        val response = sendAndWait(txId, msg)
        val handleId = response["data"]?.jsonObject?.get("id")?.jsonPrimitive?.long
            ?: throw RuntimeException("Subscriber handle ID alinamadi")
        Log.d(TAG, "Subscriber handle olusturuldu: $handleId")
        return handleId
    }

    /**
     * Janus session'i canli tutmak icin periyodik keepalive gonderir.
     */
    private fun startKeepalive() {
        scope.launch {
            while (isActive && isConnected) {
                delay(25_000) // Janus varsayilan session timeout 60sn
                if (!isConnected) break
                val msg = buildJsonObject {
                    put("janus", "keepalive")
                    put("session_id", sessionId)
                    put("transaction", newTransaction())
                    withAuth()
                }
                webSocket?.send(msg.toString())
            }
        }
    }

    /**
     * Gelen Janus mesajini isler.
     * Transaction-based response'lar ilgili CompletableDeferred'a yonlendirilir.
     * Asenkron event'ler (publisher join/leave) callback'lere iletilir.
     */
    private fun handleJanusMessage(text: String) {
        try {
            val json = Json.parseToJsonElement(text).jsonObject
            val janus = json["janus"]?.jsonPrimitive?.contentOrNull

            // Transaction-based response
            val txId = json["transaction"]?.jsonPrimitive?.contentOrNull
            if (txId != null && pendingRequests.containsKey(txId)) {
                val deferred = pendingRequests.remove(txId)
                if (janus == "error") {
                    val errorMsg = json["error"]?.jsonObject?.get("reason")?.jsonPrimitive?.contentOrNull ?: "Unknown error"
                    deferred?.completeExceptionally(RuntimeException("Janus error: $errorMsg"))
                } else {
                    deferred?.complete(json)
                }
                return
            }

            // Asenkron event'ler
            when (janus) {
                "event" -> handleEvent(json)
                "webrtcup" -> Log.d(TAG, "WebRTC baglantisi kuruldu")
                "hangup" -> Log.d(TAG, "Janus hangup alindi")
                "detached" -> Log.d(TAG, "Handle detach edildi")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Janus mesaj parse hatasi: ${e.message}")
        }
    }

    /**
     * Janus plugin event'lerini isler.
     * - publishers: Yeni publisher katildi
     * - unpublished/leaving: Publisher ayrildi
     * - jsep (subscriber icin): Janus'tan SDP offer
     */
    private fun handleEvent(json: JsonObject) {
        val pluginData = json["plugindata"]?.jsonObject?.get("data")?.jsonObject ?: return

        // Yeni publisher'lar
        val publishers = pluginData["publishers"]?.jsonArray
        if (publishers != null) {
            for (pub in publishers) {
                val obj = pub.jsonObject
                val feedId = obj["id"]?.jsonPrimitive?.long ?: continue
                val display = obj["display"]?.jsonPrimitive?.contentOrNull
                Log.d(TAG, "Yeni publisher: feedId=$feedId, display=$display")
                onPublisherJoined?.invoke(feedId, display)
            }
        }

        // Publisher ayrildi
        val unpublished = pluginData["unpublished"]?.jsonPrimitive?.longOrNull
        if (unpublished != null) {
            Log.d(TAG, "Publisher ayrildi: feedId=$unpublished")
            subscriberHandles.remove(unpublished)
            onPublisherLeft?.invoke(unpublished)
        }

        val leaving = pluginData["leaving"]?.jsonPrimitive?.longOrNull
        if (leaving != null) {
            Log.d(TAG, "Katilimci ayrildi: feedId=$leaving")
            subscriberHandles.remove(leaving)
            onPublisherLeft?.invoke(leaving)
        }

        // Subscriber icin Janus'tan SDP offer (async event olarak gelebilir)
        val jsep = json["jsep"]?.jsonObject
        if (jsep != null) {
            val type = jsep["type"]?.jsonPrimitive?.contentOrNull
            val sdp = jsep["sdp"]?.jsonPrimitive?.contentOrNull
            if (type == "offer" && sdp != null) {
                // Hangi feed'e ait oldugunu bul
                val senderHandleId = json["sender"]?.jsonPrimitive?.longOrNull
                if (senderHandleId != null) {
                    val feedId = subscriberHandles.entries.find { it.value == senderHandleId }?.key
                    if (feedId != null) {
                        onRemoteSdpOffer?.invoke(feedId, sdp)
                    }
                }
            } else if (type == "answer" && sdp != null) {
                onRemoteSdpAnswer?.invoke(sdp)
            }
        }
    }

    /**
     * Mesaj gonderir ve yanit bekler.
     */
    private suspend fun sendAndWait(txId: String, msg: JsonObject): JsonObject {
        val deferred = CompletableDeferred<JsonObject>()
        pendingRequests[txId] = deferred
        val sent = webSocket?.send(msg.toString()) ?: false
        if (!sent) {
            pendingRequests.remove(txId)
            throw RuntimeException("Janus mesaj gonderilemedi")
        }
        return withTimeout(JANUS_TIMEOUT_MS) { deferred.await() }
    }

    private fun newTransaction(): String = UUID.randomUUID().toString().take(12)

    /**
     * Tum kaynaklari temizler ve baglanitiyi kapatir.
     */
    fun disconnect() {
        scope.cancel()
        isConnected = false
        pendingRequests.forEach { (_, deferred) ->
            deferred.cancel()
        }
        pendingRequests.clear()
        subscriberHandles.clear()
        webSocket?.close(1000, "Client disconnect")
        webSocket = null
        sessionId = 0
        publisherHandleId = 0
        onPublisherJoined = null
        onPublisherLeft = null
        onRemoteSdpOffer = null
        onRemoteSdpAnswer = null
        Log.d(TAG, "Janus client disconnect edildi")
    }
}
