package com.securechat.network.di

import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import okhttp3.OkHttpClient
import java.util.concurrent.TimeUnit
import javax.inject.Named
import javax.inject.Singleton

/**
 * Network modulunun Hilt dependency injection konfigurasyonu.
 * OkHttpClient ve diger ag bagimliliklarini saglar.
 */
@Module
@InstallIn(SingletonComponent::class)
object NetworkModule {

    /**
     * OkHttpClient instance'i olusturur.
     * WebSocket baglantilari icin optimize edilmis timeout ve ping ayarlari icerir.
     */
    @Provides
    @Singleton
    fun provideOkHttpClient(): OkHttpClient {
        return OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(0, TimeUnit.SECONDS)   // WebSocket icin timeout yok — ping/pong kontrol eder
            .writeTimeout(15, TimeUnit.SECONDS)
            .pingInterval(30, TimeUnit.SECONDS)  // 30 saniyede bir ping — baglanti canliligini kontrol et
            .retryOnConnectionFailure(true)
            .build()
    }

    /**
     * Signaling sunucusu URL'ini saglar.
     * Hardcoded development URL - production'da farklı olabilir.
     */
    @Provides
    @Singleton
    @Named("signalingUrl")
    fun provideSignalingUrl(): String {
        return "ws://185.48.182.124:9090"
    }
}
