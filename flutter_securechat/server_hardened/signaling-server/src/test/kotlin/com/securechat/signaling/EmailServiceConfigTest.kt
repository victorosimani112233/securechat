package com.securechat.signaling

import org.junit.jupiter.api.Assertions.assertDoesNotThrow
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Test

/**
 * SMTP yapilandirmasi fail-closed'dir.
 *
 * Kayit akisi e-posta OTP'sine baglidir. Eksik ya da sifresiz bir SMTP
 * yapilandirmasi sessizce kabul edilirse sistem "OTP'siz kayit" moduna
 * duser; bu, kayit kapisini tamamen kaldirmakla ayni sey olurdu.
 */
class EmailServiceConfigTest {

    private val valid = mapOf(
        "SMTP_HOST" to "smtp.example.invalid",
        "SMTP_FROM" to "no-reply@example.invalid",
        "SMTP_PORT" to "587",
        "SMTP_TLS" to "starttls",
    )

    @Test
    fun `a complete configuration is accepted`() {
        assertDoesNotThrow { EmailService.validate(valid) }
    }

    @Test
    fun `host and sender are mandatory`() {
        assertThrows(IllegalArgumentException::class.java) {
            EmailService.validate(valid - "SMTP_HOST")
        }
        assertThrows(IllegalArgumentException::class.java) {
            EmailService.validate(valid - "SMTP_FROM")
        }
        assertThrows(IllegalArgumentException::class.java) {
            EmailService.validate(valid + ("SMTP_HOST" to ""))
        }
    }

    @Test
    fun `transport encryption is mandatory`() {
        // "none" kabul edilseydi OTP kodlari ag uzerinde duz metin giderdi.
        for (mode in listOf("none", "plain", "", "tls-maybe")) {
            assertThrows(IllegalArgumentException::class.java) {
                EmailService.validate(valid + ("SMTP_TLS" to mode))
            }
        }
        assertDoesNotThrow { EmailService.validate(valid + ("SMTP_TLS" to "SSL")) }
        assertDoesNotThrow { EmailService.validate(valid + ("SMTP_TLS" to "StartTLS")) }
    }

    @Test
    fun `the port must be a real port`() {
        for (port in listOf("0", "70000", "-1")) {
            assertThrows(IllegalArgumentException::class.java) {
                EmailService.validate(valid + ("SMTP_PORT" to port))
            }
        }
        // Okunamayan deger varsayilan 587'ye duser.
        assertDoesNotThrow { EmailService.validate(valid + ("SMTP_PORT" to "not-a-port")) }
    }

    @Test
    fun `a username without a password is refused`() {
        assertThrows(IllegalArgumentException::class.java) {
            EmailService.validate(valid + ("SMTP_USERNAME" to "otp-sender"))
        }
        assertDoesNotThrow {
            EmailService.validate(
                valid + mapOf("SMTP_USERNAME" to "otp-sender", "SMTP_PASSWORD" to "secret"),
            )
        }
    }

    @Test
    fun `a password may not be supplied twice`() {
        assertThrows(IllegalArgumentException::class.java) {
            EmailService.validate(
                valid + mapOf(
                    "SMTP_USERNAME" to "otp-sender",
                    "SMTP_PASSWORD" to "secret",
                    "SMTP_PASSWORD_FILE" to "/run/secrets/smtp_password",
                ),
            )
        }
    }
}
