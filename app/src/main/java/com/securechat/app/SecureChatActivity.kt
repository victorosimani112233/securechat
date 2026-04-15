package com.securechat.app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.compose.rememberNavController
import com.securechat.app.data.IncomingMessageHandler
import com.securechat.app.data.MessagingService
import com.securechat.app.data.UserSession
import com.securechat.app.navigation.SecureChatNavHost
import com.securechat.app.ui.theme.SecureChatTheme
import com.securechat.media.CallManager
import com.securechat.media.model.CallDirection
import com.securechat.media.model.CallState
import com.securechat.network.SignalingClient
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject

@AndroidEntryPoint
class SecureChatActivity : ComponentActivity() {

    @Inject lateinit var userSession: UserSession
    @Inject lateinit var signalingClient: SignalingClient
    @Inject lateinit var callManager: CallManager
    @Inject lateinit var themeManager: com.securechat.app.ui.components.ThemeManager

    private val pendingChatPeerId = kotlinx.coroutines.flow.MutableStateFlow<String?>(null)
    private val pendingCallNavigation = kotlinx.coroutines.flow.MutableStateFlow<Pair<String, String>?>(null)

    /**
     * RECORD_AUDIO izni sonucu.
     * Uygulama baslatildiginda bu izin istenir, boylece arama basladiginda
     * izin zaten verilmis olur.
     */
    private val requestRecordAudioPermission = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) {
            Log.d("SecureChatActivity", "RECORD_AUDIO izni verildi")
        } else {
            Log.w("SecureChatActivity", "RECORD_AUDIO izni reddedildi")
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )

        enableEdgeToEdge()

        // Intent'ten chat_peer varsa kaydet
        intent.getStringExtra("chat_peer")?.let { pendingChatPeerId.value = it }

        // IncomingCallActivity'den gelen arama navigasyonu
        handleCallNavigationIntent(intent)

        // Missed call'dan geri arama intent'i
        handleCallbackIntent(intent)

        // Izinleri iste
        requestRecordAudioPermissionIfNeeded()
        requestNotificationPermissionIfNeeded()
        requestBatteryOptimizationExemption()

        val startDest = if (userSession.isLoggedIn) "conversations" else "auth/phone"

        setContent {
            SecureChatTheme(themeManager = themeManager) {
                val navController = rememberNavController()
                val callSession by callManager.callSession.collectAsStateWithLifecycle()
                val pendingChatPeer by pendingChatPeerId.collectAsStateWithLifecycle()
                val pendingCall by pendingCallNavigation.collectAsStateWithLifecycle()

                // Bildirimden veya intent'ten gelen chat_peer
                LaunchedEffect(pendingChatPeer) {
                    val peer = pendingChatPeer
                    if (!peer.isNullOrBlank()) {
                        navController.navigate("chat/$peer")
                        pendingChatPeerId.value = null
                    }
                }

                // IncomingCallActivity'den kabul edilen arama icin navigasyon
                LaunchedEffect(pendingCall) {
                    val call = pendingCall
                    if (call != null) {
                        navController.navigate("call/${call.first}/${call.second}")
                        pendingCallNavigation.value = null
                    }
                }

                // Uygulama on plandayken gelen arama — dogrudan arama ekranina git
                // (Arka planda IncomingCallActivity full-screen intent ile gosterilir)
                // pendingCall null degilse IncomingCallActivity'den zaten navigasyon yapilacak,
                // tekrar navigate etme (double navigation bug)
                LaunchedEffect(callSession) {
                    val session = callSession
                    if (session != null
                        && session.direction == CallDirection.INCOMING
                        && session.state == CallState.RINGING
                        && IncomingMessageHandler.isAppInForeground
                        && pendingCallNavigation.value == null
                    ) {
                        navController.navigate("call/${session.peerId}/${session.callType.name}")
                    }
                }

                SecureChatNavHost(
                    navController = navController,
                    startDestination = startDest,
                    onUserRegistered = { name, phone ->
                        Log.d("SecureChat", "=== onUserRegistered CALLBACK CALLED ===")
                        Log.d("SecureChat", "  - name: $name")
                        Log.d("SecureChat", "  - phone: $phone")

                        userSession.login(name, phone)

                        Log.d("SecureChat", "Calling SignalingClient.connect() from onUserRegistered")
                        Log.d("SecureChat", "Connection params:")
                        Log.d("SecureChat", "  - userId: ${userSession.userId}")
                        Log.d("SecureChat", "  - authToken: token_${userSession.userId}")
                        Log.d("SecureChat", "  - customUrl: ${BuildConfig.SIGNALING_URL}")

                        // WebSocket debugging - remove this after fixing connectivity
                        Log.w("SecureChat", "🔍 STARTING WEBSOCKET DEBUG SESSION")
                        signalingClient.debugWebSocketConnection(
                            userId = userSession.userId!!,
                            authToken = "token_${userSession.userId}",
                            customUrl = BuildConfig.SIGNALING_URL
                        )

                        // Gerçek bağlantı denemesi
                        signalingClient.connect(
                            userId = userSession.userId!!,
                            authToken = "token_${userSession.userId}",
                            customUrl = BuildConfig.SIGNALING_URL
                        )

                        MessagingService.start(this@SecureChatActivity)
                        Log.d("SecureChat", "=== onUserRegistered COMPLETED ===")
                    }
                )
            }
        }
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        intent.getStringExtra("chat_peer")?.let { pendingChatPeerId.value = it }
        handleCallNavigationIntent(intent)
        handleCallbackIntent(intent)
    }

    /**
     * IncomingCallActivity'den gelen arama kabul intent'ini isler.
     * Kabul edilen aramanin arama ekranina yonlendirilmesini saglar.
     */
    private fun handleCallNavigationIntent(intent: android.content.Intent) {
        val callPeerId = intent.getStringExtra("navigate_to_call")
        val callType = intent.getStringExtra("call_type") ?: "VOICE"
        if (callPeerId != null) {
            pendingCallNavigation.value = Pair(callPeerId, callType)
        }
    }

    /**
     * Missed call bildiriminden gelen "Geri Ara" intent'ini işler.
     * Otomatik olarak giden arama başlatır.
     */
    private fun handleCallbackIntent(intent: android.content.Intent) {
        val action = intent.getStringExtra("action")
        val peerId = intent.getStringExtra("peer_id")
        val callType = intent.getStringExtra("call_type") ?: "VOICE"

        if (action == "call_back" && !peerId.isNullOrBlank() && userSession.isLoggedIn) {
            Log.d("SecureChatActivity", "Callback intent işleniyor: $peerId, tip: $callType")

            // Hemen giden arama başlat
            val userId = userSession.userId!!
            val callTypeEnum = if (callType == "VIDEO") {
                com.securechat.network.model.CallType.VIDEO
            } else {
                com.securechat.network.model.CallType.VOICE
            }

            callManager.initiateCall(peerId, callTypeEnum, userId)

            // Arama ekranına git
            pendingCallNavigation.value = Pair(peerId, callType)
        }
    }

    override fun onResume() {
        super.onResume()
        IncomingMessageHandler.isAppInForeground = true
        // Foreground service'e app durumunu bildir
        MessagingService.updateAppState(true)
    }

    override fun onPause() {
        super.onPause()
        IncomingMessageHandler.isAppInForeground = false
        // Foreground service'e app durumunu bildir
        MessagingService.updateAppState(false)
    }

    /**
     * RECORD_AUDIO izni verilmemisse runtime izin istegi baslatir.
     * Bu metod onCreate'de cagirilir, boylece kullanici arama baslatmadan
     * once izin verilmis olur.
     */
    private fun requestRecordAudioPermissionIfNeeded() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO)
            != PackageManager.PERMISSION_GRANTED
        ) {
            Log.d("SecureChatActivity", "RECORD_AUDIO izni isteniyor...")
            requestRecordAudioPermission.launch(Manifest.permission.RECORD_AUDIO)
        } else {
            Log.d("SecureChatActivity", "RECORD_AUDIO izni zaten mevcut")
        }
    }

    private val requestNotificationPermission = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { }

    private fun requestNotificationPermissionIfNeeded() {
        if (android.os.Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
            != PackageManager.PERMISSION_GRANTED
        ) {
            requestNotificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    /**
     * Pil optimizasyonu muafiyeti ister.
     * Kullaniciya sistem diyalogu gosterir — tek dokunusla "Evet" diyerek
     * uygulamanin arka planda calismaya devam etmesini saglar.
     */
    private fun requestBatteryOptimizationExemption() {
        val pm = getSystemService(PowerManager::class.java)
        if (!pm.isIgnoringBatteryOptimizations(packageName)) {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:$packageName")
            }
            startActivity(intent)
        }
    }
}
