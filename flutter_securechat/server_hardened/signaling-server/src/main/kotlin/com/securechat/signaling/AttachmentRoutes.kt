package com.securechat.signaling

import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.ApplicationCall
import io.ktor.server.application.call
import io.ktor.server.request.header
import io.ktor.server.request.receiveChannel
import io.ktor.server.response.header
import io.ktor.server.response.respond
import io.ktor.server.response.respondFile
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import io.ktor.server.routing.post
import kotlinx.serialization.Serializable

@Serializable
data class AttachmentUploadResponse(val id: String, val expiresAt: Long)

/**
 * Sifreli ek yukleme ve indirme. Kimlik dogrulamasi zorunludur; kimlik
 * 256 bit rastgeledir ve yalniz uctan uca sifreli isaretciyle paylasilir.
 */
fun Route.attachmentRoutes(
    store: AttachmentStore,
    requireAuth: suspend (ApplicationCall) -> String?,
) {
    post("/api/v1/attachments") {
        val userId = requireAuth(call) ?: return@post
        val length = call.request.header(HttpHeaders.ContentLength)?.toLongOrNull()
        if (length == null || length <= 0) {
            call.respond(HttpStatusCode.LengthRequired, mapOf("error" to "length_required"))
            return@post
        }
        if (length > AttachmentStore.MAX_BYTES) {
            call.respond(HttpStatusCode.PayloadTooLarge, mapOf("error" to "attachment_too_large"))
            return@post
        }
        if (!RateLimiter.allow("attachment_upload", userId) ||
            !RateLimiter.allowBytes("attachment_upload_bytes", userId, length.coerceAtMost(Int.MAX_VALUE.toLong()).toInt())
        ) {
            call.respond(HttpStatusCode.TooManyRequests, mapOf("error" to "Rate limit asildi"))
            return@post
        }
        val id = try {
            store.write(call.receiveChannel(), length)
        } catch (_: IllegalArgumentException) {
            call.respond(HttpStatusCode.BadRequest, mapOf("error" to "invalid_attachment"))
            return@post
        }
        val path = store.file(id)
        if (path == null) {
            call.respond(HttpStatusCode.InternalServerError, mapOf("error" to "attachment_unavailable"))
            return@post
        }
        Metrics.attachmentUploads.increment()
        call.respond(HttpStatusCode.Created, AttachmentUploadResponse(id, store.expiresAt(path)))
    }

    get("/api/v1/attachments/{id}") {
        val userId = requireAuth(call) ?: return@get
        if (!RateLimiter.allow("attachment_download", userId)) {
            call.respond(HttpStatusCode.TooManyRequests, mapOf("error" to "Rate limit asildi"))
            return@get
        }
        val path = call.parameters["id"]?.let(store::file)
        if (path == null) {
            call.respond(HttpStatusCode.NotFound, mapOf("error" to "attachment_not_found"))
            return@get
        }
        call.response.header(HttpHeaders.CacheControl, "no-store")
        // Icerik sifreli ve opaktir; tur bilgisi isaretcidedir.
        call.respondFile(path.toFile())
    }
}
