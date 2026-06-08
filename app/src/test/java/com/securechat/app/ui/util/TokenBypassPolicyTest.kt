package com.securechat.app.ui.util

import com.google.common.truth.Truth.assertWithMessage
import org.junit.Test
import java.io.File

/**
 * Tema token disiplini icin kaynak-seviye kural denetimi.
 *
 * AzureTokens'da tanimli renkler (azure, ink, frost, ok, warn, danger, vs.)
 * yerine raw `Color(0xFF...)` kullanimi tema tutarsizligi yaratir: dark/light
 * mode degistiginde veya rebranding gerektiginde her ekran tek tek elle
 * guncellenmek zorunda kalir. Token bypass'i Sprint 1'de temizlenen 4 ekranda
 * regression olarak isaretlenir.
 *
 * Kapsam genisletilebilir — Sprint 2'de daha fazla ekran eklendiginde
 * `SCREENS_UNDER_POLICY` listesi buyur.
 */
class TokenBypassPolicyTest {

    private val repoRoot: File =
        File(System.getProperty("user.dir") ?: ".").let { cwd ->
            if (cwd.resolve("src/main/java").isDirectory) cwd.parentFile else cwd
        }

    /**
     * Bu ekranlarda artik `Color(0x...)` (ozellikle azure brand color) yasak —
     * `MaterialTheme.azure.X` kullanilmali.
     *
     * Sprint 1 ekranlari. Sprint 2'de buyur.
     */
    private val SCREENS_UNDER_POLICY = listOf(
        "app/src/main/java/com/securechat/app/ui/screen/PhoneVerificationScreen.kt",
        "app/src/main/java/com/securechat/app/ui/screen/OtpVerificationScreen.kt",
        "app/src/main/java/com/securechat/app/ui/screen/EmailOtpScreen.kt",
        "app/src/main/java/com/securechat/app/ui/screen/CreateGroupScreen.kt"
    )

    /**
     * Bilinen brand token'a karsilik gelen hex'ler — bunlar artik AzureTokens
     * uzerinden kullanilmali. Ekstra hex'ler (orn. `0xFFFFD700` altin sarisi)
     * tema token'i olmadigi icin bu listede yok, ama gelecekte eklenir.
     */
    private val BANNED_HEX_PATTERNS = listOf(
        "0xFF3E7BFA" to "MaterialTheme.azure.azure",
        "0xFF1E52D9" to "MaterialTheme.azure.azureDeep",
        "0xFF5EA3FF" to "MaterialTheme.azure.azureGlow",
        "0xFF22C55E" to "MaterialTheme.azure.ok",
        "0xFFFFB800" to "MaterialTheme.azure.warn",
        "0xFFFF5E87" to "MaterialTheme.azure.danger",
        "0xFF13161B" to "MaterialTheme.azure.ink",
        "0xFF5D6570" to "MaterialTheme.azure.inkMute",
        "0xFF8A929C" to "MaterialTheme.azure.inkSoft",
        "0xFFECEEF2" to "MaterialTheme.azure.frost",
        "0xFF9BA3AE" to "MaterialTheme.azure.frostMute",
        "0xFF6B737D" to "MaterialTheme.azure.frostSoft",
        "0xFF0D1014" to "MaterialTheme.azure.night",
        "0xFF151A21" to "MaterialTheme.azure.nightRaise",
        "0xFF1E242D" to "MaterialTheme.azure.nightEdge",
        "0xFFF4F2EC" to "MaterialTheme.azure.paper",
        "0xFFEAE7DD" to "MaterialTheme.azure.paperDim"
    )

    @Test
    fun `Sprint 1 ekranlari token bypass icermemeli`() {
        for (screenPath in SCREENS_UNDER_POLICY) {
            val file = File(repoRoot, screenPath)
            assertWithMessage("Ekran dosyasi bulunamadi: $screenPath")
                .that(file.exists())
                .isTrue()
            val source = file.readText()
            for ((hex, expectedReplacement) in BANNED_HEX_PATTERNS) {
                val occurrences = source.split(hex).size - 1
                assertWithMessage(
                    "$screenPath: raw '$hex' kullanimi yasak — '$expectedReplacement' kullan. " +
                        "Bulunan: $occurrences kez."
                )
                    .that(occurrences)
                    .isEqualTo(0)
            }
        }
    }
}
