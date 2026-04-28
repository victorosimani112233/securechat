package com.securechat.app.backup

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.io.File
import javax.inject.Inject

/**
 * Yedekleme ekrani ViewModel'i.
 * Yedek olusturma, dosya paylasma ve geri yukleme islemlerini yonetir.
 */
@HiltViewModel
class BackupViewModel @Inject constructor(
    @ApplicationContext private val context: Context,
    private val backupManager: BackupManager
) : ViewModel() {

    // ─── Create backup state ─────────────────────────────────────────

    private val _isCreating = MutableStateFlow(false)
    val isCreating: StateFlow<Boolean> = _isCreating.asStateFlow()

    private val _createdBackupFile = MutableStateFlow<File?>(null)
    val createdBackupFile: StateFlow<File?> = _createdBackupFile.asStateFlow()

    // ─── Restore backup state ────────────────────────────────────────

    private val _isRestoring = MutableStateFlow(false)
    val isRestoring: StateFlow<Boolean> = _isRestoring.asStateFlow()

    private val _restoreResult = MutableStateFlow<BackupManager.RestoreResult?>(null)
    val restoreResult: StateFlow<BackupManager.RestoreResult?> = _restoreResult.asStateFlow()

    private val _remainingAttempts = MutableStateFlow(5)
    val remainingAttempts: StateFlow<Int> = _remainingAttempts.asStateFlow()

    // ─── Events ──────────────────────────────────────────────────────

    private val _toastEvent = MutableSharedFlow<String>()
    val toastEvent: SharedFlow<String> = _toastEvent.asSharedFlow()

    // ─── Actions ─────────────────────────────────────────────────────

    fun createBackup(password: String) {
        viewModelScope.launch(Dispatchers.IO) {
            _isCreating.value = true
            try {
                val file = backupManager.createBackup(password)
                _createdBackupFile.value = file
                _toastEvent.emit("Yedek oluşturuldu")
            } catch (e: Exception) {
                android.util.Log.e("BackupVM", "Yedek olusturulamadi", e)
                _toastEvent.emit("Yedek oluşturulamadı: ${e.message}")
            } finally {
                _isCreating.value = false
            }
        }
    }

    fun restoreBackup(uri: Uri, password: String) {
        viewModelScope.launch(Dispatchers.IO) {
            _isRestoring.value = true
            _restoreResult.value = null
            try {
                val result = backupManager.restoreBackup(uri, password)
                _restoreResult.value = result
                _remainingAttempts.value = backupManager.getRemainingAttempts(uri)

                when (result) {
                    is BackupManager.RestoreResult.Success ->
                        _toastEvent.emit("Yedek başarıyla geri yüklendi")
                    is BackupManager.RestoreResult.WrongPassword ->
                        _toastEvent.emit("Şifre hatalı (${_remainingAttempts.value} hak kaldı)")
                    is BackupManager.RestoreResult.AttemptsExhausted ->
                        _toastEvent.emit("5 hatalı deneme — yedek dosyası silindi")
                    is BackupManager.RestoreResult.Error ->
                        _toastEvent.emit(result.message)
                }
            } catch (e: Exception) {
                _toastEvent.emit("Geri yükleme hatası: ${e.message}")
            } finally {
                _isRestoring.value = false
            }
        }
    }

    fun updateRemainingAttempts(uri: Uri) {
        _remainingAttempts.value = backupManager.getRemainingAttempts(uri)
    }

    fun clearRestoreResult() {
        _restoreResult.value = null
    }

    /**
     * Olusturulan yedek dosyasini sistem paylasim menu'su ile paylas.
     */
    fun shareBackupFile(file: File) {
        try {
            val uri = FileProvider.getUriForFile(
                context,
                "${context.packageName}.fileprovider",
                file
            )
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = "application/octet-stream"
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(Intent.createChooser(intent, "Yedeği paylaş").apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            })
        } catch (e: Exception) {
            android.util.Log.e("BackupVM", "Paylasim hatasi", e)
            viewModelScope.launch { _toastEvent.emit("Paylaşılamadı: ${e.message}") }
        }
    }
}
