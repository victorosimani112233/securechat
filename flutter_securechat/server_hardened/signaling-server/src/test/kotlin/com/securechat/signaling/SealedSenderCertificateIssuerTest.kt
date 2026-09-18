package com.securechat.signaling

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.signal.libsignal.metadata.certificate.CertificateValidator
import org.signal.libsignal.metadata.certificate.InvalidCertificateException
import org.signal.libsignal.metadata.certificate.SenderCertificate
import org.signal.libsignal.protocol.ecc.Curve

class SealedSenderCertificateIssuerTest {
    @Test
    fun `issued certificate is bound to sender identity and short lived`() {
        val identity = Curve.generateKeyPair()
        val now = 1_900_000_000_000L
        val issued = SealedSenderCertificateIssuer.issue(
            senderId = "bf86f9ed-f640-41b7-8c22-58c076982b09",
            senderIdentityPublicKey = identity.publicKey.serialize(),
            nowMillis = now,
        )
        val certificate = SenderCertificate(issued.certificate)
        val validator = CertificateValidator(
            Curve.decodePoint(issued.trustRootPublicKey, 0),
        )

        validator.validate(certificate, now)
        assertEquals("bf86f9ed-f640-41b7-8c22-58c076982b09", certificate.senderUuid)
        assertEquals(1, certificate.senderDeviceId)
        assertTrue(certificate.key.serialize().contentEquals(identity.publicKey.serialize()))
        assertEquals(now + 24L * 60L * 60L * 1000L, certificate.expiration)
        assertThrows(InvalidCertificateException::class.java) {
            validator.validate(certificate, certificate.expiration + 1)
        }
    }
}
