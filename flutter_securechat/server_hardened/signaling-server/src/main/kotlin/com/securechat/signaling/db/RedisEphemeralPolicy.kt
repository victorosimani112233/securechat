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
    /**
     * Sessiz tahliyeye izin veren politikalar.
     *
     * `allkeys-*` altinda Redis, bellek dolunca TTL'i dolmamis herhangi bir
     * key'i atabilir. Bu is yukunde iki sonucu vardir ve ikisi de sessizdir:
     * teslim edilmemis E2EE ciphertext kaybolur, ve rate limit pencereleri
     * sifirlanir. Ikincisi saldirganin tetikleyebilecegi bir bypass'tir —
     * kuyruklari doldurarak bellek baskisi yaratmak yeterlidir.
     *
     * Butun key'lerimiz zaten TTL tasir ve kuyruk boyutlari uygulama
     * tarafinda sinirlidir; dolayisiyla dogru davranis tahliye degil,
     * `noeviction` ile yazmayi reddetmektir: rate limiter fail-closed olur,
     * kuyruk yazimi hata verir, gonderen 503 alip yeniden dener. Veri
     * sessizce kaybolmaz.
     */
    private val EVICTING_POLICIES = setOf(
        "allkeys-lru",
        "allkeys-lfu",
        "allkeys-random",
    )

    fun requireMemoryOnly(configuration: Map<String, String>) {
        val appendOnly = configuration["appendonly"]?.trim()?.lowercase()
        val snapshotSchedule = configuration["save"]?.trim()
        require(appendOnly == "no") {
            "Redis AOF persistence must be disabled (appendonly=no)"
        }
        require(snapshotSchedule != null && snapshotSchedule.isEmpty()) {
            "Redis RDB snapshots must be disabled (save='')"
        }
        val evictionPolicy = configuration["maxmemory-policy"]?.trim()?.lowercase()
        require(evictionPolicy !in EVICTING_POLICIES) {
            "Redis must not silently evict live keys (maxmemory-policy=$evictionPolicy); " +
                "use noeviction so queue writes and rate limits fail closed"
        }
    }
}
