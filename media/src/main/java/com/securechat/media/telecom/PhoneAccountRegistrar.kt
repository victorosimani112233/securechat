package com.securechat.media.telecom

import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.telecom.PhoneAccount
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.util.Log
import androidx.core.content.ContextCompat
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * SELF_MANAGED PhoneAccount kaydini yoneten yardimci.
 *
 * Application#onCreate'de [register] cagrilir. Idempotent — daha onceden kayitli
 * ise no-op. PhoneAccount kaydi basarisiz olursa exception YUTULUR ve `false`
 * doner; mevcut [com.securechat.media.IncomingCallHandler] (NotificationCompat
 * .CallStyle) fallback olarak devreye girer.
 *
 * **Capabilities:**
 * - `CAPABILITY_SELF_MANAGED` — Telecom UI gostermez, ses focus + cellular
 *   coexistence yonetir
 * - `CAPABILITY_VIDEO_CALLING` + `CAPABILITY_SUPPORTS_VIDEO_CALLING` — video
 *   araması destegi
 *
 * **Permission:** `MANAGE_OWN_CALLS` — manifest'te declared. Kullaniciya runtime
 * istek gerekmez (normal-level permission, install-time grant).
 *
 * **Handle scheme:** `sip` — SELF_MANAGED VoIP icin standart pattern. `tel:`
 * cellular ile karistirilir, ozel bir scheme kullanmak Telecom Framework
 * tarafindan beklenir.
 */
@Singleton
class PhoneAccountRegistrar @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private val telecomManager: TelecomManager? by lazy {
        context.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager
    }

    /**
     * PhoneAccount handle — tum modullerin TelecomManager.placeCall /
     * addNewIncomingCall icin kullanmasi gereken referans.
     */
    val handle: PhoneAccountHandle by lazy {
        PhoneAccountHandle(
            ComponentName(context, SecureChatConnectionService::class.java),
            ACCOUNT_ID
        )
    }

    /**
     * PhoneAccount'u TelecomManager'a kaydeder. Idempotent.
     *
     * @return true ise kayit basarili veya zaten mevcut. false ise:
     *   - TELECOM_SERVICE bulunamadi (cihaz desteklemiyor)
     *   - MANAGE_OWN_CALLS izni runtime'da reddedildi (normal-level olsa da
     *     bazi OEM'ler ek kontrol uyguluyor)
     *   - register() exception firlatti
     */
    fun register(): Boolean {
        val tm = telecomManager ?: run {
            Log.w(TAG, "TelecomManager bulunamadi — Telecom desteksiz cihaz")
            return false
        }
        if (!hasManageOwnCallsPermission()) {
            Log.w(TAG, "MANAGE_OWN_CALLS izni yok — PhoneAccount kayit atlandi")
            return false
        }
        return try {
            // Mevcutsa Telecom kendi tarafinda update yapar; explicit kontrol
            // yapmamiza gerek yok ama log icin kontrol edelim.
            val existing = try { tm.getPhoneAccount(handle) } catch (_: Exception) { null }
            if (existing != null) {
                Log.d(TAG, "PhoneAccount zaten kayitli: ${handle.id}")
            }
            val phoneAccount = PhoneAccount.builder(handle, ACCOUNT_LABEL)
                .setCapabilities(buildCapabilities())
                .addSupportedUriScheme(PhoneAccount.SCHEME_SIP)
                .setShortDescription(SHORT_DESCRIPTION)
                .build()
            tm.registerPhoneAccount(phoneAccount)
            Log.i(TAG, "PhoneAccount kayit basarili: ${handle.id}")
            true
        } catch (t: Throwable) {
            // SecurityException, IllegalArgumentException, vs.
            Log.e(TAG, "PhoneAccount kayit basarisiz", t)
            false
        }
    }

    /**
     * PhoneAccount'u sistemden siler. Test ve uninstall senaryolari icin.
     * Normal calismada cagrilmaz — PhoneAccount uygulama kaldirilana kadar
     * kayitli kalmali.
     */
    fun unregister() {
        try {
            telecomManager?.unregisterPhoneAccount(handle)
            Log.d(TAG, "PhoneAccount silindi: ${handle.id}")
        } catch (t: Throwable) {
            Log.w(TAG, "PhoneAccount silinemedi", t)
        }
    }

    /**
     * SELF_MANAGED PhoneAccount kullanimaya hazir mi? false ise CallManager
     * mevcut (Telecom-disi) akisi kullanmaya devam etmeli.
     */
    fun isAvailable(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val tm = telecomManager ?: return false
        if (!hasManageOwnCallsPermission()) return false
        return try {
            tm.getPhoneAccount(handle) != null
        } catch (_: Throwable) {
            false
        }
    }

    private fun hasManageOwnCallsPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.MANAGE_OWN_CALLS
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun buildCapabilities(): Int {
        return PhoneAccount.CAPABILITY_SELF_MANAGED or
            PhoneAccount.CAPABILITY_VIDEO_CALLING or
            PhoneAccount.CAPABILITY_SUPPORTS_VIDEO_CALLING
    }

    /**
     * Kullanici adresi (callId/peerId) icin SIP-scheme Uri uretir.
     * placeCall() ve addNewIncomingCall() handle parametresi icin kullanilir.
     */
    fun addressFor(peerId: String): Uri =
        Uri.fromParts(PhoneAccount.SCHEME_SIP, peerId, null)

    companion object {
        private const val TAG = "PhoneAccountRegistrar"
        const val ACCOUNT_ID = "securechat-self-managed-account"
        private const val ACCOUNT_LABEL = "SecureChat"
        private const val SHORT_DESCRIPTION = "SecureChat ucucu sifreli aramalar"
    }
}
