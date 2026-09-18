package com.securechat.botapi.admin

import com.securechat.botapi.send.EmergencyStopFlag
import io.ktor.server.application.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import org.slf4j.LoggerFactory

private val log = LoggerFactory.getLogger("EmergencyRoutes")

/**
 * /admin/emergency endpoint'leri (stop/resume/status) — global kill switch.
 * Tetiklendiginde tum /v1/send istekleri 503 doner (cache miss bile).
 */
fun Route.emergencyRoutes() {

    post("/admin/emergency/stop") {
        EmergencyStopFlag.set()
        log.warn("[Admin] BOT_API_EMERGENCY_STOP_SET — tum send istekleri 503 dondurecek")
        call.respond(mapOf("emergency_stop" to true))
    }

    post("/admin/emergency/resume") {
        EmergencyStopFlag.clear()
        log.info("[Admin] BOT_API_EMERGENCY_RESUME — send istekleri tekrar isleniyor")
        call.respond(mapOf("emergency_stop" to false))
    }

    get("/admin/emergency/status") {
        call.respond(mapOf("emergency_stop" to EmergencyStopFlag.isTripped()))
    }
}
