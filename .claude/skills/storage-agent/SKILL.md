---
name: storage-agent
description: >
  Yerel veri saklama agentı. Room (SQLite) veritabanı tasarımı, DAO implementasyonu,
  SQLCipher ile veritabanı şifreleme, migration stratejisi ve reactive data flow (Flow)
  sağlar. Tüm mesajlar, konuşmalar, kriptografik anahtarlar ve kullanıcı tercihleri
  yalnızca cihaz üzerinde saklanır — sunucuya hiçbir veri gönderilmez.
  Entity tasarımı, index optimizasyonu ve veritabanı bakım işlemleri bu agentın sorumluluğundadır.
---

# Storage Agent — Yerel Veritabanı ve Veri Yönetimi

## Rol
Sen SecureChat'in depolama agentısın. Görevin tüm verileri güvenli şekilde cihaz üzerinde
saklamak. Sunucu tarafında hiçbir mesaj verisi tutulmaz — her şey lokal SQLite'da.

## Sorumluluklar

### 1. Room Database

```kotlin
@Database(
    entities = [
        MessageEntity::class,
        ConversationEntity::class,
        ContactEntity::class,
        PreKeyEntity::class,
        SignedPreKeyEntity::class,
        SessionEntity::class,
        IdentityEntity::class
    ],
    version = 1,
    exportSchema = true
)
@TypeConverters(Converters::class)
abstract class SecureChatDatabase : RoomDatabase() {
    abstract fun messageDao(): MessageDao
    abstract fun conversationDao(): ConversationDao
    abstract fun contactDao(): ContactDao
    abstract fun preKeyDao(): PreKeyDao
    abstract fun signedPreKeyDao(): SignedPreKeyDao
    abstract fun sessionDao(): SessionDao
    abstract fun identityDao(): IdentityDao
}
```

### 2. SQLCipher Entegrasyonu

```kotlin
@Module
@InstallIn(SingletonComponent::class)
object DatabaseModule {
    
    @Provides
    @Singleton
    fun provideDatabase(
        @ApplicationContext context: Context,
        keyStoreManager: KeyStoreManager
    ): SecureChatDatabase {
        val passphrase = keyStoreManager.getDatabasePassphrase()
        val factory = SupportFactory(passphrase)
        
        return Room.databaseBuilder(
            context,
            SecureChatDatabase::class.java,
            "securechat.db"
        )
        .openHelperFactory(factory) // SQLCipher
        .fallbackToDestructiveMigration() // Geliştirme aşamasında
        .build()
    }
}
```

### 3. Entity Tanımları

```kotlin
@Entity(
    tableName = "messages",
    indices = [
        Index(value = ["conversation_id", "timestamp"]),
        Index(value = ["sender_id"]),
        Index(value = ["status"])
    ],
    foreignKeys = [
        ForeignKey(
            entity = ConversationEntity::class,
            parentColumns = ["id"],
            childColumns = ["conversation_id"],
            onDelete = ForeignKey.CASCADE
        )
    ]
)
data class MessageEntity(
    @PrimaryKey val id: String, // UUID
    @ColumnInfo(name = "conversation_id") val conversationId: String,
    @ColumnInfo(name = "sender_id") val senderId: String,
    @ColumnInfo(name = "content") val content: String, // Çözülmüş metin (bellekte şifreli, DB'de SQLCipher)
    @ColumnInfo(name = "content_type") val contentType: MessageContentType, // TEXT, IMAGE, FILE, VOICE_NOTE
    @ColumnInfo(name = "timestamp") val timestamp: Long,
    @ColumnInfo(name = "status") val status: MessageStatus, // SENDING, SENT, DELIVERED, READ, FAILED
    @ColumnInfo(name = "reply_to_id") val replyToId: String? = null,
    @ColumnInfo(name = "is_outgoing") val isOutgoing: Boolean
)

@Entity(
    tableName = "conversations",
    indices = [Index(value = ["last_message_timestamp"])]
)
data class ConversationEntity(
    @PrimaryKey val id: String,
    @ColumnInfo(name = "peer_id") val peerId: String,
    @ColumnInfo(name = "peer_name") val peerName: String,
    @ColumnInfo(name = "peer_phone") val peerPhone: String,
    @ColumnInfo(name = "last_message") val lastMessage: String?,
    @ColumnInfo(name = "last_message_timestamp") val lastMessageTimestamp: Long?,
    @ColumnInfo(name = "unread_count") val unreadCount: Int = 0,
    @ColumnInfo(name = "is_muted") val isMuted: Boolean = false,
    @ColumnInfo(name = "is_pinned") val isPinned: Boolean = false
)

@Entity(tableName = "contacts")
data class ContactEntity(
    @PrimaryKey val id: String,
    @ColumnInfo(name = "phone_number") val phoneNumber: String,
    @ColumnInfo(name = "phone_hash") val phoneHash: String, // SHA-256 hash
    @ColumnInfo(name = "display_name") val displayName: String,
    @ColumnInfo(name = "is_registered") val isRegistered: Boolean,
    @ColumnInfo(name = "avatar_uri") val avatarUri: String? = null,
    @ColumnInfo(name = "last_seen") val lastSeen: Long? = null
)

// Kriptografik key entity'leri
@Entity(tableName = "prekeys")
data class PreKeyEntity(
    @PrimaryKey val id: Int,
    @ColumnInfo(name = "record", typeAffinity = ColumnInfo.BLOB) val record: ByteArray
)

@Entity(tableName = "signed_prekeys")
data class SignedPreKeyEntity(
    @PrimaryKey val id: Int,
    @ColumnInfo(name = "record", typeAffinity = ColumnInfo.BLOB) val record: ByteArray,
    @ColumnInfo(name = "created_at") val createdAt: Long
)

@Entity(tableName = "sessions")
data class SessionEntity(
    @PrimaryKey val addressName: String, // userId:deviceId
    @ColumnInfo(name = "record", typeAffinity = ColumnInfo.BLOB) val record: ByteArray
)

@Entity(tableName = "identities")
data class IdentityEntity(
    @PrimaryKey val addressName: String,
    @ColumnInfo(name = "identity_key", typeAffinity = ColumnInfo.BLOB) val identityKey: ByteArray,
    @ColumnInfo(name = "trust_level") val trustLevel: TrustLevel // UNTRUSTED, TRUSTED_UNVERIFIED, TRUSTED_VERIFIED
)
```

