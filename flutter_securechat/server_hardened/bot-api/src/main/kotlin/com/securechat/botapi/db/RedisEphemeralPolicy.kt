package com.securechat.botapi.db

/** Bot queues and replay/idempotency state are RAM-only by contract. */
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
