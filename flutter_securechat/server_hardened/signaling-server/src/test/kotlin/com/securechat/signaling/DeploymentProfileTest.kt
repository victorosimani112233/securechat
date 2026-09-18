package com.securechat.signaling

import org.junit.jupiter.api.Assertions.assertDoesNotThrow
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Gelistirme profili yalniz altyapi kapilarini gevsetir.
 *
 * Bu ayrimin testle sabitlenmesi onemlidir: profil zamanla "her seyi kapat"
 * anahtarina donusurse, urunun mesaj gizliligi iddiasi da onunla birlikte
 * sessizce kaybolur.
 */
class DeploymentProfileTest {

    private val development = mapOf("SECURECHAT_PROFILE" to "development")

    @Test
    fun `the profile must be selected explicitly`() {
        // Beyan yoksa davranis degismez: mevcut dagitimlar yanlislikla
        // gevsemez.
        assertFalse(DeploymentProfile.isDevelopment(emptyMap()))
        assertThrows(IllegalArgumentException::class.java) {
            ProductionDeploymentPolicy.validate(emptyMap())
        }
    }

    @Test
    fun `a contradictory profile declaration is refused`() {
        // Hangisinin kazandigi okuyucuya gore degisen bir yapilandirma,
        // guvenlik kapisinda kabul edilemez.
        assertThrows(IllegalArgumentException::class.java) {
            ProductionDeploymentPolicy.validate(
                development + ("PRIVACY_PRODUCTION_MODE" to "true"),
            )
        }
    }

    @Test
    fun `development skips infrastructure gates`() {
        // HSM, dogrulanmis PostgreSQL TLS'i, TLS'li SMTP, Firebase yolu ve
        // cevrimdisi Sealed Sender sertifikasi olmadan calisabilmeli.
        assertTrue(DeploymentProfile.isDevelopment(development))
        assertDoesNotThrow { ProductionDeploymentPolicy.validate(development) }
    }

    @Test
    fun `development still refuses plaintext queues`() {
        // Gevseyen sey altyapidir; sunucunun okunabilir zarf saklamasi degil.
        assertThrows(IllegalArgumentException::class.java) {
            ProductionDeploymentPolicy.validate(
                development + ("ALLOW_LEGACY_PLAINTEXT_QUEUE" to "true"),
            )
        }
    }

    @Test
    fun `legacy prekey fetch needs both the profile and an explicit opt-in`() {
        // Bayrak tek basina yetmez: production'da deger ne olursa olsun
        // klasik paket kullanici token'iyla verilmez.
        val optIn = mapOf("ALLOW_LEGACY_V1_PREKEY_FETCH" to "true")

        assertFalse(DeploymentProfile.allowsLegacyPreKeyFetch(optIn))
        assertFalse(DeploymentProfile.allowsLegacyPreKeyFetch(development))
        assertTrue(DeploymentProfile.allowsLegacyPreKeyFetch(development + optIn))
        assertFalse(
            DeploymentProfile.allowsLegacyPreKeyFetch(
                mapOf("PRIVACY_PRODUCTION_MODE" to "true") + optIn,
            ),
        )
    }

    @Test
    fun `production remains fully gated`() {
        val production = mapOf(
            "PRIVACY_PRODUCTION_MODE" to "true",
            "DATABASE_URL" to "jdbc:postgresql://db.internal/securechat?sslmode=verify-full",
            "DIRECTORY_OPRF_KEY_BACKEND" to "PKCS11",
            "SMTP_TLS" to "starttls",
            "FIREBASE_SERVICE_ACCOUNT_PATH" to "/run/secrets/firebase_service_account",
            "TURN_HOST" to "relay.example.invalid",
            "SEALED_SENDER_SERVER_CERTIFICATE" to "Zm9ybWF0LWNoZWNrZWQtZWxzZXdoZXJl",
            "SEALED_SENDER_TRUST_ROOT_PUBLIC_KEY" to "Zm9ybWF0LWNoZWNrZWQtZWxzZXdoZXJl",
        )

        assertDoesNotThrow { ProductionDeploymentPolicy.validate(production) }
        // Profil eklenmesi production kapilarini kaldirmaz.
        assertThrows(IllegalArgumentException::class.java) {
            ProductionDeploymentPolicy.validate(
                production + ("DIRECTORY_OPRF_KEY_BACKEND" to "PKCS8"),
            )
        }
    }
}
