package com.securechat.signaling

import java.util.Base64
import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Test
import org.signal.libsignal.metadata.certificate.ServerCertificate
import org.signal.libsignal.protocol.ecc.Curve

/**
 * Production yapilandirmasi: trust root ozel anahtari relay'de bulunmaz.
 *
 * Sunucu yalniz cevrimdisi imzalanmis bir server certificate ve ona karsilik
 * gelen server anahtariyla calisir. Boylece relay ele gecse bile saldirgan yeni
 * sender certificate uretemez.
 */
class SealedSenderOfflineTrustRootTest {

    private val trustRoot = Curve.generateKeyPair()
    private val server = Curve.generateKeyPair()
    private val certificate = ServerCertificate(trustRoot.privateKey, 1, server.publicKey)

    private fun encode(material: ByteArray) = Base64.getEncoder().encodeToString(material)

    private fun offlineEnvironment(): Map<String, String> = mapOf(
        "PRIVACY_PRODUCTION_MODE" to "true",
        "SEALED_SENDER_SERVER_PRIVATE_KEY" to encode(server.privateKey.serialize()),
        "SEALED_SENDER_SERVER_CERTIFICATE" to encode(certificate.serialized),
        "SEALED_SENDER_TRUST_ROOT_PUBLIC_KEY" to encode(trustRoot.publicKey.serialize()),
    )

    @Test
    fun `an offline issued certificate loads without the trust root private key`() {
        val state = SealedSenderCertificateIssuer.load(offlineEnvironment())

        assertArrayEquals(trustRoot.publicKey.serialize(), state.trustRootPublicKey)
        assertArrayEquals(certificate.serialized, state.serverCertificate.serialized)
    }

    @Test
    fun `production refuses to fall back to in-process certificate issuance`() {
        // Trust root ozel anahtari verilmis olsa bile production bu yolu
        // kabul etmemelidir; anahtarin makinede bulunmasi zaten hatadir.
        val fallback = mapOf(
            "PRIVACY_PRODUCTION_MODE" to "true",
            "SEALED_SENDER_SERVER_PRIVATE_KEY" to encode(server.privateKey.serialize()),
            "SEALED_SENDER_TRUST_ROOT_PRIVATE_KEY" to encode(trustRoot.privateKey.serialize()),
        )

        assertThrows(IllegalArgumentException::class.java) {
            SealedSenderCertificateIssuer.load(fallback)
        }
    }

    @Test
    fun `a certificate signed by a different root is refused`() {
        // Yanlis eslenmis bir set sessizce yuklenirse sunucu saglikli gorunur
        // ama urettigi her zarf istemcide reddedilir.
        val otherRoot = Curve.generateKeyPair()

        assertThrows(IllegalArgumentException::class.java) {
            SealedSenderCertificateIssuer.load(
                offlineEnvironment() +
                    ("SEALED_SENDER_TRUST_ROOT_PUBLIC_KEY" to encode(otherRoot.publicKey.serialize())),
            )
        }
    }

    @Test
    fun `a certificate that does not match the server key is refused`() {
        val otherServer = Curve.generateKeyPair()

        assertThrows(IllegalArgumentException::class.java) {
            SealedSenderCertificateIssuer.load(
                offlineEnvironment() +
                    ("SEALED_SENDER_SERVER_PRIVATE_KEY" to encode(otherServer.privateKey.serialize())),
            )
        }
    }
}
