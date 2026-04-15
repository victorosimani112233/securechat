package com.securechat.contacts

import android.content.Context
import android.database.ContentObserver
import android.os.Handler
import android.os.Looper
import android.provider.ContactsContract
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Cihaz rehberindeki degisiklikleri dinler.
 * Rehber degistiginde otomatik olarak kullanici kesfini yeniden calistirir.
 * Lifecycle-aware: startObserving/stopObserving ile yonetilir, leak onlenir.
 */
@Singleton
class ContactsObserver @Inject constructor(
    @ApplicationContext private val context: Context,
    private val userDiscoveryService: UserDiscoveryService
) {
    private var contentObserver: ContentObserver? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    /**
     * Rehber degisikliklerini dinlemeye baslar.
     * Birden fazla kez cagirilsa bile yalnizca bir observer kaydedilir.
     */
    fun startObserving() {
        if (contentObserver != null) return
        contentObserver = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) {
                scope.launch {
                    userDiscoveryService.discoverRegisteredUsers()
                }
            }
        }
        context.contentResolver.registerContentObserver(
            ContactsContract.Contacts.CONTENT_URI,
            true,
            contentObserver!!
        )
    }

    /**
     * Rehber dinlemeyi durdurur ve observer'i temizler.
     */
    fun stopObserving() {
        contentObserver?.let {
            context.contentResolver.unregisterContentObserver(it)
        }
        contentObserver = null
    }
}
