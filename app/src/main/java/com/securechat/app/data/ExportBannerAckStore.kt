package com.securechat.app.data

import android.content.Context
import android.content.SharedPreferences
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * "Bu grupta sohbet disa aktarma acik" bilgilendirme banner'inin uyari acknowledgement
 * durumunu tutar. Kullanici banner'i bir kez kapatinca tekrar gostermeyiz.
 *
 * Toggle kapanip TEKRAR acilirsa ack sifirlanir — yani kullanici yeni durumdan
 * bilgi sahibi olabilsin diye banner tekrar gosterilir.
 *
 * Lokal-only persistans: SharedPreferences. Sunucuya bilgi sizmaz.
 */
@Singleton
class ExportBannerAckStore @Inject constructor(
    @ApplicationContext context: Context
) {
    private val prefs: SharedPreferences =
        context.getSharedPreferences("export_banner_ack", Context.MODE_PRIVATE)

    /**
     * Banner gosterilmeli mi?
     * Donus: true => banner aktif (henuz ack yok), false => ack edilmis.
     */
    fun shouldShow(groupId: String): Boolean = !prefs.getBoolean(keyAck(groupId), false)

    /**
     * Kullanici banner'i kapatinca cagrilir — bir daha gosterilmez.
     * (Toggle resetlerse `reset()` ile temizlenir.)
     */
    fun acknowledge(groupId: String) {
        prefs.edit().putBoolean(keyAck(groupId), true).apply()
    }

    /**
     * Export izni KAPATILIP tekrar acildiginda cagrilir — banner tekrar gosterilsin.
     * IncomingMessageHandler.handleGroupNotification (UPDATE_EXPORT_POLICY) icinde
     * yeni durum "true" ise bu metod cagrilir.
     */
    fun reset(groupId: String) {
        prefs.edit().remove(keyAck(groupId)).apply()
    }

    private fun keyAck(groupId: String): String = "ack:$groupId"
}
