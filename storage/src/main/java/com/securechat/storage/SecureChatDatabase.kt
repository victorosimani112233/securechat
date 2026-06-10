package com.securechat.storage

import androidx.room.Database
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import com.securechat.storage.dao.CallLogDao
import com.securechat.storage.dao.ContactDao
import com.securechat.storage.dao.ConversationDao
import com.securechat.storage.dao.ExportLogDao
import com.securechat.storage.dao.IdentityDao
import com.securechat.storage.dao.MessageDao
import com.securechat.storage.dao.PendingTimerUpdateDao
import com.securechat.storage.dao.PreKeyDao
import com.securechat.storage.dao.SenderKeyDao
import com.securechat.storage.dao.SessionDao
import com.securechat.storage.dao.SignedPreKeyDao
import com.securechat.storage.dao.ScheduledMessageDao
import com.securechat.storage.entity.CallLogEntity
import com.securechat.storage.entity.ContactEntity
import com.securechat.storage.entity.ConversationEntity
import com.securechat.storage.entity.ExportLogEntity
import com.securechat.storage.entity.IdentityEntity
import com.securechat.storage.entity.MessageEntity
import com.securechat.storage.entity.PendingTimerUpdateEntity
import com.securechat.storage.entity.PreKeyEntity
import com.securechat.storage.entity.ScheduledMessageEntity
import com.securechat.storage.entity.SenderKeyEntity
import com.securechat.storage.entity.SessionEntity
import com.securechat.storage.entity.SignedPreKeyEntity

/**
 * SecureChat Room veritabani. SQLCipher ile sifrelenir.
 * Tum mesajlar, konusmalar, kisiler ve kriptografik anahtarlar burada saklanir.
 */
@Database(
    entities = [
        MessageEntity::class,
        ConversationEntity::class,
        ContactEntity::class,
        PreKeyEntity::class,
        SignedPreKeyEntity::class,
        SessionEntity::class,
        IdentityEntity::class,
        CallLogEntity::class,
        ScheduledMessageEntity::class,
        PendingTimerUpdateEntity::class,
        ExportLogEntity::class,
        SenderKeyEntity::class
    ],
    version = 21,
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
    abstract fun callLogDao(): CallLogDao
    abstract fun scheduledMessageDao(): ScheduledMessageDao
    abstract fun pendingTimerUpdateDao(): PendingTimerUpdateDao
    abstract fun exportLogDao(): ExportLogDao
    abstract fun senderKeyDao(): SenderKeyDao
}
