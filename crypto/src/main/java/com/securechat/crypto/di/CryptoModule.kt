package com.securechat.crypto.di

import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent

/**
 * Crypto modulu Hilt DI modulu.
 * Tum ana siniflar (@Singleton + @Inject constructor) otomatik olarak
 * Hilt tarafindan saglanir.
 *
 * CryptoPreKeyStore, CryptoSignedPreKeyStore, CryptoSessionStore ve
 * CryptoIdentityStore interface'leri storage modulu tarafindan
 * bind edilecektir.
 */
@Module
@InstallIn(SingletonComponent::class)
object CryptoModule {
    // Tum siniflar @Inject constructor kullandigindan
    // Hilt bunlari otomatik olarak saglar.
    // Bu modul ileride gerekecek ozel binding'ler icin ayrilmistir.
}
