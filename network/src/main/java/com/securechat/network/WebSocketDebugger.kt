package com.securechat.network

import android.util.Log
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import java.util.concurrent.TimeUnit

/**
 * WebSocket bağlantı sorunlarını debug etmek için utility sınıfı.
 *
 * Bu sınıf:
 * - WebSocket handshake sürecini detaylı loglar
 * - HTTP vs WebSocket protokol farklarını analiz eder
 * - Server compatibility sorunlarını tespit eder
 *
 * DEBUG KULLANIMI:
 * ```
 * val debugger = WebSocketDebugger()
 * debugger.testWebSocketConnection("ws://16.171.233.101:9090", "901234567890", "token_901234567890")
 * ```
 */
class WebSocketDebugger {

    private val okHttpClient = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(10, TimeUnit.SECONDS)
        .build()

    /**
     * WebSocket bağlantısını test eder ve detaylı debug bilgisi çıktısı verir.
     *
     * @param baseUrl WebSocket server URL'i (ws:// veya wss://)
     * @param userId Test user ID'si
     * @param authToken Authorization token'i
     */
    fun testWebSocketConnection(
        baseUrl: String,
        userId: String,
        authToken: String
    ) {
        Log.d("SecureChat", "🔍 === WebSocket DEBUG SESSION STARTED ===")
        Log.d("SecureChat", "Target server: $baseUrl")
        Log.d("SecureChat", "User ID: $userId")
        // GUVENLIK (M4 fix): Auth token (10 char bile) loglanmaz — token enumeration kolaylasir.
        Log.d("SecureChat", "Auth token: [REDACTED]")

        val wsUrl = "$baseUrl/ws?userId=$userId"
        Log.d("SecureChat", "Full WebSocket URL: $wsUrl")

        val request = Request.Builder()
            .url(wsUrl)
            .addHeader("Authorization", "Bearer $authToken")
            .addHeader("User-Agent", "SecureChat-Android/1.0")
            .build()

        // GUVENLIK (M4 fix): Request header'lari token icerir — loglanmaz.
        Log.d("SecureChat", "📤 Request headers: [REDACTED — Authorization header icerir]")

        val webSocket = okHttpClient.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                Log.d("SecureChat", "✅ WebSocket connection SUCCESS!")
                Log.d("SecureChat", "📥 RESPONSE DETAILS:")
                Log.d("SecureChat", "  Status: ${response.code} ${response.message}")
                Log.d("SecureChat", "  Protocol: ${response.protocol}")
                // GUVENLIK (M4 fix): Response header'lari Set-Cookie veya echo'lanmis Authorization icerebilir.
                Log.d("SecureChat", "📥 Response headers: [REDACTED]")

                // Test bir mesaj gönder
                val testMessage = """{"type":"ping","timestamp":${System.currentTimeMillis()}}"""
                Log.d("SecureChat", "📤 Sending test message: $testMessage")
                webSocket.send(testMessage)

                // Bağlantıyı 5 saniye sonra kapat
                Thread {
                    Thread.sleep(5000)
                    Log.d("SecureChat", "🔚 Closing test WebSocket connection")
                    webSocket.close(1000, "Debug test completed")
                }.start()
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                Log.d("SecureChat", "📨 WebSocket message received:")
                Log.d("SecureChat", "  Content: ${text.take(200)}...")
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                Log.e("SecureChat", "❌ WebSocket connection FAILED!")

                // Exception detayları
                Log.e("SecureChat", "💥 EXCEPTION DETAILS:")
                Log.e("SecureChat", "  Type: ${t.javaClass.simpleName}")
                Log.e("SecureChat", "  Message: ${t.message}")

                // HTTP response varsa detayları
                if (response != null) {
                    Log.e("SecureChat", "📥 HTTP RESPONSE:")
                    Log.e("SecureChat", "  Status: ${response.code} ${response.message}")
                    Log.e("SecureChat", "  Protocol: ${response.protocol}")
                    // GUVENLIK (M4 fix): Response header'lari hassas bilgi icerebilir.
                    Log.e("SecureChat", "📥 Response headers: [REDACTED]")

                    try {
                        val body = response.body?.string()
                        if (!body.isNullOrEmpty()) {
                            Log.e("SecureChat", "📥 RESPONSE BODY:")
                            Log.e("SecureChat", "  ${body.take(500)}...")
                        }
                    } catch (e: Exception) {
                        Log.e("SecureChat", "Could not read response body: ${e.message}")
                    }
                } else {
                    Log.e("SecureChat", "📥 No HTTP response (connection failed before handshake)")
                }

                // Stack trace
                Log.e("SecureChat", "📚 STACK TRACE:")
                Log.e("SecureChat", t.stackTraceToString())

                analyzeConnectionFailure(t, response)
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                Log.d("SecureChat", "🔚 WebSocket connection closed")
                Log.d("SecureChat", "  Close code: $code")
                Log.d("SecureChat", "  Reason: $reason")
                Log.d("SecureChat", "🔍 === WebSocket DEBUG SESSION ENDED ===")
            }

            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                Log.w("SecureChat", "⚠️ WebSocket connection closing...")
                Log.w("SecureChat", "  Close code: $code")
                Log.w("SecureChat", "  Reason: $reason")
            }
        })
    }

    /**
     * WebSocket bağlantı hatasını analiz eder ve olası çözümler önerir.
     */
    private fun analyzeConnectionFailure(throwable: Throwable, response: Response?) {
        Log.w("SecureChat", "🔧 === CONNECTION FAILURE ANALYSIS ===")

        when {
            throwable is java.net.ConnectException -> {
                Log.w("SecureChat", "❌ CONNECTION REFUSED")
                Log.w("SecureChat", "Possible causes:")
                Log.w("SecureChat", "  - Server is not running")
                Log.w("SecureChat", "  - Wrong port number")
                Log.w("SecureChat", "  - Firewall blocking connection")
                Log.w("SecureChat", "  - Server only accepting localhost connections")
            }

            throwable is java.net.SocketTimeoutException -> {
                Log.w("SecureChat", "❌ CONNECTION TIMEOUT")
                Log.w("SecureChat", "Possible causes:")
                Log.w("SecureChat", "  - Server is overloaded")
                Log.w("SecureChat", "  - Network connectivity issues")
                Log.w("SecureChat", "  - Proxy/NAT blocking connection")
            }

            response?.code == 404 -> {
                Log.w("SecureChat", "❌ HTTP 404 - WebSocket endpoint not found")
                Log.w("SecureChat", "Possible causes:")
                Log.w("SecureChat", "  - Wrong WebSocket path (check /ws)")
                Log.w("SecureChat", "  - Server routing misconfiguration")
                Log.w("SecureChat", "  - WebSocket handler not registered")
            }

            response?.code == 401 || response?.code == 403 -> {
                Log.w("SecureChat", "❌ HTTP ${response.code} - Authentication failed")
                Log.w("SecureChat", "Possible causes:")
                Log.w("SecureChat", "  - Invalid Authorization token")
                Log.w("SecureChat", "  - Token format incorrect (missing 'Bearer ')")
                Log.w("SecureChat", "  - Server not recognizing authorization header")
            }

            response?.code in 400..499 -> {
                Log.w("SecureChat", "❌ HTTP ${response?.code} - Client error")
                Log.w("SecureChat", "Possible causes:")
                Log.w("SecureChat", "  - Malformed WebSocket handshake request")
                Log.w("SecureChat", "  - Missing required headers")
                Log.w("SecureChat", "  - Invalid query parameters")
            }

            response?.code in 500..599 -> {
                Log.w("SecureChat", "❌ HTTP ${response?.code} - Server error")
                Log.w("SecureChat", "Possible causes:")
                Log.w("SecureChat", "  - WebSocket server internal error")
                Log.w("SecureChat", "  - Database connection failure")
                Log.w("SecureChat", "  - Server configuration error")
            }

            response == null -> {
                Log.w("SecureChat", "❌ No HTTP response received")
                Log.w("SecureChat", "Possible causes:")
                Log.w("SecureChat", "  - Network connectivity failure")
                Log.w("SecureChat", "  - DNS resolution failure")
                Log.w("SecureChat", "  - TCP connection rejected")
                Log.w("SecureChat", "  - SSL/TLS handshake failure (for wss://)")
            }

            else -> {
                Log.w("SecureChat", "❌ Unknown connection failure")
                Log.w("SecureChat", "Exception type: ${throwable.javaClass.name}")
                Log.w("SecureChat", "Check server logs for more details")
            }
        }

        Log.w("SecureChat", "🔧 === SUGGESTED DEBUGGING STEPS ===")
        Log.w("SecureChat", "1. Test HTTP endpoint: curl http://16.171.233.101:9090/")
        Log.w("SecureChat", "2. Test WebSocket with wscat: wscat -c ws://16.171.233.101:9090/ws")
        Log.w("SecureChat", "3. Check server logs for handshake errors")
        Log.w("SecureChat", "4. Verify server accepts WebSocket upgrade requests")
        Log.w("SecureChat", "5. Test with browser WebSocket console")
    }

    /**
     * HTTP endpoint'ini test eder (WebSocket karşılaştırması için).
     */
    fun testHttpEndpoint(baseUrl: String) {
        Log.d("SecureChat", "🌐 Testing HTTP endpoint: $baseUrl")

        val httpUrl = baseUrl.replace("ws://", "http://").replace("wss://", "https://")

        try {
            val request = Request.Builder()
                .url(httpUrl)
                .build()
            val response = okHttpClient.newCall(request).execute()
            Log.d("SecureChat", "✅ HTTP request SUCCESS!")
            Log.d("SecureChat", "  Status: ${response.code} ${response.message}")

            val body = response.body?.string()
            if (!body.isNullOrEmpty()) {
                Log.d("SecureChat", "  Body: ${body.take(200)}...")
            }
            response.close()

            // Server compatibility check'i de çalıştır
            val hostPort = baseUrl.replace("ws://", "").replace("wss://", "")
            val checker = ServerCompatibilityChecker()
            checker.checkServerCompatibility(hostPort)

        } catch (e: Exception) {
            Log.e("SecureChat", "❌ HTTP request FAILED: ${e.message}")

            // Yine de server compatibility check yap
            try {
                val hostPort = baseUrl.replace("ws://", "").replace("wss://", "")
                val checker = ServerCompatibilityChecker()
                checker.checkServerCompatibility(hostPort)
            } catch (compatError: Exception) {
                Log.e("SecureChat", "Server compatibility check also failed: ${compatError.message}")
            }
        }

        // Server implementation hints
        ServerCompatibilityChecker.logServerImplementationHints()
    }
}