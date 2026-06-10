package com.securechat.storage.domain

import com.securechat.storage.model.MessageContentType
import com.securechat.storage.model.MessageStatus

/**
 * Yerel mesaj domain modeli. Entity'den bagimsiz, is katmaninda kullanilir.
 *
 * Dosya mesajlari icin content alani su formatta saklanir:
 * "dosyaAdi|mimeType|dosyaBoyutu|yerelDosyaYolu"
 * Ornegin: "foto.jpg|image/jpeg|123456|/data/.../foto.jpg"
 *
 * Bu ayristirmayi kolaylastirmak icin yardimci ozellikler mevcuttur.
 */
data class LocalMessage(
    val id: String,
    val conversationId: String,
    val senderId: String,
    val peerId: String,
    val content: String,
    val contentType: MessageContentType,
    val timestamp: Long,
    val status: MessageStatus,
    val replyToId: String? = null,
    val isOutgoing: Boolean,
    val isStarred: Boolean = false,
    val expiresAt: Long? = null,
    val editedAt: Long? = null,
    val editHistory: String? = null, // Onceki iceriklerin JSON dizisi
    val reactions: String? = null, // Emoji reaksiyonlari JSON: {"👍":["userId1"],"❤️":["userId2"]}
    val caption: String? = null, // Medya altyazisi — resim/video ile ayni baloncukta
    val isViewOnce: Boolean = false, // Tek gosterimlik medya
    val isViewed: Boolean = false, // Tek gosterimlik medya goruntulendi mi
    val isPinned: Boolean = false, // Mesaj sabitlenmis mi (chat-icinde pin)
    val pinnedAt: Long? = null // Pin zaman damgasi (ms)
) {
    /** Bu mesaj duzenlenmis mi. */
    val isEdited: Boolean
        get() = editedAt != null


    /** Dosya mesaji ise dosya adini dondurur. */
    val fileName: String?
        get() = if (isFileMessage) content.split("|").getOrNull(0) else null

    /** Dosya mesaji ise MIME tipini dondurur. */
    val fileMimeType: String?
        get() = if (isFileMessage) content.split("|").getOrNull(1) else null

    /** Dosya mesaji ise dosya boyutunu (byte) dondurur. */
    val fileSize: Long?
        get() = if (isFileMessage) content.split("|").getOrNull(2)?.toLongOrNull() else null

    /** Dosya mesaji ise yerel dosya yolunu dondurur. */
    val filePath: String?
        get() = if (isFileMessage) content.split("|").getOrNull(3) else null

    /** Bu mesaj silinmis mi. */
    val isDeleted: Boolean
        get() = contentType == MessageContentType.DELETED

    /** Bu mesaj bir dosya mesaji mi (IMAGE veya FILE). */
    val isFileMessage: Boolean
        get() = contentType == MessageContentType.IMAGE || contentType == MessageContentType.FILE

    /** Bu mesaj bir anket mesaji mi. */
    val isPollMessage: Boolean
        get() = contentType == MessageContentType.POLL

    /** Bu mesaj bir sistem mesaji mi (grup olaylari, arama bilgileri vb.). */
    val isSystemMessage: Boolean
        get() = contentType == MessageContentType.SYSTEM

    /** Dosya mesaji ise resim mi kontrol eder. */
    val isImageFile: Boolean
        get() = contentType == MessageContentType.IMAGE ||
            (isFileMessage && (fileMimeType?.startsWith("image/") == true))

    /**
     * Mesajin onizleme metni — sohbet listesi, reply preview, forward icin.
     * Dosya/anket gibi ozel mesajlarda ham JSON/pipe-string yerine okunabilir
     * etiket dondurur. Caption varsa onu tercih eder (resim caption'lari WhatsApp
     * gibi tek baloncuk gibi davranir).
     */
    val previewText: String
        get() {
            // Dosya tipi caption oncelikli — WhatsApp tarzi kisa ozet
            val cap = caption?.takeIf { it.isNotBlank() }
            return when {
                isDeleted -> "Bu mesaj silindi"
                isViewOnce && contentType == MessageContentType.IMAGE -> "📷 Tek gösterimlik fotoğraf"
                isViewOnce && contentType == MessageContentType.FILE && fileMimeType?.startsWith("video/") == true -> "🎥 Tek gösterimlik video"
                // Tek gosterimlik METIN — gercek icerik sohbet listesinde gozukmemeli
                // (mesajin amaci: gosterim sonrasi geri donulemez gizlilik). Bu case'i
                // unutursak fallback `else -> content` mesajin tam metnini sohbet
                // onizlemesine sizdiriyordu; ayrica tuketildikten sonra content="" oldugu
                // icin de bos preview gozukurdu.
                isViewOnce && contentType == MessageContentType.TEXT -> "🔒 Tek gösterimlik mesaj"
                // Diger view-once content type'lari icin guvenli fallback
                isViewOnce -> "🔒 Tek gösterimlik içerik"
                contentType == MessageContentType.IMAGE -> cap?.let { "📷 $it" } ?: "📷 Fotoğraf"
                contentType == MessageContentType.FILE -> {
                    val mt = fileMimeType ?: ""
                    val label = when {
                        mt.startsWith("video/") -> "🎥 Video"
                        mt.startsWith("audio/") -> "🎵 Ses"
                        else -> "📎 ${fileName ?: "Dosya"}"
                    }
                    cap?.let { "$label · $it" } ?: label
                }
                contentType == MessageContentType.VOICE_NOTE -> "🎤 Sesli mesaj"
                contentType == MessageContentType.POLL -> {
                    val q = try {
                        org.json.JSONObject(content).optString("question", "")
                    } catch (_: Exception) { "" }
                    if (q.isNotBlank()) "📊 Anket: $q" else "📊 Anket"
                }
                contentType == MessageContentType.SYSTEM -> {
                    val parts = content.split("|")
                    if (parts.size >= 6 && parts[0] == "CALL") "📞 ${parts[5]}" else content
                }
                else -> content
            }
        }

    companion object {
        /**
         * Dosya mesaji icin content stringi olusturur.
         *
         * @param fileName Dosya adi
         * @param mimeType MIME tipi
         * @param fileSize Dosya boyutu (byte)
         * @param filePath Yerel dosya yolu (opsiyonel)
         * @return Pipe ile ayrilmis content stringi
         */
        fun buildFileContent(
            fileName: String,
            mimeType: String,
            fileSize: Long,
            filePath: String = ""
        ): String = "$fileName|$mimeType|$fileSize|$filePath"
    }
}
