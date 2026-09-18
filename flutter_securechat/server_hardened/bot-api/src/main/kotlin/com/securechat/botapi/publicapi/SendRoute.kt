package com.securechat.botapi.publicapi

import com.securechat.botapi.send.SendPipeline
import io.ktor.server.application.*
import io.ktor.server.routing.*

/**
 * Public listener'in TEK endpoint'i: POST /v1/send.
 * SendPipeline orchestration'i tum guard'lari + Signal encrypt + WS delivery yapar.
 */
private val defaultPipeline by lazy { SendPipeline() }

/**
 * @param pipeline testlerin kendi client cozumlemesini verebilmesi icin
 *   disaridan gecilebilir; uretimde varsayilan tekil kullanilir.
 */
fun Route.sendRoute(pipeline: SendPipeline? = null) {
    val active = pipeline ?: defaultPipeline
    post("/v1/send") {
        active.handle(call)
    }
}
