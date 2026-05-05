package com.securechat.network.di

import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import dagger.multibindings.ElementsIntoSet
import okhttp3.Interceptor
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

    /** Default empty interceptor set — app module @IntoSet ile interceptor ekleyebilir. */
    @Provides
    @ElementsIntoSet
    fun provideDefaultInterceptors(): Set<@JvmSuppressWildcards Interceptor> = emptySet()

    /**
     * OkHttpClient instance'i — app modulundeki interceptor'lari (AuthInterceptor gibi) entegre eder.
     */
    @Provides
    @Singleton
    fun provideOkHttpClient(
        interceptors: Set<@JvmSuppressWildcards Interceptor>
    ): OkHttpClient {
        val builder = OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(0, TimeUnit.SECONDS)
            .writeTimeout(15, TimeUnit.SECONDS)
            .pingInterval(30, TimeUnit.SECONDS)
            .retryOnConnectionFailure(true)
        interceptors.forEach { builder.addInterceptor(it) }
        return builder.build()
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
