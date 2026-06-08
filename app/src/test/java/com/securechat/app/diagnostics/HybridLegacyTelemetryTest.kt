package com.securechat.app.diagnostics

import com.google.common.truth.Truth.assertThat
import org.junit.Before
import org.junit.Test

class HybridLegacyTelemetryTest {

    @Before
    fun setup() {
        HybridLegacyTelemetry.reset()
    }

    @Test
    fun `reset sonrasi tum sayaclar sifir, timestamp null`() {
        val snapshot = HybridLegacyTelemetry.state.value
        assertThat(snapshot.directLegacyCount).isEqualTo(0)
        assertThat(snapshot.groupLegacyCount).isEqualTo(0)
        assertThat(snapshot.firstLegacyAtMs).isNull()
        assertThat(snapshot.lastLegacyAtMs).isNull()
        assertThat(snapshot.totalLegacyCount).isEqualTo(0)
    }

    @Test
    fun `recordDirectLegacy artirir + timestamp tutar`() {
        HybridLegacyTelemetry.recordDirectLegacy()

        val snapshot = HybridLegacyTelemetry.state.value
        assertThat(snapshot.directLegacyCount).isEqualTo(1)
        assertThat(snapshot.groupLegacyCount).isEqualTo(0)
        assertThat(snapshot.firstLegacyAtMs).isNotNull()
        assertThat(snapshot.lastLegacyAtMs).isNotNull()
        assertThat(snapshot.firstLegacyAtMs).isEqualTo(snapshot.lastLegacyAtMs)
    }

    @Test
    fun `recordGroupLegacy ayri sayacta tutulur`() {
        HybridLegacyTelemetry.recordGroupLegacy()
        HybridLegacyTelemetry.recordGroupLegacy()

        val snapshot = HybridLegacyTelemetry.state.value
        assertThat(snapshot.groupLegacyCount).isEqualTo(2)
        assertThat(snapshot.directLegacyCount).isEqualTo(0)
        assertThat(snapshot.totalLegacyCount).isEqualTo(2)
    }

    @Test
    fun `first ve last timestamp dogru takip eder`() {
        HybridLegacyTelemetry.recordDirectLegacy()
        val first = HybridLegacyTelemetry.state.value.firstLegacyAtMs!!
        Thread.sleep(10) // gercek delta icin
        HybridLegacyTelemetry.recordGroupLegacy()
        val snapshot = HybridLegacyTelemetry.state.value

        assertThat(snapshot.firstLegacyAtMs).isEqualTo(first) // ilk degisemez
        assertThat(snapshot.lastLegacyAtMs!!).isGreaterThan(first)
    }

    @Test
    fun `daysSinceLastLegacy 7 gun once timestamp icin 7 doner`() {
        val sevenDaysMs = 7L * 24 * 60 * 60 * 1000
        val now = 1780000000000L
        val sevenDaysAgo = now - sevenDaysMs

        val snapshot = HybridLegacyTelemetry.Snapshot(
            directLegacyCount = 1,
            groupLegacyCount = 0,
            firstLegacyAtMs = sevenDaysAgo,
            lastLegacyAtMs = sevenDaysAgo
        )
        assertThat(snapshot.daysSinceLastLegacy(now)).isEqualTo(7)
    }

    @Test
    fun `daysSinceLastLegacy lastLegacyAtMs null ise null doner`() {
        val snapshot = HybridLegacyTelemetry.Snapshot()
        assertThat(snapshot.daysSinceLastLegacy(System.currentTimeMillis())).isNull()
    }

    @Test
    fun `thread safety - concurrent record sayisi dogru`() {
        val threads = (1..40).map {
            Thread {
                repeat(25) {
                    HybridLegacyTelemetry.recordDirectLegacy()
                    HybridLegacyTelemetry.recordGroupLegacy()
                }
            }
        }
        threads.forEach { it.start() }
        threads.forEach { it.join() }

        val snapshot = HybridLegacyTelemetry.state.value
        // 40 thread x 25 = 1000 her sayac
        assertThat(snapshot.directLegacyCount).isEqualTo(1000)
        assertThat(snapshot.groupLegacyCount).isEqualTo(1000)
        assertThat(snapshot.totalLegacyCount).isEqualTo(2000)
    }
}
