package com.securechat.media

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import com.securechat.network.SignalMessage
import com.securechat.network.SignalingClient
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.File
import java.util.Base64
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Dosya transferini yoneten sinif.
 *
 * Kucuk dosyalar (<5MB) Base64 olarak encode edilip
 * WebSocket signaling kanali uzerinden gonderilir.
 *
 * Desteklenen dosya tipleri: resim, video, belge (pdf, word, zip, txt vb.)
 *
 * GUVENLIK NOTU: Dosya icerigi bellek uzerinde Base64'e cevrilir.
 * Buyuk dosyalar icin bellek tuketimi yuksek olabilir.
 * MAX_FILE_SIZE limiti bu riski sinirlar.
 */
@Singleton
class FileTransferManager @Inject constructor(
    @ApplicationContext private val context: Context,
    private val signalingClient: SignalingClient
) {
    companion object {
        /** WebSocket uzerinden gonderilebilecek maksimum dosya boyutu (5MB). */
        const val MAX_FILE_SIZE = 5 * 1024 * 1024L
    }

    /**
     * Belirtilen URI'daki dosyayi karsi tarafa gonderir.
     *
     * Dosya ContentResolver uzerinden okunur, Base64'e encode edilir
     * ve FileTransfer sinyali olarak signaling kanalina gonderilir.
     *
     * @param localUserId Gonderen kullanicinin ID'si
     * @param recipientId Alici kullanicinin ID'si
     * @param uri Gonderilecek dosyanin content URI'si
     * @param isGroup Grup mesaji mi
     * @param groupMembers Grup uyelerinin ID listesi (grup mesaji ise)
     * @return Gonderim basarili ise true, dosya cok buyuk veya okuma hatasi ise false
     */
    suspend fun sendFile(
        localUserId: String,
        recipientId: String,
        uri: Uri,
        isGroup: Boolean = false,
        groupMembers: List<String> = emptyList()
    ): FileTransferResult {
        val contentResolver = context.contentResolver
        val mimeType = contentResolver.getType(uri) ?: "application/octet-stream"
        val fileName = getFileName(uri) ?: "dosya"

        val inputStream = contentResolver.openInputStream(uri)
            ?: return FileTransferResult.Error("Dosya okunamadi")
        val bytes = inputStream.use { it.readBytes() }

        if (bytes.size > MAX_FILE_SIZE) {
            return FileTransferResult.Error("Dosya boyutu cok buyuk (maksimum 5MB)")
        }

        val encoded = Base64.getEncoder().encodeToString(bytes)

        val signal = SignalMessage.FileTransfer(
            senderId = localUserId,
            recipientId = recipientId,
            timestamp = System.currentTimeMillis(),
            fileName = fileName,
            mimeType = mimeType,
            fileSize = bytes.size.toLong(),
            data = encoded
        )

        val sent = if (isGroup && groupMembers.isNotEmpty()) {
            var allSent = true
            for (member in groupMembers) {
                if (member != localUserId) {
                    if (!signalingClient.sendSignal(signal.copy(recipientId = member))) {
                        allSent = false
                    }
                }
            }
            allSent
        } else {
            signalingClient.sendSignal(signal)
        }

        return if (sent) {
            FileTransferResult.Success(fileName, mimeType, bytes.size.toLong())
        } else {
            FileTransferResult.Error("Dosya gonderilemedi")
        }
    }

    /**
     * Alinan dosyayi yerel depolamaya kaydeder.
     *
     * Dosya Base64'ten decode edilir ve uygulamanin dahili deposuna yazilir.
     * Dosya adi carpismalarini onlemek icin zaman damgasi eklenir.
     *
     * @param fileName Orijinal dosya adi
     * @param data Base64 encoded dosya icerigi
     * @return Kaydedilen dosyanin URI'si, hata durumunda null
     */
    fun saveReceivedFile(fileName: String, data: String): Uri? {
        return try {
            val decoded = Base64.getDecoder().decode(data)
            val dir = File(context.filesDir, "received_files")
            dir.mkdirs()
            // Dosya adi carpismalarini onlemek icin zaman damgasi ekle
            val safeFileName = sanitizeFileName(fileName)
            val file = File(dir, "${System.currentTimeMillis()}_$safeFileName")
            file.writeBytes(decoded)
            Uri.fromFile(file)
        } catch (e: Exception) {
            android.util.Log.e("FileTransferManager", "Dosya kaydedilemedi: ${e.message}")
            null
        }
    }

    /**
     * Giden dosyayı sent_files dizinine kopyalar.
     * Bu sayede giden dosyalar da local path ile erişilebilir hale gelir.
     *
     * @param uri Gönderilecek dosyanın content URI'si
     * @param fileName Dosya adı
     * @return Kopyalanan dosyanın local path'i, hata durumunda null
     */
    fun copySentFile(uri: Uri, fileName: String): String? {
        return try {
            val contentResolver = context.contentResolver
            val inputStream = contentResolver.openInputStream(uri) ?: return null

            val dir = File(context.filesDir, "sent_files")
            dir.mkdirs()

            val safeFileName = sanitizeFileName(fileName)
            val file = File(dir, "${System.currentTimeMillis()}_$safeFileName")

            inputStream.use { input ->
                file.outputStream().use { output ->
                    input.copyTo(output)
                }
            }

            file.absolutePath
        } catch (e: Exception) {
            android.util.Log.e("FileTransferManager", "Giden dosya kopyalanamadı: ${e.message}")
            null
        }
    }

    /**
     * URI'dan dosya adini cozumler.
     * ContentResolver uzerinden DISPLAY_NAME kolonunu okur.
     * Bulunamazsa URI'nin son segmentini kullanir.
     */
    fun getFileName(uri: Uri): String? {
        val cursor = context.contentResolver.query(uri, null, null, null, null)
        cursor?.use {
            if (it.moveToFirst()) {
                val nameIndex = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (nameIndex >= 0) return it.getString(nameIndex)
            }
        }
        return uri.lastPathSegment
    }

    /**
     * URI'dan MIME tipini cozumler.
     * ContentResolver uzerinden MIME tipi alinir.
     */
    fun getMimeType(uri: Uri): String {
        return context.contentResolver.getType(uri) ?: "application/octet-stream"
    }

    /**
     * URI'dan dosya boyutunu cozumler.
     */
    fun getFileSize(uri: Uri): Long? {
        val cursor = context.contentResolver.query(uri, null, null, null, null)
        cursor?.use {
            if (it.moveToFirst()) {
                val sizeIndex = it.getColumnIndex(OpenableColumns.SIZE)
                if (sizeIndex >= 0) return it.getLong(sizeIndex)
            }
        }
        return null
    }

    /**
     * Dosya adini guvenli hale getirir.
     * Ozel karakterleri ve path traversal girisimlerini temizler.
     */
    private fun sanitizeFileName(name: String): String {
        // Oncelikle path ayiricilari ve path traversal girisimlerini temizle
        val baseName = name.substringAfterLast("/").substringAfterLast("\\")
        return baseName.replace(Regex("[^a-zA-Z0-9._-]"), "_")
            .replace("..", "_") // Path traversal onleme
            .take(100) // Dosya adi uzunlugunu sinirla
    }
}

/**
 * Dosya transfer sonuc sinifi.
 */
sealed class FileTransferResult {
    data class Success(
        val fileName: String,
        val mimeType: String,
        val fileSize: Long
    ) : FileTransferResult()

    data class Error(val message: String) : FileTransferResult()
}