### 4. DAO Implementasyonları

```kotlin
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
    
    @Query("DELETE FROM messages WHERE id = :messageId")
    suspend fun delete(messageId: String)
    
    @Query("DELETE FROM messages WHERE conversation_id = :conversationId")
    suspend fun deleteByConversation(conversationId: String)
    
    @Query("SELECT COUNT(*) FROM messages WHERE conversation_id = :conversationId AND status != 'READ' AND is_outgoing = 0")
    fun getUnreadCount(conversationId: String): Flow<Int>
}

@Dao
interface ConversationDao {
    @Query("SELECT * FROM conversations ORDER BY is_pinned DESC, last_message_timestamp DESC")
    fun getAll(): Flow<List<ConversationEntity>>
    
    @Query("SELECT * FROM conversations WHERE peer_id = :peerId LIMIT 1")
    suspend fun getByPeerId(peerId: String): ConversationEntity?
    
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(conversation: ConversationEntity)
    
    @Query("UPDATE conversations SET unread_count = 0 WHERE id = :conversationId")
    suspend fun markAsRead(conversationId: String)
    
    @Query("DELETE FROM conversations WHERE id = :conversationId")
    suspend fun delete(conversationId: String)
    
    @Transaction
    suspend fun deleteWithMessages(conversationId: String, messageDao: MessageDao) {
        messageDao.deleteByConversation(conversationId)
        delete(conversationId)
    }
}

@Dao
interface PreKeyDao {
    @Query("SELECT * FROM prekeys WHERE id = :id")
    suspend fun get(id: Int): PreKeyEntity?
    
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(preKey: PreKeyEntity)
    
    @Query("DELETE FROM prekeys WHERE id = :id")
    suspend fun delete(id: Int)
    
    @Query("SELECT COUNT(*) FROM prekeys")
    suspend fun count(): Int
    
    @Query("SELECT MAX(id) FROM prekeys")
    suspend fun maxId(): Int?
}
```

### 5. Repository Pattern

```kotlin
class MessageRepositoryImpl @Inject constructor(
    private val messageDao: MessageDao,
    private val conversationDao: ConversationDao
) : MessageRepository {
    
    override suspend fun saveMessage(message: LocalMessage) {
        val entity = message.toEntity()
        messageDao.insert(entity)
        
        // Konuşmanın son mesajını güncelle
        conversationDao.getByPeerId(message.peerId)?.let { conv ->
            conversationDao.insert(
                conv.copy(
                    lastMessage = message.content,
                    lastMessageTimestamp = message.timestamp,
                    unreadCount = if (!message.isOutgoing) conv.unreadCount + 1 else conv.unreadCount
                )
            )
        }
    }
    
    override fun getMessages(conversationId: String): Flow<List<LocalMessage>> {
        return messageDao.getMessages(conversationId).map { entities ->
            entities.map { it.toDomain() }
        }
    }
    
    override fun getConversations(): Flow<List<Conversation>> {
        return conversationDao.getAll().map { entities ->
            entities.map { it.toDomain() }
        }
    }
    
    override suspend fun deleteMessage(messageId: String) {
        messageDao.delete(messageId)
    }
    
    override suspend fun deleteConversation(conversationId: String) {
        messageDao.deleteByConversation(conversationId)
        conversationDao.delete(conversationId)
    }
}
```

### 6. Veri Silme ve Temizlik

```kotlin
class DataCleanupManager @Inject constructor(
    private val database: SecureChatDatabase
) {
    // Belirli süreden eski mesajları sil (kullanıcı ayarına göre)
    suspend fun cleanOldMessages(retentionDays: Int) {
        val cutoff = System.currentTimeMillis() - (retentionDays * 24 * 60 * 60 * 1000L)
        database.messageDao().deleteOlderThan(cutoff)
    }
    
    // Tüm verileri sil (hesap silme / panic button)
    suspend fun nukeAllData() {
        database.clearAllTables()
        // SQLCipher key'i de sıfırla
    }
}
```

## Güvenlik Kuralları
1. **SQLCipher zorunlu** — veritabanı her zaman şifreli
2. **DB passphrase Android Keystore'da** — SharedPreferences'da DEĞİL
3. **WAL mode aktif** — performans için
4. **Export schema true** — migration doğrulaması için
5. **Cascade delete** — konuşma silinince mesajlar da silinmeli
6. **VACUUM periyodik** — silinen verinin diskten temizlenmesi

## Bağımlılıklar
- `crypto-agent` → Key entity'lerinin persist edilmesi
- `infra-agent` → Room dependency ve Hilt modül yapısı

## Test Gereksinimleri
- Unit test: Tüm DAO operasyonları (in-memory DB ile)
- Unit test: Migration'lar
- Unit test: Repository CRUD
- Unit test: Flow emission doğrulaması
- Integration test: SQLCipher ile DB açma/kapama
