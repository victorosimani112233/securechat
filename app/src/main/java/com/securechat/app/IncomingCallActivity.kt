package com.securechat.app

import android.Manifest
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.core.content.ContextCompat
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Call
import androidx.compose.material.icons.filled.CallEnd
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.securechat.app.data.UserSession
import com.securechat.app.ui.theme.SecureChatTheme
import com.securechat.media.CallManager
import com.securechat.media.IncomingCallHandler
import com.securechat.media.model.CallDirection
import com.securechat.media.model.CallState
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject

/**
 * Kilit ekrani uzerinde gelen aramayi gosteren Activity.
 *
 * Android'in full-screen intent mekanizmasi ile tetiklenir.
 * Ekran kapali/kilitli olsa bile arama ekranini gosterir.
 * Kabul edildiginde SecureChatActivity'ye yonlendirir,
 * reddedildiginde kapanir.
 */
@AndroidEntryPoint
class IncomingCallActivity : ComponentActivity() {

    @Inject lateinit var callManager: CallManager
    @Inject lateinit var userSession: UserSession
    @Inject lateinit var incomingCallHandler: IncomingCallHandler

    /** Arama kabul edilmeden once RECORD_AUDIO izni kontrol edilir ve gerekirse istenir. */
    private fun ensureAudioPermissionAndAccept(userId: String, peerId: String, callType: String) {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO)
            == PackageManager.PERMISSION_GRANTED
        ) {
            doAcceptCall(userId, peerId, callType)
        } else {
            // Izin iste — sonuc donunce kabul et
            pendingAcceptUserId = userId
            pendingAcceptPeerId = peerId
            pendingAcceptCallType = callType
            audioPermissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
        }
    }

    private var pendingAcceptUserId: String? = null
    private var pendingAcceptPeerId: String? = null
    private var pendingAcceptCallType: String? = null

    private val audioPermissionLauncher = registerForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.RequestPermission()
    ) { _ ->
        // Izin verilsin verilmesin aramayi kabul et (ses gitmeyebilir ama UI akisi bozulmasin)
        val uid = pendingAcceptUserId ?: return@registerForActivityResult
        val pid = pendingAcceptPeerId ?: return@registerForActivityResult
        val ct = pendingAcceptCallType ?: "VOICE"
        doAcceptCall(uid, pid, ct)
    }

    private fun doAcceptCall(userId: String, peerId: String, callType: String) {
        incomingCallHandler.dismissIncomingCall()
        callManager.acceptCall(userId)
        val intent = android.content.Intent(this, SecureChatActivity::class.java).apply {
            putExtra("navigate_to_call", peerId)
            putExtra("call_type", callType)
            flags = android.content.Intent.FLAG_ACTIVITY_NEW_TASK or
                android.content.Intent.FLAG_ACTIVITY_CLEAR_TOP or
                android.content.Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        startActivity(intent)
        finish()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Kilit ekrani uzerinde goster, ekrani ac, kilidi bypass et
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as android.app.KeyguardManager

            // Samsung cihazlar için özel fallback mekanizması
            val isSamsungDevice = Build.MANUFACTURER.equals("samsung", ignoreCase = true) ||
                                 Build.BRAND.equals("samsung", ignoreCase = true)

            if (isSamsungDevice) {
                // Samsung'da requestDismissKeyguard bazen başarısız olur
                // Callback ile başarı durumunu track et
                val callback = object : android.app.KeyguardManager.KeyguardDismissCallback() {
                    override fun onDismissError() {
                        super.onDismissError()
                        // Fallback: deprecated flag'leri de kullan
                        @Suppress("DEPRECATION")
                        window.addFlags(
                            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                            WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                            WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
                        )
                    }

                    override fun onDismissCancelled() {
                        super.onDismissCancelled()
                        // Fallback: kullanıcı dismiss'i cancel ettiyse de flag'leri kullan
                        @Suppress("DEPRECATION")
                        window.addFlags(
                            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                            WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                            WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
                        )
                    }
                }
                keyguardManager.requestDismissKeyguard(this, callback)
            } else {
                // Samsung olmayan cihazlarda normal yaklaşım
                keyguardManager.requestDismissKeyguard(this, null)
            }
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
            )
        }
        window.addFlags(
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
            WindowManager.LayoutParams.FLAG_ALLOW_LOCK_WHILE_SCREEN_ON
        )

        val peerId = intent.getStringExtra("peer_id") ?: ""
        val peerName = intent.getStringExtra("peer_name") ?: peerId

        setContent {
            SecureChatTheme {
                val callSession by callManager.callSession.collectAsStateWithLifecycle()
                val secondaryCallEarly by callManager.secondaryIncomingCall.collectAsStateWithLifecycle()

                // BUG FIX: Activity bu peerId icin acildi. Eger peerId secondary slot'taki
                // ise (= aktif baska cagri var), DisposableEffect primary ACTIVE'i gorup
                // otomatik finish() yapmamali. Aktivite SECONDARY cagri icin acik, primary
                // dokunulmaz.
                val activityForSecondary = secondaryCallEarly?.peerId == peerId &&
                    callSession?.peerId != peerId

                // Arama durumu degistiginde Activity'yi kapat
                DisposableEffect(callSession, secondaryCallEarly, activityForSecondary) {
                    if (activityForSecondary) {
                        // Secondary cagri icin acik — primary state degisikliklerini ignore.
                        // Sadece secondary cagrinin durumu bittiyse kapat.
                        val secState = secondaryCallEarly?.state
                        if (secondaryCallEarly == null ||
                            secState == CallState.ENDED ||
                            secState == CallState.REJECTED ||
                            secState == CallState.FAILED ||
                            secState == CallState.BUSY
                        ) {
                            finish()
                        }
                    } else {
                        val session = callSession
                        if (session == null ||
                            session.state == CallState.ENDED ||
                            session.state == CallState.REJECTED ||
                            session.state == CallState.FAILED ||
                            session.state == CallState.BUSY
                        ) {
                            finish()
                        }
                        if (session != null && session.state == CallState.ACTIVE) {
                            finish()
                        }
                    }
                    onDispose { }
                }

                val isSecondary = activityForSecondary

                IncomingCallScreen(
                    peerName = peerName,
                    onAccept = {
                        val userId = userSession.userId ?: return@IncomingCallScreen
                        if (isSecondary) {
                            // Secondary kabul: mevcut aktif cagri kapatilir, ikincil aktif olur.
                            // CallManager.acceptSecondaryCall bu swap'i ele alir.
                            incomingCallHandler.dismissIncomingCall()
                            callManager.acceptSecondaryCall(userId)
                            // CallScreen aktif cagrida zaten acik; finish() yeterli.
                            finish()
                        } else {
                            val callType = callSession?.callType?.name ?: "VOICE"
                            ensureAudioPermissionAndAccept(userId, peerId, callType)
                        }
                    },
                    onReject = {
                        val userId = userSession.userId ?: return@IncomingCallScreen
                        incomingCallHandler.dismissIncomingCall()
                        if (isSecondary) {
                            // SADECE ikincil cagriyi reddet — primary aktif cagri DOKUNULMAZ.
                            callManager.rejectSecondaryCall(userId)
                        } else {
                            callManager.rejectCall(userId)
                        }
                        finish()
                    }
                )
            }
        }
    }

    /**
     * Kullanici activity'i swipe/back/sistem ile kapatirsa zil sesi takilmasin.
     * Eger session hala RINGING ise (yani kabul/reddet akisi tamamlanmadiysa)
     * zorla reject ile temizlik tetiklenir — bu sayede #13 hayalet arama,
     * "ekranda UI yok ama ses caliyor" durumu engellenir.
     */
    override fun onDestroy() {
        super.onDestroy()
        if (isFinishing) {
            // BUG FIX: Aktif primary cagri + secondary ringing varsa, activity swipe ile
            // kapanmasi primary'i sonlandirmamali. Once secondary slot'a bak.
            val secondary = callManager.secondaryIncomingCall.value
            val userId = userSession.userId
            if (userId == null) return

            if (secondary != null && secondary.state == com.securechat.media.model.CallState.RINGING) {
                // Activity secondary cagri icin acilmisti → sadece secondary'yi temizle.
                incomingCallHandler.dismissIncomingCall()
                callManager.rejectSecondaryCall(userId)
                return
            }

            val session = callManager.currentSession
            if (session != null && session.state == com.securechat.media.model.CallState.RINGING &&
                session.direction == com.securechat.media.model.CallDirection.INCOMING) {
                incomingCallHandler.dismissIncomingCall()
                callManager.rejectCall(userId)
            }
        }
    }
}

