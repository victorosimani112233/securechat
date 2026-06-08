package com.securechat.app.diagnostics

import com.google.common.truth.Truth.assertThat
import org.junit.Test

/**
 * CrashLogFormatter saf logic icin birim testler.
 *
 * Deterministik bir epochMs zaman damgasi enjekte ederek format
 * cikitilari assert edilir — testler test runner saatine bagimsiz.
 */
class CrashLogFormatterTest {

    private val sampleMetadata = CrashMetadata(
        versionName = "1.0.77-2cd3ce9",
        versionCode = 77,
        androidRelease = "14",
        androidSdkInt = 34,
        deviceModel = "Pixel 7",
        deviceManufacturer = "Google",
        threadName = "main"
    )

    // 2026-06-08T15:30:42Z = epoch ms (UTC olarak hesaplandi).
    private val fixedEpochMs = 1780932642000L

    @Test
    fun `format - basari yolu tum metadata satirlari icerir`() {
        val exc = RuntimeException("Test patladi")

        val output = CrashLogFormatter.format(exc, sampleMetadata, fixedEpochMs)

        assertThat(output).contains("=== ELÇİM CRASH REPORT ===")
        assertThat(output).contains("timestamp: 2026-06-08T15:30:42Z")
        assertThat(output).contains("versionName: 1.0.77-2cd3ce9")
        assertThat(output).contains("versionCode: 77")
        assertThat(output).contains("android: 14 (SDK 34)")
        assertThat(output).contains("device: Pixel 7")
        assertThat(output).contains("manufacturer: Google")
        assertThat(output).contains("thread: main")
        assertThat(output).contains("--- STACK ---")
        assertThat(output).contains("RuntimeException")
        assertThat(output).contains("Test patladi")
    }

    @Test
    fun `format - stack trace nested cause icerir`() {
        val root = IllegalStateException("Root sebep")
        val outer = RuntimeException("Sarmali", root)

        val output = CrashLogFormatter.format(outer, sampleMetadata, fixedEpochMs)

        assertThat(output).contains("Sarmali")
        assertThat(output).contains("Root sebep")
        // printStackTrace varsayilan olarak "Caused by:" satiri ekler
        assertThat(output).contains("Caused by:")
    }

    @Test
    fun `format - PLAINTEXT_FILTERED token iceren satir loga yansimaz`() {
        val exc = RuntimeException("PLAINTEXT_FILTERED gizli mesaj icerigi")

        val output = CrashLogFormatter.format(exc, sampleMetadata, fixedEpochMs)

        assertThat(output).doesNotContain("PLAINTEXT_FILTERED")
        assertThat(output).doesNotContain("gizli mesaj icerigi")
    }

    @Test
    fun `fileName - epoch ms tabanli artici sira saglar`() {
        val name1 = CrashLogFormatter.fileName(1000L)
        val name2 = CrashLogFormatter.fileName(2000L)

        assertThat(name1).isEqualTo("crash_1000.txt")
        assertThat(name2).isEqualTo("crash_2000.txt")
        // Alfasayisal sort kronolojik sirada artar (sabit basamak gerekmez,
        // ama bizim icin <= MAX_LONG digit fark her zaman ayni; basit dosyalar).
        assertThat(name1 < name2).isTrue()
    }

    @Test
    fun `format - UTC timezone garanti — yerel timezone fark etmez`() {
        // Java timezone offsetti degistirsek bile cikti UTC ISO-8601 olmali.
        val originalTz = java.util.TimeZone.getDefault()
        try {
            java.util.TimeZone.setDefault(java.util.TimeZone.getTimeZone("America/New_York"))
            val output = CrashLogFormatter.format(
                RuntimeException("tz"),
                sampleMetadata,
                fixedEpochMs
            )
            assertThat(output).contains("timestamp: 2026-06-08T15:30:42Z")
        } finally {
            java.util.TimeZone.setDefault(originalTz)
        }
    }
}
