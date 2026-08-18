package com.securechat.signaling

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertInstanceOf
import org.junit.jupiter.api.Test
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.PrivateKey
import java.security.Signature
import java.util.Base64
import java.util.UUID

/**
 * Servis assertion sozlesmesi.
 *
 * Buradaki uretim adimlari bot-api tarafindaki `BotServiceTokenMinter` ile
 * birebir ayni bicimi kurar; iki modul birbirine bagimli olmadigi icin bicim
 * her iki tarafta da testle sabitlenir.
 */
class ServiceAssertionTest {

    private val encoder: Base64.Encoder = Base64.getUrlEncoder().withoutPadding()
    private val subject = "123e4567-e89b-42d3-a456-426614174000"

    private fun keyPair(): KeyPair = KeyPairGenerator.getInstance("Ed25519").generateKeyPair()

    private fun assertion(
        key: PrivateKey,
        subject: String = this.subject,
        scope: String = "prekey.upload",
        issuedAt: Long = System.currentTimeMillis() / 1000,
        lifetimeSeconds: Long = 60,
        jti: String = UUID.randomUUID().toString(),
    ): String {
        val payload =
            """{"sub":"$subject","scp":"$scope","iat":$issuedAt,""" +
                """"exp":${issuedAt + lifetimeSeconds},"jti":"$jti"}"""
        val signingInput = "sc1.${encoder.encodeToString(payload.toByteArray(Charsets.UTF_8))}"
        val signature = Signature.getInstance("Ed25519").run {
            initSign(key)
            update(signingInput.toByteArray(Charsets.US_ASCII))
            sign()
        }
        return "$signingInput.${encoder.encodeToString(signature)}"
    }

    @Test
    fun `a correctly scoped assertion is accepted`() {
        val keys = keyPair()
        val result = ServiceAssertion.verify(
            assertion(keys.private),
            keys.public,
            ServiceAssertion.Scope.PREKEY_UPLOAD,
        )
        assertEquals(
            ServiceAssertion.Result.Accepted(subject, ServiceAssertion.Scope.PREKEY_UPLOAD),
            result,
        )
    }

    @Test
    fun `an assertion signed by another key is rejected`() {
        val attacker = keyPair()
        val server = keyPair()
        val result = ServiceAssertion.verify(
            assertion(attacker.private),
            server.public,
            ServiceAssertion.Scope.PREKEY_UPLOAD,
        )
        assertEquals(ServiceAssertion.Result.Rejected, result)
    }

    @Test
    fun `scope is not interchangeable`() {
        val keys = keyPair()
        // Yayin yetkisi olan bir assertion WS baglantisi acamaz.
        assertEquals(
            ServiceAssertion.Result.Rejected,
            ServiceAssertion.verify(
                assertion(keys.private, scope = "prekey.upload"),
                keys.public,
                ServiceAssertion.Scope.WS_CONNECT,
            ),
        )
        assertEquals(
            ServiceAssertion.Result.Rejected,
            ServiceAssertion.verify(
                assertion(keys.private, scope = "account.delete"),
                keys.public,
                ServiceAssertion.Scope.PREKEY_UPLOAD,
            ),
        )
    }

    @Test
    fun `expired and long lived assertions are rejected`() {
        val keys = keyPair()
        val now = System.currentTimeMillis() / 1000

        assertEquals(
            ServiceAssertion.Result.Rejected,
            ServiceAssertion.verify(
                assertion(keys.private, issuedAt = now - 600, lifetimeSeconds = 60),
                keys.public,
                ServiceAssertion.Scope.PREKEY_UPLOAD,
                nowSeconds = now,
            ),
        )
        // Kalici credential uretilemez: omur ust siniri asilirsa reddedilir.
        assertEquals(
            ServiceAssertion.Result.Rejected,
            ServiceAssertion.verify(
                assertion(keys.private, lifetimeSeconds = ServiceAssertion.MAX_LIFETIME_SECONDS + 1),
                keys.public,
                ServiceAssertion.Scope.PREKEY_UPLOAD,
            ),
        )
    }

    @Test
    fun `a future dated assertion beyond the skew window is rejected`() {
        val keys = keyPair()
        val now = System.currentTimeMillis() / 1000
        assertEquals(
            ServiceAssertion.Result.Rejected,
            ServiceAssertion.verify(
                assertion(keys.private, issuedAt = now + 600),
                keys.public,
                ServiceAssertion.Scope.PREKEY_UPLOAD,
                nowSeconds = now,
            ),
        )
    }

    @Test
    fun `a tampered payload invalidates the signature`() {
        val keys = keyPair()
        val original = assertion(keys.private)
        val parts = original.split('.')
        val forgedPayload = encoder.encodeToString(
            """{"sub":"00000000-0000-4000-8000-000000000000","scp":"prekey.upload",""".toByteArray() +
                """"iat":1,"exp":2,"jti":"x"}""".toByteArray(),
        )
        val forged = "${parts[0]}.$forgedPayload.${parts[2]}"
        assertEquals(
            ServiceAssertion.Result.Rejected,
            ServiceAssertion.verify(forged, keys.public, ServiceAssertion.Scope.PREKEY_UPLOAD),
        )
    }

    @Test
    fun `malformed envelopes are rejected without throwing`() {
        val keys = keyPair()
        for (candidate in listOf(
            "",
            "sc1",
            "sc1.only-two",
            "sc2.${encoder.encodeToString("{}".toByteArray())}.AAAA",
            "sc1.!!!not-base64!!!.AAAA",
            "sc1.${encoder.encodeToString("not-json".toByteArray())}.AAAA",
        )) {
            assertInstanceOf(
                ServiceAssertion.Result.Rejected::class.java,
                ServiceAssertion.verify(
                    candidate,
                    keys.public,
                    ServiceAssertion.Scope.PREKEY_UPLOAD,
                ),
            )
        }
    }

    @Test
    fun `a non uuid subject is rejected`() {
        val keys = keyPair()
        assertEquals(
            ServiceAssertion.Result.Rejected,
            ServiceAssertion.verify(
                assertion(keys.private, subject = "registration-grant"),
                keys.public,
                ServiceAssertion.Scope.PREKEY_UPLOAD,
            ),
        )
    }
}
