package com.securechat.app.ui.viewmodel.chat

import com.securechat.storage.domain.LocalMessage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * Faz 9: Sohbet-ici arama state'i + akisi.
 *
 * Mevcut mesaj listesi uzerinde substring arama (file mesajlari haric).
 * Sonuclar ters kronolojik; ileri/geri navigation + highlight.
 *
 * Caller mesajlarin guncel snapshot'ini saglamali (provideMessages lambda).
 */
class ChatSearchManager(
    private val provideMessages: () -> List<LocalMessage>,
    private val scope: CoroutineScope
) {
    private val _query = MutableStateFlow("")
    val query: StateFlow<String> = _query.asStateFlow()

    private val _resultIds = MutableStateFlow<List<String>>(emptyList())
    val resultIds: StateFlow<List<String>> = _resultIds.asStateFlow()

    private val _currentIndex = MutableStateFlow(-1)
    val currentIndex: StateFlow<Int> = _currentIndex.asStateFlow()

    private val _highlightedMessageId = MutableStateFlow<String?>(null)
    val highlightedMessageId: StateFlow<String?> = _highlightedMessageId.asStateFlow()

    /** Caller'a scroll request — UI Lazycolumn'i scrollToItem ile tepki verir. */
    private val _scrollToMessageId = MutableSharedFlow<String>()
    val scrollToMessageId: SharedFlow<String> = _scrollToMessageId.asSharedFlow()

    fun search(query: String) {
        _query.value = query
        if (query.isBlank()) {
            _resultIds.value = emptyList()
            _currentIndex.value = -1
            _highlightedMessageId.value = null
            return
        }
        val lowerQuery = query.lowercase()
        val results = provideMessages()
            .filter { !it.isFileMessage && it.content.lowercase().contains(lowerQuery) }
            .sortedByDescending { it.timestamp }
            .map { it.id }
        _resultIds.value = results
        if (results.isNotEmpty()) {
            _currentIndex.value = 0
            navigateToResult(results[0])
        } else {
            _currentIndex.value = -1
            _highlightedMessageId.value = null
        }
    }

    /** Asagi ok: bir sonraki arama sonucuna gider (daha eski mesaj). */
    fun next() {
        val results = _resultIds.value
        if (results.isEmpty()) return
        val nextIndex = (_currentIndex.value + 1).coerceAtMost(results.size - 1)
        _currentIndex.value = nextIndex
        navigateToResult(results[nextIndex])
    }

    /** Yukari ok: bir onceki arama sonucuna gider (daha yeni mesaj). */
    fun previous() {
        val results = _resultIds.value
        if (results.isEmpty()) return
        val prevIndex = (_currentIndex.value - 1).coerceAtLeast(0)
        _currentIndex.value = prevIndex
        navigateToResult(results[prevIndex])
    }

    /** Disaridan navigation (reply tap, search result tap vb.). */
    fun navigateToMessage(messageId: String) {
        _highlightedMessageId.value = messageId
        scope.launch { _scrollToMessageId.emit(messageId) }
    }

    fun clear() {
        _query.value = ""
        _resultIds.value = emptyList()
        _currentIndex.value = -1
        _highlightedMessageId.value = null
    }

    private fun navigateToResult(messageId: String) {
        _highlightedMessageId.value = messageId
        scope.launch { _scrollToMessageId.emit(messageId) }
    }
}
