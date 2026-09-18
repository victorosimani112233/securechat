package com.securechat.botapi.http

import io.ktor.http.HttpStatusCode
import io.ktor.server.application.ApplicationCall
import io.ktor.server.request.contentLength
import io.ktor.server.request.receiveChannel
import io.ktor.server.response.respond
import io.ktor.utils.io.core.readBytes

/**
 * Govde okuma tavani.
 *
 * Hicbir route govdeyi sinirsiz okumamalidir: `receiveChannel().toByteArray()`
 * gelen ne kadarsa o kadar bayti RAM'e alir, yani tek bir istek process'i
 * bellek baskisina sokabilir. Bildirilen `Content-Length` tek basina yeterli
 * degildir — chunked gonderimde bulunmayabilir ya da yalan olabilir — bu
 * yuzden okuma da tavan+1 bayt ile sinirlanir.
 */
object BoundedBody {

    /** Bot gonderim govdesi; downstream WebSocket cercevesi de bu buyuklukte sinirlidir. */
    const val SEND_LIMIT_BYTES = 256 * 1024

    /** Admin/kontrol govdeleri kucuk JSON'lardir. */
    const val CONTROL_LIMIT_BYTES = 8 * 1024

    /**
     * @return govde baytlari, tavan asilirsa null (413 yanitlanmistir).
     */
    suspend fun read(call: ApplicationCall, maximumBytes: Int): ByteArray? {
        val declared = call.request.contentLength()
        if (declared != null && declared > maximumBytes) {
            call.respond(HttpStatusCode.PayloadTooLarge, mapOf("error" to "body_too_large"))
            return null
        }
        val bytes = call.receiveChannel()
            .readRemaining(maximumBytes.toLong() + 1L)
            .readBytes()
        if (bytes.size > maximumBytes) {
            call.respond(HttpStatusCode.PayloadTooLarge, mapOf("error" to "body_too_large"))
            return null
        }
        return bytes
    }
}
