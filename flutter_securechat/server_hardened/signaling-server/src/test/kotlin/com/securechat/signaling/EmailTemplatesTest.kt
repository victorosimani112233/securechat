package com.securechat.signaling

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Kod e-postalari ayni Turkce bicimi kullanir (QA 2026-10-13 T9).
 *
 * Kurtarma e-postasi Ingilizce tek satirdi ("Your account recovery code"),
 * kayit dogrulama e-postasi ise Turkce ve bicimliydi.
 */
class EmailTemplatesTest {

    @Test
    fun `every purpose renders a Turkish formatted code mail`() {
        for (purpose in EmailTemplates.Purpose.entries) {
            val mail = EmailTemplates.code(purpose, "819179")

            assertTrue(mail.html.contains("819179"), purpose.name)
            assertTrue(mail.text.contains("819179"), purpose.name)
            assertTrue(mail.html.contains("10 dakika"), purpose.name)
            assertTrue(mail.text.contains("10 dakika"), purpose.name)
            assertTrue(mail.html.contains("Bu isteği siz yapmadıysanız"), purpose.name)
            for (english in listOf("Your ", "code:", "Expires in", "recovery code")) {
                assertFalse(mail.subject.contains(english), "${purpose.name}: $english")
                assertFalse(mail.html.contains(english), "${purpose.name}: $english")
                assertFalse(mail.text.contains(english), "${purpose.name}: $english")
            }
        }
    }

    @Test
    fun `subjects tell the purposes apart`() {
        assertEquals("SecureChat — Doğrulama Kodu", EmailTemplates.code(EmailTemplates.Purpose.REGISTRATION, "1").subject)
        assertEquals("SecureChat — Hesap Kurtarma Kodu", EmailTemplates.code(EmailTemplates.Purpose.ACCOUNT_RECOVERY, "1").subject)
        assertEquals(
            "SecureChat — Kurtarma E-postası Doğrulama",
            EmailTemplates.code(EmailTemplates.Purpose.RECOVERY_ENROLLMENT, "1").subject,
        )
    }

    @Test
    fun `the code is escaped and digits only reach the mail`() {
        val mail = EmailTemplates.code(EmailTemplates.Purpose.ACCOUNT_RECOVERY, "<b>12</b>")

        assertFalse(mail.html.contains("<b>12</b>"))
    }
}
