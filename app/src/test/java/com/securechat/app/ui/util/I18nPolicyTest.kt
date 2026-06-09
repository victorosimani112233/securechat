package com.securechat.app.ui.util

import com.google.common.truth.Truth.assertWithMessage
import org.junit.Test
import java.io.File

/**
 * Sprint 1 ekranlarinda hardcoded Turkce metin kullaniminin regresyonunu engeller.
 *
 * Kapsam: label/placeholder/title/button Text("..."); dialog title ve body;
 * critical contentDescription'lar. Kapsam disi: log mesajlari, dokuman yorumlari,
 * compose-disi diagnostic string'ler.
 *
 * Kural: bilinen kullanici-yuzlu Turkce metinler artik strings.xml uzerinden
 * `stringResource(R.string.X)` ile gelmelidir. Bunlardan biri kaynak dosyada
 * literal olarak gorunurse regression hatasi atilir. Sprint 2'de kapsam buyur.
 */
class I18nPolicyTest {

    private val repoRoot: File =
        File(System.getProperty("user.dir") ?: ".").let { cwd ->
            if (cwd.resolve("src/main/java").isDirectory) cwd.parentFile else cwd
        }

    /**
     * Sprint 1 ekranlari + her birinde artik gorunmemesi gereken Turkce literal'ler.
     * `phrases` listesindeki herhangi biri kaynakta gecerse test fail.
     */
    private val POLICY = mapOf(
        "app/src/main/java/com/securechat/app/ui/screen/PhoneVerificationScreen.kt" to listOf(
            "\"Adınız\"", "\"Telefon Numarası\"", "\"Kod\"", "\"Başla\"",
            "\"Kayıt Ol\"", "\"Güvenli mesajlaşma\"", "\"Tekrar Dene\"", "\"Iptal\""
        ),
        "app/src/main/java/com/securechat/app/ui/screen/OtpVerificationScreen.kt" to listOf(
            "\"Dogrulama\"", "\"Doğrula\"", "\"Doğrulama Kodu\"", "\"Kodu Tekrar Gönder\"",
            "\"Hayir, yeni basla\"", "\"Evet, yedegi geri yukle\""
        ),
        "app/src/main/java/com/securechat/app/ui/screen/EmailOtpScreen.kt" to listOf(
            "\"E-posta\"", "\"E-posta Doğrulama\"", "\"6 Haneli Kod\"",
            "\"Kod Gönder\"", "\"Farklı e-posta kullan\"", "\"Geliştirme Modu — Atla\""
        ),
        "app/src/main/java/com/securechat/app/ui/screen/CreateGroupScreen.kt" to listOf(
            "\"Yeni Grup\"", "\"Oluştur\"", "\"Grup Adı\"", "\"Kişi ara...\"",
            "\"Numara ile Ekle\"", "\"Kayıtlı Kişiler\"", "\"Kullanıcı Bulunamadı\""
        ),
        // Sprint 6-B kapsamlari
        "app/src/main/java/com/securechat/app/ui/screen/ContactsScreen.kt" to listOf(
            "\"Davet Gönder\"", "\"Kapat\"", "\"Kişi ara...\"",
            "\"Rehber Erişimi Ver\"", "\"Davet Et\"", "\"Bağlantı Hatası\""
        ),
        "app/src/main/java/com/securechat/app/ui/screen/AddGroupMemberScreen.kt" to listOf(
            "\"Davet Gönder\"", "\"Kapat\"", "\"Kişi ara...\""
        )
    )

    @Test
    fun `Sprint 1 ekranlari hardcoded kritik Turkce metin icermemeli`() {
        for ((path, bannedPhrases) in POLICY) {
            val file = File(repoRoot, path)
            assertWithMessage("Ekran dosyasi bulunamadi: $path").that(file.exists()).isTrue()
            val source = file.readText()
            for (phrase in bannedPhrases) {
                val occurrences = source.split(phrase).size - 1
                assertWithMessage(
                    "$path: hardcoded '$phrase' bulundu — stringResource(R.string.X) ile degistir. " +
                        "Bulunan: $occurrences kez."
                )
                    .that(occurrences)
                    .isEqualTo(0)
            }
        }
    }
}
