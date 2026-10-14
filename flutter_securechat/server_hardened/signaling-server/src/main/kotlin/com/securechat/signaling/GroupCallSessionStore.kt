package com.securechat.signaling

import java.util.concurrent.ConcurrentHashMap

/**
 * Aktif grup aramalarini in-memory tutar.
 *
 * Bir grup icin tek aktif arama varsayilir (concurrent grup aramasi desteklenmez).
 * group_call_invite ile set edilir, koordinator HANGUP ile clear edilir.
 *
 * Grup aramalari yalniz mesh calisir: medya cihazlar arasinda dogrudan
 * akar, sunucu yalniz sinyal tasir. Janus SFU 2026-10-14'te kaldirildi.
 *
 * Sonradan katilim (late-join):
 * - Yeni katilan kullanici GroupCallStatusQuery gonderir
 * - Sunucu bu store'dan callId + coordinatorId doner
 * - Istemci yanit ile koordinatore GroupCallJoinRequest gonderir
 */
object GroupCallSessionStore {
    internal const val MAX_CALL_LIFETIME_MILLIS = 4L * 60L * 60L * 1000L
    internal const val MAX_ACTIVE_CALLS = 1024
    internal const val MAX_CALLS_PER_USER = 4

    /**
     * Bir grup aramasinin katilimci tavani.
     *
     * Mesh'te her cihaz N-1 encode ve N-1 upload yapar; tavanin ustunde arama
     * kullanilamaz hale gelir. Sessiz bozulma yerine ongorulebilir ret.
     */
    const val MAX_PARTICIPANTS = 8

