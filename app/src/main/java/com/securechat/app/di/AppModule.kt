package com.securechat.app.di

import com.securechat.app.BuildConfig
import com.securechat.app.data.UserIdentityProviderImpl
import com.securechat.app.resolver.ContactNameResolverImpl
import com.securechat.common.UserIdentityProvider
import com.securechat.storage.resolver.ContactNameResolver
import dagger.Binds
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Named
import javax.inject.Singleton

/**
 * App modülü için Hilt dependency injection modülü.
 */
@Module
@InstallIn(SingletonComponent::class)
abstract class AppModule {

    /**
     * UserIdentityProvider interface'ini implementation'ına bind eder.
     */
    @Binds
    abstract fun bindUserIdentityProvider(
        implementation: UserIdentityProviderImpl
    ): UserIdentityProvider

    /**
     * ContactNameResolver interface'ini implementation'ına bind eder.
     */
    @Binds
    abstract fun bindContactNameResolver(
        implementation: ContactNameResolverImpl
    ): ContactNameResolver

    companion object {
        @Provides
        @Named("apiBaseUrl")
        fun provideApiBaseUrl(): String = BuildConfig.API_BASE_URL
    }
}