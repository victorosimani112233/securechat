package com.securechat.app.ui.viewmodel

import android.content.Context
import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.securechat.app.data.FcmTokenManager
import com.securechat.app.data.IncomingMessageHandler
import com.securechat.app.data.UserSession
import com.securechat.app.ui.components.ThemeManager
import com.securechat.network.SignalingClient
import com.securechat.storage.DataCleanupManager
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.io.File
import javax.inject.Inject

/**
 * Ayarlar ekrani ViewModel'i.
 * Profil, tema ve veri temizleme islemlerini yonetir.
 */
@HiltViewModel
class SettingsViewModel @Inject constructor(
    @ApplicationContext private val context: Context,
    private val dataCleanupManager: DataCleanupManager,
    val userSession: UserSession,
    private val themeManager: ThemeManager,
    private val fcmTokenManager: FcmTokenManager,
    private val signalingClient: SignalingClient
) : ViewModel() {

    private val _profilePhotoUri = MutableStateFlow(userSession.profilePhotoUri)
    val profilePhotoUri: StateFlow<String?> = _profilePhotoUri.asStateFlow()

    val followSystemTheme: StateFlow<Boolean> = themeManager.followSystemTheme
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), true)

    val isDarkTheme: StateFlow<Boolean> = themeManager.isDarkTheme
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), true)

    val showNotificationContent: StateFlow<Boolean> = themeManager.showNotificationContent
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), true)

    val notificationSoundUri: StateFlow<String> = themeManager.notificationSoundUri
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), "")

    val useDoodleBackground: StateFlow<Boolean> = themeManager.useDoodleBackground
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), true)

    val fullscreenMode: StateFlow<Boolean> = themeManager.fullscreenMode
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), false)

    val scheduledMessagesEnabled: StateFlow<Boolean> = themeManager.scheduledMessagesEnabled
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), true)

    private val _shareLastSeen = MutableStateFlow(userSession.shareLastSeen)
    val shareLastSeen: StateFlow<Boolean> = _shareLastSeen.asStateFlow()

    /** Depolama bilgisi — veritabani, onbellek ve dosya boyutlari. */
    data class StorageInfo(val dbSize: Long, val cacheSize: Long, val filesSize: Long) {
        val totalSize: Long get() = dbSize + cacheSize + filesSize
    }

    private val _storageInfo = MutableStateFlow<StorageInfo?>(null)
    val storageInfo: StateFlow<StorageInfo?> = _storageInfo.asStateFlow()

    /** Depolama kullanimini hesaplar (IO thread'de). */
    fun calculateStorageUsage() {
        viewModelScope.launch(Dispatchers.IO) {
            val dbFile = context.getDatabasePath("securechat.db")
            val dbSize = if (dbFile.exists()) dbFile.length() else 0L
            val cacheSize = calculateDirSize(context.cacheDir)
            val receivedDir = File(context.filesDir, "received_files")
            val sentDir = File(context.filesDir, "sent_files")
            val filesSize = calculateDirSize(receivedDir) + calculateDirSize(sentDir)
            _storageInfo.value = StorageInfo(dbSize, cacheSize, filesSize)
        }
    }

    /** Onbellegi temizler ve depolama bilgisini gunceller. */
    fun clearCache() {
        viewModelScope.launch(Dispatchers.IO) {
            context.cacheDir.deleteRecursively()
            calculateStorageUsage()
        }
    }

    /** Klasor boyutunu hesaplar (recursive). */
    private fun calculateDirSize(dir: File): Long {
        if (!dir.exists()) return 0L
        return dir.walkTopDown().filter { it.isFile }.sumOf { it.length() }
    }

    fun setShareLastSeen(share: Boolean) {
        userSession.shareLastSeen = share
        _shareLastSeen.value = share
        // Tercihi hemen sunucuya bildir — eski deger sunucuda kalmasin
        val uid = userSession.userId ?: return
        signalingClient.sendPresenceUpdate(uid, isOnline = true, hideLastSeen = !share)
    }

    init {
        IncomingMessageHandler.currentChatId = "settings"
    }

    override fun onCleared() {
        super.onCleared()
        IncomingMessageHandler.currentChatId = null
    }

    fun updateProfilePhoto(uri: String?) {
        userSession.profilePhotoUri = uri
        _profilePhotoUri.value = uri
    }

    fun setFollowSystemTheme(follow: Boolean) {
        viewModelScope.launch { themeManager.setFollowSystemTheme(follow) }
    }

    fun setDarkTheme(isDark: Boolean) {
        viewModelScope.launch {
            themeManager.setFollowSystemTheme(false)
            themeManager.setDarkTheme(isDark)
        }
    }

    fun setShowNotificationContent(show: Boolean) {
        viewModelScope.launch { themeManager.setShowNotificationContent(show) }
    }

    fun setNotificationSoundUri(uri: String) {
        viewModelScope.launch { themeManager.setNotificationSoundUri(uri) }
    }

    fun setUseDoodleBackground(use: Boolean) {
        viewModelScope.launch { themeManager.setUseDoodleBackground(use) }
    }

    fun setFullscreenMode(enabled: Boolean) {
        viewModelScope.launch { themeManager.setFullscreenMode(enabled) }
    }

    fun setScheduledMessagesEnabled(enabled: Boolean) {
        viewModelScope.launch { themeManager.setScheduledMessagesEnabled(enabled) }
    }

    /**
     * Tum sohbet verilerini siler.
     * Once sunucu tarafindaki token'lari temizler, sonra yerel verileri siler.
     */
    fun nukeAllData() {
        viewModelScope.launch(Dispatchers.IO) {
            try {
                // Once sunucudaki FCM token'i sil
                fcmTokenManager.unregisterTokenOnServer()
                // WebSocket baglantisini kes
                signalingClient.disconnect()
                // Yerel oturum verisini temizle (sunucu token invalidasyonu dahil)
                userSession.logout()
                // Veritabanindaki tum verileri sil
                dataCleanupManager.nukeAllData()
            } catch (e: Exception) {
                Log.e("SettingsViewModel", "Veri temizleme hatasi", e)
            }
        }
    }

    /**
     * Hesabi kalici olarak siler.
     * FCM token'i kaldirir, sunucuya hesap silme istegi gonderir,
     * yerel verileri temizler ve WebSocket baglantisini keser.
     */
    /** Hesap silme tamamlandiginda true olur — UI bunu gozlemleyip navigate eder. */
    private val _accountDeleted = MutableStateFlow(false)
    val accountDeleted: StateFlow<Boolean> = _accountDeleted.asStateFlow()

    fun deleteAccount() {
        viewModelScope.launch(Dispatchers.IO) {
            try {
                // Sunucudaki FCM token'i sil
                fcmTokenManager.unregisterTokenOnServer()
                // Sunucuya hesap silme istegi gonder
                val userId = userSession.userId ?: return@launch
                userSession.sendDeleteAccountRequest(userId)
                // WebSocket baglantisini kes
                signalingClient.disconnect()
                // Yerel veritabanini temizle
                dataCleanupManager.nukeAllData()
                // Yerel oturum verisini temizle
                userSession.logout()
                // UI'a bildir
                _accountDeleted.value = true
            } catch (e: Exception) {
                Log.e("SettingsViewModel", "Hesap silme hatasi", e)
            }
        }
    }
}
