package com.securechat.media.di

import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent

/**
 * Media modulu icin Hilt dependency injection modulu.
 *
 * CallManager, CallAudioManager ve IncomingCallHandler siniflari
 * @Inject constructor ile dogrudan inject edildigi icin burada
 * ek @Provides tanimi gerekmez.
 */
@Module
@InstallIn(SingletonComponent::class)
object MediaModule {
    // Tum siniflar constructor injection kullanir (@Inject)
}
