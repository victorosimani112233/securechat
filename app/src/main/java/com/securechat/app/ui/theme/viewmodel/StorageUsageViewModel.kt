package com.securechat.app.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.securechat.app.data.ChatStorageAnalyzer
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * Sohbet basina depolama kullanimi ekrani ViewModel'i.
 *
 * "Yenile" cagrildiginda yeniden analiz yapar — Flow tabanli reactive deil cunku
 * dosya boyutu hesabi I/O bound; kullanici acmadan otomatik tetiklemek gereksiz.
 */
@HiltViewModel
class StorageUsageViewModel @Inject constructor(
    private val analyzer: ChatStorageAnalyzer
) : ViewModel() {

    private val _items = MutableStateFlow<List<ChatStorageAnalyzer.ChatStorageBreakdown>>(emptyList())
    val items: StateFlow<List<ChatStorageAnalyzer.ChatStorageBreakdown>> = _items.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _cleaningId = MutableStateFlow<String?>(null)
    val cleaningId: StateFlow<String?> = _cleaningId.asStateFlow()

    init {
        refresh()
    }

    fun refresh() {
        viewModelScope.launch(Dispatchers.IO) {
            _isLoading.value = true
            try {
                _items.value = analyzer.analyzeAll()
            } finally {
                _isLoading.value = false
            }
        }
    }

    /**
     * Belirli konusmanin dosyalarini siler — mesaj metinleri kalir.
     * Tamamlandiginda liste yeniden analiz edilir.
     */
    fun cleanFiles(conversationId: String) {
        viewModelScope.launch(Dispatchers.IO) {
            _cleaningId.value = conversationId
            try {
                analyzer.cleanFilesForConversation(conversationId)
                _items.value = analyzer.analyzeAll()
            } finally {
                _cleaningId.value = null
            }
        }
    }
}
