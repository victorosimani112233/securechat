package com.securechat.app.data

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

/**
 * AutoDownloadPolicy'i DataStore (preferences) uzerinde saklar.
 *
 * Tek source-of-truth — Settings ekrani buradan okur/yazar, IncomingMessageHandler
 * dosya gelisinde buradan policy alip Decider'a verir.
 */
@Singleton
class AutoDownloadPolicyStore @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private val store: DataStore<Preferences> = context.autoDownloadDataStore

    private object Keys {
        val PHOTOS_WIFI = booleanPreferencesKey("photos_wifi")
        val PHOTOS_CELL = booleanPreferencesKey("photos_cellular")
        val VIDEOS_WIFI = booleanPreferencesKey("videos_wifi")
        val VIDEOS_CELL = booleanPreferencesKey("videos_cellular")
        val DOCS_WIFI = booleanPreferencesKey("docs_wifi")
        val DOCS_CELL = booleanPreferencesKey("docs_cellular")
        val MAX_BYTES = longPreferencesKey("max_bytes")
    }

    val policy: Flow<AutoDownloadPolicy> = store.data.map { prefs ->
        AutoDownloadPolicy(
            photosOnWifi = prefs[Keys.PHOTOS_WIFI] ?: AutoDownloadPolicy.DEFAULT.photosOnWifi,
            photosOnCellular = prefs[Keys.PHOTOS_CELL] ?: AutoDownloadPolicy.DEFAULT.photosOnCellular,
            videosOnWifi = prefs[Keys.VIDEOS_WIFI] ?: AutoDownloadPolicy.DEFAULT.videosOnWifi,
            videosOnCellular = prefs[Keys.VIDEOS_CELL] ?: AutoDownloadPolicy.DEFAULT.videosOnCellular,
            documentsOnWifi = prefs[Keys.DOCS_WIFI] ?: AutoDownloadPolicy.DEFAULT.documentsOnWifi,
            documentsOnCellular = prefs[Keys.DOCS_CELL] ?: AutoDownloadPolicy.DEFAULT.documentsOnCellular,
            maxAutoDownloadBytes = prefs[Keys.MAX_BYTES] ?: AutoDownloadPolicy.DEFAULT.maxAutoDownloadBytes
        )
    }

    suspend fun setPhotosOnWifi(value: Boolean) = store.edit { it[Keys.PHOTOS_WIFI] = value }
    suspend fun setPhotosOnCellular(value: Boolean) = store.edit { it[Keys.PHOTOS_CELL] = value }
    suspend fun setVideosOnWifi(value: Boolean) = store.edit { it[Keys.VIDEOS_WIFI] = value }
    suspend fun setVideosOnCellular(value: Boolean) = store.edit { it[Keys.VIDEOS_CELL] = value }
    suspend fun setDocumentsOnWifi(value: Boolean) = store.edit { it[Keys.DOCS_WIFI] = value }
    suspend fun setDocumentsOnCellular(value: Boolean) = store.edit { it[Keys.DOCS_CELL] = value }
    suspend fun setMaxAutoDownloadBytes(value: Long) = store.edit { it[Keys.MAX_BYTES] = value }
}

private val Context.autoDownloadDataStore: DataStore<Preferences> by preferencesDataStore(
    name = "auto_download_policy"
)
