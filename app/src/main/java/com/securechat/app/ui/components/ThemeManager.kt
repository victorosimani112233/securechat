package com.securechat.app.ui.components

import android.content.Context
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Tema yönetimi için yardımcı sınıf.
 * Kullanıcının tema tercihi (sistem, açık, koyu) ve otomatik tema değişimini yönetir.
 */
@Singleton
class ThemeManager @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private val Context.dataStore: DataStore<Preferences> by preferencesDataStore(name = "theme_settings")

    private val IS_DARK_THEME_KEY = booleanPreferencesKey("is_dark_theme")
    private val FOLLOW_SYSTEM_KEY = booleanPreferencesKey("follow_system_theme")
    private val SHOW_NOTIFICATION_CONTENT_KEY = booleanPreferencesKey("show_notification_content")
    private val NOTIFICATION_SOUND_URI_KEY = stringPreferencesKey("notification_sound_uri")
    private val USE_DOODLE_BACKGROUND_KEY = booleanPreferencesKey("use_doodle_background")
    private val FULLSCREEN_MODE_KEY = booleanPreferencesKey("fullscreen_mode")

    /**
     * Sistem temasını takip etme durumu flow'u.
     */
    val followSystemTheme: Flow<Boolean> = context.dataStore.data.map { preferences ->
        preferences[FOLLOW_SYSTEM_KEY] ?: true // Varsayılan olarak sistem temasını takip et
    }

    /**
     * Manuel koyu tema tercihi flow'u.
     */
    val isDarkTheme: Flow<Boolean> = context.dataStore.data.map { preferences ->
        preferences[IS_DARK_THEME_KEY] ?: false
    }

    /**
     * Bildirimde mesaj icerigini gosterme tercihi.
     * true = gonderici adi ve mesaj icerigi gosterilir.
     * false = sadece "Yeni mesaj" gosterilir (gizlilik modu).
     */
    val showNotificationContent: Flow<Boolean> = context.dataStore.data.map { preferences ->
        preferences[SHOW_NOTIFICATION_CONTENT_KEY] ?: true
    }

    /**
     * Bildirim sesi URI'si. Bos string = varsayilan ses.
     */
    val notificationSoundUri: Flow<String> = context.dataStore.data.map { preferences ->
        preferences[NOTIFICATION_SOUND_URI_KEY] ?: ""
    }

    /**
     * Doodle arka plan tercihi.
     * true = doodle desenli arka plan, false = duz renk arka plan.
     */
    val useDoodleBackground: Flow<Boolean> = context.dataStore.data.map { preferences ->
        preferences[USE_DOODLE_BACKGROUND_KEY] ?: true
    }

    /**
     * Tam ekran modu tercihi.
     * true = sistem navigasyon cubugu gizlenir.
     */
    val fullscreenMode: Flow<Boolean> = context.dataStore.data.map { preferences ->
        preferences[FULLSCREEN_MODE_KEY] ?: false
    }

    /**
     * Sistem tema takibini aç/kapat.
     */
    suspend fun setFollowSystemTheme(follow: Boolean) {
        context.dataStore.edit { preferences ->
            preferences[FOLLOW_SYSTEM_KEY] = follow
        }
    }

    /**
     * Manuel tema tercihini ayarla.
     */
    suspend fun setDarkTheme(isDark: Boolean) {
        context.dataStore.edit { preferences ->
            preferences[IS_DARK_THEME_KEY] = isDark
        }
    }

    /**
     * Bildirimde mesaj icerigini gosterme tercihini ayarla.
     */
    suspend fun setShowNotificationContent(show: Boolean) {
        context.dataStore.edit { preferences ->
            preferences[SHOW_NOTIFICATION_CONTENT_KEY] = show
        }
    }

    /**
     * Bildirim sesi URI'sini ayarla.
     */
    suspend fun setNotificationSoundUri(uri: String) {
        context.dataStore.edit { preferences ->
            preferences[NOTIFICATION_SOUND_URI_KEY] = uri
        }
    }

    /**
     * Doodle arka plan tercihini ayarla.
     */
    suspend fun setUseDoodleBackground(use: Boolean) {
        context.dataStore.edit { preferences ->
            preferences[USE_DOODLE_BACKGROUND_KEY] = use
        }
    }

    /**
     * Tam ekran modu tercihini ayarla.
     */
    suspend fun setFullscreenMode(enabled: Boolean) {
        context.dataStore.edit { preferences ->
            preferences[FULLSCREEN_MODE_KEY] = enabled
        }
    }
}

/**
 * Theme Manager'ı kullanarak uygun tema durumunu döndürür.
 */
@Composable
fun ThemeManager.shouldUseDarkTheme(): Boolean {
    val followSystem by followSystemTheme.collectAsState(initial = true)
    val manualDarkTheme by isDarkTheme.collectAsState(initial = false)
    val systemDarkTheme = isSystemInDarkTheme()

    return if (followSystem) systemDarkTheme else manualDarkTheme
}