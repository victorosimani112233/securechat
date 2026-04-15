package com.securechat.app.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.securechat.app.data.IncomingMessageHandler
import com.securechat.app.data.UserSession
import com.securechat.app.ui.components.ThemeManager
import com.securechat.storage.DataCleanupManager
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * Ayarlar ekrani ViewModel'i.
 * Profil, tema ve veri temizleme islemlerini yonetir.
 */
@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val dataCleanupManager: DataCleanupManager,
    val userSession: UserSession,
    private val themeManager: ThemeManager
) : ViewModel() {

    private val _profilePhotoUri = MutableStateFlow(userSession.profilePhotoUri)
    val profilePhotoUri: StateFlow<String?> = _profilePhotoUri.asStateFlow()

    val followSystemTheme: StateFlow<Boolean> = themeManager.followSystemTheme
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), true)

    val isDarkTheme: StateFlow<Boolean> = themeManager.isDarkTheme
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), true)

    val showNotificationContent: StateFlow<Boolean> = themeManager.showNotificationContent
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), true)

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

    fun nukeAllData() {
        viewModelScope.launch {
            dataCleanupManager.nukeAllData()
        }
    }
}
