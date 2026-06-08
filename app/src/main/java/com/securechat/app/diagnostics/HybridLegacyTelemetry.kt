package com.securechat.app.diagnostics

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.concurrent.atomic.AtomicLong

/**
 * Hibrit donem (30 gun) sirasinda legacy plaintext format'larin kullanim
 * sayaclari. 30 gun sonra legacy path'i kapatma karari icin veri toplar.
 *
 * Sayacli ek bilgi: ilk + son legacy alma timestamp'i.
 *
 * GUVENLIK: Mesaj icerigi loglanmaz, sadece "legacy format alindi" sayisi.
 *
 * Kullanim:
 *   - IncomingMessageHandler DirectLegacy / GroupLegacy yolunda recordX() cagrir.
 *   - Debug ekrani veya crash reporter metadata olarak StateFlow okur.
 *   - Hibrit donem sonunda telemetry "son 7 gunde 0 legacy alindi" gosteriyorsa
 *     legacy path kapatma guvenli.
 */
object HybridLegacyTelemetry {

    private val _directLegacyCount = AtomicLong(0)
    private val _groupLegacyCount = AtomicLong(0)
    private val _firstLegacyAtMs = AtomicLong(0)
    private val _lastLegacyAtMs = AtomicLong(0)

    private val _state = MutableStateFlow(Snapshot())
    val state: StateFlow<Snapshot> = _state.asStateFlow()

    /** 1:1 plaintext envelope alindi (gondericinin yeni APK yuklemedigini gosterir). */
    fun recordDirectLegacy() {
        _directLegacyCount.incrementAndGet()
        markLegacyTimestamp()
        publish()
    }

    /** Grup plaintext envelope alindi (gondericinin yeni APK yuklemedigini gosterir). */
    fun recordGroupLegacy() {
        _groupLegacyCount.incrementAndGet()
        markLegacyTimestamp()
        publish()
    }

    private fun markLegacyTimestamp() {
        val now = System.currentTimeMillis()
        _firstLegacyAtMs.compareAndSet(0L, now)
        _lastLegacyAtMs.set(now)
    }

    fun reset() {
        _directLegacyCount.set(0)
        _groupLegacyCount.set(0)
        _firstLegacyAtMs.set(0)
        _lastLegacyAtMs.set(0)
        publish()
    }

    private fun publish() {
        _state.value = Snapshot(
            directLegacyCount = _directLegacyCount.get(),
            groupLegacyCount = _groupLegacyCount.get(),
            firstLegacyAtMs = _firstLegacyAtMs.get().takeIf { it > 0 },
            lastLegacyAtMs = _lastLegacyAtMs.get().takeIf { it > 0 }
        )
    }

    data class Snapshot(
        val directLegacyCount: Long = 0,
        val groupLegacyCount: Long = 0,
        val firstLegacyAtMs: Long? = null,
        val lastLegacyAtMs: Long? = null
    ) {
        /** Son legacy mesajdan kac saniye gectigi. null = hic legacy alinmadi. */
        fun daysSinceLastLegacy(nowMs: Long = System.currentTimeMillis()): Long? =
            lastLegacyAtMs?.let { (nowMs - it) / (24L * 60 * 60 * 1000) }

        /** Hibrit donem sonunda legacy path kapatma karari icin. */
        val totalLegacyCount: Long get() = directLegacyCount + groupLegacyCount
    }
}
