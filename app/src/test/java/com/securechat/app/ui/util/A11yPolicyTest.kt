package com.securechat.app.ui.util

import com.google.common.truth.Truth.assertWithMessage
import org.junit.Test
import java.io.File

/**
 * Sprint 8-B a11y discipline policy:
 * IconButton iclerindeki Icon'lar IconButton'un tikla aksiyonunu temsil eder ve
 * MUTLAKA contentDescription'a sahip olmalidir. TalkBack kullanicilari aksi
 * takdirde "Button" diye duyuyor — neyi yapacaklarini bilmiyor.
 *
 * Bu test sadece bilinen hardcoded TR contentDescription'larin regresyonunu
 * onler. Pure decoration Icon (TopAppBar disinda metinle birlikte gosterilen)
 * `contentDescription = null` olabilir ve bu kapsam disindadir.
 *
 * Sprint 8-B'de cevirilen hardcoded literal'ler bu listede.
 */
class A11yPolicyTest {

    private val repoRoot: File =
        File(System.getProperty("user.dir") ?: ".").let { cwd ->
            if (cwd.resolve("src/main/java").isDirectory) cwd.parentFile else cwd
        }

    private val SCREENS = listOf(
        "app/src/main/java/com/securechat/app/ui/screen/ContactsScreen.kt",
        "app/src/main/java/com/securechat/app/ui/screen/AddGroupMemberScreen.kt",
        "app/src/main/java/com/securechat/app/ui/screen/SettingsScreen.kt",
        "app/src/main/java/com/securechat/app/ui/screen/ConversationsScreen.kt",
        "app/src/main/java/com/securechat/app/ui/screen/GroupInfoScreen.kt"
    )

    /**
     * Bu hardcoded TR contentDescription literal'leri artik strings.xml uzerinden
     * stringResource ile gelmelidir. Sprint 8-B kapsaminda cevirildiler;
     * geri donus olursa bu test fail eder.
     */
    private val BANNED_LITERALS = listOf(
        "contentDescription = \"Geri\"",
        "contentDescription = \"Temizle\"",
        "contentDescription = \"Daha Fazla\"",
        "contentDescription = \"Bağlantı durumu\"",
        "contentDescription = \"Sohbet başlat\"",
        "contentDescription = \"Üye İşlemleri\""
    )

    @Test
    fun `Sprint 8-B ekranlarinda banned contentDescription literal yok`() {
        for (path in SCREENS) {
            val file = File(repoRoot, path)
            assertWithMessage("Ekran bulunamadi: $path").that(file.exists()).isTrue()
            val source = file.readText()
            for (banned in BANNED_LITERALS) {
                val occurrences = source.split(banned).size - 1
                assertWithMessage(
                    "$path: hardcoded '$banned' bulundu — stringResource(R.string.X) ile degistir. " +
                        "Bulunan: $occurrences kez."
                )
                    .that(occurrences)
                    .isEqualTo(0)
            }
        }
    }
}
