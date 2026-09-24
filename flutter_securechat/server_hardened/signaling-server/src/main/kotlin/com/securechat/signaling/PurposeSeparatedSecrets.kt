package com.securechat.signaling

import java.security.MessageDigest
import java.util.Base64

/** Rejects accidental secret reuse before any public listener is opened. */
internal object PurposeSeparatedSecrets {
    private val mandatory = listOf(
        "PRIVACY_INDEX_KEY",
        "OFFLINE_QUEUE_ENCRYPTION_KEY",
        "FCM_TOKEN_ENCRYPTION_KEY",
        "JWT_SECRET",
        "TURN_SECRET",
        "METRICS_BEARER_TOKEN",
        "SEALED_SENDER_TRUST_ROOT_PRIVATE_KEY",
        "SEALED_SENDER_SERVER_PRIVATE_KEY",
    )

    private val authenticationSecretNames = setOf(
        "JWT_SECRET",
        "TURN_SECRET",
        "METRICS_BEARER_TOKEN",
        "JANUS_API_SECRET",
        "JANUS_ADMIN_SECRET",
    )

    private val encryptionKeyNames = setOf(
        "RECOVERY_INDEX_KEY",
        "RECOVERY_ENCRYPTION_KEY",
        "PRIVACY_INDEX_KEY",
        "OFFLINE_QUEUE_ENCRYPTION_KEY",
        "FCM_TOKEN_ENCRYPTION_KEY",
        "SEALED_SENDER_TRUST_ROOT_PRIVATE_KEY",
        "SEALED_SENDER_SERVER_PRIVATE_KEY",
    )

    fun validate(environment: Map<String, String> = System.getenv()) {
        loadValidated(environment)
    }

    fun validatedValue(name: String, environment: Map<String, String> = System.getenv()): String =
        loadValidated(environment).getValue(name)

    private fun loadValidated(environment: Map<String, String>): Map<String, String> {
        val names = mandatory.toMutableList()
        val recoveryNames = listOf("RECOVERY_INDEX_KEY", "RECOVERY_ENCRYPTION_KEY")
        if (recoveryNames.any { !environment[it].isNullOrBlank() || !environment["${it}_FILE"].isNullOrBlank() }) {
            names += recoveryNames
        }
        if (!environment["JANUS_WS_URL"].isNullOrBlank()) {
            names += "JANUS_API_SECRET"
            names += "JANUS_ADMIN_SECRET"
        }
        val seen = mutableMapOf<String, String>()
        val loaded = linkedMapOf<String, String>()
        for (name in names) {
            val value = SecretSource.required(name, environment)
            if (name in authenticationSecretNames) {
                SecretPolicy.requireStrong(name, value)
            }
            if (name in encryptionKeyNames) {
                val decoded = runCatching { Base64.getDecoder().decode(value.trim()) }
                    .getOrElse { throw IllegalArgumentException("$name must be valid Base64") }
                SecretPolicy.requireStrongKey(name, decoded)
            }
            val fingerprint = MessageDigest.getInstance("SHA-256")
                .digest(canonicalMaterial(value))
                .joinToString("") { "%02x".format(it) }
            val previous = seen.putIfAbsent(fingerprint, name)
            require(previous == null) {
                "$name must use purpose-separated material; it matches $previous"
            }
            loaded[name] = value
        }
        return loaded
    }

    private fun canonicalMaterial(value: String): ByteArray {
        // All 32-byte Base64-looking values are compared in decoded form.
        // Otherwise copying an AEAD key's Base64 text into JWT/TURN would
        // evade reuse detection even though disclosure of either material
        // immediately reveals the other.
        val decoded = runCatching { Base64.getDecoder().decode(value.trim()) }.getOrNull()
        if (decoded?.size == 32) return decoded
        return value.toByteArray(Charsets.UTF_8)
    }
}
