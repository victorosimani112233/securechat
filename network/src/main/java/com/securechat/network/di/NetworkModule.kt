package com.securechat.network.di

import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import dagger.multibindings.ElementsIntoSet
import okhttp3.CertificatePinner
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import java.util.concurrent.TimeUnit
import javax.inject.Singleton

/**
 * Network modulunun Hilt dependency injection konfigurasyonu.
 * OkHttpClient ve diger ag bagimliliklarini saglar.
 *
 * NOT: signalingUrl, stunUrl ve CertificatePinner provider'lari `:app` modulunde
 * (AppModule.kt) tanimli — BuildConfig fields'a erisim icin app-level binding gerekli.
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
     * CertificatePinner null degilse TLS pin'leri uygulanir (MITM korumasi).
     */
    @Provides
    @Singleton
    fun provideOkHttpClient(
        interceptors: Set<@JvmSuppressWildcards Interceptor>,
        certificatePinner: CertificatePinner?
    ): OkHttpClient {
        val builder = OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(0, TimeUnit.SECONDS)
            .writeTimeout(15, TimeUnit.SECONDS)
            .pingInterval(30, TimeUnit.SECONDS)
            .retryOnConnectionFailure(true)
        certificatePinner?.let { builder.certificatePinner(it) }
        interceptors.forEach { builder.addInterceptor(it) }
        return builder.build()
    }
}
