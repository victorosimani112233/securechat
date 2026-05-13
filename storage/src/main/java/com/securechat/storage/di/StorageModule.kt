package com.securechat.storage.di

import android.content.Context
import android.content.SharedPreferences
import androidx.room.Room
import com.securechat.crypto.store.CryptoIdentityStore
import com.securechat.crypto.store.CryptoPreKeyStore
import com.securechat.crypto.store.CryptoSessionStore
import com.securechat.crypto.store.CryptoSignedPreKeyStore
import androidx.room.RoomDatabase
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

        // Passphrase Android Keystore master key ile sarmalandi.
        val passphrase = keyStoreManager.getOrCreateDbPassphrase()

        // MIGRATION RECOVERY: Eski APK'larda "securechat_dev_passphrase" hardcoded passphrase ile
        // yaratilmis DB diskte olabilir. Yeni Keystore-derived passphrase ile decrypt fail eder
        // ("file is not a database" SQLiteException, code 26). Bu durumda DB dosyasini sil ki
        // Room temiz baslayabilsin — kullanici uninstall etmek zorunda kalmasin.
        //
        // Production'da gercek user verisi varsa bu DESTRUCTIVE — geliştirme/launch öncesi OK.
        val dbFile = context.getDatabasePath("securechat.db")
        if (dbFile.exists() && !canOpenWithPassphrase(dbFile, passphrase)) {
            android.util.Log.w(
                "StorageModule",
                "DB passphrase mismatch tespit edildi — eski DB siliniyor (one-time migration)"
            )
            context.deleteDatabase("securechat.db")
        }

        val factory = SupportOpenHelperFactory(passphrase)
        // SQLCipher dahili kopya aldi — bizim referansi sifirla.
        passphrase.fill(0)

        return Room.databaseBuilder(
            context,
            SecureChatDatabase::class.java,
            "securechat.db"
        )
            .openHelperFactory(factory)
            .fallbackToDestructiveMigration()
            .addCallback(object : RoomDatabase.Callback() {
                override fun onOpen(db: SupportSQLiteDatabase) {
                    super.onOpen(db)
                    // Silinen verilerin diskten guvenli silinmesini sagla
                    // SQLCipher PRAGMA komutlarini execSQL ile degil query ile calistirir
                    db.query("PRAGMA secure_delete = ON")
                }
            })
            .build()
    }

    /**
     * Mevcut DB dosyasinin verilen passphrase ile acilip acilamadigini test eder.
     * Hizli no-op query (PRAGMA cipher_version) — basarisizsa yanlis passphrase demektir.
     * Kaynak guvenli — sadece bu fonksiyon kapsaminda DB acilir, sonra kapatilir.
     */
    private fun canOpenWithPassphrase(dbFile: java.io.File, passphrase: ByteArray): Boolean {
        return try {
            net.zetetic.database.sqlcipher.SQLiteDatabase.openDatabase(
                dbFile.absolutePath,
                passphrase,
                null,
                net.zetetic.database.sqlcipher.SQLiteDatabase.OPEN_READONLY,
                null,
                null
            ).use { db ->
                // Yanlis passphrase ile herhangi bir compile cagrisi exception atar.
                db.rawQuery("SELECT count(*) FROM sqlite_master", null).use { it.moveToFirst() }
            }
            true
        } catch (e: Exception) {
            android.util.Log.w("StorageModule", "DB test open basarisiz: ${e.message}")
            false
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
