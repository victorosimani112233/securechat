package com.securechat.storage.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.securechat.storage.entity.MessageEntity
import com.securechat.storage.model.MessageStatus
import kotlinx.coroutines.flow.Flow

/**
 * Mesaj veri erisim nesnesi. Tum mesaj CRUD islemleri bu DAO uzerinden yapilir.
 * Flow donduren metodlar reaktif olarak degisiklikleri yayar.
 */
@Dao
interface MessageDao {

    @Query("SELECT * FROM messages WHERE conversation_id = :conversationId ORDER BY timestamp ASC")
    fun getMessages(conversationId: String): Flow<List<MessageEntity>>

    @Query("SELECT * FROM messages WHERE conversation_id = :conversationId ORDER BY timestamp DESC LIMIT :limit")
    fun getRecentMessages(conversationId: String, limit: Int): Flow<List<MessageEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(message: MessageEntity)

    @Update
    suspend fun update(message: MessageEntity)

    @Query("UPDATE messages SET status = :status WHERE id = :messageId")
    suspend fun updateStatus(messageId: String, status: MessageStatus)

    @Query("SELECT * FROM messages WHERE id = :messageId LIMIT 1")
    suspend fun getById(messageId: String): MessageEntity?

    @Query("DELETE FROM messages WHERE id = :messageId")
    suspend fun delete(messageId: String)

    @Query("DELETE FROM messages WHERE conversation_id = :conversationId")
    suspend fun deleteByConversation(conversationId: String)

    @Query("SELECT COUNT(*) FROM messages WHERE conversation_id = :conversationId AND status != 'READ' AND is_outgoing = 0")
    fun getUnreadCount(conversationId: String): Flow<Int>

    @Query("DELETE FROM messages WHERE timestamp < :cutoff")
    suspend fun deleteOlderThan(cutoff: Long)

    // 🗑️ Herkesten silme — icerik guncelleme
    @Query("UPDATE messages SET content = :content, content_type = :contentType WHERE id = :messageId")
    suspend fun updateContent(messageId: String, content: String, contentType: String)

    // 📦 Yedekleme icin tum mesajlari getir
    @Query("SELECT * FROM messages ORDER BY timestamp ASC")
    suspend fun getAllMessages(): List<MessageEntity>

    // 📄 Sayfalama destekli mesaj sorgulari
    @Query("SELECT * FROM messages WHERE conversation_id = :conversationId ORDER BY timestamp DESC LIMIT :limit OFFSET :offset")
    suspend fun getMessagesPaginated(conversationId: String, limit: Int, offset: Int): List<MessageEntity>

    /**
     * Cursor-based sayfalama: belirtilen zaman damgasindan onceki mesajlari getirir.
     * OFFSET/LIMIT yerine timestamp cursor kullanir — buyuk veri setlerinde daha verimli.
     * Paging 3 entegrasyonu yapilana kadar manual sayfalama icin kullanilir.
     */
    @Query("SELECT * FROM messages WHERE conversation_id = :conversationId AND timestamp < :beforeTimestamp ORDER BY timestamp DESC LIMIT :limit")
    suspend fun getOlderMessages(conversationId: String, beforeTimestamp: Long, limit: Int): List<MessageEntity>

    @Query("SELECT COUNT(*) FROM messages WHERE conversation_id = :conversationId")
    suspend fun getMessageCount(conversationId: String): Int

    // 📦 Yedekleme icin toplu mesaj getirme (bellek tasarruflu)
    @Query("SELECT * FROM messages ORDER BY timestamp ASC LIMIT :limit OFFSET :offset")
    suspend fun getMessagesBatch(limit: Int, offset: Int): List<MessageEntity>

    // ✏️ Mesaj duzenleme
    @Query("UPDATE messages SET content = :content, edited_at = :editedAt, edit_history = :editHistory WHERE id = :messageId")
    suspend fun updateContentEdited(messageId: String, content: String, editedAt: Long, editHistory: String?)

    // 👁️ Tek gosterimlik medya — goruntulendi olarak isaretle
    @Query("UPDATE messages SET is_viewed = 1 WHERE id = :messageId")
    suspend fun markViewOnceAsViewed(messageId: String)

    // 👁️ Tek gosterimlik TEXT — goruntulendi olarak isaretle + icerigi sifirla.
    // WhatsApp davranisi: alici acildiktan sonra icerik geri donmemeli; "Acildi"
    // placeholder kalir. content_type filtresi foto/dosya satirlarinin icerigine dokunmaz.
    @Query("UPDATE messages SET is_viewed = 1, content = '' WHERE id = :messageId AND content_type = 'TEXT'")
    suspend fun consumeViewOnceText(messageId: String)

    // ⭐ Yıldızlama özellikleri
    @Query("UPDATE messages SET is_starred = :isStarred WHERE id = :messageId")
    suspend fun updateStarred(messageId: String, isStarred: Boolean)

    @Query("SELECT * FROM messages WHERE conversation_id = :conversationId AND is_starred = 1 ORDER BY timestamp DESC")
    fun getStarredMessages(conversationId: String): Flow<List<MessageEntity>>

    @Query("SELECT * FROM messages WHERE is_starred = 1 ORDER BY timestamp DESC")
    fun getAllStarredMessages(): Flow<List<MessageEntity>>

    // 🔍 Arama özellikleri
    @Query("SELECT * FROM messages WHERE conversation_id = :conversationId AND content LIKE :searchQuery ORDER BY timestamp DESC")
    fun searchMessages(conversationId: String, searchQuery: String): Flow<List<MessageEntity>>

