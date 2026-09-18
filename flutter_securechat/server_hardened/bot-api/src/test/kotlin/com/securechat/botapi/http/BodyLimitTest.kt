package com.securechat.botapi.http

import com.google.common.truth.Truth.assertThat
import java.io.File
import org.junit.jupiter.api.Test

/**
 * Bot govde tavanlari.
 *
 * `receiveChannel().toByteArray()` gelen ne kadarsa o kadar bayti RAM'e
 * alir: tek bir istek process'i bellek baskisina sokabilirdi. Gonderim ve
 * admin route'lari artik tavanli okur.
 *
 * Yollar Ktor `ApplicationCall` gerektirdigi ve `ktor-server-test-host`
 * offline aynada bulunmadigi icin burada kaynak duzeyinde sabitlenir.
 */
class BodyLimitTest {

    private fun source(path: String): String =
        File("src/main/kotlin/com/securechat/botapi/$path").readLines()
            .filterNot { it.trimStart().startsWith("*") || it.trimStart().startsWith("//") }
            .joinToString("\n")

    @Test
    fun `the send pipeline reads a bounded body`() {
        val pipeline = source("send/SendPipeline.kt")

        assertThat(pipeline).contains("BoundedBody.read(call, BoundedBody.SEND_LIMIT_BYTES)")
        assertThat(pipeline).doesNotContain("receiveChannel().toByteArray()")
    }

    @Test
    fun `admin routes do not read an unbounded body`() {
        for (path in listOf("admin/ClientCrudRoutes.kt", "admin/IdentityRoutes.kt")) {
            val routes = source(path)

            assertThat(routes).doesNotContain("call.receive<")
            assertThat(routes).contains("BoundedBody.CONTROL_LIMIT_BYTES")
        }
    }

    @Test
    fun `the ceilings are actual bounds rather than nominal ones`() {
        // Gonderim govdesi downstream WebSocket cercevesinden buyuk olamaz;
        // kontrol govdeleri kucuk JSON'lardir.
        assertThat(BoundedBody.SEND_LIMIT_BYTES).isAtMost(256 * 1024)
        assertThat(BoundedBody.SEND_LIMIT_BYTES).isGreaterThan(0)
        assertThat(BoundedBody.CONTROL_LIMIT_BYTES).isAtMost(64 * 1024)
        assertThat(BoundedBody.CONTROL_LIMIT_BYTES).isGreaterThan(0)
    }

    @Test
    fun `the reader checks the declared length and the actual stream`() {
        val bounded = source("http/BoundedBody.kt")

        // Bildirilen Content-Length yalan olabilir ya da chunked gonderimde
        // hic bulunmayabilir; okuma da sinirlanmali.
        assertThat(bounded).contains("request.contentLength()")
        assertThat(bounded).contains("readRemaining(maximumBytes.toLong() + 1L)")
        assertThat(bounded).contains("bytes.size > maximumBytes")
        assertThat(bounded).contains("PayloadTooLarge")
    }
}
