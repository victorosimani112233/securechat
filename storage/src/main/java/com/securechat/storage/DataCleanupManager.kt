package com.securechat.storage

import javax.inject.Inject
import javax.inject.Singleton

/**
 * Veri temizlik yoneticisi. Eski mesajlari silme ve tum verileri temizleme islemlerini saglar.
 */
@Singleton
class DataCleanupManager @Inject constructor(
    private val database: SecureChatDatabase
) {

    /**
     * Belirli sureden eski mesajlari siler (kullanici ayarina gore).
     * @param retentionDays Mesajlarin saklanma suresi (gun cinsinden)
     */
    suspend fun cleanOldMessages(retentionDays: Int) {
        val cutoff = System.currentTimeMillis() - (retentionDays * 24L * 60 * 60 * 1000)
        database.messageDao().deleteOlderThan(cutoff)
    }

    /**
     * Tum verileri siler (hesap silme / panic button).
     * SQLCipher key'i de ayrica sifirlanmalidir.
     */
    suspend fun nukeAllData() {
        database.clearAllTables()
    }
}
