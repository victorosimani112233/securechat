package com.securechat.signaling

import java.security.MessageDigest

/** Rejects accidental secret reuse before any public listener is opened. */
internal object PurposeSeparatedSecrets {
    private val mandatory = listOf(
        "PRIVACY_INDEX_KEY",
        "OFFLINE_QUEUE_ENCRYPTION_KEY",
        "FCM_TOKEN_ENCRYPTION_KEY",
        "JWT_SECRET",
        "TURN_SECRET",
        "METRICS_BEARER_TOKEN",
    )

    fun validate(environment: Map<String, String> = System.getenv()) {
        val names = mandatory.toMutableList()
        if (!environment["JANUS_WS_URL"].isNullOrBlank()) {
            names += "JANUS_API_SECRET"
            names += "JANUS_ADMIN_SECRET"
        }
        val seen = mutableMapOf<String, String>()
        for (name in names) {
            val value = SecretSource.required(name, environment)
            val fingerprint = MessageDigest.getInstance("SHA-256")
                .digest(value.toByteArray(Charsets.UTF_8))
                .joinToString("") { "%02x".format(it) }
            val previous = seen.putIfAbsent(fingerprint, name)
            require(previous == null) {
                "$name must use purpose-separated material; it matches $previous"
            }
        }
    }
}
