package com.securechat.network

import android.util.Log
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.TimeUnit

/**
 * WebSocket server uyumluluğunu ve konfigürasyonunu kontrol eden utility.
 *
 * Bu sınıf farklı senaryoları test eder:
 * - HTTP endpoint erişilebilirliği
 * - WebSocket handshake compatibility
 * - Farklı path'ler (/ws, /, vb.)
 * - Header requirements
 *
 * KULLANIM:
 * ```
 * val checker = ServerCompatibilityChecker()
 * checker.checkServerCompatibility("16.171.233.101:9090")
 * ```
 */
class ServerCompatibilityChecker {

    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(5, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.SECONDS)
        .build()

    /**
     * Server compatibility'sini çeşitli testlerle kontrol eder.
     *
     * @param serverHost Server host:port (örn: "16.171.233.101:9090")
     */
    fun checkServerCompatibility(serverHost: String) {
        Log.w("SecureChat", "🔍 === SERVER COMPATIBILITY CHECK STARTED ===")
        Log.w("SecureChat", "Target server: $serverHost")

        // Test 1: Basic HTTP connectivity
        testHttpConnectivity(serverHost)

        // Test 2: WebSocket-specific HTTP headers
        testWebSocketHeaders(serverHost)

        // Test 3: Different paths
        testDifferentPaths(serverHost)

        // Test 4: Authentication requirements
        testAuthenticationRequirements(serverHost)

        Log.w("SecureChat", "🔍 === SERVER COMPATIBILITY CHECK COMPLETED ===")
    }

    /**
     * Temel HTTP bağlantısını test eder.
     */
    private fun testHttpConnectivity(serverHost: String) {
        Log.d("SecureChat", "📡 Testing basic HTTP connectivity...")

        val testUrls = listOf(
            "http://$serverHost/",
            "http://$serverHost/ws",
            "http://$serverHost/health",
            "http://$serverHost/status"
        )

        for (url in testUrls) {
            try {
                val request = Request.Builder().url(url).build()
                val response = httpClient.newCall(request).execute()

                Log.d("SecureChat", "✅ HTTP GET $url")
                Log.d("SecureChat", "  Status: ${response.code} ${response.message}")

                val contentType = response.header("Content-Type")
                val server = response.header("Server")
                val upgrade = response.header("Upgrade")
                val connection = response.header("Connection")

                Log.d("SecureChat", "  Content-Type: $contentType")
                Log.d("SecureChat", "  Server: $server")

                if (upgrade != null || connection != null) {
                    Log.d("SecureChat", "  Upgrade: $upgrade")
                    Log.d("SecureChat", "  Connection: $connection")
                }

                val body = response.body?.string()?.take(100)
                if (!body.isNullOrBlank()) {
                    Log.d("SecureChat", "  Body: $body...")
                }

                response.close()

                // WebSocket upgrade hint kontrolü
                if (response.code == 426) {
                    Log.w("SecureChat", "⚠️ Server returned 426 Upgrade Required")
                    Log.w("SecureChat", "  This suggests WebSocket upgrade is needed")
                }

            } catch (e: Exception) {
                Log.e("SecureChat", "❌ HTTP GET $url failed: ${e.message}")
            }
        }
    }

    /**
     * WebSocket-specific header'larla HTTP isteği test eder.
     */
    private fun testWebSocketHeaders(serverHost: String) {
        Log.d("SecureChat", "🔧 Testing WebSocket handshake headers...")

        val url = "http://$serverHost/ws?userId=test123"

        try {
            val request = Request.Builder()
                .url(url)
                .addHeader("Upgrade", "websocket")
                .addHeader("Connection", "Upgrade")
                .addHeader("Sec-WebSocket-Key", "dGhlIHNhbXBsZSBub25jZQ==")
                .addHeader("Sec-WebSocket-Version", "13")
                .addHeader("Authorization", "Bearer test_token")
                .build()

            val response = httpClient.newCall(request).execute()

            Log.d("SecureChat", "📤 WebSocket handshake attempt:")
            Log.d("SecureChat", "  Status: ${response.code} ${response.message}")

            // WebSocket handshake response headers
            val upgrade = response.header("Upgrade")
            val connection = response.header("Connection")
            val wsAccept = response.header("Sec-WebSocket-Accept")

            Log.d("SecureChat", "📥 Response headers:")
            Log.d("SecureChat", "  Upgrade: $upgrade")
            Log.d("SecureChat", "  Connection: $connection")
            Log.d("SecureChat", "  Sec-WebSocket-Accept: $wsAccept")

            when (response.code) {
                101 -> Log.d("SecureChat", "✅ Server supports WebSocket upgrade (101 Switching Protocols)")
                404 -> Log.w("SecureChat", "⚠️ WebSocket endpoint not found (404)")
                400 -> Log.w("SecureChat", "⚠️ Bad WebSocket handshake request (400)")
                401, 403 -> Log.w("SecureChat", "⚠️ Authentication required (${response.code})")
                426 -> Log.w("SecureChat", "⚠️ Upgrade Required (426) - good sign for WebSocket support")
                else -> Log.w("SecureChat", "⚠️ Unexpected response code: ${response.code}")
            }

            response.close()

        } catch (e: Exception) {
            Log.e("SecureChat", "❌ WebSocket handshake test failed: ${e.message}")
        }
    }

