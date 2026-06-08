package com.securechat.storage.di

import android.content.Context
import android.content.SharedPreferences
import androidx.room.Room
import com.securechat.crypto.store.CryptoIdentityStore
import com.securechat.crypto.store.CryptoPreKeyStore
import com.securechat.crypto.store.CryptoSessionStore
import com.securechat.crypto.store.CryptoSignedPreKeyStore
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase
import com.securechat.crypto.KeyStoreManager
import com.securechat.storage.SecureChatDatabase
import javax.inject.Named
import com.securechat.storage.crypto.CryptoIdentityStoreImpl
import com.securechat.storage.crypto.CryptoPreKeyStoreImpl
import com.securechat.storage.crypto.CryptoSessionStoreImpl
import com.securechat.storage.crypto.CryptoSignedPreKeyStoreImpl
import com.securechat.storage.dao.CallLogDao
import com.securechat.storage.dao.ScheduledMessageDao
import com.securechat.storage.dao.ContactDao
import com.securechat.storage.dao.ConversationDao
import com.securechat.storage.dao.IdentityDao
import com.securechat.storage.dao.MessageDao
import com.securechat.storage.dao.PreKeyDao
import com.securechat.storage.dao.SessionDao
import com.securechat.storage.dao.SignedPreKeyDao
import com.securechat.storage.repository.MessageRepository
import com.securechat.storage.repository.MessageRepositoryImpl
import dagger.Binds
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import net.zetetic.database.sqlcipher.SupportOpenHelperFactory
import javax.inject.Singleton

/**
 * Room veritabani ve DAO provider'larini saglar.
 * SQLCipher ile sifrelenmis veritabani olusturur.
 */
@Module
@InstallIn(SingletonComponent::class)
object StorageModule {

    // SQLCipher native kutuphane tek seferlik yukleme — lazy ilk erisimde yapilir
    private val sqlCipherLoaded by lazy {
        System.loadLibrary("sqlcipher")
        true
    }

    @Provides
    @Singleton
    fun provideDatabase(
        @ApplicationContext context: Context,
        keyStoreManager: KeyStoreManager
    ): SecureChatDatabase {
        sqlCipherLoaded // native lib'i yukle (lazy, sadece ilk cagride)

        // Passphrase ANDROID_ID + HMAC-SHA256 ile deterministic — her acilista AYNI.
        val passphrase = keyStoreManager.getOrCreateDbPassphrase()
        android.util.Log.d(
            "StorageModule",
            "DB aciliyor (passphrase prefix=" +
                passphrase.take(4).joinToString("") { "%02x".format(it) } + ")"
        )

        // KRITIK: Migration recovery zinciri TAMAMEN KALDIRILDI.
        // Onceki versiyonlarda canOpenWithPassphrase test'i yan etki (lock contention, WAL race)
        // yaratip CALISAN DB'leri "acilamaz" gibi gosteriyor, yedek alip sildirip kullanicinin
        // tum sohbetlerini kaybetmesine yol aciyordu. Artik:
        //   1. Passphrase deterministic (her acilista ayni)
        //   2. Room SQLCipher ile direkt DB'yi acar
        //   3. Acamazsa SQLCipher kendi exception'unu firlatir, DB SILMEK YOK
        //   4. Eger gercekten passphrase uyusmazsa kullanici uninstall+reinstall yapsin
        //
        // Bu yaklasimla "her acilista DB siliniyor" bug'i kalici cozulur.

        val factory = SupportOpenHelperFactory(passphrase)
        passphrase.fill(0)

        return Room.databaseBuilder(
            context,
            SecureChatDatabase::class.java,
            "securechat.db"
        )
            .openHelperFactory(factory)
            .addMigrations(MIGRATION_17_18)
            .fallbackToDestructiveMigration()
            .addCallback(object : RoomDatabase.Callback() {
                override fun onOpen(db: SupportSQLiteDatabase) {
                    super.onOpen(db)
                    // Silinen verilerin diskten guvenli silinmesini sagla
                    db.query("PRAGMA secure_delete = ON")
                    android.util.Log.d("StorageModule", "Room DB acildi (onOpen)")
                }
                override fun onCreate(db: SupportSQLiteDatabase) {
                    super.onCreate(db)
                    android.util.Log.d("StorageModule", "Room DB ilk kez yaratildi (onCreate)")
                }
            })
            .build()
    }

