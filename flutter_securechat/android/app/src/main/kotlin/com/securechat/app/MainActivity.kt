package com.securechat.app

import android.Manifest
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.os.Build
import android.os.PowerManager
import android.provider.ContactsContract
import android.provider.Settings
import android.telecom.PhoneAccount
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterFragmentActivity() {
    private val channelName = "com.securechat/native"
    private val contactsPermissionRequest = 4102
    private var pendingContactsPermission: MethodChannel.Result? = null
    private lateinit var nativeChannel: MethodChannel
    private var pendingAuthentication: MethodChannel.Result? = null
    private var biometricPrompt: BiometricPrompt? = null
    private val legacyRoomExporter by lazy { LegacyRoomExporter(applicationContext) }
    private val callNotifications by lazy {
        SecureChatCallNotificationManager(applicationContext)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyScreenProtectionPolicy()
        handleCallNotificationIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleCallNotificationIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        nativeChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        NativeCallRegistry.attach { action, callId ->
            runOnUiThread {
                nativeChannel.invokeMethod(
                    "nativeCallAction",
                    mapOf("action" to action, "callId" to callId)
                )
            }
        }
        nativeChannel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "enableScreenProtection" -> {
                        enableScreenProtection()
                        result.success(null)
                    }
                    "registerCallIntegration" -> registerCallIntegration(result)
                    "reportIncomingCall" -> reportIncomingCall(call.arguments, result)
                    "reportOutgoingCall" -> reportOutgoingCall(call.arguments, result)
                    "setNativeCallActive" -> updateNativeCall(call.arguments, true, result)
                    "endNativeCall" -> updateNativeCall(call.arguments, false, result)
                    "authenticateLockedChat" -> authenticateLockedChat(call.arguments, result)
                    "getCallReadiness" -> getCallReadiness(result)
                    "openCallReadinessSetting" -> openCallReadinessSetting(call.arguments, result)
                    "requestContactsPermission" -> requestContactsPermission(result)
                    "readContacts" -> readContacts(result)
                    "openLocalFile" -> openLocalFile(call.arguments, result)
                    "shareLocalFile" -> shareLocalFile(call.arguments, result)
                    "getDiagnosticsMetadata" -> getDiagnosticsMetadata(result)
                    "exportLegacyRoomDatabase" -> runLegacyRoomOperation(result) {
                        legacyRoomExporter.export()
                    }
                    "archiveLegacyRoomDatabase" -> runLegacyRoomOperation(result) {
                        legacyRoomExporter.archiveAfterImport()
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun runLegacyRoomOperation(
        result: MethodChannel.Result,
        operation: () -> Map<String, Any?>
    ) {
        Thread {
            try {
                val value = operation()
                runOnUiThread { result.success(value) }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error("ROOM_MIGRATION_FAILED", error.message, null)
                }
            }
        }.start()
    }

    override fun onDestroy() {
        biometricPrompt?.cancelAuthentication()
        pendingAuthentication?.success(false)
        pendingAuthentication = null
        NativeCallRegistry.detach()
        super.onDestroy()
    }

    private fun authenticateLockedChat(arguments: Any?, result: MethodChannel.Result) {
        if (pendingAuthentication != null) {
            result.error("AUTH_IN_PROGRESS", "Authentication is already in progress", null)
            return
        }
        val manager = BiometricManager.from(this)
        val authenticators = BiometricManager.Authenticators.BIOMETRIC_WEAK or
            BiometricManager.Authenticators.DEVICE_CREDENTIAL
        if (manager.canAuthenticate(authenticators) != BiometricManager.BIOMETRIC_SUCCESS) {
            result.error("AUTH_UNAVAILABLE", "No biometric or device credential is configured", null)
            return
        }
        pendingAuthentication = result
        val title = (arguments as? Map<*, *>)?.get("title")?.toString()
            ?.take(80)?.takeIf { it.isNotBlank() } ?: "Kilitli Sohbet"
        val prompt = BiometricPrompt(
            this,
            ContextCompat.getMainExecutor(this),
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(
                    authenticationResult: BiometricPrompt.AuthenticationResult
                ) {
                    finishAuthentication(true)
                }

                override fun onAuthenticationError(
                    errorCode: Int,
                    errString: CharSequence
                ) {
                    finishAuthentication(false)
                }
            }
        )
        biometricPrompt = prompt
        prompt.authenticate(
            BiometricPrompt.PromptInfo.Builder()
                .setTitle(title)
                .setSubtitle("Bu sohbete erişmek için kimliğinizi doğrulayın")
                .setAllowedAuthenticators(authenticators)
                .build()
        )
    }

    private fun finishAuthentication(success: Boolean) {
        val result = pendingAuthentication ?: return
        pendingAuthentication = null
        biometricPrompt = null
        result.success(success)
    }

    private fun getCallReadiness(result: MethodChannel.Result) {
        val power = getSystemService(PowerManager::class.java)
        val battery = power?.isIgnoringBatteryOptimizations(packageName) == true
        val notification = if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            "notApplicable"
        } else if (ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            "granted"
        } else {
            "denied"
        }
        val fullScreen = if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            "notApplicable"
        } else if (getSystemService(NotificationManager::class.java)
                ?.canUseFullScreenIntent() == true
        ) {
            "granted"
        } else {
            "denied"
        }
        result.success(
            mapOf(
                "battery" to if (battery) "granted" else "denied",
                "fullScreenIntent" to fullScreen,
                "notification" to notification,
                "overlay" to if (Settings.canDrawOverlays(this)) "granted" else "denied"
            )
        )
    }

    private fun openCallReadinessSetting(arguments: Any?, result: MethodChannel.Result) {
        val kind = (arguments as? Map<*, *>)?.get("kind")?.toString().orEmpty()
        val packageUri = Uri.parse("package:$packageName")
        val intent = when (kind) {
            "battery" -> Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, packageUri)
            "fullScreenIntent" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, packageUri)
            } else null
            "notification" -> Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            }
            "overlay" -> Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, packageUri)
            else -> null
        }
        if (intent == null || intent.resolveActivity(packageManager) == null) {
            result.success(false)
            return
        }
        try {
            startActivity(intent)
            result.success(true)
        } catch (_: Exception) {
            result.success(false)
        }
    }

    private fun accountHandle(): PhoneAccountHandle = PhoneAccountHandle(
        ComponentName(this, SecureChatConnectionService::class.java),
        "elcim_self_managed"
    )

    private fun registerCallIntegration(result: MethodChannel.Result) {
        try {
            callNotifications.ensureChannels()
            val telecom = getSystemService(TelecomManager::class.java)
            telecom.registerPhoneAccount(
                PhoneAccount.builder(accountHandle(), "Elcim")
                    .setCapabilities(PhoneAccount.CAPABILITY_SELF_MANAGED)
                    .build()
            )
            result.success(null)
        } catch (error: Exception) {
            result.error("TELECOM_REGISTER_FAILED", error.message, null)
        }
    }

    private fun reportIncomingCall(arguments: Any?, result: MethodChannel.Result) {
        val data = arguments as? Map<*, *> ?: return result.error(
            "INVALID_ARGUMENTS", "Call arguments are missing", null
        )
        try {
            val callId = data["callId"]?.toString().orEmpty()
            val peerName = data["peerName"]?.toString().orEmpty()
            val peerId = data["peerId"]?.toString().orEmpty()
            val redactIdentity = data["redactIdentity"] as? Boolean ?: true
            val hasVideo = data["hasVideo"] as? Boolean ?: false
            require(callId.isNotBlank() && peerId.isNotBlank())
            NativeCallRegistry.remember(callId, peerId, peerName, hasVideo, redactIdentity)
            val info = requireNotNull(NativeCallRegistry.findByCallId(callId))
            val extras = callExtras(callId, peerId, peerName, hasVideo, redactIdentity)
            getSystemService(TelecomManager::class.java)
                .addNewIncomingCall(accountHandle(), extras)
            callNotifications.showIncoming(info)
            result.success(null)
        } catch (error: Exception) {
            result.error("INCOMING_CALL_FAILED", error.message, null)
        }
    }

    private fun reportOutgoingCall(arguments: Any?, result: MethodChannel.Result) {
        val data = arguments as? Map<*, *> ?: return result.error(
            "INVALID_ARGUMENTS", "Call arguments are missing", null
        )
        try {
            val callId = data["callId"]?.toString().orEmpty()
            val peerName = data["peerName"]?.toString().orEmpty()
            val peerId = data["peerId"]?.toString().orEmpty()
            val redactIdentity = data["redactIdentity"] as? Boolean ?: true
            val hasVideo = data["hasVideo"] as? Boolean ?: false
            require(callId.isNotBlank() && peerId.isNotBlank())
            NativeCallRegistry.remember(callId, peerId, peerName, hasVideo, redactIdentity)
            val info = requireNotNull(NativeCallRegistry.findByCallId(callId))
            getSystemService(TelecomManager::class.java).placeCall(
                Uri.fromParts("securechat", callId, null),
                callExtras(callId, peerId, peerName, hasVideo, redactIdentity)
            )
            callNotifications.showConnecting(info)
            result.success(null)
        } catch (error: Exception) {
            result.error("OUTGOING_CALL_FAILED", error.message, null)
        }
    }

    private fun callExtras(
        callId: String,
        peerId: String,
        peerName: String,
        hasVideo: Boolean,
        redactIdentity: Boolean
    ) = Bundle().apply {
        putParcelable(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, accountHandle())
        putString(SecureChatConnectionService.EXTRA_CALL_ID, callId)
        putString(SecureChatConnectionService.EXTRA_PEER_ID, peerId)
        putString(SecureChatConnectionService.EXTRA_PEER_NAME, peerName)
        putBoolean(SecureChatConnectionService.EXTRA_HAS_VIDEO, hasVideo)
        putBoolean(SecureChatConnectionService.EXTRA_REDACT_IDENTITY, redactIdentity)
    }

    private fun updateNativeCall(
        arguments: Any?,
        active: Boolean,
        result: MethodChannel.Result
    ) {
        val callId = (arguments as? Map<*, *>)?.get("callId")?.toString()
        if (callId.isNullOrBlank()) {
            result.error("INVALID_ARGUMENTS", "callId is missing", null)
            return
        }
        val info = NativeCallRegistry.findByCallId(callId)
        if (active) {
            NativeCallRegistry.setActive(callId)
            if (info != null) callNotifications.showEstablished(info)
        } else {
            NativeCallRegistry.end(callId)
            callNotifications.cancel()
        }
        result.success(null)
    }

    private fun handleCallNotificationIntent(intent: Intent?) {
        if (intent?.action != SecureChatCallNotificationManager.ACTION_NOTIFICATION) return
        val action = intent.getStringExtra(SecureChatCallNotificationManager.EXTRA_ACTION)
        val callId = intent.getStringExtra(SecureChatCallNotificationManager.EXTRA_CALL_ID)
        intent.action = null
        intent.removeExtra(SecureChatCallNotificationManager.EXTRA_ACTION)
        intent.removeExtra(SecureChatCallNotificationManager.EXTRA_CALL_ID)
        if (action.isNullOrBlank() || callId.isNullOrBlank()) return
        val info = NativeCallRegistry.findByCallId(callId)
        when (action) {
            SecureChatCallNotificationManager.ACTION_ANSWER -> {
                if (info != null) callNotifications.showConnecting(info)
            }
            SecureChatCallNotificationManager.ACTION_END -> callNotifications.cancel()
            SecureChatCallNotificationManager.ACTION_OPEN -> Unit
            else -> return
        }
        NativeCallRegistry.emit(action, callId)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == contactsPermissionRequest) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingContactsPermission?.success(granted)
            pendingContactsPermission = null
        }
    }

    private fun requestContactsPermission(result: MethodChannel.Result) {
        if (ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.READ_CONTACTS
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (pendingContactsPermission != null) {
            result.error("REQUEST_IN_PROGRESS", "Contacts permission request in progress", null)
            return
        }
        pendingContactsPermission = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.READ_CONTACTS),
            contactsPermissionRequest
        )
    }

    private fun readContacts(result: MethodChannel.Result) {
        if (ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.READ_CONTACTS
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            result.error("PERMISSION_DENIED", "Contacts permission not granted", null)
            return
        }
        try {
            val contacts = linkedMapOf<String, MutableMap<String, Any?>>()
            val projection = arrayOf(
                ContactsContract.CommonDataKinds.Phone.CONTACT_ID,
                ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                ContactsContract.CommonDataKinds.Phone.NUMBER
            )
            contentResolver.query(
                ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                projection,
                null,
                null,
                ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME + " COLLATE LOCALIZED ASC"
            )?.use { cursor ->
                val idIndex = cursor.getColumnIndexOrThrow(
                    ContactsContract.CommonDataKinds.Phone.CONTACT_ID
                )
                val nameIndex = cursor.getColumnIndexOrThrow(
                    ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME
                )
                val numberIndex = cursor.getColumnIndexOrThrow(
                    ContactsContract.CommonDataKinds.Phone.NUMBER
                )
                while (cursor.moveToNext()) {
                    val number = cursor.getString(numberIndex)?.trim().orEmpty()
                    if (number.isEmpty()) continue
                    val key = "${cursor.getLong(idIndex)}:$number"
                    contacts[key] = mutableMapOf(
                        "displayName" to cursor.getString(nameIndex).orEmpty(),
                        "phoneNumber" to number,
                        "avatarUri" to null
                    )
                }
            }
            result.success(contacts.values.toList())
        } catch (error: Exception) {
            result.error("CONTACTS_READ_FAILED", error.message, null)
        }
    }

    private fun enableScreenProtection() {
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
    }

    private fun applyScreenProtectionPolicy() {
        if (allowsDebugScreenCapture()) {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            enableScreenProtection()
        }
    }

    private fun allowsDebugScreenCapture(): Boolean {
        val debuggable = applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
        if (!debuggable) return false
        val metadata = packageManager.getApplicationInfo(
            packageName,
            PackageManager.GET_META_DATA
        ).metaData
        return metadata?.getBoolean("com.securechat.DEBUG_ALLOW_SCREEN_CAPTURE") == true
    }

    private fun openLocalFile(arguments: Any?, result: MethodChannel.Result) {
        val file = mediaFile(arguments, result) ?: return
        val mime = (arguments as Map<*, *>)["mimeType"]?.toString()
            ?.takeIf { it.isNotBlank() } ?: "application/octet-stream"
        try {
            val uri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                file
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mime)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(Intent.createChooser(intent, "Dosyayı aç"))
            result.success(null)
        } catch (error: Exception) {
            result.error("FILE_OPEN_FAILED", error.message, null)
        }
    }

    private fun shareLocalFile(arguments: Any?, result: MethodChannel.Result) {
        val file = mediaFile(arguments, result) ?: return
        val mime = (arguments as Map<*, *>)["mimeType"]?.toString()
            ?.takeIf { it.isNotBlank() } ?: "application/octet-stream"
        try {
            val uri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                file
            )
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = mime
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(Intent.createChooser(intent, "Dosyayı paylaş"))
            result.success(null)
        } catch (error: Exception) {
            result.error("FILE_SHARE_FAILED", error.message, null)
        }
    }

    private fun getDiagnosticsMetadata(result: MethodChannel.Result) {
        val packageInfo = packageManager.getPackageInfo(packageName, 0)
        val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageInfo.longVersionCode.toString()
        } else {
            @Suppress("DEPRECATION")
            packageInfo.versionCode.toString()
        }
        result.success(
            mapOf(
                "versionName" to (packageInfo.versionName ?: "unknown"),
                "versionCode" to versionCode,
                "operatingSystem" to "android",
                "osVersion" to Build.VERSION.RELEASE,
                "deviceModel" to Build.MODEL,
                "manufacturer" to Build.MANUFACTURER
            )
        )
    }

    private fun mediaFile(
        arguments: Any?,
        result: MethodChannel.Result
    ): File? {
        val path = (arguments as? Map<*, *>)?.get("path")?.toString()
        if (path.isNullOrBlank()) {
            result.error("INVALID_ARGUMENTS", "File path is missing", null)
            return null
        }
        try {
            val file = File(path).canonicalFile
            val roots = listOf(
                File(filesDir, "media"),
                File(filesDir, "crash_logs")
            ).map { it.canonicalFile }
            val allowed = roots.any { root ->
                file.path == root.path || file.path.startsWith(root.path + File.separator)
            }
            if (!allowed || !file.exists() || !file.isFile) {
                result.error(
                    "FILE_NOT_ALLOWED",
                    "Only retained media and local redacted diagnostics may leave private app storage",
                    null
                )
                return null
            }
            return file
        } catch (error: Exception) {
            result.error("FILE_NOT_ALLOWED", error.message, null)
            return null
        }
    }
}
