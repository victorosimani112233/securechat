package com.securechat.app.data

import com.securechat.storage.dao.ConversationDao
import com.securechat.storage.dao.MessageDao
import com.securechat.storage.entity.ConversationEntity
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Konusma basina depolama kullanim analizi.
 *
 * Her konusmanin kapladigi yer (dosya mesajlari + metin overhead) hesaplanir.
 * Saf islem — yeni state tutmaz, sadece okur ve siler (cleanForConversation).
 *
 * Metin overhead: gercek SQLite + indeks maliyeti tahmin etmek zor; bir mesaj basina
 * ortalama 256 bayt kabul edilir (id+content+meta). Bu bir tahmin — kullaniciya
 * gosterirken "yaklasik" ifadesi tercih edilir.
 */
@Singleton
class ChatStorageAnalyzer @Inject constructor(
    private val messageDao: MessageDao,
    private val conversationDao: ConversationDao
) {
    companion object {
        /** Her TEXT mesaji icin tahmini DB overhead (byte). */
        const val TEXT_OVERHEAD_PER_MESSAGE = 256L
    }

    /** Tek konusma icin depolama dokumlu. */
    data class ChatStorageBreakdown(
        val conversationId: String,
        val displayName: String,
        val isGroup: Boolean,
        val messageCount: Int,
        val fileCount: Int,
        val fileBytes: Long,
        val totalBytes: Long
    )

    /**
     * Tum konusmalar icin breakdown listesi — buyuk konusma onde.
     */
    suspend fun analyzeAll(): List<ChatStorageBreakdown> {
        val conversations = conversationDao.getAllImmediate()
        return conversations
            .map { analyze(it) }
            .sortedByDescending { it.totalBytes }
    }

    /** Tek konusma icin breakdown. */
    suspend fun analyze(conversation: ConversationEntity): ChatStorageBreakdown {
        val messageCount = messageDao.getMessageCount(conversation.id)
        val fileContents = messageDao.getFileContentsByConversation(conversation.id)
        var fileBytes = 0L
        var fileCount = 0
        for (content in fileContents) {
            val parts = content.split("|")
            // Pipe format: "name|mime|size|path"
            val sizeFromDb = parts.getOrNull(2)?.toLongOrNull()
            val path = parts.getOrNull(3)
            val diskSize = if (!path.isNullOrBlank()) {
                runCatching {
                    val f = File(path)
                    if (f.exists() && f.isFile) f.length() else 0L
                }.getOrDefault(0L)
            } else 0L
            // Gercek disk boyutu varsa onu kullan; yoksa DB'deki boyut tahmini
            val effective = if (diskSize > 0) diskSize else (sizeFromDb ?: 0L)
            fileBytes += effective
            fileCount += 1
        }
        val textOverhead = messageCount.toLong() * TEXT_OVERHEAD_PER_MESSAGE
        return ChatStorageBreakdown(
            conversationId = conversation.id,
            displayName = conversation.peerName.ifBlank { conversation.peerId },
            isGroup = conversation.isGroup,
            messageCount = messageCount,
            fileCount = fileCount,
            fileBytes = fileBytes,
            totalBytes = fileBytes + textOverhead
        )
    }

    /**
     * Konusmadaki tum medya/dosya mesajlarini siler.
     * Mesaj metni (TEXT) kalir; sadece dosya kayitlari + fiziksel dosyalar gider.
     *
     * @return silinen toplam byte
     */
    suspend fun cleanFilesForConversation(conversationId: String): Long {
        val fileContents = messageDao.getFileContentsByConversation(conversationId)
        var freed = 0L
        for (content in fileContents) {
            val path = content.split("|").getOrNull(3) ?: continue
            if (path.isBlank()) continue
            runCatching {
                val f = File(path)
                if (f.exists() && f.isFile) {
                    val size = f.length()
                    if (f.delete()) freed += size
                }
            }
        }
        messageDao.deleteMediaByConversation(conversationId)
        return freed
    }
}
