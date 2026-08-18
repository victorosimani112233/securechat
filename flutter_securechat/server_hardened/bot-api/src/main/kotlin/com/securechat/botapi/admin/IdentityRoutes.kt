package com.securechat.botapi.admin

import com.securechat.botapi.signal.PeerIdentityStore
import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import kotlinx.serialization.Serializable
import org.slf4j.LoggerFactory

private val log = LoggerFactory.getLogger("IdentityRoutes")

@Serializable
private data class ApproveRotationRequest(val recipientUserId: String, val deviceId: Int = 1)

private val UUID_PATTERN = Regex(
    "(?i)^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
)

/**
 * `/admin/identity` — alici identity pinlerinin operator gorunumu ve
 * rotasyon onayi.
 *
 * Bir alicinin identity key'i degistiginde bot gonderimi fail-closed
 * reddeder. Bu, sunucu tarafinda yapilan sessiz bir anahtar degisimini
 * gorunur kilar. Rotasyon ancak burada acikca onaylandiktan sonra kabul
 * edilir; onay pini duserur ve bir sonraki gonderim yeni anahtari
 * trust-on-first-use ile yeniden pinler.
 */
fun Route.identityRoutes() {

    get("/admin/identity") {
        val pins = PeerIdentityStore.listPins().map {
            mapOf(
                // Ham alici UUID'si tutulmaz; operator opaque index ve public
                // anahtarin parmak izini gorur.
                "recipientIndex" to it.recipientIndex,
                "deviceId" to it.deviceId.toString(),
                "fingerprint" to it.fingerprint,
            )
        }
        call.respond(mapOf("pins" to pins))
    }

    post("/admin/identity/approve-rotation") {
        val body = try {
            call.receive<ApproveRotationRequest>()
        } catch (_: Exception) {
            call.respond(HttpStatusCode.BadRequest, mapOf("error" to "recipientUserId gerekli"))
            return@post
        }
        if (!UUID_PATTERN.matches(body.recipientUserId) || body.deviceId !in 1..99) {
            call.respond(HttpStatusCode.BadRequest, mapOf("error" to "gecersiz alici"))
            return@post
        }
        val index = PeerIdentityStore.recipientIndex(body.recipientUserId)
        val cleared = PeerIdentityStore.approveRotation(index, body.deviceId)
        log.warn("[Admin] BOT_IDENTITY_ROTATION_APPROVED cleared={}", cleared)
        call.respond(mapOf("cleared" to cleared.toString()))
    }
}