    // NOT: canOpenWithPassphrase + tryRekeyDatabase + LEGACY_DEV_PASSPHRASE tamamen kaldirildi.
    // Yedek-al-sil yolu CALISAN DB'leri yanlislikla siliyordu (kullanici sohbetleri her
    // acilista kayboluyordu). Artik passphrase deterministic, Room direkt SQLCipher ile
    // acar, hata varsa exception firlatir — DB SILMEK YOK.

    /**
     * v17 -> v18: Sohbet disa aktarma izni alani + export_log tablosu.
     *  - ConversationEntity.is_export_enabled (BOOLEAN, default 0)
     *  - export_log tablosu (admin-only encrypted log girdileri icin)
     * Veri kaybi olmaz; mevcut konusmalarda export default kapali kalir.
     */
    private val MIGRATION_17_18 = object : Migration(17, 18) {
        override fun migrate(db: SupportSQLiteDatabase) {
            db.execSQL("ALTER TABLE conversations ADD COLUMN is_export_enabled INTEGER NOT NULL DEFAULT 0")
            db.execSQL(
                """
                CREATE TABLE IF NOT EXISTS export_log (
                    id TEXT NOT NULL PRIMARY KEY,
                    group_id TEXT NOT NULL,
                    actor_user_id TEXT NOT NULL,
                    actor_display_name TEXT NOT NULL,
                    event_type TEXT NOT NULL,
                    timestamp INTEGER NOT NULL,
                    message_count INTEGER NOT NULL,
                    first_msg_ts INTEGER,
                    last_msg_ts INTEGER
                )
                """.trimIndent()
            )
            db.execSQL("CREATE INDEX IF NOT EXISTS index_export_log_group_id_timestamp ON export_log(group_id, timestamp)")
            db.execSQL("CREATE INDEX IF NOT EXISTS index_export_log_timestamp ON export_log(timestamp)")
        }
    }

    @Provides
    fun provideMessageDao(db: SecureChatDatabase): MessageDao = db.messageDao()

    @Provides
    fun provideConversationDao(db: SecureChatDatabase): ConversationDao = db.conversationDao()

    @Provides
    fun provideCallLogDao(db: SecureChatDatabase): CallLogDao = db.callLogDao()

    @Provides
    fun provideScheduledMessageDao(db: SecureChatDatabase): ScheduledMessageDao = db.scheduledMessageDao()

    @Provides
    fun providePendingTimerUpdateDao(db: SecureChatDatabase): com.securechat.storage.dao.PendingTimerUpdateDao =
        db.pendingTimerUpdateDao()

    @Provides
    fun provideContactDao(db: SecureChatDatabase): ContactDao = db.contactDao()

    @Provides
    fun providePreKeyDao(db: SecureChatDatabase): PreKeyDao = db.preKeyDao()

    @Provides
    fun provideSignedPreKeyDao(db: SecureChatDatabase): SignedPreKeyDao = db.signedPreKeyDao()

    @Provides
    fun provideSessionDao(db: SecureChatDatabase): SessionDao = db.sessionDao()

    @Provides
    fun provideIdentityDao(db: SecureChatDatabase): IdentityDao = db.identityDao()

    @Provides
    fun provideExportLogDao(db: SecureChatDatabase): com.securechat.storage.dao.ExportLogDao =
        db.exportLogDao()

    @Provides
    @Singleton
    @Named("crypto")
    fun provideCryptoPrefs(@ApplicationContext context: Context): SharedPreferences {
        return context.getSharedPreferences("crypto_prefs", Context.MODE_PRIVATE)
    }
}

/**
 * Interface binding'lerini saglar. Crypto store ve repository implementasyonlari burada baglanir.
 */
@Module
@InstallIn(SingletonComponent::class)
abstract class StorageBindingsModule {

    @Binds
    @Singleton
    abstract fun bindCryptoPreKeyStore(impl: CryptoPreKeyStoreImpl): CryptoPreKeyStore

    @Binds
    @Singleton
    abstract fun bindCryptoSignedPreKeyStore(impl: CryptoSignedPreKeyStoreImpl): CryptoSignedPreKeyStore

    @Binds
    @Singleton
    abstract fun bindCryptoSessionStore(impl: CryptoSessionStoreImpl): CryptoSessionStore

    @Binds
    @Singleton
    abstract fun bindCryptoIdentityStore(impl: CryptoIdentityStoreImpl): CryptoIdentityStore

    @Binds
    @Singleton
    abstract fun bindMessageRepository(impl: MessageRepositoryImpl): MessageRepository
}
