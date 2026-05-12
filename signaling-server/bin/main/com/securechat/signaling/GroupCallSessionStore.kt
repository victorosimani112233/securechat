package com.securechat.signaling

import java.util.concurrent.ConcurrentHashMap

/**
 * Aktif grup aramalarini in-memory tutar.
 *
 * Bir grup icin tek aktif arama varsayilir (concurrent grup aramasi desteklenmez).
 * group_call_invite ile set edilir, koordinator HANGUP ile clear edilir.
 *
 * Sonradan katilim (late-join):
 * - Yeni katilan kullanici GroupCallStatusQuery gonderir
 * - Sunucu bu store'dan callId + coordinatorId + mode + (SFU ise) roomInfo doner
 * - Istemci yanit ile koordinatore GroupCallJoinRequest gonderir veya SFU'ya bind olur
 */
object GroupCallSessionStore {

    /**
     * Aktif grup aramasi bilgisi.
     * mode: "MESH" (<4 katilimci) veya "SFU" (>=4 katilimci).
     * SFU modunda sfuRoom alanlari doludur.
     */
    data class ActiveCall(
        val groupId: String,
        val callId: String,
        val coordinatorId: String,
        val callType: String, // VOICE veya VIDEO
        val participants: MutableSet<String>,
        val mode: String,
        val sfuRoomId: Long? = null,
        val janusWsUrl: String? = null,
        // GUVENLIK: apiSecret BURADAN KALDIRILDI (C2 fix) — client'a hicbir sekilde sizmaz.
        val startedAt: Long = System.currentTimeMillis()
    )

    private val active = ConcurrentHashMap<String, ActiveCall>()

    /** Grup aramasi baslat. group_call_invite handler tarafindan cagirilir. */
    fun start(
        groupId: String,
        callId: String,
        coordinatorId: String,
        callType: String,
        participants: List<String>,
        mode: String,
        sfuRoomId: Long? = null,
        janusWsUrl: String? = null
    ) {
        active[groupId] = ActiveCall(
            groupId = groupId,
            callId = callId,
            coordinatorId = coordinatorId,
            callType = callType,
            participants = participants.toMutableSet(),
            mode = mode,
            sfuRoomId = sfuRoomId,
            janusWsUrl = janusWsUrl
        )
    }

    /** Mevcut arama bilgisini doner, yoksa null. */
    fun get(groupId: String): ActiveCall? = active[groupId]

    /** SFU bilgisi yoksa sonradan set et (Janus room asenkron olarak yaratiliyor). */
    fun updateSfuInfo(groupId: String, sfuRoomId: Long, janusWsUrl: String) {
        val current = active[groupId] ?: return
        active[groupId] = current.copy(
            mode = "SFU",
            sfuRoomId = sfuRoomId,
            janusWsUrl = janusWsUrl
        )
    }

    /** Yeni katilimci ekle (geri donus icin participant listesini guncel tut). */
    fun addParticipant(groupId: String, userId: String) {
        active[groupId]?.participants?.add(userId)
    }

    /** Katilimciyi cikar (explicit HANGUP veya WebSocket disconnect). */
    fun removeParticipant(groupId: String, userId: String): Boolean {
        return active[groupId]?.participants?.remove(userId) ?: false
    }

    /**
     * Kullanicinin participant oldugu tum aktif aramalari doner.
     * WebSocket disconnect handler'i tarafindan kullanilir — bir kullanici
     * birden fazla grup aramasinda olamaz pratikte ama defansif yaklasim.
     */
    fun findActiveCallsForUser(userId: String): List<ActiveCall> {
        return active.values.filter { it.participants.contains(userId) || it.coordinatorId == userId }
    }

    /**
     * Koordinatorlugu yeni bir uyeye devret. Eski koordinator disconnect oldugunda
     * sunucu kalan participants'tan birini secer; arama kesilmez.
     *
     * GUVENLIK (H9 fix): Race condition korumasi.
     * Iki concurrent disconnect ayni anda transferCoordinator cagirirsa, eskiden iki
     * coordinator atamasi yapilabiliyordu. Artik per-groupId synchronized block ile
     * atomic — sadece bir transfer basarili olur. Online filter caller sorumlulugu.
     *
     * @param onlineFilter Yeni coordinator'in online oldugunu dogrulayan predicate.
     *                     Eger newCoordinatorId offline ise null doner — caller baska
     *                     candidate denesin.
     * @return Devir basarili ise (eski, yeni) ciftini, basarisizsa null.
     */
    fun transferCoordinator(
        groupId: String,
        newCoordinatorId: String,
        onlineFilter: (String) -> Boolean = { true }
    ): Pair<String, String>? {
        // groupId-scoped lock: per-group transfer atomic.
        val lock = transferLocks.computeIfAbsent(groupId) { Any() }
        synchronized(lock) {
            val current = active[groupId] ?: return null
            if (newCoordinatorId == current.coordinatorId) return null
            // ZORUNLU: online filter — offline candidate'a coordinator atamasi yapilmaz.
            if (!onlineFilter(newCoordinatorId)) return null
            val previous = current.coordinatorId
            active[groupId] = current.copy(coordinatorId = newCoordinatorId)
            return previous to newCoordinatorId
        }
    }

    /** Per-groupId synchronization lock'lari — transferCoordinator atomic'lik garantisi. */
    private val transferLocks = ConcurrentHashMap<String, Any>()

    /** Arama bitti — koordinator HANGUP'i ile. */
    fun end(groupId: String) {
        active.remove(groupId)
    }

    fun isActive(groupId: String): Boolean = active.containsKey(groupId)

    fun all(): Map<String, ActiveCall> = active.toMap()
}
