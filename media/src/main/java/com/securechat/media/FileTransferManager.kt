package com.securechat.media

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.provider.OpenableColumns
import com.securechat.network.SignalMessage
import com.securechat.network.SignalingClient
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.util.Base64
import java.util.UUID
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
    private val signalingClient: SignalingClient,
    private val senderKeyStore: com.securechat.crypto.SecureChatSenderKeyStore
) {
    companion object {
        /** WebSocket uzerinden gonderilebilecek maksimum dosya boyutu (1GB). */
        const val MAX_FILE_SIZE = 1024 * 1024 * 1024L
        /**
         * Chunk boyutu — her parca 128KB.
         * Base64 sonrasi ~170KB, JSON envelope ile birlikte ~172KB.
         * Server [maxFrameSize=256KB] limiti altinda guvenli marjla kalir.
         * NOT: 512KB chunk Base64 sonrasi 682KB oluyordu ve server frame'i drop
         * ediyordu — dosyalar karsi tarafa hic ulasmiyordu.
         */
        const val CHUNK_SIZE = 128 * 1024
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
        groupMembers: List<String> = emptyList(),
        groupName: String? = null,
        caption: String? = null,
        isViewOnce: Boolean = false,
        originalMessageId: String? = null,
        /** Sureli mesaj icin mutlak expiresAt — alici tarafta ayni anda dolacak (Asama 3). */
        absoluteExpiresAt: Long? = null
    ): FileTransferResult {
        val contentResolver = context.contentResolver
        val originalMimeType = contentResolver.getType(uri) ?: "application/octet-stream"
        val originalFileName = getFileName(uri) ?: "dosya"

        // HEIC/HEIF formatindaki resimleri JPEG'e donustur (Android 10+ native destek)
        val isHeic = originalMimeType.equals("image/heic", ignoreCase = true) ||
                originalMimeType.equals("image/heif", ignoreCase = true)
        val effectiveUri: Uri
        val mimeType: String
        val fileName: String
        if (isHeic) {
            val convertedUri = convertHeicToJpeg(uri)
            if (convertedUri != null) {
                effectiveUri = convertedUri
                mimeType = "image/jpeg"
                fileName = originalFileName.substringBeforeLast(".") + ".jpg"
            } else {
                // Donusum basarisiz olursa orijinal dosya ile devam et
                effectiveUri = uri
                mimeType = originalMimeType
                fileName = originalFileName
            }
        } else {
            effectiveUri = uri
            mimeType = originalMimeType
            fileName = originalFileName
        }

        // Dosya boyutunu URI'dan al (bellege okumadan)
        val totalSize = getFileSize(effectiveUri) ?: 0L
        if (totalSize > MAX_FILE_SIZE) {
            return FileTransferResult.Error("Dosya boyutu cok buyuk (maksimum 1GB)")
        }

        val inputStream = contentResolver.openInputStream(effectiveUri)
            ?: return FileTransferResult.Error("Dosya okunamadi")

        return inputStream.use { stream ->
            sendFileChunked(stream, totalSize, localUserId, recipientId, fileName, mimeType, isGroup, groupMembers, groupName, caption, isViewOnce, originalMessageId, absoluteExpiresAt)
        }
    }

    /**
     * Dosyayi chunk'lar halinde gonderir.
     * Bellekte sadece 1 chunk (512KB) tutulur — 1GB dosya icin bile sabit bellek kullanimi.
     * Her chunk ayri bir FileTransfer sinyali olarak gonderilir.
     * transferId ile alici tarafta parcalar birlestirilir.
     */
    private suspend fun sendFileChunked(
        stream: InputStream,
        totalSize: Long,
        localUserId: String,
        recipientId: String,
        fileName: String,
        mimeType: String,
        isGroup: Boolean,
        groupMembers: List<String>,
        groupName: String?,
        caption: String?,
        isViewOnce: Boolean,
        originalMessageId: String?,
        absoluteExpiresAt: Long?
    ): FileTransferResult {
        val transferId = UUID.randomUUID().toString()
        val totalChunks = ((totalSize + CHUNK_SIZE - 1) / CHUNK_SIZE).toInt().coerceAtLeast(1)
        val buffer = ByteArray(CHUNK_SIZE)
        var chunkIndex = 0
        var totalRead = 0L

        // App idle sonrasi ilk medya gonderiminde socket kapali olabilir — onceden baglanti
        // bekle (max 8sn). Boylece ilk chunk drop edilmez. ensureConnected zaten bagliysa
        // hemen doner; basarisizsa retry per-chunk loop devreye girer.
        runCatching {
            signalingClient.ensureConnected(
                userId = localUserId,
                authToken = "token_$localUserId",
                timeoutMs = 8_000L
            )
        }

        // Grup chunk'lari GroupCipher ile sifrelenir (Sender Keys). 1:1 transfer ve
        // group caption ayni sema ile sifrelenir; flag = "gsk-v1". 1:1 file encrypt
        // hibrit donem boyunca plaintext kalir (sonraki release'te SessionCipher ile).
        val groupCipher = if (isGroup) {
            try {
                val senderKeyName = org.whispersystems.libsignal.groups.SenderKeyName(
                    recipientId,
                    org.whispersystems.libsignal.SignalProtocolAddress(localUserId, 1)
                )
                org.whispersystems.libsignal.groups.GroupCipher(senderKeyStore, senderKeyName)
            } catch (e: Exception) {
                android.util.Log.w("FileTransferManager", "GroupCipher init fail, plaintext fallback: ${e.message}")
                null
            }
        } else null

        while (true) {
            val bytesRead = stream.readNBytes(buffer, CHUNK_SIZE)
            if (bytesRead <= 0) break

            totalRead += bytesRead
            val chunkData = if (bytesRead == buffer.size) buffer else buffer.copyOf(bytesRead)

            // Sifreleme: grup ise chunkData GroupCipher ile encrypt, sonra Base64;
            // 1:1 ise direkt Base64 (legacy plaintext).
            val (encodedData, encryption) = if (groupCipher != null) {
                try {
                    val ciphertext = groupCipher.encrypt(chunkData)
                    Pair(Base64.getEncoder().encodeToString(ciphertext), "gsk-v1")
                } catch (e: Exception) {
                    android.util.Log.w("FileTransferManager", "Grup chunk encrypt fail, plaintext fallback: ${e.message}")
                    Pair(Base64.getEncoder().encodeToString(chunkData), null)
                }
            } else {
                Pair(Base64.getEncoder().encodeToString(chunkData), null)
            }

            // Caption (son chunk) — grup ise ayni GroupCipher ile sifrele, sonra Base64.
            val rawCaption = if (chunkIndex == totalChunks - 1) caption else null
            val finalCaption = if (rawCaption != null && groupCipher != null && encryption == "gsk-v1") {
                try {
                    val capBytes = rawCaption.toByteArray(Charsets.UTF_8)
                    val capCt = groupCipher.encrypt(capBytes)
                    capBytes.fill(0)
                    Base64.getEncoder().encodeToString(capCt)
                } catch (e: Exception) {
                    android.util.Log.w("FileTransferManager", "Caption encrypt fail, plaintext fallback: ${e.message}")
                    rawCaption
                }
            } else rawCaption

            val signal = SignalMessage.FileTransfer(
                senderId = localUserId,
                recipientId = recipientId,
                timestamp = System.currentTimeMillis(),
                fileName = fileName,
                mimeType = mimeType,
                fileSize = totalSize,
                data = encodedData,
                groupId = if (isGroup) recipientId else null,
                groupName = if (isGroup) groupName else null,
                transferId = transferId,
                chunkIndex = chunkIndex,
                totalChunks = totalChunks,
                // Caption ve view-once meta verisi yalnizca son chunk'ta tasinir,
                // alici tarafta tum parcalar birlestirildikten sonra mesaj olusturulurken kullanilir.
                caption = finalCaption,
                isViewOnce = isViewOnce,
                originalMessageId = if (chunkIndex == totalChunks - 1) originalMessageId else null,
                // Sureli mesaj: sadece son chunk'ta tasi (alici tum chunk'lari birlestirince mesaji
                // olusturur, oradan expiresAt kullanilir).
                absoluteExpiresAt = if (chunkIndex == totalChunks - 1) absoluteExpiresAt else null,
                encryption = encryption
            )

            // Chunk gonderim — basarisizsa max 3 retry, her retry oncesi ensureConnected.
            // Onceden tum transfer'i tek hata ile drop ediyordu; gecici disconnect (ag degisimi,
            // ping timeout) durumlarinda media kalici fail oluyordu. Artik 3*2sn=6sn ek pencere
            // var ve socket aciliyorsa devam edebilir.
            var sent = false
            for (attempt in 0..3) {
                if (attempt > 0) {
                    kotlinx.coroutines.delay(2_000L)
                    runCatching {
                        signalingClient.ensureConnected(
                            userId = localUserId,
                            authToken = "token_$localUserId",
                            timeoutMs = 3_000L
                        )
                    }
                }
                sent = if (isGroup && groupMembers.isNotEmpty()) {
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
                if (sent) break
            }

            if (!sent) {
                _transferProgress.value = null
                return FileTransferResult.Error("Dosya gonderilemedi (parca ${chunkIndex + 1}/$totalChunks)")
            }

            // Gonderim ilerlemesini raporla
            _transferProgress.value = TransferProgress(transferId, chunkIndex + 1, totalChunks, totalRead, totalSize)

            chunkIndex++
        }

        // Transfer tamamlandi
        _transferProgress.value = null
        return FileTransferResult.Success(fileName, mimeType, totalRead)
    }

    /**
     * InputStream'den belirtilen miktarda byte okur.
     * Java 11+ readNBytes gibi calisir ama Android uyumlu.
     */
    private fun InputStream.readNBytes(buffer: ByteArray, maxBytes: Int): Int {
        var totalRead = 0
        while (totalRead < maxBytes) {
            val bytesRead = read(buffer, totalRead, maxBytes - totalRead)
            if (bytesRead == -1) break
            totalRead += bytesRead
        }
        return totalRead
    }

    /** Dosya transfer ilerleme bilgisi. */
    data class TransferProgress(
        val transferId: String,
        val chunksSent: Int,
        val totalChunks: Int,
        val bytesSent: Long,
        val totalBytes: Long
    ) {
        val percent: Int get() = if (totalBytes > 0) ((bytesSent * 100) / totalBytes).toInt() else 0
    }

    /** Aktif transfer ilerleme durumu — UI tarafindan gozlemlenir. */
    private val _transferProgress = kotlinx.coroutines.flow.MutableStateFlow<TransferProgress?>(null)
    val transferProgress: kotlinx.coroutines.flow.StateFlow<TransferProgress?> = _transferProgress

    /**
     * Devam eden chunk transferlerini tutan buffer.
     * Key: transferId, Value: alinan chunk'larin listesi (index -> decoded bytes).
     */
    private val chunkBuffers = java.util.concurrent.ConcurrentHashMap<String, ChunkBuffer>()

    /** Bir chunk transferinin durumunu tutar. */
    private data class ChunkBuffer(
        val fileName: String,
        val mimeType: String,
        val fileSize: Long,
        val totalChunks: Int,
        val chunks: java.util.concurrent.ConcurrentHashMap<Int, ByteArray> = java.util.concurrent.ConcurrentHashMap(),
        val createdAt: Long = System.currentTimeMillis()
    ) {
        val isComplete: Boolean get() = chunks.size == totalChunks
    }

    /**
     * Gelen bir dosya chunk'ini isler.
     * Tek parcali dosyalar dogrudan kaydedilir.
     * Coklu chunk transferlerinde tum parcalar gelene kadar buffer'da tutulur,
     * son parca geldiginde dosya birlestirilir ve kaydedilir.
     *
     * @param transferId Transfer benzersiz kimlik (null ise tek parca)
     * @param chunkIndex Bu parcanin sirasi (0-based)
     * @param totalChunks Toplam parca sayisi
     * @param fileName Dosya adi
     * @param mimeType MIME tipi
     * @param fileSize Toplam dosya boyutu
     * @param data Base64 encoded chunk verisi
     * @return Tek parca veya tum parcalar tamam ise kaydedilen dosyanin URI'si; henuz tamamlanmadiysa null
     */
    fun receiveChunk(
        transferId: String?,
        chunkIndex: Int,
        totalChunks: Int,
        fileName: String,
        mimeType: String,
        fileSize: Long,
        data: String
    ): Uri? {
        // Tek parcali transfer — dogrudan kaydet (geriye uyumlu)
        if (totalChunks <= 1 || transferId == null) {
            return saveReceivedFile(fileName, data)
        }

        // Chunk'i decode et
        val decoded = try {
            Base64.getDecoder().decode(data)
        } catch (e: Exception) {
            android.util.Log.e("FileTransferManager", "Chunk decode hatasi: transferId=$transferId, chunk=$chunkIndex")
            return null
        }

        // Buffer'a ekle (yoksa olustur)
        val buffer = chunkBuffers.getOrPut(transferId) {
            ChunkBuffer(fileName, mimeType, fileSize, totalChunks)
        }
        buffer.chunks[chunkIndex] = decoded

        android.util.Log.d("FileTransferManager", "Chunk alindi: $transferId [${ chunkIndex + 1}/$totalChunks] (${buffer.chunks.size} adet)")

        // Tum parcalar geldi mi?
        if (!buffer.isComplete) {
            return null // Henuz tamamlanmadi
        }

        // Tum parcalar geldi — birlestir ve kaydet
        return try {
            val dir = File(context.filesDir, "received_files")
            dir.mkdirs()
            val safeFileName = sanitizeFileName(fileName)
            val file = File(dir, "${System.currentTimeMillis()}_$safeFileName")

            FileOutputStream(file).use { output ->
                for (i in 0 until totalChunks) {
                    val chunk = buffer.chunks[i]
                    if (chunk != null) {
                        output.write(chunk)
                    } else {
                        android.util.Log.e("FileTransferManager", "Eksik chunk: $transferId index=$i")
                        file.delete()
                        chunkBuffers.remove(transferId)
                        return null
                    }
                }
            }

            chunkBuffers.remove(transferId)
            android.util.Log.d("FileTransferManager", "Chunked dosya birlestirildi: $fileName (${file.length()} byte)")
            Uri.fromFile(file)
        } catch (e: Exception) {
            android.util.Log.e("FileTransferManager", "Chunk birlestirme hatasi: ${e.message}")
            chunkBuffers.remove(transferId)
            null
        }
    }

    /**
     * Eski tamamlanmamis transferleri temizler (10 dakikadan eski).
     * Periyodik olarak cagirilmalidir.
     */
    fun cleanupStaleTransfers() {
        val staleThreshold = System.currentTimeMillis() - 10 * 60 * 1000
        val staleIds = chunkBuffers.entries
            .filter { it.value.createdAt < staleThreshold }
            .map { it.key }
        staleIds.forEach { chunkBuffers.remove(it) }
        if (staleIds.isNotEmpty()) {
            android.util.Log.d("FileTransferManager", "${staleIds.size} eski transfer temizlendi")
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
     * Unicode harfler (Turkce karakterler dahil: gusocsIi) korunur.
     */
    internal fun sanitizeFileName(name: String): String {
        // Oncelikle path ayiricilari ve path traversal girisimlerini temizle
        val baseName = name.substringAfterLast("/").substringAfterLast("\\")
        return baseName.replace(Regex("[^a-zA-Z0-9._\\-\\p{L}]"), "_")
            .replace("..", "_") // Path traversal onleme
            .take(100) // Dosya adi uzunlugunu sinirla
    }

    /**
     * HEIC/HEIF formatindaki resmi JPEG'e donusturur.
     * Android 10+ BitmapFactory uzerinden native HEIC decode destegi saglar.
     *
     * @param uri Kaynak HEIC dosyasinin URI'si
     * @return Donusturulen JPEG dosyasinin URI'si, hata durumunda null
     */
    internal fun convertHeicToJpeg(uri: Uri): Uri? {
        return try {
            val inputStream = context.contentResolver.openInputStream(uri) ?: return null
            val bitmap = inputStream.use { BitmapFactory.decodeStream(it) } ?: return null

            // GUVENLIK (M11 fix): cacheDir media scanner ve diger uygulamalar tarafindan
            // gorunebilir (MODE_PRIVATE ama indexer'lar erisebilir). filesDir/no_backup
            // altinda tut — backup'a girmez, scanner gormez, sadece bu uygulama erisir.
            val convertedDir = File(context.noBackupFilesDir, "heic_converted")
            convertedDir.mkdirs()
            val jpegFile = File(convertedDir, "converted_${System.currentTimeMillis()}.jpg")

            FileOutputStream(jpegFile).use { outputStream ->
                bitmap.compress(Bitmap.CompressFormat.JPEG, 90, outputStream)
            }
            bitmap.recycle()

            Uri.fromFile(jpegFile)
        } catch (e: Exception) {
            android.util.Log.e("FileTransferManager", "HEIC donusumu basarisiz: ${e.message}")
            null
        }
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
