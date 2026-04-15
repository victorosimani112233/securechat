package com.securechat.app.util

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Calendar

/**
 * TimeFormatter birim testleri.
 */
class TimeFormatterTest {

    @Test
    fun `formatTime returns HH-mm format`() {
        // 2026-04-02 14:30:00 UTC+3 icin bir timestamp olustur
        val calendar = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 14)
            set(Calendar.MINUTE, 30)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val result = TimeFormatter.formatTime(calendar.timeInMillis)

        assertEquals("14:30", result)
    }

    @Test
    fun `formatTime returns correct format for midnight`() {
        val calendar = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val result = TimeFormatter.formatTime(calendar.timeInMillis)

        assertEquals("00:00", result)
    }

    @Test
    fun `formatTimestamp returns empty string for null`() {
        assertEquals("", TimeFormatter.formatTimestamp(null))
    }

    @Test
    fun `formatTimestamp returns empty string for zero`() {
        assertEquals("", TimeFormatter.formatTimestamp(0L))
    }

    @Test
    fun `formatTimestamp returns time for today`() {
        // Bugunun bir saati
        val now = System.currentTimeMillis()
        val result = TimeFormatter.formatTimestamp(now)

        // HH:mm formatinda olmali (icerisinde : olmali)
        assertTrue("Bugunun timestamp'i saat formatinda olmali: $result", result.contains(":"))
    }

    @Test
    fun `formatTimestamp returns Dun for yesterday`() {
        val yesterday = Calendar.getInstance().apply {
            add(Calendar.DAY_OF_YEAR, -1)
            set(Calendar.HOUR_OF_DAY, 12)
        }
        val result = TimeFormatter.formatTimestamp(yesterday.timeInMillis)

        assertEquals("Dun", result)
    }

    @Test
    fun `formatDuration formats seconds only`() {
        val result = TimeFormatter.formatDuration(45_000L)
        assertEquals("00:45", result)
    }

    @Test
    fun `formatDuration formats minutes and seconds`() {
        val result = TimeFormatter.formatDuration(125_000L)
        assertEquals("02:05", result)
    }

    @Test
    fun `formatDuration formats hours minutes and seconds`() {
        val result = TimeFormatter.formatDuration(3_661_000L)
        assertEquals("1:01:01", result)
    }

    @Test
    fun `formatDuration formats zero duration`() {
        val result = TimeFormatter.formatDuration(0L)
        assertEquals("00:00", result)
    }

    @Test
    fun `formatDuration formats exactly one hour`() {
        val result = TimeFormatter.formatDuration(3_600_000L)
        assertEquals("1:00:00", result)
    }
}
