package com.securechat.signaling

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Guvenilen proxy siniri.
 *
 * Uygulama reverse proxy arkasindadir; soket adresi proxy'nin adresidir ve
 * IP basina limitler bu yuzden tek kimlik uzerinde toplanir. `X-Forwarded-For`
 * okumak sarttir, fakat header'a kosulsuz guvenmek limitin tamamen
 * atlanmasina izin verir. Bu testler iki hatanin da yapilmadigini sabitler.
 */
class ClientAddressTest {

    /** Production fonksiyonunu, guvenilen liste enjekte edilerek cagirir. */
    private fun resolveWith(
        trustedProxies: String?,
        socketAddress: String,
        forwardedFor: String?,
    ): String = ClientAddress.resolve(
        socketAddress = socketAddress,
        forwardedFor = forwardedFor,
        trustedProxies = ClientAddress.parseTrusted(trustedProxies),
    )

    @Test
    fun `without a trusted list the header is ignored`() {
        assertEquals(
            "10.9.9.9",
            resolveWith(null, "10.9.9.9", "1.2.3.4"),
        )
        assertEquals(
            "10.9.9.9",
            resolveWith("", "10.9.9.9", "1.2.3.4"),
        )
    }

    @Test
    fun `a forged header from an untrusted client is ignored`() {
        // Istemci dogrudan baglanip header uydurursa limiti atlayamamali.
        assertEquals(
            "203.0.113.7",
            resolveWith("127.0.0.1", "203.0.113.7", "1.2.3.4"),
        )
    }

    @Test
    fun `a header from a trusted proxy identifies the real client`() {
        assertEquals(
            "203.0.113.7",
            resolveWith("127.0.0.1", "127.0.0.1", "203.0.113.7"),
        )
    }

    @Test
    fun `only the rightmost untrusted hop is taken from the chain`() {
        // Soldaki girdiler istemci tarafindan uydurulabilir; guvenilen
        // proxy'nin ekledigi en sagdaki guvenilmeyen adres gercek istemcidir.
        assertEquals(
            "203.0.113.7",
            resolveWith(
                "127.0.0.1,10.0.0.0/8",
                "127.0.0.1",
                "1.1.1.1, 203.0.113.7, 10.0.0.5",
            ),
        )
    }

    @Test
    fun `cidr ranges are honoured`() {
        val trusted = ClientAddress.parseTrusted("10.0.0.0/8")
        assertTrue(trusted.single().contains(java.net.InetAddress.getByName("10.1.2.3").address))
        assertFalse(trusted.single().contains(java.net.InetAddress.getByName("11.1.2.3").address))
    }

    @Test
    fun `a malformed trusted entry is dropped instead of widening trust`() {
        assertTrue(ClientAddress.parseTrusted("not-an-ip").isEmpty())
        assertTrue(ClientAddress.parseTrusted("10.0.0.0/99").isEmpty())
        // Gecerli girdi bozuk girdinin yaninda korunur.
        assertEquals(1, ClientAddress.parseTrusted("not-an-ip,127.0.0.1").size)
    }

    @Test
    fun `a hostname in the header is never resolved`() {
        // DNS cozumlemesi saldirgan kontrolundeki bir degerle tetiklenmemeli.
        assertEquals(
            "127.0.0.1",
            ClientAddress.resolve(
                socketAddress = "127.0.0.1",
                forwardedFor = "attacker.example.com",
                trustedProxies = ClientAddress.parseTrusted("127.0.0.1"),
            ),
        )
    }

    @Test
    fun `an empty chain falls back to the socket address`() {
        assertEquals(
            "127.0.0.1",
            resolveWith("127.0.0.1", "127.0.0.1", " , , "),
        )
    }
}
