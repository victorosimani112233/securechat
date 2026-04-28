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
    val editHistory: String? = null // Onceki iceriklerin JSON dizisi
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

    /** Dosya mesaji ise resim mi kontrol eder. */
    val isImageFile: Boolean
        get() = contentType == MessageContentType.IMAGE ||
            (isFileMessage && (fileMimeType?.startsWith("image/") == true))

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
