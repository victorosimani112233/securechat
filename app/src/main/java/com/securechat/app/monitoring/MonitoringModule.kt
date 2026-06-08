package com.securechat.app.monitoring

import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

/**
 * Monitoring bagimliliklari — CrashReporter, gelecekte AnalyticsReporter vb.
 *
 * Crashlytics aktif olunca:
 *   - bindCrashReporter -> CrashlyticsCrashReporter (yeni dosya)
 *   - app/build.gradle.kts: id("com.google.gms.google-services") + crashlytics plugin
 *   - SecureChatApplication.onCreate: setCustomKey("commit", BuildConfig.VERSION_NAME)
 *
 * Suanlik NoopCrashReporter — sadece logcat'e yazar.
 */
@Module
@InstallIn(SingletonComponent::class)
abstract class MonitoringModule {

    @Binds
    @Singleton
    abstract fun bindCrashReporter(impl: NoopCrashReporter): CrashReporter
}
