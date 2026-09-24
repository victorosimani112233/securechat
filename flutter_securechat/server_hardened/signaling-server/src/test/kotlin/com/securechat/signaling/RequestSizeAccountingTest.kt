package com.securechat.signaling

import java.io.File
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Boyut muhasebesi.
 *
 * HTTP govdeleri ve WebSocket cerceveleri UTF-8 byte olarak sinirlanir.
 * Dosyalar parcali aktarilir; dakikalik dosya byte kotasi uygulanmaz.
 *
 * Bu yollar Ktor `ApplicationCall` gerektirdigi ve `ktor-server-test-host`
 * offline aynada bulunmadigi icin burada kaynak duzeyinde sabitlenir;
 * aritmetigin kendisi ayrica dogrulanir.
 */
class RequestSizeAccountingTest {

    private fun source(name: String): String =
        File("src/main/kotlin/com/securechat/signaling/$name").readLines()
            .filterNot { it.trimStart().startsWith("*") || it.trimStart().startsWith("//") }
            .joinToString("\n")

    @Test
    fun `a multi byte body is four times larger than its character count`() {
        // Emoji: 1 karakter, 4 byte.
        val text = "🎉".repeat(1_000)

        assertEquals(2_000, text.length) // surrogate cifti: 2 char
        assertEquals(4_000, text.toByteArray(Charsets.UTF_8).size)
        assertTrue(text.toByteArray(Charsets.UTF_8).size > text.length)
    }

    @Test
    fun `turkish characters also cost more than one byte`() {
        val text = "çağrı şifreli görüşme"

        assertTrue(text.toByteArray(Charsets.UTF_8).size > text.length)
    }

    @Test
    fun `the websocket frame ceiling is measured in utf 8 bytes`() {
        val websocket = source("WebSocketRoutes.kt")

        assertTrue(
            websocket.contains("text.toByteArray(Charsets.UTF_8).size"),
            "frame boyutu byte cinsinden olculmeli",
        )
        // `text.length` ile karsilastirma yapan bir tavan geri gelmemeli.
        assertTrue(
            !websocket.contains("text.length > MAX_MESSAGE_BYTES"),
            "karakter sayisiyla byte tavani karsilastirilmis",
        )
    }

    @Test
    fun `file transfers have no per minute byte quota but retain frame and message limits`() {
        val websocket = source("WebSocketRoutes.kt")
        assertTrue("file_chunk_bytes" !in RateLimiter.LIMITS)
        assertTrue(!websocket.contains("FILE_BYTE_RATE_LIMIT"))
        assertTrue(!websocket.contains("file_chunk_bytes"))
        assertTrue(websocket.contains("byteSize > MAX_MESSAGE_BYTES"))
        assertTrue(websocket.contains("""RateLimiter.allow("ws_message", userId)"""))
    }

    @Test
    fun `no http route reads a body without a ceiling`() {
        val http = source("HttpRoutes.kt")

        // `receiveBounded` / `receivePrivateDirectoryJson` disinda ham bir
        // `call.receive<...>()` govdeyi sinirsiz okur.
        val unbounded = Regex("""call\.receive<""").findAll(http).count()
        assertEquals(0, unbounded, "tavansiz govde okumasi var")
        assertTrue(http.contains("receiveBounded"))
    }

    @Test
    fun `every declared body ceiling is small enough to be a real bound`() {
        val http = source("HttpRoutes.kt")
        val limits = Regex("""const val (\w*BODY_LIMIT) = ([\d\s*]+)""")
            .findAll(http)
            .map { match ->
                val value = match.groupValues[2].split('*')
                    .map { it.trim().toInt() }
                    .reduce(Int::times)
                match.groupValues[1] to value
            }
            .toList()

        assertTrue(limits.isNotEmpty(), "hic govde tavani bulunamadi")
        for ((name, value) in limits) {
            assertTrue(value in 1..(1024 * 1024), "$name = $value byte, tavan olarak anlamsiz")
        }
    }
}
