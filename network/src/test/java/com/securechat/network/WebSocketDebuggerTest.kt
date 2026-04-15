package com.securechat.network

import com.google.common.truth.Truth.assertThat
import kotlinx.coroutines.test.runTest
import org.junit.Before
import org.junit.Test

/**
 * WebSocketDebugger unit testleri.
 * Debug functionality'nin doğru çalıştığını ve loglama yapabildiğini test eder.
 */
class WebSocketDebuggerTest {

    private lateinit var webSocketDebugger: WebSocketDebugger

    @Before
    fun setUp() {
        webSocketDebugger = WebSocketDebugger()
    }

    @Test
    fun `WebSocketDebugger instantiation succeeds`() {
        // WebSocketDebugger'ın oluşturulabildiğini test et
        assertThat(webSocketDebugger).isNotNull()
    }

    @Test
    fun `testHttpEndpoint handles invalid URL gracefully`() = runTest {
        // Geçersiz URL ile test — exception fırlatmamalı
        try {
            webSocketDebugger.testHttpEndpoint("invalid://url")
            // Test başarılı — exception fırlatılmadı
        } catch (e: Exception) {
            // Bu durumda test fail olur
            throw AssertionError("testHttpEndpoint should handle invalid URLs gracefully", e)
        }
    }

    @Test
    fun `testWebSocketConnection handles connection failure gracefully`() = runTest {
        // Bağlantı kurulamayan bir URL ile test
        try {
            webSocketDebugger.testWebSocketConnection(
                baseUrl = "ws://nonexistent.example.com:9999",
                userId = "test_user",
                authToken = "test_token"
            )
            // Test başarılı — exception fırlatılmadı
        } catch (e: Exception) {
            // Bu durumda test fail olur
            throw AssertionError("testWebSocketConnection should handle failures gracefully", e)
        }
    }

    @Test
    fun `ServerCompatibilityChecker instantiation succeeds`() {
        val checker = ServerCompatibilityChecker()
        assertThat(checker).isNotNull()
    }

    @Test
    fun `ServerCompatibilityChecker handles invalid host gracefully`() = runTest {
        val checker = ServerCompatibilityChecker()

        try {
            checker.checkServerCompatibility("invalid.host:9999")
            // Test başarılı — exception fırlatılmadı
        } catch (e: Exception) {
            throw AssertionError("checkServerCompatibility should handle invalid hosts gracefully", e)
        }
    }

    @Test
    fun `ServerCompatibilityChecker logServerImplementationHints runs without error`() {
        try {
            ServerCompatibilityChecker.logServerImplementationHints()
            // Test başarılı — exception fırlatılmadı
        } catch (e: Exception) {
            throw AssertionError("logServerImplementationHints should run without error", e)
        }
    }
}