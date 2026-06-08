package com.securechat.app.ui.viewmodel.chat

import com.securechat.app.domain.usecase.RecordExportEventUseCase
import com.securechat.storage.repository.MessageRepository
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow

/**
 * Faz 9: Sohbet disa aktarma + admin-encrypted log entegrasyonu.
 *
 * exportConversation():
 *   1. Tum mesajlari TXT formatinda derler (sender, time, content/placeholder)
 *   2. exportText SharedFlow uzerinden UI'a yayar (kaydet/paylaş icin)
 *   3. Grup + export izni aciksa RecordExportEventUseCase ile admin'lere
 *      sifrelenmis log gonderir (zero-knowledge audit)
 *
 * Caller (ChatViewModel) groupChat + exportEnabled bayraklarini saglar.
 */
class ChatExportManager(
    private val conversationId: String,
    private val messageRepository: MessageRepository,
    private val recordExportEventUseCase: RecordExportEventUseCase
) {
    private val _exportText = MutableSharedFlow<String>()
    val exportText: SharedFlow<String> = _exportText.asSharedFlow()

    /**
     * Mesajlari export'a hazirlayip metni emit eder + admin log gonderir.
     *
     * @param peerName Sohbet adi (1:1'de karsi tarafin adi, grup'ta grup adi)
     * @param memberNames Grup uye isimleri (UUID -> isim) — 1:1'de bos
     * @param isGroupChat Grup sohbeti mi
     * @param exportEnabled Grupta admin export iznini acmis mi (admin log icin)
     */
    suspend fun exportConversation(
        peerName: String,
        memberNames: Map<String, String>,
        isGroupChat: Boolean,
        exportEnabled: Boolean
    ) {
        val messages = messageRepository.getAllMessagesForConversation(conversationId)
        val dateFormat = java.text.SimpleDateFormat("dd.MM.yyyy HH:mm", java.util.Locale("tr"))

        val sb = StringBuilder()
        sb.appendLine("elçim — Sohbet Dışa Aktarımı")
        sb.appendLine("Sohbet: $peerName")
        sb.appendLine("Tarih: ${dateFormat.format(java.util.Date())}")
        sb.appendLine("Mesaj sayısı: ${messages.size}")
        sb.appendLine("─".repeat(40))
        sb.appendLine()

        messages.forEach { msg ->
            val time = dateFormat.format(java.util.Date(msg.timestamp))
            val sender = when {
                msg.isOutgoing -> "Ben"
                msg.senderId.isNotBlank() -> memberNames[msg.senderId] ?: msg.senderId
                else -> peerName
            }
            val content = when {
                msg.isSystemMessage -> "[${msg.content}]"
                msg.isDeleted -> "[Silinen mesaj]"
                msg.isFileMessage -> "[Dosya: ${msg.fileName ?: "dosya"}]"
                msg.contentType == com.securechat.storage.model.MessageContentType.VOICE_NOTE -> "[Sesli mesaj]"
                msg.contentType == com.securechat.storage.model.MessageContentType.POLL -> "[Anket]"
                else -> msg.content
            }
            sb.appendLine("[$time] $sender: $content")
        }

        _exportText.emit(sb.toString())

        // Grup + admin export izni aciksa E2EE log
        if (isGroupChat && exportEnabled) {
            val firstTs = messages.minByOrNull { it.timestamp }?.timestamp
            val lastTs = messages.maxByOrNull { it.timestamp }?.timestamp
            runCatching {
                recordExportEventUseCase(
                    groupId = conversationId,
                    eventType = "EXPORT",
                    messageCount = messages.size,
                    firstMsgTs = firstTs,
                    lastMsgTs = lastTs
                )
            }.onFailure { e ->
                android.util.Log.w("ChatExportManager", "Export log kaydi basarisiz", e)
            }
        }
    }
}