    /**
     * Farklı path'leri test eder.
     */
    private fun testDifferentPaths(serverHost: String) {
        Log.d("SecureChat", "🛣️ Testing different WebSocket paths...")

        val paths = listOf(
            "/ws",
            "/websocket",
            "/socket.io",
            "/api/ws",
            "/signaling",
            ""
        )

        for (path in paths) {
            val url = "http://$serverHost$path?userId=test123"
            try {
                val request = Request.Builder()
                    .url(url)
                    .addHeader("Upgrade", "websocket")
                    .addHeader("Connection", "Upgrade")
                    .addHeader("Sec-WebSocket-Key", "dGhlIHNhbXBsZSBub25jZQ==")
                    .addHeader("Sec-WebSocket-Version", "13")
                    .build()

                val response = httpClient.newCall(request).execute()
                Log.d("SecureChat", "Path $path: ${response.code} ${response.message}")
                response.close()

            } catch (e: Exception) {
                Log.d("SecureChat", "Path $path: failed (${e.message})")
            }
        }
    }

    /**
     * Authentication requirement'larını test eder.
     */
    private fun testAuthenticationRequirements(serverHost: String) {
        Log.d("SecureChat", "🔐 Testing authentication requirements...")

        val url = "http://$serverHost/ws?userId=test123"

        // Test 1: No auth header
        try {
            val request = Request.Builder()
                .url(url)
                .addHeader("Upgrade", "websocket")
                .addHeader("Connection", "Upgrade")
                .addHeader("Sec-WebSocket-Key", "dGhlIHNhbXBsZSBub25jZQ==")
                .addHeader("Sec-WebSocket-Version", "13")
                .build()

            val response = httpClient.newCall(request).execute()
            Log.d("SecureChat", "No auth: ${response.code} ${response.message}")
            response.close()

        } catch (e: Exception) {
            Log.d("SecureChat", "No auth: failed (${e.message})")
        }

        // Test 2: With Bearer token
        try {
            val request = Request.Builder()
                .url(url)
                .addHeader("Upgrade", "websocket")
                .addHeader("Connection", "Upgrade")
                .addHeader("Sec-WebSocket-Key", "dGhlIHNhbXBsZSBub25jZQ==")
                .addHeader("Sec-WebSocket-Version", "13")
                .addHeader("Authorization", "Bearer token_test123")
                .build()

            val response = httpClient.newCall(request).execute()
            Log.d("SecureChat", "Bearer auth: ${response.code} ${response.message}")
            response.close()

        } catch (e: Exception) {
            Log.d("SecureChat", "Bearer auth: failed (${e.message})")
        }

        // Test 3: Invalid token format
        try {
            val request = Request.Builder()
                .url(url)
                .addHeader("Upgrade", "websocket")
                .addHeader("Connection", "Upgrade")
                .addHeader("Sec-WebSocket-Key", "dGhlIHNhbXBsZSBub25jZQ==")
                .addHeader("Sec-WebSocket-Version", "13")
                .addHeader("Authorization", "invalid_token_format")
                .build()

            val response = httpClient.newCall(request).execute()
            Log.d("SecureChat", "Invalid auth: ${response.code} ${response.message}")
            response.close()

        } catch (e: Exception) {
            Log.d("SecureChat", "Invalid auth: failed (${e.message})")
        }
    }

    companion object {
        /**
         * Server-side WebSocket implementation için Node.js kod örnekleri ve
         * yaygın sorunları log'a yazdırır.
         */
        fun logServerImplementationHints() {
            Log.w("SecureChat", "💡 === SERVER-SIDE WEBSOCKET HINTS ===")
            Log.w("SecureChat", "If using Node.js with 'ws' library, check:")
            Log.w("SecureChat", "")

            Log.w("SecureChat", "1. WebSocket Server Configuration:")
            Log.w("SecureChat", "   const wss = new WebSocket.Server({")
            Log.w("SecureChat", "     server: httpServer,")
            Log.w("SecureChat", "     path: '/ws',")
            Log.w("SecureChat", "     verifyClient: (info) => {")
            Log.w("SecureChat", "       // Verify Authorization header")
            Log.w("SecureChat", "       const auth = info.req.headers.authorization;")
            Log.w("SecureChat", "       return auth && auth.startsWith('Bearer ');")
            Log.w("SecureChat", "     }")
            Log.w("SecureChat", "   });")
            Log.w("SecureChat", "")

            Log.w("SecureChat", "2. HTTP Server should NOT handle /ws path:")
            Log.w("SecureChat", "   const server = http.createServer((req, res) => {")
            Log.w("SecureChat", "     if (req.url.startsWith('/ws')) {")
            Log.w("SecureChat", "       // Let WebSocket handle this")
            Log.w("SecureChat", "       return;")
            Log.w("SecureChat", "     }")
            Log.w("SecureChat", "     res.writeHead(200, {'Content-Type': 'text/plain'});")
            Log.w("SecureChat", "     res.end('Server OK');")
            Log.w("SecureChat", "   });")
            Log.w("SecureChat", "")

            Log.w("SecureChat", "3. Common Issues:")
            Log.w("SecureChat", "   - HTTP handler intercepting /ws requests")
            Log.w("SecureChat", "   - Missing CORS headers for WebSocket")
            Log.w("SecureChat", "   - Authorization header not parsed correctly")
            Log.w("SecureChat", "   - WebSocket Server path mismatch")
        }
    }
}