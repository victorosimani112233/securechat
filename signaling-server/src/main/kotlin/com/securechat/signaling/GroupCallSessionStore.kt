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
        val apiSecret: String? = null,
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
        janusWsUrl: String? = null,
        apiSecret: String? = null
    ) {
        active[groupId] = ActiveCall(
            groupId = groupId,
            callId = callId,
            coordinatorId = coordinatorId,
            callType = callType,
            participants = participants.toMutableSet(),
            mode = mode,
            sfuRoomId = sfuRoomId,
            janusWsUrl = janusWsUrl,
            apiSecret = apiSecret
        )
    }

    /** Mevcut arama bilgisini doner, yoksa null. */
    fun get(groupId: String): ActiveCall? = active[groupId]

    /** SFU bilgisi yoksa sonradan set et (Janus room asenkron olarak yaratiliyor). */
    fun updateSfuInfo(groupId: String, sfuRoomId: Long, janusWsUrl: String, apiSecret: String) {
        val current = active[groupId] ?: return
        active[groupId] = current.copy(
            mode = "SFU",
            sfuRoomId = sfuRoomId,
            janusWsUrl = janusWsUrl,
            apiSecret = apiSecret
        )
    }

    /** Yeni katilimci ekle (geri donus icin participant listesini guncel tut). */
    fun addParticipant(groupId: String, userId: String) {
        active[groupId]?.participants?.add(userId)
    }

    /** Arama bitti — koordinator HANGUP'i ile. */
    fun end(groupId: String) {
        active.remove(groupId)
    }

    fun isActive(groupId: String): Boolean = active.containsKey(groupId)

    fun all(): Map<String, ActiveCall> = active.toMap()
}
