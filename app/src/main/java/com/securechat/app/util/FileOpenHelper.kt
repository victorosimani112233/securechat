package com.securechat.app.util

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.Toast
import androidx.core.content.FileProvider
import java.io.File

/**
 * Dosya açma ve paylaşma yardımcı sınıfı.
 *
 * GÜVENLIK: FileProvider kullanarak secure file sharing sağlar.
 * External app'lerle dosya paylaşırken temporary read permission verir.
 *
 * MIME type detection ile doğru uygulamayı açar:
 * - PDF → PDF okuyucu
 * - Resimler → Galeri
 * - Video → Video oynatıcı
 * - Belgeler → Office uygulamaları
 */
object FileOpenHelper {

    /**
     * Dosyayı external app ile açar.
     *
     * @param context Android context
     * @param filePath Dosyanın yerel file path'i veya URI string'i
     * @param mimeType Dosyanın MIME tipi
     */
    fun openFile(context: Context, filePath: String, mimeType: String) {
        try {
            val fileUri = resolveFileUri(context, filePath) ?: return

            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(fileUri, mimeType)
                flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_ACTIVITY_NEW_TASK
            }

            // Chooser kullan — Android 11+ paket gorunurluk sorununu onler
            val chooser = Intent.createChooser(intent, "Birlikte ac").apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            context.startActivity(chooser)

        } catch (e: ActivityNotFoundException) {
            showToast(context, "Bu dosyay\u0131 a\u00e7abilecek uygulama bulunamad\u0131")
        } catch (e: SecurityException) {
            android.util.Log.e("FileOpenHelper", "Dosya erisim izni reddedildi: ${e.message}")
            showToast(context, "Dosya erisim izni reddedildi")
        } catch (e: Exception) {
            android.util.Log.e("FileOpenHelper", "Dosya acilamadi: ${e.message}")
            showToast(context, "Dosya acilamadi")
        }
    }

    /**
     * "Birlikte ac" (Share) menusunu gosterir.
     * Kullanici hangi app ile acacagini secebilir.
     */
    fun openWithChooser(context: Context, filePath: String, mimeType: String) {
        try {
            val fileUri = resolveFileUri(context, filePath) ?: return

            val viewIntent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(fileUri, mimeType)
                flags = Intent.FLAG_GRANT_READ_URI_PERMISSION
            }
            val chooser = Intent.createChooser(viewIntent, "Birlikte ac").apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            context.startActivity(chooser)

        } catch (e: ActivityNotFoundException) {
            showToast(context, "Bu dosyay\u0131 a\u00e7abilecek uygulama bulunamad\u0131")
        } catch (e: SecurityException) {
            android.util.Log.e("FileOpenHelper", "Dosya erisim izni reddedildi: ${e.message}")
            showToast(context, "Dosya erisim izni reddedildi")
        } catch (e: Exception) {
            android.util.Log.e("FileOpenHelper", "Chooser acilamadi: ${e.message}")
            showToast(context, "Dosya paylasilamadi")
        }
    }

    /**
     * Dosyayi share eder (Send intent).
     * WhatsApp, email, Bluetooth vb. ile paylasim.
     */
    fun shareFile(context: Context, filePath: String, mimeType: String, fileName: String = "Dosya") {
        try {
            val fileUri = resolveFileUri(context, filePath) ?: return

            val shareIntent = Intent(Intent.ACTION_SEND).apply {
                type = mimeType
                putExtra(Intent.EXTRA_STREAM, fileUri)
                putExtra(Intent.EXTRA_TEXT, fileName)
                flags = Intent.FLAG_GRANT_READ_URI_PERMISSION
            }
            val chooser = Intent.createChooser(shareIntent, "Dosyayi paylas").apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            context.startActivity(chooser)

        } catch (e: ActivityNotFoundException) {
            showToast(context, "Bu dosyay\u0131 a\u00e7abilecek uygulama bulunamad\u0131")
        } catch (e: SecurityException) {
            android.util.Log.e("FileOpenHelper", "Dosya erisim izni reddedildi: ${e.message}")
            showToast(context, "Dosya erisim izni reddedildi")
        } catch (e: Exception) {
            android.util.Log.e("FileOpenHelper", "Dosya paylasilamadi: ${e.message}")
            showToast(context, "Dosya paylasilamadi")
        }
    }

    /**
     * MIME type'a göre uygun icon rengi döndürür.
     * UI'da dosya tipini görsel olarak ayırt etmek için.
     */
    fun getMimeTypeColor(mimeType: String): androidx.compose.ui.graphics.Color {
        return when {
            mimeType.startsWith("image/") -> androidx.compose.ui.graphics.Color(0xFF4ECDC4) // Teal
            mimeType.startsWith("video/") -> androidx.compose.ui.graphics.Color(0xFFFF7043) // Orange
            mimeType.startsWith("audio/") -> androidx.compose.ui.graphics.Color(0xFF42A5F5) // Blue
            mimeType.contains("pdf") -> androidx.compose.ui.graphics.Color(0xFFEF5350) // Red
            mimeType.contains("document") || mimeType.contains("word") -> androidx.compose.ui.graphics.Color(0xFF5C6BC0) // Indigo
            mimeType.contains("spreadsheet") || mimeType.contains("excel") -> androidx.compose.ui.graphics.Color(0xFF66BB6A) // Green
            mimeType.contains("zip") || mimeType.contains("rar") || mimeType.contains("archive") -> androidx.compose.ui.graphics.Color(0xFF7E57C2) // Purple
            else -> androidx.compose.ui.graphics.Color(0xFF42A5F5) // Default blue
        }
    }

    /**
     * Dosya extension'ına göre user-friendly type name döndürür.
     */
    fun getFileTypeDisplayName(mimeType: String, fileName: String): String {
        return when {
            mimeType.startsWith("image/") -> "Resim"
            mimeType.startsWith("video/") -> "Video"
            mimeType.startsWith("audio/") -> "Ses"
            mimeType.contains("pdf") -> "PDF"
            mimeType.contains("document") || mimeType.contains("word") -> "Word Belgesi"
            mimeType.contains("spreadsheet") || mimeType.contains("excel") -> "Excel Tablosu"
            mimeType.contains("presentation") || mimeType.contains("powerpoint") -> "PowerPoint Sunumu"
            mimeType.contains("zip") || mimeType.contains("rar") -> "Arşiv"
            mimeType.startsWith("text/") -> "Metin Dosyası"
            else -> {
                // Extension'dan tahmin etmeye çalış
                val extension = fileName.substringAfterLast(".", "").uppercase()
                when (extension) {
                    "TXT" -> "Metin Dosyası"
                    "PDF" -> "PDF"
                    "JPG", "JPEG", "PNG", "GIF" -> "Resim"
                    "MP4", "AVI", "MOV" -> "Video"
                    "MP3", "WAV", "OGG" -> "Ses"
                    "ZIP", "RAR" -> "Arşiv"
                    "DOC", "DOCX" -> "Word Belgesi"
                    "XLS", "XLSX" -> "Excel Tablosu"
                    "PPT", "PPTX" -> "PowerPoint Sunumu"
                    else -> "Dosya"
                }
            }
        }
    }

    private fun resolveFileUri(context: Context, filePath: String): Uri? {
        return if (filePath.startsWith("content://") || filePath.startsWith("file://")) {
            Uri.parse(filePath)
        } else {
            val file = File(filePath)
            if (!file.exists()) {
                showToast(context, "Dosya bulunamadi")
                return null
            }
            FileProvider.getUriForFile(
                context,
                "${context.packageName}.fileprovider",
                file
            )
        }
    }

    private fun showToast(context: Context, message: String) {
        Toast.makeText(context, message, Toast.LENGTH_SHORT).show()
    }
}