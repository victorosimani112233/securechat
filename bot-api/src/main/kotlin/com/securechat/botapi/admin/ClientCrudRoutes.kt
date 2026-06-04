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
            call.receive<ClientAddRequest>()
        } catch (e: Exception) {
            call.respond(HttpStatusCode.BadRequest, mapOf("error" to "body_parse: ${e.message}"))
            return@post
        }

        // Public key normalize — base64 (standard veya url-safe) destekle
        val pubKey = try {
            decodePublicKey(body.publicKey)
        } catch (e: Exception) {
            call.respond(HttpStatusCode.BadRequest, mapOf("error" to "public_key_decode_failed: ${e.message}"))
            return@post
        }
        if (pubKey.size != 32) {
            call.respond(HttpStatusCode.BadRequest, mapOf(
                "error" to "public_key_size",
                "expected" to 32,
                "got" to pubKey.size
            ))
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
            log.warn("[Admin] Client olusturma hatasi: {}", e.message)
            call.respond(HttpStatusCode.BadRequest, mapOf("error" to (e.message ?: "create_failed")))
            return@post
        }

        log.info("[Admin] BOT_API_CLIENT_REGISTERED kid={}, name={}", kid, body.name)
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
            log.info("[Admin] BOT_API_CLIENT_REVOKED kid={}, reason={}", kid, reason)
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
            call.receive<RotateRequest>()
        } catch (e: Exception) {
            call.respond(HttpStatusCode.BadRequest, mapOf("error" to "body_parse: ${e.message}"))
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

        // Eski revoke
        ApiClientRepository.revoke(oldKid, "rotate")
        ClientKeyCache.broadcastInvalidate(oldKid)

        // Yeni client — ayni ayarlarla
        val newKid = ApiClientRepository.create(
            name = existing.name,
            publicKey = pubKey,
            allowList = existing.allowList,
            ratePerHour = existing.ratePerHour,
            perRecipientPerDay = existing.perRecipientPerDay,
            expiresAt = existing.expiresAt
        )
        log.info("[Admin] BOT_API_CLIENT_ROTATED old={}, new={}", oldKid, newKid)
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
    lastUsedAt = lastUsedAt?.toString(),
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
    val lastUsedAt: String?,
    val createdAt: String
)