/**
 * Gelen arama ekrani UI'i.
 * Koyu arka plan uzerinde arayan ismi, "Gelen Arama" yazisi,
 * yesil kabul ve kirmizi red butonlari gosterir.
 */
@Composable
private fun IncomingCallScreen(
    peerName: String,
    onAccept: () -> Unit,
    onReject: () -> Unit
) {
    val infiniteTransition = rememberInfiniteTransition(label = "pulse")
    val pulse by infiniteTransition.animateFloat(
        initialValue = 1f,
        targetValue = 1.15f,
        animationSpec = infiniteRepeatable(
            animation = tween(800, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "pulse"
    )

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFF0A0F18)),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
            modifier = Modifier.fillMaxWidth()
        ) {
            // Avatar placeholder
            Box(
                modifier = Modifier
                    .size(100.dp)
                    .background(Color(0xFF1E293B), CircleShape),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Default.Person,
                    contentDescription = null,
                    tint = Color(0xFF64748B),
                    modifier = Modifier.size(56.dp)
                )
            }

            Spacer(modifier = Modifier.height(24.dp))

            // Arayan ismi
            Text(
                text = peerName,
                color = Color.White,
                fontSize = 28.sp,
                fontWeight = FontWeight.Bold
            )

            Spacer(modifier = Modifier.height(8.dp))

            // Alt baslik
            Text(
                text = "Gelen Arama",
                color = Color(0xFF94A3B8),
                fontSize = 16.sp
            )

            Spacer(modifier = Modifier.height(80.dp))

            // Kabul / Reddet butonlari
            Row(
                horizontalArrangement = Arrangement.SpaceEvenly,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 48.dp)
            ) {
                // Reddet butonu
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    FilledIconButton(
                        onClick = onReject,
                        modifier = Modifier.size(64.dp),
                        shape = CircleShape,
                        colors = IconButtonDefaults.filledIconButtonColors(
                            containerColor = Color(0xFFEF4444)
                        )
                    ) {
                        Icon(
                            imageVector = Icons.Default.CallEnd,
                            contentDescription = "Reddet",
                            tint = Color.White,
                            modifier = Modifier.size(32.dp)
                        )
                    }
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        text = "Reddet",
                        color = Color(0xFF94A3B8),
                        fontSize = 14.sp
                    )
                }

                // Kabul butonu (nabiz animasyonu)
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    FilledIconButton(
                        onClick = onAccept,
                        modifier = Modifier
                            .size(64.dp)
                            .scale(pulse),
                        shape = CircleShape,
                        colors = IconButtonDefaults.filledIconButtonColors(
                            containerColor = Color(0xFF22C55E)
                        )
                    ) {
                        Icon(
                            imageVector = Icons.Default.Call,
                            contentDescription = "Kabul Et",
                            tint = Color.White,
                            modifier = Modifier.size(32.dp)
                        )
                    }
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        text = "Kabul Et",
                        color = Color(0xFF94A3B8),
                        fontSize = 14.sp
                    )
                }
            }
        }
    }
}
