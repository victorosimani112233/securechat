package com.securechat.app.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.securechat.app.data.AutoDownloadPolicy
import com.securechat.app.data.AutoDownloadPolicyStore
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * Otomatik indirme ayarlari ekrani ViewModel'i.
 *
 * Policy DataStore'dan reaktif okunur — switch toggle anlik store'a yazilir.
 */
@HiltViewModel
class AutoDownloadViewModel @Inject constructor(
    private val store: AutoDownloadPolicyStore
) : ViewModel() {

    val policy: StateFlow<AutoDownloadPolicy> = store.policy
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), AutoDownloadPolicy.DEFAULT)

    fun togglePhotos(onWifi: Boolean, value: Boolean) {
        viewModelScope.launch {
            if (onWifi) store.setPhotosOnWifi(value) else store.setPhotosOnCellular(value)
        }
    }

    fun toggleVideos(onWifi: Boolean, value: Boolean) {
        viewModelScope.launch {
            if (onWifi) store.setVideosOnWifi(value) else store.setVideosOnCellular(value)
        }
    }

    fun toggleDocuments(onWifi: Boolean, value: Boolean) {
        viewModelScope.launch {
            if (onWifi) store.setDocumentsOnWifi(value) else store.setDocumentsOnCellular(value)
        }
    }
}
