package com.securechat.signaling

import java.nio.charset.StandardCharsets
import java.security.MessageDigest

/** Mandatory bearer boundary for activity-bearing Prometheus metrics. */
object MetricsAccess {
    private val token: ByteArray by lazy {
        val value = SecretSource.required("METRICS_BEARER_TOKEN")
        require(value.length >= 32) { "METRICS_BEARER_TOKEN en az 32 karakter olmali" }
        value.toByteArray(StandardCharsets.UTF_8)
    }

    fun initialize() {
        token
    }

    fun isAuthorized(authorization: String?): Boolean {
        val candidate = authorization
            ?.takeIf { it.startsWith("Bearer ") }
            ?.removePrefix("Bearer ")
            ?.toByteArray(StandardCharsets.UTF_8)
            ?: return false
        return MessageDigest.isEqual(token, candidate)
    }
}
