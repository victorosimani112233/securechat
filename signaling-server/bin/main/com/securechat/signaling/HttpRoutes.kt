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
data class RegisterRequest(val userId: String, val phoneNumber: String)

@Serializable
data class StatusResponse(
    val status: String,
    val onlineUsers: Int,
    val registeredUsers: Int
)

fun Application.configureRoutes(
    connectionManager: ConnectionManager,
    userRegistry: UserRegistry
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

        // Kullanici kaydı
        post("/api/v1/users/register") {
            val request = call.receive<RegisterRequest>()
            val user = userRegistry.registerUser(request.userId, request.phoneNumber)
            call.respond(ServerUser(user.userId, user.phoneHash))
        }

        // Online kullanici listesi (debug icin)
        get("/api/v1/users/online") {
            val online = connectionManager.getOnlineUsers()
            call.respond(mapOf("users" to online, "count" to online.size))
        }
    }
}
