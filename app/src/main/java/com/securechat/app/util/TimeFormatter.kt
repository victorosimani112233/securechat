package com.securechat.app.util

import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.concurrent.TimeUnit

/**
 * Zaman damgasi ve sure formatlama yardimci fonksiyonlari.
 */
object TimeFormatter {

    private val timeFormat = SimpleDateFormat("HH:mm", Locale("tr"))
    private val dateFormat = SimpleDateFormat("dd.MM.yyyy", Locale("tr"))
    private val dayOfWeekFormat = SimpleDateFormat("EEEE", Locale("tr"))

    /**
     * Mesaj zaman damgasini saat:dakika formatina cevirir.
     * Ornek: 1680000000000 -> "14:30"
     */
    fun formatTime(timestamp: Long): String {
        return timeFormat.format(Date(timestamp))
    }

    /**
     * Konusman listesinde gosterilecek sekilde zaman damgasini formatlar.
     * - Bugun ise: "14:30"
     * - Dun ise: "Dun"
     * - Bu hafta ise: "Pazartesi"
     * - Daha eski ise: "25.03.2026"
     */
    fun formatTimestamp(timestamp: Long?): String {
        if (timestamp == null || timestamp == 0L) return ""

        val now = Calendar.getInstance()
        val messageTime = Calendar.getInstance().apply { timeInMillis = timestamp }

        return when {
            isSameDay(now, messageTime) -> timeFormat.format(Date(timestamp))
            isYesterday(now, messageTime) -> "Dun"
            isSameWeek(now, messageTime) -> dayOfWeekFormat.format(Date(timestamp))
            else -> dateFormat.format(Date(timestamp))
        }
    }

    /**
     * Arama suresini okunabilir formata cevirir.
     * Ornek: 125000 -> "02:05", 3661000 -> "1:01:01"
     */
    fun formatDuration(durationMs: Long): String {
        val hours = TimeUnit.MILLISECONDS.toHours(durationMs)
        val minutes = TimeUnit.MILLISECONDS.toMinutes(durationMs) % 60
        val seconds = TimeUnit.MILLISECONDS.toSeconds(durationMs) % 60

        return if (hours > 0) {
            String.format(Locale.getDefault(), "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            String.format(Locale.getDefault(), "%02d:%02d", minutes, seconds)
        }
    }

    private fun isSameDay(cal1: Calendar, cal2: Calendar): Boolean {
        return cal1.get(Calendar.YEAR) == cal2.get(Calendar.YEAR) &&
                cal1.get(Calendar.DAY_OF_YEAR) == cal2.get(Calendar.DAY_OF_YEAR)
    }

    private fun isYesterday(now: Calendar, other: Calendar): Boolean {
        val yesterday = Calendar.getInstance().apply {
            timeInMillis = now.timeInMillis
            add(Calendar.DAY_OF_YEAR, -1)
        }
        return isSameDay(yesterday, other)
    }

    private fun isSameWeek(now: Calendar, other: Calendar): Boolean {
        return now.get(Calendar.YEAR) == other.get(Calendar.YEAR) &&
                now.get(Calendar.WEEK_OF_YEAR) == other.get(Calendar.WEEK_OF_YEAR)
    }
}
