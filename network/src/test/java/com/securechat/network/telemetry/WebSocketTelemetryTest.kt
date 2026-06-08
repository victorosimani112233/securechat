package com.securechat.network.telemetry

import com.google.common.truth.Truth.assertThat
import org.junit.Before
import org.junit.Test

/**
 * WebSocketTelemetry singleton icin birim testler.
 *
 * Her test before-block'unda reset() cagrir — paylasilan singleton state
 * sizintisini engellemek icin. Test'ler thread-safe counter davranisini
 * dogrular.
 */
class WebSocketTelemetryTest {

    @Before
    fun setup() {
        WebSocketTelemetry.reset()
    }

    @Test
    fun `reset baslangic state'ini sifirlar`() {
        val snapshot = WebSocketTelemetry.state.value
        assertThat(snapshot.connects).isEqualTo(0)
        assertThat(snapshot.disconnects).isEqualTo(0)
        assertThat(snapshot.failures).isEqualTo(0)
        assertThat(snapshot.reconnectAttempts).isEqualTo(0)
        assertThat(snapshot.lastFailure).isNull()
        assertThat(snapshot.lastWasNormalClose).isFalse()
    }

    @Test
    fun `recordConnected sayaci artirir ve state guncellenir`() {
        WebSocketTelemetry.recordConnected()
        WebSocketTelemetry.recordConnected()
        WebSocketTelemetry.recordConnected()

        assertThat(WebSocketTelemetry.state.value.connects).isEqualTo(3)
    }

    @Test
    fun `recordDisconnected normal flag'i yansitir`() {
        WebSocketTelemetry.recordDisconnected(normal = true)

        val snapshot = WebSocketTelemetry.state.value
        assertThat(snapshot.disconnects).isEqualTo(1)
        assertThat(snapshot.lastWasNormalClose).isTrue()
    }

    @Test
    fun `recordDisconnected default normal false`() {
        WebSocketTelemetry.recordDisconnected()

        val snapshot = WebSocketTelemetry.state.value
        assertThat(snapshot.disconnects).isEqualTo(1)
        assertThat(snapshot.lastWasNormalClose).isFalse()
    }

    @Test
    fun `recordFailure exception class ve message'i yakalar`() {
        val exc = java.net.SocketTimeoutException("connect timed out")

        WebSocketTelemetry.recordFailure(exc, httpCode = 502)

        val snapshot = WebSocketTelemetry.state.value
        assertThat(snapshot.failures).isEqualTo(1)
        val failure = snapshot.lastFailure
        assertThat(failure).isNotNull()
        assertThat(failure!!.exceptionClass).isEqualTo("SocketTimeoutException")
        assertThat(failure.message).isEqualTo("connect timed out")
        assertThat(failure.httpCode).isEqualTo(502)
        assertThat(failure.timestampMs).isGreaterThan(0L)
    }

    @Test
    fun `recordFailure message max 200 karakter trimler`() {
        val longMsg = "x".repeat(500)
        WebSocketTelemetry.recordFailure(RuntimeException(longMsg))

        val failure = WebSocketTelemetry.state.value.lastFailure!!
        assertThat(failure.message!!.length).isEqualTo(200)
    }

    @Test
    fun `recordReconnectAttempt sayaci artirir`() {
        repeat(5) { WebSocketTelemetry.recordReconnectAttempt() }

        assertThat(WebSocketTelemetry.state.value.reconnectAttempts).isEqualTo(5)
    }

    @Test
    fun `multiple events kombine snapshot uretir`() {
        WebSocketTelemetry.recordConnected()
        WebSocketTelemetry.recordDisconnected(normal = false)
        WebSocketTelemetry.recordReconnectAttempt()
        WebSocketTelemetry.recordFailure(RuntimeException("boom"))

        val snapshot = WebSocketTelemetry.state.value
        assertThat(snapshot.connects).isEqualTo(1)
        assertThat(snapshot.disconnects).isEqualTo(1)
        assertThat(snapshot.reconnectAttempts).isEqualTo(1)
        assertThat(snapshot.failures).isEqualTo(1)
        assertThat(snapshot.lastFailure?.exceptionClass).isEqualTo("RuntimeException")
        assertThat(snapshot.lastWasNormalClose).isFalse()
    }

    @Test
    fun `thread safety - 1000 concurrent increment counter dogru`() {
        val threads = (1..50).map {
            Thread {
                repeat(20) { WebSocketTelemetry.recordConnected() }
            }
        }
        threads.forEach { it.start() }
        threads.forEach { it.join() }

        // 50 thread x 20 increment = 1000
        assertThat(WebSocketTelemetry.state.value.connects).isEqualTo(1000)
    }
}
