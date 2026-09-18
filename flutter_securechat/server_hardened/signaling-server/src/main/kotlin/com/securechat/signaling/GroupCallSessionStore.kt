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
    private const val MAX_CALL_LIFETIME_MILLIS = 4L * 60L * 60L * 1000L

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
        /**
         * Immutable snapshot. Onceki `MutableSet` concurrent map icinde
         * thread-safe degildi: es zamanli katilim/ayrilis kayip guncelleme
         * uretebiliyordu. Tum degisiklikler per-group lock altinda kopya
         * uzerinden yapilir.
         */
        val participants: Set<String>,
        /**
         * Medya frame sifrelemesi bildiren katilimcilar. SFU'ya ancak
         * herkes bildirdiginde sessizce gecilebilir; aksi halde medya
         * Janus'ta acik olur ve bu acik operator kabulu ister.
         */
        val mediaE2eeParticipants: Set<String> = emptySet(),
        val mode: String,
        val sfuRoomId: Long? = null,
        val janusWsUrl: String? = null,
        // GUVENLIK: apiSecret BURADAN KALDIRILDI (C2 fix) — client'a hicbir sekilde sizmaz.
        val startedAt: Long = System.currentTimeMillis()
    ) {
        /** Tum katilimcilar medya sifrelemesi bildiriyor mu. */
        val mediaEndToEndEncrypted: Boolean
            get() = participants.isNotEmpty() &&
                mediaE2eeParticipants.containsAll(participants)
    }

    /** Katilimci ekleme sonucu. */
    enum class JoinResult { ADDED, ALREADY_PRESENT, CALL_NOT_FOUND, CAPACITY_REACHED }

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
        janusWsUrl: String? = null,
        mediaE2eeParticipants: Set<String> = emptySet()
    ) {
        active[groupId] = ActiveCall(
            groupId = groupId,
            callId = callId,
            coordinatorId = coordinatorId,
            callType = callType,
            participants = participants.toSet(),
            mediaE2eeParticipants = mediaE2eeParticipants.intersect(participants.toSet()),
            mode = mode,
            sfuRoomId = sfuRoomId,
            janusWsUrl = janusWsUrl
        )
    }

    /** Mevcut arama bilgisini doner; stale in-memory metadata fail-closed silinir. */
    fun get(groupId: String): ActiveCall? {
        val value = active[groupId] ?: return null
        if (System.currentTimeMillis() - value.startedAt > MAX_CALL_LIFETIME_MILLIS) {
            end(groupId)
            return null
        }
        return value
    }

    /** SFU olusturma isini ayni grup icin atomik olarak tek kez baslatir. */
    fun promoteToSfu(groupId: String): Boolean {
        val lock = transferLocks.computeIfAbsent(groupId) { Any() }
        synchronized(lock) {
            val current = get(groupId) ?: return false
            if (current.mode != "MESH") return false
            active[groupId] = current.copy(mode = "SFU_PENDING")
            return true
        }
    }

    fun cancelSfuPromotion(groupId: String) {
        val lock = transferLocks.computeIfAbsent(groupId) { Any() }
        synchronized(lock) {
            val current = get(groupId) ?: return
            if (current.mode == "SFU_PENDING") {
                active[groupId] = current.copy(mode = "MESH")
            }
        }
    }

    /** SFU bilgisi yoksa sonradan set et (Janus room asenkron olarak yaratiliyor). */
    fun updateSfuInfo(groupId: String, sfuRoomId: Long, janusWsUrl: String) {
        val current = get(groupId) ?: return
        active[groupId] = current.copy(
            mode = "SFU",
            sfuRoomId = sfuRoomId,
            janusWsUrl = janusWsUrl
        )
    }

    /**
     * Yeni katilimci ekler.
     *
     * `capacity` cagirandan gelir: SFU kullanilamiyorken mesh tavani,
     * kullanilabiliyorken protokol tavani gecerlidir. Kontrol lock altinda
     * yapilir, yoksa iki es zamanli katilim tavani birlikte asabilirdi.
     */
    fun addParticipant(
        groupId: String,
        userId: String,
        capacity: Int,
        mediaE2ee: Boolean = false
    ): JoinResult {
        val lock = transferLocks.computeIfAbsent(groupId) { Any() }
        synchronized(lock) {
            val current = get(groupId) ?: return JoinResult.CALL_NOT_FOUND
            if (userId in current.participants) {
                if (mediaE2ee && userId !in current.mediaE2eeParticipants) {
                    active[groupId] = current.copy(
                        mediaE2eeParticipants = current.mediaE2eeParticipants + userId,
                    )
                }
                return JoinResult.ALREADY_PRESENT
            }
            if (current.participants.size >= capacity) return JoinResult.CAPACITY_REACHED
            active[groupId] = current.copy(
                participants = current.participants + userId,
                mediaE2eeParticipants = if (mediaE2ee) {
                    current.mediaE2eeParticipants + userId
                } else {
                    current.mediaE2eeParticipants
                },
            )
            return JoinResult.ADDED
        }
    }

    /** Katilimciyi cikar (explicit HANGUP veya WebSocket disconnect). */
    fun removeParticipant(groupId: String, userId: String): Boolean {
        val lock = transferLocks.computeIfAbsent(groupId) { Any() }
        synchronized(lock) {
            val current = get(groupId) ?: return false
            if (userId !in current.participants) return false
            active[groupId] = current.copy(
                participants = current.participants - userId,
                mediaE2eeParticipants = current.mediaE2eeParticipants - userId,
            )
            return true
        }
    }

    /**
     * Kullanicinin participant oldugu tum aktif aramalari doner.
     * WebSocket disconnect handler'i tarafindan kullanilir — bir kullanici
     * birden fazla grup aramasinda olamaz pratikte ama defansif yaklasim.
     */
    fun findActiveCallsForUser(userId: String): List<ActiveCall> {
        purgeExpired()
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
            val current = get(groupId) ?: return null
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
        transferLocks.remove(groupId)
    }

    fun isActive(groupId: String): Boolean = get(groupId) != null

    fun all(): Map<String, ActiveCall> {
        purgeExpired()
        return active.toMap()
    }

    private fun purgeExpired() {
        val now = System.currentTimeMillis()
        active.values
            .filter { now - it.startedAt > MAX_CALL_LIFETIME_MILLIS }
            .forEach { end(it.groupId) }
    }
}
