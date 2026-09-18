package com.securechat.botapi.admin

import com.securechat.botapi.auth.ClientKeyCache
import com.securechat.botapi.db.ApiClientRepository
import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import kotlinx.serialization.Serializable
import org.slf4j.LoggerFactory
import java.time.Instant
import java.util.Base64
import com.securechat.botapi.http.BoundedBody
import kotlinx.serialization.json.Json

private val log = LoggerFactory.getLogger("ClientCrudRoutes")

/**
 * /admin/clients endpoint'leri (CRUD + rotate) — bot-admin-cli tarafindan kullanilir.
 *
 * Tum endpoint'ler X-Admin-Token header'ini gerektirir (AdminListener
 * interceptor'unda kontrol ediliyor). Sadece localhost / Unix socket
 * uzerinden erisilebilir.
 */
fun Route.clientCrudRoutes() {

    // POST /admin/clients — yeni client kaydet
    post("/admin/clients") {
        val body = try {
            decodeBounded<ClientAddRequest>(call)
        } catch (_: Exception) {
            call.respond(HttpStatusCode.BadRequest, mapOf("error" to "body_parse_failed"))
            return@post
        }

        // Public key normalize — base64 (standard veya url-safe) destekle
        val pubKey = try {
            decodePublicKey(body.publicKey)
        } catch (_: Exception) {
            call.respond(HttpStatusCode.BadRequest, mapOf("error" to "public_key_decode_failed"))
            return@post
        }
        if (pubKey.size != 32) {
            // Karisik tipli map serialize edilemez; sayilar metin olarak
            // verilir ki hata yaniti gercekten donebilsin.
            call.respond(
                HttpStatusCode.BadRequest,
                mapOf(
                    "error" to "public_key_size",
                    "expected" to "32",
                    "got" to pubKey.size.toString(),
                ),
            )
            return@post
        }

        // Alan sinirlari: sinirsiz allow-list, negatif/asiri kota veya cok
        // uzak bir expiry kabul edilmemeli.
        val invalidField = when {
            body.name.isBlank() || body.name.length > 128 -> "name"
            body.allowList.isEmpty() || body.allowList.size > MAX_ALLOW_LIST -> "allow_list"
            body.allowList.any { it.isBlank() || it.length > 128 } -> "allow_list_entry"
            body.allowList.any { !it.startsWith("user:") && !it.startsWith("group:") } ->
                "allow_list_scheme"
            body.allowList.distinct().size != body.allowList.size -> "allow_list_duplicate"
            (body.ratePerHour ?: 50) !in 1..MAX_RATE_PER_HOUR -> "rate_per_hour"
            (body.perRecipientPerDay ?: 500) !in 1..MAX_PER_RECIPIENT_PER_DAY ->
                "per_recipient_per_day"
            (body.expiresInDays ?: 1) !in 1..MAX_EXPIRY_DAYS -> "expires_in_days"
            else -> null
        }
        if (invalidField != null) {
            call.respond(
                HttpStatusCode.BadRequest,
                mapOf("error" to "invalid_field", "field" to invalidField),
            )
            return@post
        }

        val expires = body.expiresInDays?.let { Instant.now().plusSeconds(it * 86400L) }
        val kid = try {
            ApiClientRepository.create(
                name = body.name,
                publicKey = pubKey,
                allowList = body.allowList,
                ratePerHour = body.ratePerHour ?: 50,
                perRecipientPerDay = body.perRecipientPerDay ?: 500,
                expiresAt = expires
            )
        } catch (e: Exception) {
            log.warn("[Admin] Client olusturma hatasi: {}", e.javaClass.simpleName)
            call.respond(HttpStatusCode.BadRequest, mapOf("error" to "create_failed"))
            return@post
        }

        log.info("[Admin] BOT_API_CLIENT_REGISTERED")
        call.respond(HttpStatusCode.Created, ClientAddResponse(kid = kid, name = body.name))
    }

    // GET /admin/clients — list
    get("/admin/clients") {
        val rows = ApiClientRepository.listAll().map { it.toView() }
        call.respond(rows)
    }

    // DELETE /admin/clients/:kid — revoke
    delete("/admin/clients/{kid}") {
        val kid = call.parameters["kid"]
            ?: return@delete call.respond(HttpStatusCode.BadRequest, mapOf("error" to "kid yok"))
        val reason = call.request.queryParameters["reason"]
        val ok = ApiClientRepository.revoke(kid, reason)
        if (ok) {
            ClientKeyCache.broadcastInvalidate(kid)
            log.info("[Admin] BOT_API_CLIENT_REVOKED")
            call.respond(mapOf("revoked" to kid))
        } else {
            call.respond(HttpStatusCode.NotFound, mapOf("error" to "kid_not_found_or_already_revoked"))
        }
    }

    // POST /admin/clients/:kid/rotate — atomic: eski revoke + yeni client ayni allowList ile
    post("/admin/clients/{kid}/rotate") {
        val oldKid = call.parameters["kid"]
            ?: return@post call.respond(HttpStatusCode.BadRequest, mapOf("error" to "kid yok"))
        val body = try {
            decodeBounded<RotateRequest>(call)
        } catch (_: Exception) {
            call.respond(HttpStatusCode.BadRequest, mapOf("error" to "body_parse_failed"))
            return@post
        }
        val pubKey = try { decodePublicKey(body.newPublicKey) } catch (e: Exception) {
            call.respond(HttpStatusCode.BadRequest, mapOf("error" to "public_key_decode_failed"))
            return@post
        }
        if (pubKey.size != 32) {
            call.respond(HttpStatusCode.BadRequest, mapOf("error" to "public_key_size"))
            return@post
        }

        // Eski client'i bul (revoked olsa bile listAll'da var) — ayar miras alinir
        val existing = ApiClientRepository.listAll().firstOrNull { it.kid == oldKid }
            ?: return@post call.respond(HttpStatusCode.NotFound, mapOf("error" to "kid_not_found"))

        // Once yeni credential olusturulur, sonra eski iptal edilir.
        // Ters sirada create hatasi client'i credential'siz birakirdi:
        // eski anahtar iptal, yeni anahtar yok.
        val newKid = try {
            ApiClientRepository.create(
                name = existing.name,
                publicKey = pubKey,
                allowList = existing.allowList,
                ratePerHour = existing.ratePerHour,
                perRecipientPerDay = existing.perRecipientPerDay,
                expiresAt = existing.expiresAt
            )
        } catch (e: Exception) {
            log.warn("[Admin] Rotate basarisiz, eski credential korunuyor: {}", e.javaClass.simpleName)
            call.respond(HttpStatusCode.InternalServerError, mapOf("error" to "rotate_failed"))
            return@post
        }
        ApiClientRepository.revoke(oldKid, "rotate")
        ClientKeyCache.broadcastInvalidate(oldKid)
        log.info("[Admin] BOT_API_CLIENT_ROTATED")
        call.respond(mapOf("oldKid" to oldKid, "newKid" to newKid))
    }
}

