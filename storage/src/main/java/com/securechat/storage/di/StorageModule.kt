package com.securechat.storage.di

import android.content.Context
import android.content.SharedPreferences
import androidx.room.Room
import com.securechat.crypto.store.CryptoIdentityStore
import com.securechat.crypto.store.CryptoPreKeyStore
import com.securechat.crypto.store.CryptoSessionStore
import com.securechat.crypto.store.CryptoSignedPreKeyStore
import com.securechat.storage.SecureChatDatabase
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
    fun provideDatabase(@ApplicationContext context: Context): SecureChatDatabase {
        // Gelistirme asamasinda sabit passphrase, production'da KeyStoreManager'dan alinacak
        sqlCipherLoaded // native lib'i yukle (lazy, sadece ilk cagride)
        val passphrase = "securechat_dev_passphrase".toByteArray()
        val factory = SupportOpenHelperFactory(passphrase)

        return Room.databaseBuilder(
            context,
            SecureChatDatabase::class.java,
            "securechat.db"
        )
            .openHelperFactory(factory)
            .fallbackToDestructiveMigration()
            .build()
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
