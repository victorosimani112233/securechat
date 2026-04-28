package com.securechat.app.backup

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import com.securechat.app.data.UserSession
import com.securechat.storage.dao.ContactDao
import com.securechat.storage.dao.ConversationDao
import com.securechat.storage.dao.MessageDao
import com.securechat.storage.entity.ContactEntity
import com.securechat.storage.entity.ConversationEntity
import com.securechat.storage.entity.MessageEntity
import com.securechat.storage.model.MessageContentType
import com.securechat.storage.model.MessageStatus
import dagger.hilt.android.qualifiers.ApplicationContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.zip.GZIPInputStream
import java.util.zip.GZIPOutputStream
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Profil yedekleme yoneticisi.
 * Tum sohbetleri, mesajlari, kisileri ve profil bilgisini
 * sifrelenmis dosya olarak yedekler ve geri yukler.
 *
 * Dosya formati: GZIP(JSON) -> AES-256-GCM
 * Deneme sayaci: SharedPreferences ile takip, 5 yanlis = dosya silinir.
 */
@Singleton
class BackupManager @Inject constructor(
    @ApplicationContext private val context: Context,
    private val messageDao: MessageDao,
    private val conversationDao: ConversationDao,
    private val contactDao: ContactDao,
    private val userSession: UserSession
) {
    companion object {
        private const val BACKUP_VERSION = 1
        private const val MAX_ATTEMPTS = 5
        private const val PREFS_NAME = "backup_attempts"
        private const val FILE_EXTENSION = ".elbk"
    }

    private val attemptPrefs by lazy {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    // ─── Yedek Olusturma ─────────────────────────────────────────────

    /**
     * Tum verileri sifrelenmis yedek dosyasina yazar.
     * Downloads klasorune kaydeder — dosya yoneticisinden gorunur.
     * @return Olusturulan dosya (dahili kopya, paylasim icin)
     */
    suspend fun createBackup(password: String): File {
        val json = buildBackupJson()
        val compressed = compress(json.toString().toByteArray(Charsets.UTF_8))
        val encrypted = BackupCrypto.encrypt(compressed, password)

        val timestamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
        val fileName = "elcim_backup_$timestamp$FILE_EXTENSION"

        // Downloads klasorune kaydet (MediaStore ile — dosya yoneticisinden gorunur)
        saveToDownloads(fileName, encrypted)

        // Dahili kopya da tut (paylasim ve FileProvider icin)
        val backupDir = File(context.filesDir, "backups").apply { mkdirs() }
        val internalFile = File(backupDir, fileName)
        internalFile.writeBytes(encrypted)

        android.util.Log.d("BackupManager", "Yedek olusturuldu: Downloads/$fileName (${encrypted.size} byte)")
        return internalFile
    }

    /**
     * Dosyayi Downloads klasorune kaydeder.
     * Android 10+ icin MediaStore, oncesi icin dogrudan dosya yazimi kullanir.
     */
    private fun saveToDownloads(fileName: String, data: ByteArray) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                put(MediaStore.Downloads.MIME_TYPE, "application/octet-stream")
                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/Elcim")
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val uri = context.contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            if (uri != null) {
                context.contentResolver.openOutputStream(uri)?.use { it.write(data) }
                values.clear()
                values.put(MediaStore.Downloads.IS_PENDING, 0)
                context.contentResolver.update(uri, values, null, null)
            }
        } else {
            @Suppress("DEPRECATION")
            val downloadsDir = File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                "Elcim"
            ).apply { mkdirs() }
            File(downloadsDir, fileName).writeBytes(data)
        }
    }

    /**
     * Yedek JSON'ini olustururken mesajlari toplu olarak (batch) isler.
     * Tum mesajlari tek seferde belleğe yuklemek yerine BATCH_SIZE'lik parcalar halinde okur.
     * Bu sayede buyuk veri setlerinde OOM hatasinin onune gecilir.
     */
    private suspend fun buildBackupJson(): JSONObject {
        val root = JSONObject()
        root.put("version", BACKUP_VERSION)
        root.put("createdAt", System.currentTimeMillis())

        // Profil
        val profile = JSONObject().apply {
            put("userId", userSession.userId ?: "")
            put("displayName", userSession.displayName ?: "")
            put("phoneNumber", userSession.phoneNumber ?: "")
            put("profilePhotoUri", userSession.profilePhotoUri ?: "")
        }
        root.put("profile", profile)

        // Konusmalar
        val conversations = JSONArray()
        for (conv in conversationDao.getAllImmediate()) {
            conversations.put(conversationToJson(conv))
        }
        root.put("conversations", conversations)

        // Mesajlar — toplu okuma ile bellek tasarrufu
        val batchSize = 1000
        val messages = JSONArray()
        var offset = 0
        while (true) {
            val batch = messageDao.getMessagesBatch(batchSize, offset)
            if (batch.isEmpty()) break
            for (msg in batch) {
                messages.put(messageToJson(msg))
            }
            offset += batch.size
            // Son batch batchSize'dan kucukse tum mesajlar okunmustur
            if (batch.size < batchSize) break
        }
        root.put("messages", messages)

        // Kisiler
        val contacts = JSONArray()
        for (contact in contactDao.getAllOnce()) {
            contacts.put(contactToJson(contact))
        }
        root.put("contacts", contacts)

        return root
    }

    // ─── Yedek Geri Yukleme ──────────────────────────────────────────

    sealed class RestoreResult {
        data object Success : RestoreResult()
        data object WrongPassword : RestoreResult()
        data class AttemptsExhausted(val deleted: Boolean) : RestoreResult()
        data class Error(val message: String) : RestoreResult()
    }

    /**
     * Sifrelenmis yedek dosyasini geri yukler.
     * 5 yanlis sifre denemesinden sonra dosya silinir.
     */
    suspend fun restoreBackup(uri: Uri, password: String): RestoreResult {
        val fileKey = uri.toString()

        // Deneme sayisi kontrolu
        val attempts = getAttemptCount(fileKey)
        if (attempts >= MAX_ATTEMPTS) {
            deleteBackupFile(uri)
            clearAttemptCount(fileKey)
            return RestoreResult.AttemptsExhausted(deleted = true)
        }

        // Dosyayi oku
        val encrypted = try {
            context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
                ?: return RestoreResult.Error("Dosya okunamadi")
        } catch (e: Exception) {
            return RestoreResult.Error("Dosya okunamadi: ${e.message}")
        }

        // Sifre coz
        val compressed = BackupCrypto.decrypt(encrypted, password)
        if (compressed == null) {
            val newAttempts = attempts + 1
            setAttemptCount(fileKey, newAttempts)

            if (newAttempts >= MAX_ATTEMPTS) {
                deleteBackupFile(uri)
                clearAttemptCount(fileKey)
                return RestoreResult.AttemptsExhausted(deleted = true)
            }

            return RestoreResult.WrongPassword
        }

        // Basarili — sayaci sifirla
        clearAttemptCount(fileKey)

        // Decompress ve parse
        return try {
            val jsonStr = decompress(compressed).toString(Charsets.UTF_8)
            val json = JSONObject(jsonStr)
            applyBackup(json)
            RestoreResult.Success
        } catch (e: Exception) {
            android.util.Log.e("BackupManager", "Geri yukleme hatasi", e)
            RestoreResult.Error("Yedek dosyasi bozuk: ${e.message}")
        }
    }

    /**
     * Belirtilen URI icin kalan deneme hakkini dondurur.
     */
    fun getRemainingAttempts(uri: Uri): Int {
        return MAX_ATTEMPTS - getAttemptCount(uri.toString())
    }

    private suspend fun applyBackup(json: JSONObject) {
        val version = json.optInt("version", 1)
        if (version > BACKUP_VERSION) {
            throw IllegalStateException("Desteklenmeyen yedek surumu: $version")
        }

        // Profil geri yukle
        val profile = json.getJSONObject("profile")
        val backupUserId = profile.getString("userId")
        val backupPhone = profile.getString("phoneNumber")

        // Ayni hesap kontrolu: telefon numarasi eslesmeli
        val currentPhone = userSession.phoneNumber
        if (!currentPhone.isNullOrBlank() && currentPhone != backupPhone) {
            throw IllegalStateException("Yedek farkli bir hesaba ait (telefon numarasi eslesmiyor)")
        }

        userSession.userId = backupUserId
        userSession.displayName = profile.getString("displayName")
        userSession.phoneNumber = backupPhone
        val photoUri = profile.optString("profilePhotoUri", "")
        if (photoUri.isNotBlank()) {
            userSession.profilePhotoUri = photoUri
        }

        // Konusmalar
        val conversations = json.getJSONArray("conversations")
        for (i in 0 until conversations.length()) {
            val conv = jsonToConversation(conversations.getJSONObject(i))
            conversationDao.insert(conv)
        }

        // Mesajlar
        val messages = json.getJSONArray("messages")
        for (i in 0 until messages.length()) {
            val msg = jsonToMessage(messages.getJSONObject(i))
            messageDao.insert(msg)
        }

        // Kisiler
        val contacts = json.getJSONArray("contacts")
        for (i in 0 until contacts.length()) {
            val contact = jsonToContact(contacts.getJSONObject(i))
            contactDao.insert(contact)
        }

        android.util.Log.d("BackupManager",
            "Yedek geri yuklendi: ${conversations.length()} konusma, ${messages.length()} mesaj, ${contacts.length()} kisi")
    }

    // ─── Deneme Sayaci ───────────────────────────────────────────────

    private fun getAttemptCount(key: String): Int = attemptPrefs.getInt(key, 0)

    private fun setAttemptCount(key: String, count: Int) {
        attemptPrefs.edit().putInt(key, count).apply()
    }

    private fun clearAttemptCount(key: String) {
        attemptPrefs.edit().remove(key).apply()
    }

    private fun deleteBackupFile(uri: Uri) {
        try {
            // Yerel dosya ise dogrudan sil
            val path = uri.path
            if (path != null) {
                val file = File(path)
                if (file.exists()) file.delete()
            }
            // Content URI ise ContentResolver ile sil
            context.contentResolver.delete(uri, null, null)
            android.util.Log.w("BackupManager", "Yedek dosyasi silindi (5 yanlis deneme)")
        } catch (e: Exception) {
            android.util.Log.e("BackupManager", "Yedek silinemedi: ${e.message}")
        }
    }

    // ─── GZIP Compress/Decompress ────────────────────────────────────

    private fun compress(data: ByteArray): ByteArray {
        val bos = ByteArrayOutputStream()
        GZIPOutputStream(bos).use { it.write(data) }
        return bos.toByteArray()
    }

    private fun decompress(data: ByteArray): ByteArray {
        return GZIPInputStream(data.inputStream()).use { it.readBytes() }
    }

    // ─── JSON Serialization ──────────────────────────────────────────

    private fun conversationToJson(c: ConversationEntity) = JSONObject().apply {
        put("id", c.id)
        put("peerId", c.peerId)
        put("peerName", c.peerName)
        put("peerPhone", c.peerPhone)
        put("lastMessage", c.lastMessage ?: "")
        put("lastMessageTimestamp", c.lastMessageTimestamp ?: 0L)
        put("unreadCount", c.unreadCount)
        put("isMuted", c.isMuted)
        put("isPinned", c.isPinned)
        put("isGroup", c.isGroup)
        put("groupMembers", c.groupMembers ?: "")
        put("contactNote", c.contactNote ?: "")
        put("customNotificationUri", c.customNotificationUri ?: "")
        put("isArchived", c.isArchived)
        put("disappearingDuration", c.disappearingDuration)
        put("groupAdmins", c.groupAdmins ?: "")
        put("isFavorite", c.isFavorite)
    }

    private fun jsonToConversation(j: JSONObject): ConversationEntity {
        fun optNullableString(key: String): String? {
            val v = j.optString(key, "")
            return v.ifBlank { null }
        }
        return ConversationEntity(
            id = j.getString("id"),
            peerId = j.getString("peerId"),
            peerName = j.getString("peerName"),
            peerPhone = j.optString("peerPhone", ""),
            lastMessage = optNullableString("lastMessage"),
            lastMessageTimestamp = j.optLong("lastMessageTimestamp", 0L).takeIf { it > 0 },
            unreadCount = j.optInt("unreadCount", 0),
            isMuted = j.optBoolean("isMuted", false),
            isPinned = j.optBoolean("isPinned", false),
            isGroup = j.optBoolean("isGroup", false),
            groupMembers = optNullableString("groupMembers"),
            contactNote = optNullableString("contactNote"),
            customNotificationUri = optNullableString("customNotificationUri"),
            isArchived = j.optBoolean("isArchived", false),
            disappearingDuration = j.optLong("disappearingDuration", 0L),
            groupAdmins = optNullableString("groupAdmins"),
            isFavorite = j.optBoolean("isFavorite", false)
        )
    }

    private fun messageToJson(m: MessageEntity) = JSONObject().apply {
        put("id", m.id)
        put("conversationId", m.conversationId)
        put("senderId", m.senderId)
        put("content", m.content)
        put("contentType", m.contentType.name)
        put("timestamp", m.timestamp)
        put("status", m.status.name)
        put("replyToId", m.replyToId ?: "")
        put("isOutgoing", m.isOutgoing)
        put("isStarred", m.isStarred)
        put("expiresAt", m.expiresAt ?: 0L)
        put("editedAt", m.editedAt ?: 0L)
    }

    private fun jsonToMessage(j: JSONObject): MessageEntity {
        val replyTo = j.optString("replyToId", "")
        return MessageEntity(
            id = j.getString("id"),
            conversationId = j.getString("conversationId"),
            senderId = j.getString("senderId"),
            content = j.getString("content"),
            contentType = try { MessageContentType.valueOf(j.getString("contentType")) } catch (_: Exception) { MessageContentType.TEXT },
            timestamp = j.getLong("timestamp"),
            status = try { MessageStatus.valueOf(j.getString("status")) } catch (_: Exception) { MessageStatus.SENT },
            replyToId = replyTo.ifBlank { null },
            isOutgoing = j.getBoolean("isOutgoing"),
            isStarred = j.optBoolean("isStarred", false),
            expiresAt = j.optLong("expiresAt", 0L).takeIf { it > 0 },
            editedAt = j.optLong("editedAt", 0L).takeIf { it > 0 }
        )
    }

    private fun contactToJson(c: ContactEntity) = JSONObject().apply {
        put("id", c.id)
        put("phoneNumber", c.phoneNumber)
        put("phoneHash", c.phoneHash)
        put("displayName", c.displayName)
        put("isRegistered", c.isRegistered)
        put("avatarUri", c.avatarUri ?: "")
        put("lastSeen", c.lastSeen ?: 0L)
    }

    private fun jsonToContact(j: JSONObject): ContactEntity {
        val avatar = j.optString("avatarUri", "")
        return ContactEntity(
            id = j.getString("id"),
            phoneNumber = j.getString("phoneNumber"),
            phoneHash = j.getString("phoneHash"),
            displayName = j.getString("displayName"),
            isRegistered = j.optBoolean("isRegistered", false),
            avatarUri = avatar.ifBlank { null },
            lastSeen = j.optLong("lastSeen", 0L).takeIf { it > 0 }
        )
    }

    // ─── Yedek dosyalarini listele ───────────────────────────────────

    /**
     * Yerel yedek dosyalarini dondurur (en yeni once).
     */
    fun getLocalBackups(): List<File> {
        val backupDir = File(context.filesDir, "backups")
        return backupDir.listFiles { f -> f.extension == FILE_EXTENSION.removePrefix(".") }
            ?.sortedByDescending { it.lastModified() }
            ?: emptyList()
    }
}
