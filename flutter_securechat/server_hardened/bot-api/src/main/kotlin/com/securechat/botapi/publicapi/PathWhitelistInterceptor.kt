package com.securechat.botapi.publicapi

import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.util.pipeline.*

/**
 * Public listener'a defense-in-depth: yalnizca POST /v1/send istegi gecer,
 * geri kalan her sey 404 doner. Route ag aci zaten yalnizca /v1/send'i
 * iceriyor, ama yanlislikla yeni route eklenirse bu interceptor yine de korur.
 *
 * Pipeline'in en basina (Plugins phase) install edilir.
 */
object PathWhitelistInterceptor {

    private const val ALLOWED_PATH = "/v1/send"

    fun install(application: Application) {
        application.intercept(ApplicationCallPipeline.Plugins) {
            val req = call.request
            if (req.path() != ALLOWED_PATH || req.httpMethod != HttpMethod.Post) {
                call.respond(HttpStatusCode.NotFound)
                finish()
            }
        }
    }
}
