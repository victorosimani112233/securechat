package com.securechat.signaling.db

/**
 * Privacy boundary for Redis-backed transient state.
 *
 * Client E2EE ciphertext, OTP challenges, revocation markers and live call
 * state must never be copied to RDB/AOF files or their backups. A deployment
 * that cannot prove both persistence mechanisms are disabled is rejected
 * before any network listener is opened.
 */
object RedisEphemeralPolicy {
    fun requireMemoryOnly(configuration: Map<String, String>) {
        val appendOnly = configuration["appendonly"]?.trim()?.lowercase()
        val snapshotSchedule = configuration["save"]?.trim()
        require(appendOnly == "no") {
            "Redis AOF persistence must be disabled (appendonly=no)"
        }
        require(snapshotSchedule != null && snapshotSchedule.isEmpty()) {
            "Redis RDB snapshots must be disabled (save='')"
        }
    }
}
