package com.securechat.app.ui.util

import com.google.common.truth.Truth.assertThat
import com.google.common.truth.Truth.assertWithMessage
import org.junit.Test
import java.io.File

/**
 * Form ekranlarinda kullanici girdilerinin rotation/process death sonrasi
 * korunmasi icin `rememberSaveable` kullaniminin contract testi.
 *
 * Compose state restoration runtime testi (instrumentation/robolectric) mevcut
 * olmadigindan, bu test KAYNAK SEVIYESINDE grep tabanli kural denetimi yapar:
 * Belirtilen ekranlarda kritik state'ler `var X by remember { mutableStateOf` ile
 * tanimlanirsa regresyon olarak isaretlenir. Doğru kullanim:
 * `var X by rememberSaveable { mutableStateOf(...) }`.
 *
 * Istisna listesinde geçen state'ler kasitlidir (orn. `isLoading` —
 * coroutine'ler rotation'da restart edilmez, zombi spinner yaratir).
 */
class FormStateRetentionPolicyTest {

    /** Repo kök dizini — test her durumda çalışabilmeli. */
    private val repoRoot: File =
        File(System.getProperty("user.dir") ?: ".").let { cwd ->
            // gradle çalıştırırken cwd modül kökünde (app/) olur; ondan parent al.
            if (cwd.resolve("src/main/java").isDirectory) cwd.parentFile else cwd
        }

    /** Belirli bir ekran dosyasinda saveable kullanmasi gereken alanlar yasakli mi? */
    private fun assertSaveableUsedFor(
        screenPath: String,
        criticalStateNames: List<String>
    ) {
        val file = File(repoRoot, screenPath)
        assertThat(file.exists()).isTrue()
        val source = file.readText()
        criticalStateNames.forEach { stateName ->
            // "var <name> by remember {" kalipta kullanim regression sayilir.
            val violation = Regex(
                """\bvar\s+$stateName\s+by\s+remember\s*\{\s*mutableStateOf"""
            )
            val matches = violation.findAll(source).toList()
            assertWithMessage("$screenPath: '$stateName' rememberSaveable yerine remember kullaniyor")
                .that(matches)
                .isEmpty()
            // Pozitif kontrol: rememberSaveable kullanildigini da teyit et.
            val expected = Regex(
                """\bvar\s+$stateName\s+by\s+rememberSaveable\s*\{\s*mutableStateOf"""
            )
            assertWithMessage("$screenPath: '$stateName' rememberSaveable ile tanimli olmali")
                .that(expected.containsMatchIn(source))
                .isTrue()
        }
    }

    @Test
    fun `PhoneVerificationScreen kritik state'ler saveable kullanmali`() {
        assertSaveableUsedFor(
            "app/src/main/java/com/securechat/app/ui/screen/PhoneVerificationScreen.kt",
            listOf(
                "displayName",
                "phoneNumber",
                "countryCode",
                "showContactsPermissionDialog",
                "submitAttempted"
            )
        )
    }

    @Test
    fun `OtpVerificationScreen kritik state'ler saveable kullanmali`() {
        assertSaveableUsedFor(
            "app/src/main/java/com/securechat/app/ui/screen/OtpVerificationScreen.kt",
            listOf(
                "otpCode",
                "countdown",
                "canResend",
                "errorMessage",
                "showBackupPrompt"
            )
        )
        // `isLoading` BiLEREK saveable degil — coroutine rotation'da restart edilmez.
    }

    @Test
    fun `EmailOtpScreen kritik state'ler saveable kullanmali`() {
        assertSaveableUsedFor(
            "app/src/main/java/com/securechat/app/ui/screen/EmailOtpScreen.kt",
            listOf(
                "email",
                "otpCode",
                "step",
                "error",
                "info",
                "smtpDisabled"
            )
        )
        // `loading` BiLEREK saveable degil.
    }

    @Test
    fun `CreateGroupScreen kritik state'ler saveable kullanmali`() {
        assertSaveableUsedFor(
            "app/src/main/java/com/securechat/app/ui/screen/CreateGroupScreen.kt",
            listOf(
                "showPhoneInput",
                "selectedCountryCodeId"
            )
        )
    }
}
