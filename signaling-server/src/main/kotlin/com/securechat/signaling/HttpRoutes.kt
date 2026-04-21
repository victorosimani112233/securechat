package com.securechat.signaling

import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import kotlinx.serialization.Serializable

@Serializable
data class CheckUsersRequest(val hashes: List<String>)

@Serializable
data class CheckUsersResponse(val users: List<ServerUser>)

@Serializable
data class ServerUser(val userId: String, val phoneHash: String)

@Serializable
data class RegisterRequest(val userId: String, val phoneHash: String, val encryptedPhone: String? = null)

@Serializable
data class PhoneLookupResponse(val userId: String, val encryptedPhone: String?)

@Serializable
data class StatusResponse(
    val status: String,
    val onlineUsers: Int,
    val registeredUsers: Int
)

@Serializable
data class FcmRegisterRequest(val userId: String, val fcmToken: String)

@Serializable
data class FcmUnregisterRequest(val userId: String)

fun Application.configureRoutes(
    connectionManager: ConnectionManager,
    userRegistry: UserRegistry,
    fcmTokenStore: FcmTokenStore? = null
) {
    routing {
        // Sunucu durumu
        get("/") {
            call.respond(
                StatusResponse(
                    status = "ok",
                    onlineUsers = connectionManager.getOnlineCount(),
                    registeredUsers = userRegistry.getUserCount()
                )
            )
        }

        get("/health") {
            call.respondText("OK", ContentType.Text.Plain)
        }

        // Kullanici kesfi API (contacts-agent bunu kullanir)
        post("/api/v1/users/check") {
            val request = call.receive<CheckUsersRequest>()
            val matched = userRegistry.checkRegisteredHashes(request.hashes)
            val response = CheckUsersResponse(
                users = matched.map { ServerUser(it.userId, it.phoneHash) }
            )
            println("[API] Kullanici sorgusu: ${request.hashes.size} hash, ${matched.size} eslesme")
            call.respond(response)
        }

        // Kullanici kaydi — UUID, phoneHash ve sifreli telefon numarasi alir
        // encryptedPhone istemcide AES-GCM ile sifreli, sunucu cozemez
        post("/api/v1/users/register") {
            val request = call.receive<RegisterRequest>()
            val user = userRegistry.registerUserByHash(request.userId, request.phoneHash, request.encryptedPhone)
            call.respond(ServerUser(user.userId, user.phoneHash))
        }

        // Kullanici sifreli telefon numarasi sorgulama — bilinmeyen kisi icin
        // Sunucu sifreli veriyi olduğu gibi dondurur, cozme anahtari yok
        get("/api/v1/users/{userId}/phone") {
            val userId = call.parameters["userId"] ?: run {
                call.respond(HttpStatusCode.BadRequest, mapOf("error" to "userId gerekli"))
                return@get
            }
            val user = userRegistry.getUserByUserId(userId)
            if (user == null) {
                call.respond(HttpStatusCode.NotFound, mapOf("error" to "Kullanici bulunamadi"))
            } else {
                call.respond(PhoneLookupResponse(userId = user.userId, encryptedPhone = user.encryptedPhone))
            }
        }

        // Online kullanici listesi (debug icin)
        get("/api/v1/users/online") {
            val online = connectionManager.getOnlineUsers()
            call.respond(mapOf("users" to online, "count" to online.size))
        }

        // --- FCM Token Yonetimi ---

        // FCM token kaydi — cihaz acildiginda veya token yenilendiginde cagirilir
        post("/api/v1/fcm/register") {
            if (fcmTokenStore == null) {
                call.respond(HttpStatusCode.ServiceUnavailable, mapOf("error" to "FCM devre disi"))
                return@post
            }
            val request = call.receive<FcmRegisterRequest>()
            fcmTokenStore.registerToken(request.userId, request.fcmToken)
            println("[API] FCM token kaydedildi: ${request.userId}")
            call.respond(HttpStatusCode.OK, mapOf("status" to "ok"))
        }

        // FCM token silme — logout durumunda cagirilir
        post("/api/v1/fcm/unregister") {
            if (fcmTokenStore == null) {
                call.respond(HttpStatusCode.ServiceUnavailable, mapOf("error" to "FCM devre disi"))
                return@post
            }
            val request = call.receive<FcmUnregisterRequest>()
            fcmTokenStore.removeToken(request.userId)
            println("[API] FCM token silindi: ${request.userId}")
            call.respond(HttpStatusCode.OK, mapOf("status" to "ok"))
        }
    }
}