private fun decodePublicKey(s: String): ByteArray {
    val trimmed = s.trim()
    return try {
        Base64.getDecoder().decode(trimmed)
    } catch (e: Exception) {
        Base64.getUrlDecoder().decode(trimmed)
    }
}

private fun ApiClientRepository.ClientSummary.toView() = ClientView(
    kid = kid,
    name = name,
    allowList = allowList,
    ratePerHour = ratePerHour,
    perRecipientPerDay = perRecipientPerDay,
    expiresAt = expiresAt?.toString(),
    revokedAt = revokedAt?.toString(),
    createdAt = createdAt.toString()
)

@Serializable
private data class ClientAddRequest(
    val name: String,
    val publicKey: String,            // base64 (standard veya url-safe)
    val allowList: List<String> = emptyList(),
    val ratePerHour: Int? = null,
    val perRecipientPerDay: Int? = null,
    val expiresInDays: Long? = null
)

@Serializable
private data class ClientAddResponse(val kid: String, val name: String)

/** Admin girdisi icin ust sinirlar. */
private const val MAX_ALLOW_LIST = 256
private const val MAX_RATE_PER_HOUR = 10_000
private const val MAX_PER_RECIPIENT_PER_DAY = 10_000
private const val MAX_EXPIRY_DAYS = 365

@Serializable
private data class RotateRequest(val newPublicKey: String)

@Serializable
private data class ClientView(
    val kid: String,
    val name: String,
    val allowList: List<String>,
    val ratePerHour: Int,
    val perRecipientPerDay: Int,
    val expiresAt: String?,
    val revokedAt: String?,
    val createdAt: String
)

/**
 * Tavanli admin govde okumasi.
 *
 * `call.receive<T>()` govdeyi sinirsiz okur. Admin yuzu yalniz Unix
 * socket'ten erisilse de sinirsiz okuma bir tavan olmadan birakilmamalidir.
 */
private suspend inline fun <reified T> decodeBounded(call: ApplicationCall): T {
    val bytes = BoundedBody.read(call, BoundedBody.CONTROL_LIMIT_BYTES)
        ?: throw IllegalArgumentException("body_too_large")
    return Json { ignoreUnknownKeys = true }
        .decodeFromString<T>(bytes.toString(Charsets.UTF_8))
}
