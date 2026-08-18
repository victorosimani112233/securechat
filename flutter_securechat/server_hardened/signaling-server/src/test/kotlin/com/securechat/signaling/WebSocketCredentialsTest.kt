package com.securechat.signaling

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

class WebSocketCredentialsTest {

    @Test
    fun `bearer header is the only accepted carrier`() {
        assertEquals(
            WebSocketCredentials.Result.Accepted("jwt-value"),
            WebSocketCredentials.extract("Bearer jwt-value", null),
        )
        assertEquals(
            WebSocketCredentials.Result.Accepted("jwt-value"),
            WebSocketCredentials.extract("Bearer   jwt-value  ", null),
        )
    }

    @Test
    fun `a query token is rejected instead of being used`() {
        assertEquals(
            WebSocketCredentials.Result.TokenInQuery,
            WebSocketCredentials.extract(null, "jwt-value"),
        )
    }

    @Test
    fun `a query token is rejected even when a valid header is also present`() {
        // Proxy logu token'i zaten yakalamistir; header'a dusup baglantiyi
        // kabul etmek sizintiyi gorunmez kilar.
        assertEquals(
            WebSocketCredentials.Result.TokenInQuery,
            WebSocketCredentials.extract("Bearer jwt-value", "jwt-value"),
        )
    }

    @Test
    fun `missing and malformed credentials are distinguished`() {
        assertEquals(WebSocketCredentials.Result.Missing, WebSocketCredentials.extract(null, null))
        assertEquals(WebSocketCredentials.Result.Missing, WebSocketCredentials.extract("   ", null))
        assertEquals(WebSocketCredentials.Result.Missing, WebSocketCredentials.extract(null, "   "))
        assertEquals(
            WebSocketCredentials.Result.MalformedHeader,
            WebSocketCredentials.extract("jwt-value", null),
        )
        assertEquals(
            WebSocketCredentials.Result.MalformedHeader,
            WebSocketCredentials.extract("Basic dXNlcjpwYXNz", null),
        )
        assertEquals(
            WebSocketCredentials.Result.MalformedHeader,
            WebSocketCredentials.extract("Bearer    ", null),
        )
    }
}
