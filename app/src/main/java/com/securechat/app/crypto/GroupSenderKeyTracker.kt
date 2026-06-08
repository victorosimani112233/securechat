package com.securechat.app.crypto

import android.content.Context
import android.content.SharedPreferences
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Hangi grup uyesine SKDM (SenderKeyDistributionMessage) gonderildigini izler.
 * Cift gonderim onlemek icin SharedPreferences'ta kayit tutar.
 *
 * Key formati: "$groupId:$memberId" → bool
 * Rotate sonrasi tum kayitlari sifirla (rotate(groupId)).
 *
 * GUVENLIK: Sadece "gonderildi mi" flag'i tutar; iceriksiz, anahtar materyali yok.
 */
@Singleton
class GroupSenderKeyTracker @Inject constructor(
    @ApplicationContext context: Context
) {
    private val prefs: SharedPreferences =
        context.getSharedPreferences("group_skdm_tracker", Context.MODE_PRIVATE)

    fun isDistributed(groupId: String, memberId: String): Boolean =
        prefs.getBoolean(key(groupId, memberId), false)

    fun markDistributed(groupId: String, memberId: String) {
        prefs.edit().putBoolean(key(groupId, memberId), true).apply()
    }

    /** Grup icin tum SKDM dagitim kayitlarini sifirla (rotation sonrasi). */
    fun clearGroup(groupId: String) {
        val prefix = "$groupId:"
        val editor = prefs.edit()
        prefs.all.keys.filter { it.startsWith(prefix) }.forEach { editor.remove(it) }
        editor.apply()
    }

    private fun key(groupId: String, memberId: String): String = "$groupId:$memberId"
}
