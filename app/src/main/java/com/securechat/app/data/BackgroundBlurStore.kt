package com.securechat.app.data

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.preferencesDataStore
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Goruntulu arama arka plan bulanik tercihini DataStore'da saklar.
 *
 * Su an: UI toggle anlik state, gercek frame processing PeerConnectionManager'a
 * sonraki sprintte enjekte edilecek (ML Kit SelfieSegmentation gerekli).
 *
 * Tercih nedeni: kullanici sectiyse her cagrida otomatik aktif olur — daha az
 * tikla tutarli deneyim. Performans riski olan eski cihazlarda kullanici manuel
 * kapatabilir.
 */
@Singleton
class BackgroundBlurStore @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private val store: DataStore<Preferences> = context.bgBlurDataStore

    private object Keys {
        val ENABLED = booleanPreferencesKey("enabled")
    }

    val enabled: Flow<Boolean> = store.data.map { it[Keys.ENABLED] ?: false }

    suspend fun setEnabled(value: Boolean) {
        store.edit { it[Keys.ENABLED] = value }
    }
}

private val Context.bgBlurDataStore: DataStore<Preferences> by preferencesDataStore(
    name = "background_blur_pref"
)