    /** Aktif grup aramasi bilgisi. */
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
        // Call-scoped admission only, never a persistent group directory.
        val invitedParticipants: Set<String> = participants,
        val joinedParticipants: Set<String> = participants,
        val requiresMediaE2ee: Boolean = false,
        val instanceId: String = java.util.UUID.randomUUID().toString(),
        /** Medya frame sifrelemesi bildiren katilimcilar. */
        val mediaE2eeParticipants: Set<String> = emptySet(),
        val startedAt: Long = System.currentTimeMillis()
    ) {
        /** Tum katilimcilar medya sifrelemesi bildiriyor mu. */
        val mediaEndToEndEncrypted: Boolean
            get() = joinedParticipants.isNotEmpty() &&
                mediaE2eeParticipants.containsAll(joinedParticipants)
    }

    /** Katilimci ekleme sonucu. */
    enum class JoinResult {
        ADDED, ALREADY_PRESENT, CALL_NOT_FOUND, CAPACITY_REACHED,
        CONTEXT_MISMATCH, NOT_INVITED, ENCRYPTION_REQUIRED, SERVER_CAPACITY_REACHED, USER_CAPACITY_REACHED
    }

    private val active = ConcurrentHashMap<String, ActiveCall>()
    private val admissionLock = Any()
    // One short, non-suspending lock makes global admissions and retirement
    // accounting atomic with per-call updates. No network work holds this lock.
    private fun lockFor(@Suppress("UNUSED_PARAMETER") groupId: String) = admissionLock

    fun invite(
        groupId: String, callId: String, coordinatorId: String, callType: String,
        recipientId: String, mediaE2ee: Boolean,
    ): JoinResult = synchronized(admissionLock) {
        purgeExpired()
        synchronized(lockFor(groupId)) admission@{
        val current = get(groupId)
        if (current == null) {
            if (active.size >= MAX_ACTIVE_CALLS) return@admission JoinResult.SERVER_CAPACITY_REACHED
            if (callsFor(coordinatorId) >= MAX_CALLS_PER_USER || callsFor(recipientId) >= MAX_CALLS_PER_USER) {
                return@admission JoinResult.USER_CAPACITY_REACHED
            }
            active[groupId] = ActiveCall(
                groupId, callId, coordinatorId, callType,
                participants = setOf(coordinatorId, recipientId),
                joinedParticipants = setOf(coordinatorId),
                requiresMediaE2ee = mediaE2ee,
                mediaE2eeParticipants = if (mediaE2ee) setOf(coordinatorId) else emptySet(),
            )
            return@admission JoinResult.ADDED
        }
        if (current.callId != callId || current.coordinatorId != coordinatorId ||
            current.callType != callType || current.requiresMediaE2ee != mediaE2ee
        ) return@admission JoinResult.CONTEXT_MISMATCH
        if (recipientId in current.participants) return@admission JoinResult.ALREADY_PRESENT
        if (current.participants.size >= MAX_PARTICIPANTS ||
            (recipientId !in current.invitedParticipants && current.invitedParticipants.size >= 256)
        ) return@admission JoinResult.CAPACITY_REACHED
        if (callsFor(recipientId) >= MAX_CALLS_PER_USER) return@admission JoinResult.USER_CAPACITY_REACHED
        active[groupId] = current.copy(
            participants = current.participants + recipientId,
            invitedParticipants = current.invitedParticipants + recipientId,
        )
        JoinResult.ADDED
        }
    }

    private fun callsFor(userId: String): Int = active.values.count { userId in it.participants }

    fun confirmJoin(
        groupId: String, callId: String, coordinatorId: String, callType: String,
        userId: String, mediaE2ee: Boolean,
    ): JoinResult = synchronized(lockFor(groupId)) {
        val current = get(groupId) ?: return@synchronized JoinResult.CALL_NOT_FOUND
        if (current.callId != callId || current.coordinatorId != coordinatorId || current.callType != callType) {
            return@synchronized JoinResult.CONTEXT_MISMATCH
        }
        if (userId !in current.invitedParticipants) return@synchronized JoinResult.NOT_INVITED
        if (userId !in current.participants && current.participants.size >= MAX_PARTICIPANTS) {
            return@synchronized JoinResult.CAPACITY_REACHED
        }
        if (userId !in current.participants && callsFor(userId) >= MAX_CALLS_PER_USER) {
            return@synchronized JoinResult.USER_CAPACITY_REACHED
        }
        if (!mediaE2ee && current.requiresMediaE2ee) {
            return@synchronized JoinResult.ENCRYPTION_REQUIRED
        }
        active[groupId] = current.copy(
            participants = current.participants + userId,
            joinedParticipants = current.joinedParticipants + userId,
            mediaE2eeParticipants = if (mediaE2ee) current.mediaE2eeParticipants + userId
                else current.mediaE2eeParticipants - userId,
        )
        if (userId in current.joinedParticipants) JoinResult.ALREADY_PRESENT else JoinResult.ADDED
    }

    /** Grup aramasi baslat. group_call_invite handler tarafindan cagirilir. */
    fun start(
        groupId: String,
        callId: String,
        coordinatorId: String,
        callType: String,
        participants: List<String>,
        mediaE2eeParticipants: Set<String> = emptySet()
    ) {
        require(participants.toSet().size <= MAX_PARTICIPANTS)
        synchronized(lockFor(groupId)) { active[groupId] = ActiveCall(
            groupId = groupId,
            callId = callId,
            coordinatorId = coordinatorId,
            callType = callType,
            participants = participants.toSet(),
            mediaE2eeParticipants = mediaE2eeParticipants.intersect(participants.toSet()),
        ) }
    }

    /** Mevcut arama bilgisini doner; stale in-memory metadata fail-closed silinir. */
    fun get(groupId: String): ActiveCall? = synchronized(lockFor(groupId)) {
        val value = active[groupId] ?: return null
        if (System.currentTimeMillis() - value.startedAt > MAX_CALL_LIFETIME_MILLIS) {
            expireCall(value)
            return null
        }
        return value
    }

    /**
     * Yeni katilimci ekler. Tavan kontrolu lock altinda yapilir, yoksa iki
     * es zamanli katilim tavani birlikte asabilirdi.
     */
    fun addParticipant(
        groupId: String,
        userId: String,
        mediaE2ee: Boolean = false
    ): JoinResult {
        synchronized(lockFor(groupId)) {
            val current = get(groupId) ?: return JoinResult.CALL_NOT_FOUND
            if (userId in current.participants) {
                if (mediaE2ee && userId !in current.mediaE2eeParticipants) {
                    active[groupId] = current.copy(
                        mediaE2eeParticipants = current.mediaE2eeParticipants + userId,
                    )
                }
                return JoinResult.ALREADY_PRESENT
            }
            if (current.participants.size >= MAX_PARTICIPANTS) return JoinResult.CAPACITY_REACHED
            active[groupId] = current.copy(
                participants = current.participants + userId,
                invitedParticipants = current.invitedParticipants + userId,
                joinedParticipants = current.joinedParticipants + userId,
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
        synchronized(lockFor(groupId)) {
            val current = get(groupId) ?: return false
            if (userId !in current.participants) return false
            active[groupId] = current.copy(
                participants = current.participants - userId,
                joinedParticipants = current.joinedParticipants - userId,
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
        synchronized(lockFor(groupId)) {
            val current = get(groupId) ?: return null
            if (newCoordinatorId == current.coordinatorId) return null
            if (newCoordinatorId !in current.joinedParticipants) return null
            // ZORUNLU: online filter — offline candidate'a coordinator atamasi yapilmaz.
            if (!onlineFilter(newCoordinatorId)) return null
            val previous = current.coordinatorId
            active[groupId] = current.copy(coordinatorId = newCoordinatorId)
            return previous to newCoordinatorId
        }
    }

    /** Per-groupId synchronization lock'lari — transferCoordinator atomic'lik garantisi. */

    /** Arama bitti — koordinator HANGUP'i ile. */
    fun end(groupId: String, expectedInstanceId: String? = null) {
        synchronized(lockFor(groupId)) {
            val current = active[groupId] ?: return
            if (expectedInstanceId != null && current.instanceId != expectedInstanceId) return
            expireCall(current)
        }
    }

    fun isActive(groupId: String): Boolean = get(groupId) != null

    fun all(): Map<String, ActiveCall> {
        purgeExpired()
        return active.toMap()
    }

    internal fun purgeExpired(now: Long = System.currentTimeMillis()) = synchronized(admissionLock) {
        active.values
            .filter { now - it.startedAt > MAX_CALL_LIFETIME_MILLIS }
            .forEach(::expireCall)
    }

    private fun expireCall(call: ActiveCall) = synchronized(lockFor(call.groupId)) {
        val current = active[call.groupId] ?: return@synchronized
        if (current.instanceId != call.instanceId || current.startedAt != call.startedAt) return@synchronized
        active.remove(call.groupId, current)
    }
}
