package com.securechat.telecom

import android.content.ComponentName
import android.content.Context
import android.net.Uri
import android.os.Build
import android.telecom.PhoneAccount
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.util.Log
import androidx.annotation.RequiresApi
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * SecureChat'i sisteme "calling app" olarak kaydeder.
 *
 * Application.onCreate'te bir kez [register] çağrılmalı. PhoneAccount sisteme bildirilince
 * Telecom Framework SecureChatConnectionService'i bind edebilir.
 *
 * NOT: PhoneAccount kayıt edilse bile kullanıcının bunu **manuel etkinleştirmesi**
 * gerekebilir (Settings → Phone Apps → SecureChat). SELF_MANAGED capability ile
 * çoğu cihazda otomatik aktif olur.
 */
@Singleton
class PhoneAccountRegistrar @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private val telecomManager: TelecomManager? by lazy {
        context.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager
    }

    val phoneAccountHandle: PhoneAccountHandle? by lazy {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return@lazy null
        PhoneAccountHandle(
            ComponentName(context, SecureChatConnectionService::class.java),
            ACCOUNT_ID
        )
    }

    @RequiresApi(Build.VERSION_CODES.O)
    fun register() {
        if (!TELECOM_ENABLED) {
            Log.d(TAG, "Telecom devre disi (TELECOM_ENABLED=false) — register atlandi")
            return
        }
        val tm = telecomManager ?: return
        val handle = phoneAccountHandle ?: return

        // Zaten kayıtlı mı?
        try {
            val existing = tm.getPhoneAccount(handle)
            if (existing != null) {
                Log.d(TAG, "PhoneAccount zaten kayıtlı: $ACCOUNT_ID")
                return
            }
        } catch (e: SecurityException) {
            // MANAGE_OWN_CALLS yokken getPhoneAccount fail eder — devam et, register dene
            Log.w(TAG, "getPhoneAccount SecurityException: ${e.message}")
        }

        try {
            val account = PhoneAccount.builder(handle, "SecureChat")
                .setCapabilities(
                    PhoneAccount.CAPABILITY_SELF_MANAGED or
                    PhoneAccount.CAPABILITY_SUPPORTS_VIDEO_CALLING or
                    PhoneAccount.CAPABILITY_VIDEO_CALLING
                )
                .setShortDescription("SecureChat sesli/görüntülü arama")
                .setSupportedUriSchemes(listOf(PhoneAccount.SCHEME_TEL, PhoneAccount.SCHEME_SIP))
                .build()
            tm.registerPhoneAccount(account)
            Log.d(TAG, "PhoneAccount kaydedildi: $ACCOUNT_ID")
        } catch (e: SecurityException) {
            Log.e(TAG, "PhoneAccount kaydı SecurityException: ${e.message}")
        } catch (e: Exception) {
            Log.e(TAG, "PhoneAccount kaydı hatası: ${e.message}")
        }
    }

    /**
     * Gelen arama bildirimi sisteme — `addNewIncomingCall` çağrısı.
     * Sistem ConnectionService.onCreateIncomingConnection'ı tetikler.
     */
    @RequiresApi(Build.VERSION_CODES.O)
    fun notifyIncomingCall(callId: String, peerId: String, peerName: String, isVideo: Boolean): Boolean {
        if (!TELECOM_ENABLED) {
            Log.d(TAG, "Telecom devre disi — notifyIncomingCall atlandi")
            return false
        }
        val tm = telecomManager ?: return false
        val handle = phoneAccountHandle ?: return false
        return try {
            val extras = android.os.Bundle().apply {
                putString(SecureChatConnectionService.EXTRA_CALL_ID, callId)
                putString(SecureChatConnectionService.EXTRA_PEER_ID, peerId)
                putString(SecureChatConnectionService.EXTRA_PEER_NAME, peerName)
                putBoolean(SecureChatConnectionService.EXTRA_IS_VIDEO, isVideo)
                // Telecom URI — sistem caller bilgisi için kullanır
                val uri = Uri.fromParts("tel", peerId, null)
                putParcelable(TelecomManager.EXTRA_INCOMING_CALL_ADDRESS, uri)
            }
            tm.addNewIncomingCall(handle, extras)
            Log.d(TAG, "addNewIncomingCall: callId=$callId peer=$peerId")
            true
        } catch (e: SecurityException) {
            Log.e(TAG, "notifyIncomingCall SecurityException: ${e.message}")
            false
        } catch (e: Exception) {
            Log.e(TAG, "notifyIncomingCall hatası: ${e.message}")
            false
        }
    }

    /**
     * Giden arama başlat — `placeCall` çağrısı.
     * Sistem ConnectionService.onCreateOutgoingConnection'ı tetikler.
     */
    @RequiresApi(Build.VERSION_CODES.O)
    fun placeOutgoingCall(callId: String, peerId: String, peerName: String, isVideo: Boolean): Boolean {
        if (!TELECOM_ENABLED) {
            Log.d(TAG, "Telecom devre disi — placeOutgoingCall atlandi")
            return false
        }
        val tm = telecomManager ?: return false
        val handle = phoneAccountHandle ?: return false
        return try {
            val uri = Uri.fromParts("tel", peerId, null)
            val extras = android.os.Bundle().apply {
                putParcelable(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, handle)
                val callExtras = android.os.Bundle().apply {
                    putString(SecureChatConnectionService.EXTRA_CALL_ID, callId)
                    putString(SecureChatConnectionService.EXTRA_PEER_ID, peerId)
                    putString(SecureChatConnectionService.EXTRA_PEER_NAME, peerName)
                    putBoolean(SecureChatConnectionService.EXTRA_IS_VIDEO, isVideo)
                }
                putBundle(TelecomManager.EXTRA_OUTGOING_CALL_EXTRAS, callExtras)
            }
            tm.placeCall(uri, extras)
            Log.d(TAG, "placeCall: callId=$callId peer=$peerId")
            true
        } catch (e: SecurityException) {
            Log.e(TAG, "placeCall SecurityException: ${e.message}")
            false
        } catch (e: Exception) {
            Log.e(TAG, "placeCall hatası: ${e.message}")
            false
        }
    }

    companion object {
        /**
         * Telecom Framework entegrasyonu ana feature flag'i.
         * 2026-05-11: SELF_MANAGED ConnectionService bazi cihazlarda hayalet
         * call/UI cakismalarina sebep oluyordu. Cihaz testi ile dogrulanana kadar
         * notification + IncomingCallActivity tek UI kaynagi olarak kullanilir.
         * Re-enable: bu flag'i true yap.
         */
        const val TELECOM_ENABLED = false

        const val ACCOUNT_ID = "securechat-self-managed"
        private const val TAG = "PhoneAccountReg"
    }
}
