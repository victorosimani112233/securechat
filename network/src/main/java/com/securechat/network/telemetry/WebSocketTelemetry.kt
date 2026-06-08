package com.securechat.network.telemetry

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.concurrent.atomic.AtomicInteger

/**
 * WebSocket baglanti yasam dongusu sayaclari + son hata kaydi.
 *
 * Pure logic — Android API'sine veya Hilt'e dokunmaz. SignalingClient
 * lifecycle callback'lerinden cagrilir, debug ekrani veya destek paylasimi
 * icin StateFlow ile gozlemlenir.
 *
 * Amaclanan kullanim:
 *   - Bugunkü gibi "WS surekli kopuyor" sorununda kullanici cihazindan saysal
 *     dogrulama: kac kez koptu? Son hata neydi? Ne kadar surede yeniden baglandi?
 *   - Crash reporter'a metadata eklemek (rapora bagli olarak).
 *
 * GUVENLIK: Hicbir kullanici icerigi loglanmaz; sadece bagla/kopma sayaclari +
 * exception class name + opsiyonel HTTP code.
 */
object WebSocketTelemetry {

    private val _connects = AtomicInteger(0)
    private val _disconnects = AtomicInteger(0)
    private val _failures = AtomicInteger(0)
    private val _reconnectAttempts = AtomicInteger(0)

    private val _lastFailure = MutableStateFlow<FailureRecord?>(null)
    val lastFailure: StateFlow<FailureRecord?> = _lastFailure.asStateFlow()

    private val _state = MutableStateFlow(Snapshot())
    val state: StateFlow<Snapshot> = _state.asStateFlow()

    /** Yeni connect basarisi (onOpen). */
    fun recordConnected() {
        _connects.incrementAndGet()
        publishSnapshot()
    }

    /** Connection kapandi (onClosed). normal=true kullanici disconnect cagirdiysa. */
    fun recordDisconnected(normal: Boolean = false) {
        _disconnects.incrementAndGet()
        publishSnapshot(lastWasNormalClose = normal)
    }

    /** Connection kuruluyorken hata (onFailure). */
    fun recordFailure(throwable: Throwable, httpCode: Int? = null) {
        _failures.incrementAndGet()
        _lastFailure.value = FailureRecord(
            exceptionClass = throwable.javaClass.simpleName,
            message = throwable.message?.take(MAX_MESSAGE_LEN),
            httpCode = httpCode,
            timestampMs = System.currentTimeMillis()
        )
        publishSnapshot()
    }

    /** Reconnect denemesi planlandi (backoff'tan ciktiktan sonra). */
    fun recordReconnectAttempt() {
        _reconnectAttempts.incrementAndGet()
        publishSnapshot()
    }

    /** Tum sayaclari sifirla — debug ekraninda "reset" icin. */
    fun reset() {
        _connects.set(0)
        _disconnects.set(0)
        _failures.set(0)
        _reconnectAttempts.set(0)
        _lastFailure.value = null
        publishSnapshot()
    }

    private fun publishSnapshot(lastWasNormalClose: Boolean = _state.value.lastWasNormalClose) {
        _state.value = Snapshot(
            connects = _connects.get(),
            disconnects = _disconnects.get(),
            failures = _failures.get(),
            reconnectAttempts = _reconnectAttempts.get(),
            lastFailure = _lastFailure.value,
            lastWasNormalClose = lastWasNormalClose
        )
    }

    /** Tek seferlik tum sayaclari icerir — debug ekrani UI render'i icin. */
    data class Snapshot(
        val connects: Int = 0,
        val disconnects: Int = 0,
        val failures: Int = 0,
        val reconnectAttempts: Int = 0,
        val lastFailure: FailureRecord? = null,
        /** Son disconnect kullanici tarafindan tetiklendi mi (normal logout vb.). */
        val lastWasNormalClose: Boolean = false
    )

    data class FailureRecord(
        val exceptionClass: String,
        val message: String?,
        val httpCode: Int?,
        val timestampMs: Long
    )

    private const val MAX_MESSAGE_LEN = 200
}
