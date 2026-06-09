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
    @Inject lateinit var iceServerFetcher: com.securechat.network.IceServerFetcher
    @Inject lateinit var userDiscoveryService: com.securechat.contacts.UserDiscoveryService
    @Inject lateinit var preKeyUploader: com.securechat.app.data.PreKeyUploader
    @Inject lateinit var phoneAccountRegistrar: dagger.Lazy<com.securechat.telecom.PhoneAccountRegistrar>
    @Inject lateinit var contactNameResolver: com.securechat.storage.resolver.ContactNameResolver
    @Inject lateinit var incomingCallHandler: com.securechat.media.IncomingCallHandler

    private var presenceJob: Job? = null

    private val pendingChatPeerId = kotlinx.coroutines.flow.MutableStateFlow<String?>(null)
    private val pendingCallNavigation = kotlinx.coroutines.flow.MutableStateFlow<Pair<String, String>?>(null)
    /** Sistem paylasim intent'inden gelen metin veya URI. */
    val pendingShareText = kotlinx.coroutines.flow.MutableStateFlow<String?>(null)
    val pendingShareUri = kotlinx.coroutines.flow.MutableStateFlow<android.net.Uri?>(null)

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

        // ICE server fetcher'a API base URL'i set et
        iceServerFetcher.apiBaseUrl = BuildConfig.API_BASE_URL
        iceServerFetcher.accessTokenProvider = { userSession.accessToken }
        // User discovery'ye de auth token saglayicisi ver
        userDiscoveryService.accessTokenProvider = { userSession.accessToken }

        // Tema tercihini SharedPreferences'tan senkron oku — DataStore'dan runBlocking YAPMA
        // DataStore cold-read eski cihazlarda main thread'i bloklar ve ANR'a yol acar
        val themePrefs = getSharedPreferences("theme_settings_cache", MODE_PRIVATE)
        val followSystem = themePrefs.getBoolean("follow_system", true)
        val isDark = themePrefs.getBoolean("is_dark", false)
        val nightMode = when {
            followSystem -> AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM
            isDark -> AppCompatDelegate.MODE_NIGHT_YES
            else -> AppCompatDelegate.MODE_NIGHT_NO
        }
        AppCompatDelegate.setDefaultNightMode(nightMode)

        // DataStore degerlerini arka planda oku ve cache'i guncelle
        lifecycleScope.launch {
            val realFollowSystem = themeManager.followSystemTheme.first()
            val realIsDark = themeManager.isDarkTheme.first()
            themePrefs.edit()
                .putBoolean("follow_system", realFollowSystem)
                .putBoolean("is_dark", realIsDark)
                .apply()
        }

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

        // Sistem paylasim intent'ini handle et
        handleShareIntent(intent)

        // Intent'ten chat_peer varsa kaydet — VALIDATION ZORUNLU (M8 fix).
        intent.getStringExtra("chat_peer")?.let { extractAndValidatePeerId(it) }?.let {
            pendingChatPeerId.value = it
        }

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
        requestBatteryOptimizationExemption()

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
                    apiBaseUrl = BuildConfig.API_BASE_URL,
                    onUserRegistered = { name, phone, registrationToken ->
                        Log.d("SecureChat", "onUserRegistered (regToken=${if (registrationToken != null) "yes" else "no"})")

                        userSession.login(name, phone)

                        lifecycleScope.launch {
                            registerUserOnServer(userSession.userId!!, phone, registrationToken)

                            if (!userSession.accessToken.isNullOrBlank()) {
                                // Reactive provider: AppLifecycleObserver tarafindan onTokenRefreshRequired
                                // zaten set edildi; burada sadece ilk connect tetiklenir.
                                signalingClient.connect(
                                    userId = userSession.userId!!,
                                    customUrl = BuildConfig.SIGNALING_URL
                                ) { userSession.accessToken }
                            } else {
                                Log.e("SecureChat", "Access token alinamadi, WS baglanti atlandi")
                            }

                            fcmTokenManager.registerTokenOnServer()

                            // Signal Protocol PreKey bundle'i yukle (yalnizca yeni kayit oldugunda)
                            // Mevcut kullanici icin replenish yeterli
                            try {
                                if (!userSession.accessToken.isNullOrBlank()) {
                                    preKeyUploader.uploadInitialBundle()
                                }
                            } catch (e: Exception) {
                                Log.w("SecureChat", "PreKey upload hatasi: ${e.message}")
                            }
                        }
                    }
                )
            }
        }
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        handleShareIntent(intent)
        intent.getStringExtra("chat_peer")?.let { extractAndValidatePeerId(it) }?.let {
            pendingChatPeerId.value = it
        }
        handleCallNavigationIntent(intent)
        handleCallbackIntent(intent)
    }

    /**
     * GUVENLIK (M8 fix): Intent extras validation.
     * chat_peer extras malicious app tarafindan dolduruluyor olabilir. UUID format'i zorunlu
     * (a-z0-9- karakterleri, 32-36 char). Gecersizse null donulur, navigasyon yapilmaz.
     */
    private fun extractAndValidatePeerId(raw: String): String? {
        val trimmed = raw.trim()
        if (trimmed.isEmpty() || trimmed.length > 64) return null
        if (!trimmed.matches(Regex("^[a-zA-Z0-9_-]{8,64}$"))) {
            Log.w("SecureChatActivity", "Gecersiz chat_peer intent extras — reddedildi")
            return null
        }
        return trimmed
    }

    /**
     * GUVENLIK (M8 fix): Paylasilan Uri'nin authority'sini dogrula.
     * Sadece content:// scheme'ler (FileProvider) ve media store kabul edilir.
     * file:// reddedilir (storage path traversal koruma). http(s):// reddedilir.
     */
    private fun isAcceptableShareUri(uri: android.net.Uri): Boolean {
        val scheme = uri.scheme?.lowercase() ?: return false
        if (scheme != "content") return false
        // content:// uri: authority FileProvider veya media store olmali
        val authority = uri.authority ?: return false
        return authority.startsWith("com.") ||
            authority == "media" ||
            authority.endsWith(".fileprovider") ||
            authority == "${BuildConfig.APPLICATION_ID}.fileprovider"
    }

    @Suppress("DEPRECATION") // getParcelableExtra typed versiyon API 33+ — min SDK 26 destegi icin eski API
    private fun handleShareIntent(intent: android.content.Intent) {
        when (intent.action) {
            android.content.Intent.ACTION_SEND -> {
                val text = intent.getStringExtra(android.content.Intent.EXTRA_TEXT)
                val uri = intent.getParcelableExtra<android.net.Uri>(android.content.Intent.EXTRA_STREAM)
                // Text uzunluk siniri (DoS koruma) — 100KB ustu paylasimi reddet
                if (text != null && text.length <= 100_000) pendingShareText.value = text
                if (uri != null && isAcceptableShareUri(uri)) pendingShareUri.value = uri
                Log.d("SecureChatActivity", "Share intent: textLen=${text?.length}, uriAccepted=${uri?.let { isAcceptableShareUri(it) }}")
            }
            android.content.Intent.ACTION_SEND_MULTIPLE -> {
                val uris = intent.getParcelableArrayListExtra<android.net.Uri>(android.content.Intent.EXTRA_STREAM)
                val firstValid = uris?.firstOrNull { isAcceptableShareUri(it) }
                if (firstValid != null) pendingShareUri.value = firstValid
                Log.d("SecureChatActivity", "Share multiple intent: ${uris?.size} items, valid=${firstValid != null}")
            }
        }
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
    private suspend fun registerUserOnServer(userId: String, phone: String, registrationToken: String? = null) {
        try {
            val phoneDigits = com.securechat.contacts.PhoneNumberNormalizer.normalizeDigits(phone)
            val phoneHash = com.securechat.contacts.UserDiscoveryService.hashPhoneNumber(phoneDigits)
            Log.d("SecureChat", "Kayit: phone=${phone.take(4)}***, normalized=$phoneDigits, hash=${phoneHash.take(12)}...")
            val encryptedPhone = com.securechat.contacts.PhoneEncryptor.encrypt(phoneDigits)
            val json = org.json.JSONObject().apply {
                put("userId", userId)
                put("phoneHash", phoneHash)
                put("encryptedPhone", encryptedPhone)
                if (!registrationToken.isNullOrBlank()) put("registrationToken", registrationToken)
            }
            val body = json.toString().toRequestBody("application/json".toMediaType())
            val request = okhttp3.Request.Builder()
                .url("${BuildConfig.API_BASE_URL}/api/v1/users/register")
                .post(body)
                .build()
            kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                okhttp3.OkHttpClient().newCall(request).execute().use { response ->
                    val responseBody = response.body?.string()
                    Log.d("SecureChat", "Sunucu kaydi: ${response.code}")

                    if (response.code == 403 && responseBody?.contains("registrationToken") == true) {
                        Log.e("SecureChat", "registrationToken zorunlu — OTP dogrulamasi gerekli")
                        return@use
                    }
                    if (response.isSuccessful && responseBody != null) {
                        val responseJson = org.json.JSONObject(responseBody)
                        val serverUserId = responseJson.optString("userId", "")
                        val isNew = responseJson.optBoolean("isNew", true)
                        val accessToken = responseJson.optString("accessToken", "")
                        val refreshToken = responseJson.optString("refreshToken", "")

                        if (!isNew && serverUserId.isNotBlank() && serverUserId != userId) {
                            Log.d("SecureChat", "Mevcut kullanici bulundu, userId guncelleniyor: $userId -> $serverUserId")
                            userSession.userId = serverUserId
                        }

                        // GUVENLIK: Atomic olarak access+refresh token sakla
                        if (accessToken.isNotBlank() && refreshToken.isNotBlank()) {
                            userSession.saveTokens(accessToken, refreshToken)
                            Log.d("SecureChat", "Access+refresh token kaydedildi")
                        } else if (accessToken.isNotBlank()) {
                            // Eski API: sadece accessToken
                            userSession.accessToken = accessToken
                            Log.w("SecureChat", "Sadece access token alindi, refresh yok")
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

        // Notification "Kabul Et" akisi: bildirimden gelir, burada accept + navigate yapilir.
        // Activity launch BroadcastReceiver'da kisitli oldugundan PendingIntent.getActivity
        // ile dogrudan buraya yonlendirildi.
        val acceptCall = intent.getBooleanExtra("accept_call", false)
        if (acceptCall) {
            val acceptPeerId = intent.getStringExtra("call_peer_id")
            val acceptCallType = intent.getStringExtra("call_type") ?: "VOICE"
            val userId = userSession.userId
            if (!acceptPeerId.isNullOrBlank() && userId != null) {
                Log.d("SecureChatActivity", "Notification ACCEPT: $acceptPeerId / $acceptCallType")
                incomingCallHandler.dismissIncomingCall()
                callManager.acceptCall(userId)
                pendingCallNavigation.value = Pair(acceptPeerId, acceptCallType)
            }
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
            notifyTelecomOutgoing(peerId, callTypeEnum)
            pendingCallNavigation.value = Pair(peerId, callType)
        }
    }

    /**
     * Telecom Framework'e giden arama bildirimi yapar.
     * Sistem [com.securechat.telecom.SecureChatConnectionService.onCreateOutgoingConnection]
     * çağrılır → bridge `onConnectionCreated` + `startDialing` → state observer ACCEPT
     * geldiğinde `setActive` eder. API 26+ koşulu ConnectionService gereği.
     */
    private fun notifyTelecomOutgoing(peerId: String, callType: com.securechat.network.model.CallType) {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.O) return
        val session = callManager.currentSession ?: return
        lifecycleScope.launch(kotlinx.coroutines.Dispatchers.IO) {
            val peerName = try { contactNameResolver.resolveDisplayName(peerId) } catch (_: Exception) { peerId }
            try {
                phoneAccountRegistrar.get().placeOutgoingCall(
                    callId = session.callId,
                    peerId = peerId,
                    peerName = peerName,
                    isVideo = callType == com.securechat.network.model.CallType.VIDEO
                )
            } catch (e: Exception) {
                Log.w("SecureChatActivity", "Telecom placeOutgoingCall hatasi: ${e.message}")
            }
        }
    }

    override fun onResume() {
        super.onResume()
        IncomingMessageHandler.isAppInForeground = true
        // FCM sistem bildirimlerini temizle — uygulama acikken tekrar gosterilmesin
        getSystemService(android.app.NotificationManager::class.java).cancelAll()
        IncomingMessageHandler.clearNotificationCounts()
        // Uygulama on plana gelince cevrimici bildir
        // NOT: hide degerini her seferinde canli oku — ayar degisince eski deger kalmasin
        val uid = userSession.userId ?: return
        presenceJob?.cancel()
        presenceJob = lifecycleScope.launch {
            signalingClient.connectionState.collect { state ->
                if (state is ConnectionState.Connected) {
                    val hide = !userSession.shareLastSeen
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

    /**
     * Madde 7: Home tusu/Recent tusu ile aktif video aramayi PiP moduna gecir.
     * onUserLeaveHint kullanici home/recents tusuna bastigi anda cagrilir.
     */
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        try {
            val session = callManager.currentSession
            val isVideoActive = session != null &&
                session.callType == com.securechat.network.model.CallType.VIDEO &&
                session.state == com.securechat.media.model.CallState.ACTIVE
            if (isVideoActive && android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                val params = android.app.PictureInPictureParams.Builder()
                    .setAspectRatio(android.util.Rational(9, 16))
                    .build()
                enterPictureInPictureMode(params)
            }
        } catch (e: Exception) {
            Log.w("SecureChat", "PiP gecisi basarisiz: ${e.message}")
        }
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

    /**
     * Pil optimizasyonu muafiyetini kontrol eder ve kullaniciya bir kez sorar.
     * Muafiyet olmadan FCM push mesajlari gecikebilir ve aramalar gec ulasir.
     * Kullanici reddederse bir daha sorulmaz.
     */
    private fun requestBatteryOptimizationExemption() {
        if (!userSession.isLoggedIn) return
        if (!com.securechat.app.util.BatteryOptimizationHelper.shouldPromptOnLaunch(this)) return
        // Sistem dialog'u — tek tap, kullanici Settings'e gitmek zorunda degil
        com.securechat.app.util.BatteryOptimizationHelper.requestExemption(this)
    }
}
