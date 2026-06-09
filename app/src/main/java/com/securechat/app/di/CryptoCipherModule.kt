package com.securechat.app.di

import com.securechat.app.crypto.OneToOneFileCipherImpl
import com.securechat.media.crypto.OneToOneFileCipher
import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

/**
 * media.OneToOneFileCipher arayuzunu app modulundeki concrete impl ile baglar.
 *
 * Bu binding olmadan FileTransferManager 1:1 dosyalari plaintext gonderir
 * (cipher null default'a duser). Production'da binding zorunlu — Sprint 6-A
 * 1:1 file E2EE hedefini saglar.
 */
@Module
@InstallIn(SingletonComponent::class)
abstract class CryptoCipherModule {

    @Binds
    @Singleton
    abstract fun bindOneToOneFileCipher(impl: OneToOneFileCipherImpl): OneToOneFileCipher
}
