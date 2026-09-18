package com.securechat.signaling

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Kimliksiz guvenlik olayi sayaclari.
 *
 * Sayaclar metrics yuzeyine baglanmadigi surece hicbir yerde gorunmuyordu:
 * container `logging=none` ile calistigi icin bir auth saldirisi ya da
 * retention disi bir olay fark edilmeden geciyordu. Sayaclarin kendisi
 * kimlik tasimamalidir — cagri imzasi kimlik girdilerini kasten yutar.
 */
class AuditMetricsTest {

    @Test
    fun `identity inputs are discarded and only the event type is counted`() {
        val event = "TEST_IDENTITY_DISCARDED"
        val before = AuditLog.count(event)

        AuditLog.log(
            userId = "123e4567-e89b-42d3-a456-426614174000",
            eventType = event,
            metadata = mapOf("phone" to "+905551234567"),
            ipAddress = "198.51.100.7",
        )

        assertEquals(before + 1, AuditLog.count(event))
        // Anahtar yalniz olay turudur; kimlik girdileri hicbir yere yazilmaz.
        assertTrue(AuditLog.snapshot().keys.contains(event))
        assertFalse(
            AuditLog.snapshot().keys.any { it.contains("905551234567") || it.contains("198.51.100") },
        )
    }

    @Test
    fun `a malformed event type is refused instead of creating a new series`() {
        val before = AuditLog.snapshot().size

        for (bad in listOf("", "lowercase", "1_STARTS_WITH_DIGIT", "HAS SPACE", "A".repeat(80))) {
            AuditLog.log(eventType = bad)
        }

        // Serbest metin kabul edilseydi saldirgan kontrollu bir deger
        // metrics'te kalici bir seri olusturabilirdi.
        assertEquals(before, AuditLog.snapshot().size)
    }

    @Test
    fun `the aggregate counter is visible on the metrics surface`() {
        Metrics.registerAuditCounters()
        AuditLog.log(eventType = "TEST_AGGREGATE_VISIBLE")

        val scrape = Metrics.registry.scrape()

        assertTrue(
            scrape.contains("securechat_security_events_total"),
            "toplam sayac metrics ciktisinda yok",
        )
    }

    @Test
    fun `a named event is exposed as its own series`() {
        val event = "TEST_NAMED_SERIES"
        Metrics.registerAuditCounter(event)
        AuditLog.log(eventType = event)
        AuditLog.log(eventType = event)

        val scrape = Metrics.registry.scrape()
        val line = scrape.lines().firstOrNull {
            it.startsWith("securechat_security_event{") && it.contains(event)
        }

        assertTrue(line != null, "olay serisi metrics ciktisinda yok")
        assertTrue(line!!.trim().endsWith("2.0"), line)
    }

    @Test
    fun `the metrics surface carries no account identifier`() {
        AuditLog.log(
            userId = "123e4567-e89b-42d3-a456-426614174000",
            eventType = "TEST_NO_IDENTITY_IN_SCRAPE",
        )
        Metrics.registerAuditCounter("TEST_NO_IDENTITY_IN_SCRAPE")

        val scrape = Metrics.registry.scrape()

        assertFalse(scrape.contains("123e4567-e89b-42d3-a456-426614174000"))
    }
}
