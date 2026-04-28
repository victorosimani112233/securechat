package com.securechat.app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.util.Log
import android.view.WindowManager
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.app.AppCompatDelegate
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.compose.rememberNavController
import com.securechat.app.data.FcmTokenManager
import com.securechat.app.data.IncomingMessageHandler
import com.securechat.app.data.UserSession
import com.securechat.app.navigation.SecureChatNavHost
import com.securechat.app.ui.theme.SecureChatTheme
import com.securechat.media.CallManager
import com.securechat.media.model.CallDirection
import com.securechat.media.model.CallState
import com.securechat.network.SignalingClient
import com.securechat.network.model.ConnectionState
import dagger.hilt.android.AndroidEntryPoint
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import javax.inject.Inject

@AndroidEntryPoint
class SecureChatActivity : AppCompatActivity() {

    @Inject lateinit var userSession: UserSession
    @Inject lateinit var signalingClient: SignalingClient
    @Inject lateinit var callManager: CallManager
    @Inject lateinit var themeManager: com.securechat.app.ui.components.ThemeManager
    @Inject lateinit var fcmTokenManager: FcmTokenManager

    private var presenceJob: Job? = null

    private val pendingChatPeerId = kotlinx.coroutines.flow.MutableStateFlow<String?>(null)
    private val pendingCallNavigation = kotlinx.coroutines.flow.MutableStateFlow<Pair<String, String>?>(null)

