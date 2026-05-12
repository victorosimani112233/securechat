package com.securechat.app.di

import android.content.Context
import android.content.SharedPreferences
import com.securechat.app.BuildConfig
import com.securechat.app.data.AuthInterceptor
import com.securechat.app.data.UserIdentityProviderImpl
import com.securechat.app.resolver.ContactNameResolverImpl
import com.securechat.common.UserIdentityProvider
import com.securechat.storage.resolver.ContactNameResolver
import dagger.Binds
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import dagger.multibindings.IntoSet
import okhttp3.CertificatePinner
import okhttp3.Interceptor
import javax.inject.Named
import javax.inject.Singleton

/**
 * App modulu icin Hilt dependency injection modulu.
 */
@Module
@InstallIn(SingletonComponent::class)
abstract class AppModule {

    /**
     * UserIdentityProvider interface'ini implementation'ina bind eder.
     */
    @Binds
    abstract fun bindUserIdentityProvider(
        implementation: UserIdentityProviderImpl
    ): UserIdentityProvider

    /**
     * ContactNameResolver interface'ini implementation'ina bind eder.
     */
    @Binds
    abstract fun bindContactNameResolver(
        implementation: ContactNameResolverImpl
    ): ContactNameResolver

    /**
     * AuthInterceptor'i NetworkModule'un OkHttp interceptor set'ine ekler.
     * Bu sayede tum HTTP isteklerine Authorization header eklenir ve 401 durumunda
     * otomatik token refresh + retry yapilir.
     */
    @Binds
    @IntoSet
    abstract fun bindAuthInterceptor(impl: AuthInterceptor): Interceptor

    /**
     * Telecom Framework ConnectionService callback'leri ↔ CallManager köprüsü.
     */
    @Binds
    @Singleton
    abstract fun bindConnectionBridge(
        impl: com.securechat.telecom.TelecomCallBridge
    ): com.securechat.telecom.ConnectionBridge

    companion object {
        @Provides
        @Named("apiBaseUrl")
        fun provideApiBaseUrl(): String = BuildConfig.API_BASE_URL

        /**
         * Signaling sunucusu WebSocket URL'i — BuildConfig'den okunur.
         * Dev: ws://... (cleartext, sadece local network), Prod: wss://... (TLS).
         */
        @Provides
        @Singleton
        @Named("signalingUrl")
        fun provideSignalingUrl(): String = BuildConfig.SIGNALING_URL

        /**
         * Fallback STUN sunucusu URL'i — TURN credential cekilemezse kullanilir.
         * Dev: hardcoded IP, Prod: stun.securechat.app domain.
         */
        @Provides
        @Singleton
        @Named("stunUrl")
        fun provideStunUrl(): String = BuildConfig.STUN_URL

        /**
         * TLS Certificate Pinner — BuildConfig'den okur, MITM korumasi.
         *
         * Pin format: "sha256/<base64>"
         * Pin uretmek icin sunucuya bagli iken:
         *   openssl s_client -connect HOST:443 -servername HOST </dev/null 2>/dev/null \
         *     | openssl x509 -pubkey -noout \
         *     | openssl pkey -pubin -outform der \
         *     | openssl dgst -sha256 -binary | openssl enc -base64
         *
         * CERT_PIN_HOST veya CERT_PIN_SHA256 bos ise pinning DISABLE (dev flavor).
         *
         * PRODUCTION GUVENLIK: prod flavor'da CERT_PIN_SHA256 bos ise build fail edilmeli.
         * Backup pin (CERT_PIN_SHA256_BACKUP) cert rotation sirasinda apk brick'ini onler;
         * yeni cert deploy edilirken eski APK'lar backup pin ile dogrulamaya devam eder.
         */
        @Provides
        @Singleton
        fun provideCertificatePinner(): CertificatePinner? {
            val host = BuildConfig.CERT_PIN_HOST
            val primaryPin = BuildConfig.CERT_PIN_SHA256
            val backupPin = BuildConfig.CERT_PIN_SHA256_BACKUP
            val signalingUrl = BuildConfig.SIGNALING_URL
            val apiUrl = BuildConfig.API_BASE_URL

            // GUVENLIK FAIL-FAST: TLS endpoint kullaniliyorsa pin ZORUNLU.
            // Pin olmadan TLS = MITM saldirisina aciksin (Let's Encrypt veya calinmis CA ile).
            val usesTls = signalingUrl.startsWith("wss://") || apiUrl.startsWith("https://")
            if (usesTls) {
                check(host.isNotBlank() && primaryPin.isNotBlank()) {
                    "Production build TLS kullaniyor (signalingUrl=$signalingUrl) ancak " +
                    "CERT_PIN_SHA256 BuildConfig field'i bos. Bu MITM saldirisina aciktir. " +
                    "app/build.gradle.kts'te prod flavor icin pin set et."
                }
                check(backupPin.isNotBlank()) {
                    "Production build CERT_PIN_SHA256 set edilmis ama CERT_PIN_SHA256_BACKUP bos. " +
                    "Backup pin olmadan cert rotation eski APK'lari brick eder. Zorunludur."
                }
            }

            if (host.isBlank() || primaryPin.isBlank()) return null
            val builder = CertificatePinner.Builder()
                .add(host, "sha256/$primaryPin")
            if (backupPin.isNotBlank()) {
                builder.add(host, "sha256/$backupPin")
            }
            return builder.build()
        }

        /**
         * Uygulama genelinde kullanilan SharedPreferences instance'i.
         * Cevrimdisi kuyruk, bekleyen islemler gibi verileri saklar.
         */
        @Provides
        @Singleton
        fun provideSharedPreferences(
            @ApplicationContext context: Context
        ): SharedPreferences = context.getSharedPreferences("securechat_prefs", Context.MODE_PRIVATE)
    }
}