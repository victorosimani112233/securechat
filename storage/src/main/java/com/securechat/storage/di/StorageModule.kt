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

        // MIGRATION RECOVERY (multi-source): Yeni deterministic passphrase ile DB acilamazsa
        // 3 kaynaktan rekey dene:
        //   1. Eski Keystore-encrypted random passphrase (onceki versionlardan)
        //   2. Hardcoded "securechat_dev_passphrase" (en eski dev versionlardan)
        // Hicbiri tutmazsa DB YEDEKLE (silme yerine) — kullanici verisi disk'te korunur.
        val dbFile = context.getDatabasePath("securechat.db")
        if (dbFile.exists()) {
            android.util.Log.d("StorageModule", "DB var, yeni passphrase ile test ediliyor")
            if (canOpenWithPassphrase(dbFile, passphrase)) {
                android.util.Log.d("StorageModule", "DB yeni passphrase ile acildi — migration gerekmiyor")
            } else {
                android.util.Log.w(
                    "StorageModule",
                    "DB yeni deterministic passphrase ile acilamadi — legacy yollar deneniyor"
                )

                var rekeyed = false

                // 1. ESKI KEYSTORE PASSPHRASE: onceki versionlarda Keystore-encrypted random passphrase
                val legacyKeystorePassphrase = keyStoreManager.getLegacyPassphraseIfAny()
                if (legacyKeystorePassphrase != null) {
                    android.util.Log.i("StorageModule", "Legacy Keystore passphrase deneniyor")
                    rekeyed = tryRekeyDatabase(dbFile, legacyKeystorePassphrase, passphrase)
                    legacyKeystorePassphrase.fill(0)
                    if (rekeyed) {
                        keyStoreManager.clearLegacyPassphrase()
                        android.util.Log.i(
                            "StorageModule",
                            "Legacy Keystore passphrase ile rekey BASARILI — sohbetler korundu"
                        )
                    }
                }

                // 2. HARDCODED LEGACY PASSPHRASE: en eski dev versionlardan
                if (!rekeyed) {
                    android.util.Log.i("StorageModule", "Hardcoded legacy passphrase deneniyor")
                    val hardcodedLegacy = LEGACY_DEV_PASSPHRASE.toByteArray(Charsets.UTF_8)
                    rekeyed = tryRekeyDatabase(dbFile, hardcodedLegacy, passphrase)
                    hardcodedLegacy.fill(0)
                    if (rekeyed) {
                        android.util.Log.i(
                            "StorageModule",
                            "Hardcoded legacy passphrase ile rekey BASARILI"
                        )
                    }
                }

                if (!rekeyed) {
                    // 3. Hicbir passphrase calismadi — DB'yi YEDEKLE (silme yerine).
                    val ts = System.currentTimeMillis()
                    val backupFile = java.io.File(dbFile.parentFile, "securechat.db.broken_$ts")
                    try {
                        dbFile.renameTo(backupFile)
                        java.io.File(dbFile.parentFile, "securechat.db-journal").delete()
                        java.io.File(dbFile.parentFile, "securechat.db-wal").delete()
                        java.io.File(dbFile.parentFile, "securechat.db-shm").delete()
                        android.util.Log.e(
                            "StorageModule",
                            "DB hicbir passphrase ile acilamadi — YEDEK ALINDI: ${backupFile.name}. " +
                                "Kullanici verisi disk'te korundu, recovery icin manuel mudahale gerekir."
                        )
                    } catch (e: Exception) {
                        android.util.Log.e("StorageModule", "DB yedek alinamadi: ${e.message}, son care delete", e)
                        context.deleteDatabase("securechat.db")
                    }
                }
            }
        } else {
            android.util.Log.d("StorageModule", "DB dosyasi yok, ilk acilis — yeni DB yaratilacak")
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
     * Eski hardcoded passphrase — sadece migration recovery'de kullanilir.
     * Production'a giden tum APK'lar Keystore-derived passphrase'e gecmis olur,
     * sonraki versiyonlarda bu constant kaldirilabilir (kalan kullanicilar zaten rekey olmus).
     */
    private const val LEGACY_DEV_PASSPHRASE = "securechat_dev_passphrase"

    /**
     * Mevcut DB dosyasinin verilen passphrase ile acilip acilamadigini test eder.
     * Yanlis passphrase ile SQLCipher prepareStatement asamasinda exception atar.
     */
    private fun canOpenWithPassphrase(dbFile: java.io.File, passphrase: ByteArray): Boolean {
        return try {
            val db = net.zetetic.database.sqlcipher.SQLiteDatabase.openDatabase(
                dbFile.absolutePath,
                passphrase,
                null,
                net.zetetic.database.sqlcipher.SQLiteDatabase.OPEN_READONLY,
                null,
                null
            )
            try {
                // Yanlis passphrase ile herhangi bir compile cagrisi exception atar.
                db.rawQuery("SELECT count(*) FROM sqlite_master", null).use { it.moveToFirst() }
                true
            } finally {
                db.close()
            }
        } catch (e: Exception) {
            android.util.Log.w("StorageModule", "DB test open basarisiz: ${e.message}")
            false
        }
    }

    /**
     * Eski passphrase ile DB'yi acip yeni passphrase ile rekey eder.
     * SQLCipher native changePassword() kullanir — atomic, schema/data korunur, sohbetler kaybolmaz.
     *
     * @return true ise basarili — DB artik newKey ile acilabilir; false ise migration mumkun degil.
     */
    private fun tryRekeyDatabase(
        dbFile: java.io.File,
        oldKey: ByteArray,
        newKey: ByteArray
    ): Boolean {
        return try {
            val db = net.zetetic.database.sqlcipher.SQLiteDatabase.openDatabase(
                dbFile.absolutePath,
                oldKey,
                null,
                net.zetetic.database.sqlcipher.SQLiteDatabase.OPEN_READWRITE,
                null,
                null
            )
            try {
                // changePassword PRAGMA rekey'i atomic olarak calistirir.
                db.changePassword(newKey)
            } finally {
                db.close()
            }
            // Dogrula: yeni key ile gercekten acilabiliyor mu?
            canOpenWithPassphrase(dbFile, newKey)
        } catch (e: Exception) {
            android.util.Log.w("StorageModule", "Rekey hatasi: ${e.message}")
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
