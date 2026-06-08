package com.securechat.app.data

import android.content.Context
import android.content.SharedPreferences
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Onboarding + permission walkthrough akislarinin tamamlanma durumunu tutar.
 * Lokal-only persistans (SharedPreferences). Kullanici acknowledge ettiyse
 * akislari tekrar gostermeyiz.
 *
 * Settings ekraninda "Onboarding'i tekrar goster" toggle'i (varsa) reset() cagirir.
 */
@Singleton
class OnboardingAckStore @Inject constructor(
    @ApplicationContext context: Context
) {
    private val prefs: SharedPreferences =
        context.getSharedPreferences("onboarding_ack", Context.MODE_PRIVATE)

    /** Onboarding (3 sayfalik intro) tamamlandi mi. */
    fun isOnboardingCompleted(): Boolean = prefs.getBoolean(KEY_ONBOARDING, false)

    fun markOnboardingCompleted() {
        prefs.edit().putBoolean(KEY_ONBOARDING, true).apply()
    }

    /** Permission walkthrough goruldu mu. (Permission'lar yine her zaman runtime'da istenir.) */
    fun isPermissionsWalkthroughSeen(): Boolean = prefs.getBoolean(KEY_PERMS, false)

    fun markPermissionsWalkthroughSeen() {
        prefs.edit().putBoolean(KEY_PERMS, true).apply()
    }

    /** Hem onboarding hem perms walkthrough'u sifirla — Settings'ten "tekrar goster" icin. */
    fun reset() {
        prefs.edit().clear().apply()
    }

    companion object {
        private const val KEY_ONBOARDING = "onboarding_completed"
        private const val KEY_PERMS = "perms_walkthrough_seen"
    }
}
