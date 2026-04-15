package com.securechat.contacts.di

import com.google.i18n.phonenumbers.PhoneNumberUtil
import com.securechat.contacts.ContactRepository
import com.securechat.contacts.ContactRepositoryImpl
import com.securechat.contacts.DiscoveryApiService
import dagger.Binds
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import javax.inject.Singleton

/**
 * Contacts modulunun Hilt bagimliliklari.
 * PhoneNumberUtil ve DiscoveryApiService instance'larini saglar.
 */
@Module
@InstallIn(SingletonComponent::class)
abstract class ContactsModule {

    companion object {

        @Provides
        @Singleton
        fun providePhoneNumberUtil(): PhoneNumberUtil {
            return PhoneNumberUtil.getInstance()
        }

        @Provides
        @Singleton
        fun provideDiscoveryApiService(): DiscoveryApiService {
            return Retrofit.Builder()
                .baseUrl("https://api.securechat.app/")
                .addConverterFactory(GsonConverterFactory.create())
                .build()
                .create(DiscoveryApiService::class.java)
        }
    }

    @Binds
    abstract fun bindContactRepository(impl: ContactRepositoryImpl): ContactRepository
}
