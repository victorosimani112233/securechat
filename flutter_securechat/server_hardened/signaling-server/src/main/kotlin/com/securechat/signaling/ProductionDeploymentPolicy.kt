package com.securechat.signaling

import java.nio.file.Path

/**
 * Privacy guarantees which must survive an operator bypassing the compose
 * wrapper. This validation runs before database, Redis or network listeners.
 */
object ProductionDeploymentPolicy {
    fun validate(environment: Map<String, String> = System.getenv()) {
        require(environment["PRIVACY_PRODUCTION_MODE"]?.equals("true", ignoreCase = true) == true) {
            "PRIVACY_PRODUCTION_MODE=true is required"
        }

        requireSecurePostgres(environment["DATABASE_URL"])
        require(environment["DIRECTORY_OPRF_KEY_BACKEND"]?.trim()?.uppercase() == "PKCS11") {
            "Production directory OPRF requires the PKCS11 backend"
        }
        require(environment["ALLOW_LEGACY_PLAINTEXT_QUEUE"]?.equals("true", ignoreCase = true) != true) {
            "Legacy plaintext queues are forbidden in production"
        }

        val smtpTls = environment["SMTP_TLS"]?.trim()?.lowercase()
        require(smtpTls in setOf("starttls", "ssl")) {
            "Production SMTP must use starttls or ssl"
        }

        if (!environment["JANUS_WS_URL"].isNullOrBlank()) {
            require(environment["JANUS_PUBLIC_WS_URL"]?.startsWith("wss://") == true) {
                "The client-facing Janus URL must use wss"
            }
        }

        val firebasePath = environment["FIREBASE_SERVICE_ACCOUNT_PATH"]
        require(!firebasePath.isNullOrBlank() && Path.of(firebasePath).isAbsolute) {
            "Firebase service-account path must be absolute"
        }
    }

    internal fun requireSecurePostgres(value: String?) {
        val url = value?.trim().orEmpty()
        require(url.startsWith("jdbc:postgresql://")) {
            "DATABASE_URL must use the PostgreSQL JDBC scheme"
        }
        val authority = url.removePrefix("jdbc:postgresql://").substringBefore('/')
        require('@' !in authority) { "DATABASE_URL must not embed user-info credentials" }

        val parameters = url.substringAfter('?', missingDelimiterValue = "")
            .split('&')
            .mapNotNull { entry ->
                val delimiter = entry.indexOf('=')
                if (delimiter <= 0) null else {
                    entry.substring(0, delimiter).lowercase() to
                        entry.substring(delimiter + 1).lowercase()
                }
            }
            .toMap()
        require(parameters["sslmode"] == "verify-full") {
            "DATABASE_URL must use sslmode=verify-full"
        }
        require("password" !in parameters) {
            "DATABASE_URL must not embed a database password"
        }
    }
}
