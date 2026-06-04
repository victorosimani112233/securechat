package com.securechat.botapi.publicapi

import com.securechat.botapi.send.SendPipeline
import io.ktor.server.application.*
import io.ktor.server.routing.*

/**
 * Public listener'in TEK endpoint'i: POST /v1/send.
 * SendPipeline orchestration'i tum guard'lari + Signal encrypt + WS delivery yapar.
 */
private val pipeline = SendPipeline()

fun Route.sendRoute() {
    post("/v1/send") {
        pipeline.handle(call)
    }
}
