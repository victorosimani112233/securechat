package com.securechat.contacts

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Rehber erisim izni yonetimi.
 * Runtime permission kontrolu yapar, izin yoksa graceful degrade saglanir.
 */
@Singleton
class ContactPermissionManager @Inject constructor(
    @ApplicationContext private val context: Context
) {
    /**
     * READ_CONTACTS izninin verilip verilmedigini kontrol eder.
     */
    fun hasPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            context, Manifest.permission.READ_CONTACTS
        ) == PackageManager.PERMISSION_GRANTED
    }
}