    private val requestRecordAudioPermission = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) {
            Log.d("SecureChatActivity", "RECORD_AUDIO izni verildi")
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        super.onCreate(savedInstanceState)

        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )

        enableEdgeToEdge()

        // Klavye ve sistem UI icin night mode'u senkron ayarla (setContent'ten once olmali)
        val nightMode = kotlinx.coroutines.runBlocking {
            val followSystem = themeManager.followSystemTheme.first()
            if (followSystem) {
                AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM
            } else {
                if (themeManager.isDarkTheme.first()) AppCompatDelegate.MODE_NIGHT_YES
                else AppCompatDelegate.MODE_NIGHT_NO
            }
        }
        AppCompatDelegate.setDefaultNightMode(nightMode)

        // Tam ekran modu tercihi — kullanıcının ayarına göre navigasyon çubuğunu yönet
        lifecycleScope.launch {
            themeManager.fullscreenMode.collect { fullscreen ->
                val insetsController = WindowCompat.getInsetsController(window, window.decorView)
                if (fullscreen) {
                    insetsController.hide(WindowInsetsCompat.Type.navigationBars())
                    insetsController.systemBarsBehavior =
                        WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                } else {
                    insetsController.show(WindowInsetsCompat.Type.navigationBars())
                }
            }
        }

        // Tema degisikliklerini dinamik olarak dinle (kullanici ayarlardan degistirirse)
        lifecycleScope.launch {
            themeManager.followSystemTheme.collect { followSystem ->
                if (followSystem) {
                    AppCompatDelegate.setDefaultNightMode(AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM)
                } else {
                    launch {
                        themeManager.isDarkTheme.collect { isDark ->
                            AppCompatDelegate.setDefaultNightMode(
                                if (isDark) AppCompatDelegate.MODE_NIGHT_YES
                                else AppCompatDelegate.MODE_NIGHT_NO
                            )
                        }
                    }
                }
            }
        }

        // Intent'ten chat_peer varsa kaydet
        intent.getStringExtra("chat_peer")?.let { pendingChatPeerId.value = it }

        // IncomingCallActivity'den gelen arama navigasyonu
        handleCallNavigationIntent(intent)

        // Missed call'dan geri arama intent'i
        handleCallbackIntent(intent)

        // FCM sistem bildirimlerini temizle — uygulama acildiginda tekrar gosterilmesin
        val nm = getSystemService(android.app.NotificationManager::class.java)
        nm.cancelAll()
        IncomingMessageHandler.clearNotificationCounts()

        // Izinleri iste
        requestRecordAudioPermissionIfNeeded()
        requestNotificationPermissionIfNeeded()

        val startDest = if (userSession.isLoggedIn) "conversations" else "auth/phone"
        // Bildirimden veya intent'ten geliyorsa splash'i atla
        val hasIncomingIntent = intent.hasExtra("chat_peer") ||
                intent.hasExtra("navigate_to_call") ||
                intent.getStringExtra("action") == "call_back"
        val skipSplash = hasIncomingIntent || (userSession.isLoggedIn && savedInstanceState != null)

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

                // Uygulama on plandayken gelen arama
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
                    skipSplash = skipSplash,
                    onUserRegistered = { name, phone ->
                        Log.d("SecureChat", "onUserRegistered")

                        userSession.login(name, phone)

                        // Sunucuya UUID + phoneHash kaydi
                        // Sunucu ayni telefon icin mevcut userId dondururse onu kullan
                        lifecycleScope.launch {
                            registerUserOnServer(userSession.userId!!, phone)

                            // WebSocket baglantisi (sunucu kaydindan sonra — userId degismis olabilir)
                            signalingClient.connect(
                                userId = userSession.userId!!,
                                authToken = "token_${userSession.userId}",
                                customUrl = BuildConfig.SIGNALING_URL
                            )

                            fcmTokenManager.registerTokenOnServer()
                        }
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
     * Sunucuya UUID + phoneHash + sifreli telefon numarasi kaydeder.
     * Plaintext numara GONDERILMEZ — AES-GCM ile sifrelenir, sunucu cozemez.
     */
    /**
     * Sunucuya UUID + phoneHash + sifreli telefon numarasi kaydeder.
     * Sunucu ayni phoneHash icin kayit bulursa mevcut userId'yi dondurur.
     * Bu durumda yerel userId guncellenir — boylece ayni numara her zaman ayni UUID'yi kullanir.
     */
    private suspend fun registerUserOnServer(userId: String, phone: String) {
        try {
            val phoneDigits = phone.replace(Regex("[^0-9]"), "")
            val phoneHash = com.securechat.contacts.UserDiscoveryService.hashPhoneNumber(phoneDigits)
            val encryptedPhone = com.securechat.contacts.PhoneEncryptor.encrypt(phoneDigits)
            val json = org.json.JSONObject().apply {
                put("userId", userId)
                put("phoneHash", phoneHash)
                put("encryptedPhone", encryptedPhone)
            }
            val body = json.toString()
                .toRequestBody("application/json".toMediaType())
            val request = okhttp3.Request.Builder()
                .url("${BuildConfig.API_BASE_URL}/api/v1/users/register")
                .post(body)
                .build()
            kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                okhttp3.OkHttpClient().newCall(request).execute().use { response ->
                    val responseBody = response.body?.string()
                    Log.d("SecureChat", "Sunucu kaydi: ${response.code}, body=$responseBody")

                    if (response.isSuccessful && responseBody != null) {
                        val responseJson = org.json.JSONObject(responseBody)
                        val serverUserId = responseJson.optString("userId", "")
                        val isNew = responseJson.optBoolean("isNew", true)

                        if (!isNew && serverUserId.isNotBlank() && serverUserId != userId) {
                            // Sunucu mevcut kullaniciyi dondurdu — yerel userId'yi guncelle
                            Log.d("SecureChat", "Mevcut kullanici bulundu, userId guncelleniyor: $userId -> $serverUserId")
                            userSession.userId = serverUserId
                        }
                    }
                }
            }
        } catch (e: Exception) {
            Log.e("SecureChat", "Sunucu kaydi basarisiz: ${e.message}")
        }
    }

    private fun handleCallNavigationIntent(intent: android.content.Intent) {
        val callPeerId = intent.getStringExtra("navigate_to_call")
        val callType = intent.getStringExtra("call_type") ?: "VOICE"
        if (callPeerId != null) {
            pendingCallNavigation.value = Pair(callPeerId, callType)
        }
    }

    private fun handleCallbackIntent(intent: android.content.Intent) {
        val action = intent.getStringExtra("action")
        val peerId = intent.getStringExtra("peer_id")
        val callType = intent.getStringExtra("call_type") ?: "VOICE"

        if (action == "call_back" && !peerId.isNullOrBlank() && userSession.isLoggedIn) {
            Log.d("SecureChatActivity", "Callback intent: $peerId, $callType")

            val userId = userSession.userId!!
            val callTypeEnum = if (callType == "VIDEO") {
                com.securechat.network.model.CallType.VIDEO
            } else {
                com.securechat.network.model.CallType.VOICE
            }

            callManager.initiateCall(peerId, callTypeEnum, userId)
            pendingCallNavigation.value = Pair(peerId, callType)
        }
    }

    override fun onResume() {
        super.onResume()
        IncomingMessageHandler.isAppInForeground = true
        // FCM sistem bildirimlerini temizle — uygulama acikken tekrar gosterilmesin
        getSystemService(android.app.NotificationManager::class.java).cancelAll()
        IncomingMessageHandler.clearNotificationCounts()
        // Uygulama on plana gelince cevrimici bildir
        val uid = userSession.userId ?: return
        presenceJob?.cancel()
        val hide = !userSession.shareLastSeen
        presenceJob = lifecycleScope.launch {
            signalingClient.connectionState.collect { state ->
                if (state is ConnectionState.Connected) {
                    signalingClient.sendPresenceUpdate(uid, true, hideLastSeen = hide)
                }
            }
        }
    }

    override fun onPause() {
        super.onPause()
        IncomingMessageHandler.isAppInForeground = false
        presenceJob?.cancel()
        presenceJob = null
        val hide = !userSession.shareLastSeen
        userSession.userId?.let { signalingClient.sendPresenceUpdate(it, false, hideLastSeen = hide) }
    }

    private fun requestRecordAudioPermissionIfNeeded() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO)
            != PackageManager.PERMISSION_GRANTED
        ) {
            requestRecordAudioPermission.launch(Manifest.permission.RECORD_AUDIO)
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
}