    @Query("SELECT * FROM messages WHERE content LIKE :searchQuery AND content_type IN ('TEXT', 'VOICE_NOTE') ORDER BY timestamp DESC LIMIT :limit")
    suspend fun searchAllMessages(searchQuery: String, limit: Int = 100): List<MessageEntity>

    // 📱 Medya/Doküman özellikleri
    // Resim mesajlari (IMAGE) ve video/ses tipinde FILE mesajlari medya sekmesinde gosterilir.
    @Query("SELECT * FROM messages WHERE conversation_id = :conversationId AND (content_type = 'IMAGE' OR (content_type = 'FILE' AND (content LIKE '%|video/%' OR content LIKE '%|audio/%' OR content LIKE '%|image/%'))) ORDER BY timestamp DESC")
    fun getMediaMessages(conversationId: String): Flow<List<MessageEntity>>

    // Dokuman sekmesi: video/ses/resim disindaki FILE mesajlari
    @Query("SELECT * FROM messages WHERE conversation_id = :conversationId AND content_type = 'FILE' AND content NOT LIKE '%|image/%' AND content NOT LIKE '%|video/%' AND content NOT LIKE '%|audio/%' ORDER BY timestamp DESC")
    fun getDocumentMessages(conversationId: String): Flow<List<MessageEntity>>

    // Sureli mesaj — suresi dolan mesajlari sil
    @Query("DELETE FROM messages WHERE expires_at IS NOT NULL AND expires_at < :now")
    suspend fun deleteExpiredMessages(now: Long): Int

    // Sureli mesaj — silinecek mesajlarin etkilenecek konusma id'lerini doner (silmeden once).
    // MessageRepositoryImpl.deleteExpiredMessages bu listeyi alip silme sonrasi her konusmanin
    // lastMessage degerini tazeler — boylece konusma listesinde stale preview kalmaz.
    @Query("SELECT DISTINCT conversation_id FROM messages WHERE expires_at IS NOT NULL AND expires_at < :now")
    suspend fun getExpiredConversationIds(now: Long): List<String>

    // Sureli mesaj — silinecek MEDYA tipindeki mesajlarin (FILE/IMAGE/VOICE_NOTE) content
    // alanini doner. content = "fileName|mimeType|fileSize|filePath" formati; caller
    // path'i parse edip fiziksel dosyayi siler (DB delete sonrasi).
    @Query("""
        SELECT content FROM messages
        WHERE expires_at IS NOT NULL AND expires_at < :now
          AND content_type IN ('FILE', 'IMAGE', 'VOICE_NOTE')
    """)
    suspend fun getExpiredMediaContents(now: Long): List<String>

    // Konusmadaki en son geriye kalan mesaj (suresi dolmamis) — lastMessage senkronu icin.
    @Query("SELECT * FROM messages WHERE conversation_id = :conversationId ORDER BY timestamp DESC LIMIT 1")
    suspend fun getLatestMessage(conversationId: String): MessageEntity?

    // Race penceresi: DisappearingTimer signal gec geldiginde, son N saniyedeki gelen mesajlara
    // retroaktif expiresAt uygula. Sadece is_outgoing = 0 (gelen) ve expires_at NULL olanlar.
    // expires_at = timestamp + duration (mesajin gelis zamanindan itibaren).
    @Query("""
        UPDATE messages
        SET expires_at = timestamp + :duration
        WHERE conversation_id = :conversationId
          AND is_outgoing = 0
          AND expires_at IS NULL
          AND timestamp >= :windowStart
          AND timestamp <= :now
    """)
    suspend fun applyRetroactiveExpiry(
        conversationId: String,
        duration: Long,
        windowStart: Long,
        now: Long
    ): Int

    // Takilmis SENDING mesajlari bul — belirtilen zaman damgasindan eski, giden mesajlar
    @Query("SELECT * FROM messages WHERE status = 'SENDING' AND is_outgoing = 1 AND timestamp < :olderThan")
    suspend fun getStuckSendingMessages(olderThan: Long): List<MessageEntity>

    // Takilmis SENDING mesajlari toplu olarak FAILED olarak isaretle
    @Query("UPDATE messages SET status = 'FAILED' WHERE status = 'SENDING' AND timestamp < :cutoff")
    suspend fun markStuckMessagesAsFailed(cutoff: Long): Int

    // Emoji reaksiyon guncelleme
    @Query("UPDATE messages SET reactions = :reactions WHERE id = :messageId")
    suspend fun updateReactions(messageId: String, reactions: String?)

    // 📌 Pin mesaj — sabitleme/cikarma
    @Query("UPDATE messages SET is_pinned = :isPinned, pinned_at = :pinnedAt WHERE id = :messageId")
    suspend fun updatePinned(messageId: String, isPinned: Boolean, pinnedAt: Long?)

    // Konusmadaki son sabitlenmis mesaj — banner icin. Birden fazla pin varsa
    // en sonuncusu (pinned_at DESC) one cikar. NULL pinned_at kayitlarini dahil etmemek
    // icin is_pinned = 1 + pinned_at NOT NULL.
    @Query(
        """
        SELECT * FROM messages
        WHERE conversation_id = :conversationId AND is_pinned = 1 AND pinned_at IS NOT NULL
        ORDER BY pinned_at DESC LIMIT 1
        """
    )
    fun observeLatestPinned(conversationId: String): Flow<MessageEntity?>

    // Tum sabitli mesajlar (en yenisinden eskiye) — gelecekte "pinler listesi" ekrani icin.
    @Query(
        """
        SELECT * FROM messages
        WHERE conversation_id = :conversationId AND is_pinned = 1
        ORDER BY pinned_at DESC
        """
    )
    fun getPinnedMessages(conversationId: String): Flow<List<MessageEntity>>
}
