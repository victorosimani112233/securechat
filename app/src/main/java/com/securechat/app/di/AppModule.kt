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