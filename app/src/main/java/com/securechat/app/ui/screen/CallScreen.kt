package com.securechat.app.ui.screen

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.util.Log
import android.view.WindowManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.EaseInOut
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Call
import androidx.compose.material.icons.filled.CallEnd
import androidx.compose.material.icons.filled.Cameraswitch
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MicOff
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material.icons.filled.VideocamOff
import androidx.compose.material.icons.automirrored.filled.VolumeOff
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.securechat.app.ui.viewmodel.CallViewModel
import com.securechat.app.util.TimeFormatter
import com.securechat.media.model.CallDirection
import com.securechat.media.model.CallState
import com.securechat.network.model.CallType
import kotlinx.coroutines.delay
import org.webrtc.EglBase
import org.webrtc.RendererCommon
import org.webrtc.SurfaceViewRenderer
import org.webrtc.VideoTrack
import kotlin.math.abs
import kotlin.math.sin
import kotlin.random.Random

/**
 * Arama ekrani.
 * Premium animasyonlarla zenginlestirilmis: animasyonlu gradient arka plan,
 * yuzen parcacik efekti, gelistirilmis avatar animasyonlari, yumusak buton gecisleri.
 *
 * Midnight Teal tasarim: koyu lacivert-siyah gradient, cyan vurgular.
 *
 * Arama ekrani acildiginda RECORD_AUDIO izni kontrol edilir ve gerekirse istenir.
 * Hem arayan hem de aranan tarafin bu izne ihtiyaci vardir.
 */
@Composable
fun CallScreen(
    peerId: String,
    callType: CallType,
    viewModel: CallViewModel = hiltViewModel(),
    onCallEnded: () -> Unit
) {
    val context = LocalContext.current
    val callSession by viewModel.callState.collectAsStateWithLifecycle()
    val callDuration by viewModel.callDuration.collectAsStateWithLifecycle()

    // RECORD_AUDIO runtime izin istegi
    val recordAudioPermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) {
            Log.d("CallScreen", "RECORD_AUDIO izni verildi")
        } else {
            Log.w("CallScreen", "RECORD_AUDIO izni reddedildi, ses gonderilemeyecek")
        }
    }

    // CAMERA izni (video aramalar icin)
    val cameraPermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        Log.d("CallScreen", "CAMERA izni: $granted")
    }

    // Izinleri iste
    LaunchedEffect(Unit) {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO)
            != PackageManager.PERMISSION_GRANTED
        ) {
            recordAudioPermissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
        }
        if (callType == CallType.VIDEO &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA)
            != PackageManager.PERMISSION_GRANTED
        ) {
            cameraPermissionLauncher.launch(Manifest.permission.CAMERA)
        }
    }

    // Arama sonlaninca geri don — her iki taraf icin de calisir
    LaunchedEffect(callSession?.state) {
        val state = callSession?.state
        if (state == CallState.ENDED || state == CallState.FAILED) {
            delay(1500)
            onCallEnded()
        }
    }

    // Session null olursa da ekrani kapat (cleanupCall sonrasi)
    var callWasActive by remember { mutableStateOf(false) }
    LaunchedEffect(callSession?.state) {
        if (callSession != null) callWasActive = true
    }
    LaunchedEffect(callSession) {
        if (callSession == null && callWasActive) {
            delay(300)
            onCallEnded()
        }
    }

    val isIncomingRinging = callSession?.direction == CallDirection.INCOMING
        && callSession?.state == CallState.RINGING
    val isRinging = callSession?.state == CallState.RINGING
        || callSession?.state == CallState.INITIATING
    val isActive = callSession?.state == CallState.ACTIVE
    val isConnecting = callSession?.state == CallState.CONNECTING

    // Video track'leri — SurfaceViewRenderer'a baglanir
    val remoteVideoTrack by viewModel.remoteVideoTrack.collectAsStateWithLifecycle()
    val localVideoTrack by viewModel.localVideoTrack.collectAsStateWithLifecycle()
    val remoteVideoTracks by viewModel.remoteVideoTracks.collectAsStateWithLifecycle()
    val eglBaseContext = viewModel.eglBaseContext
    val isGroupCall = callSession?.isGroupCall == true
    val isVideoActive = callType == CallType.VIDEO && callSession?.state == CallState.ACTIVE
    val remoteCameraEnabled by viewModel.remoteCameraEnabled.collectAsStateWithLifecycle()

    // --- [1] Ekrani uyku moduna gecirmesini engelle (video arama aktifken) ---
    if (isVideoActive) {
        val activity = context as? Activity
        DisposableEffect(Unit) {
            activity?.window?.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            onDispose {
                activity?.window?.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            }
        }
    }

    // --- [2] Video aktifken kontrolleri otomatik gizle (3 saniye sonra) ---
    var controlsVisible by remember { mutableStateOf(true) }
    // Sayac her dokunusta arttirilir, LaunchedEffect yeniden tetiklenir
    var controlsResetCounter by remember { mutableIntStateOf(0) }

    // Video aktifken 3 saniye sonra kontrolleri gizle
    LaunchedEffect(controlsResetCounter, isVideoActive) {
        if (isVideoActive && controlsVisible) {
            delay(3000)
            controlsVisible = false
        }
    }

    // Video aktif degilken kontroller her zaman gorunur
    LaunchedEffect(isVideoActive) {
        if (!isVideoActive) {
            controlsVisible = true
        }
    }

    // --- [5] PIP dokunarak video gorunumlerini degistir ---
    var isVideoSwapped by remember { mutableStateOf(false) }

    // Buyuk gorunumde gosterilecek track (normal: remote, swap: local)
    val mainVideoTrack = if (isVideoSwapped) localVideoTrack else remoteVideoTrack
    // PIP gorunumde gosterilecek track (normal: local, swap: remote)
    val pipVideoTrack = if (isVideoSwapped) remoteVideoTrack else localVideoTrack

    Box(
        modifier = Modifier
            .fillMaxSize()
            .then(
                if (isVideoActive) {
                    Modifier.pointerInput(Unit) {
                        detectTapGestures {
                            controlsVisible = true
                            controlsResetCounter++
                        }
                    }
                } else {
                    Modifier
                }
            )
    ) {
        // --- Animasyonlu gradient arka plan ---
        AnimatedGradientBackground(
            isRinging = isRinging,
            isActive = isActive
        )

        // --- Yuzen parcacik efekti ---
        FloatingParticles()

        // Video arama aktifse: grup video grid VEYA 1-to-1 tam ekran video
        if (isVideoActive && eglBaseContext != null) {
            if (isGroupCall && remoteVideoTracks.isNotEmpty()) {
                // Grup video: Grid layout
                GroupVideoGrid(
                    remoteVideoTracks = remoteVideoTracks,
                    localVideoTrack = localVideoTrack,
                    eglBaseContext = eglBaseContext!!
                )
            } else if (!isGroupCall) {
                // 1-to-1 video: Tam ekran
                val currentMainTrack = remember { mutableStateOf<VideoTrack?>(null) }
                val currentMainMirror = remember { mutableStateOf(false) }

                if (mainVideoTrack != null) {
                    AndroidView(
                        factory = { ctx ->
                            SurfaceViewRenderer(ctx).apply {
                                init(eglBaseContext, null)
                                setScalingType(RendererCommon.ScalingType.SCALE_ASPECT_FILL)
                                setEnableHardwareScaler(true)
                                setMirror(isVideoSwapped)
                                currentMainMirror.value = isVideoSwapped
                            }
                        },
                        update = { renderer ->
                            if (currentMainMirror.value != isVideoSwapped) {
                                renderer.setMirror(isVideoSwapped)
                                currentMainMirror.value = isVideoSwapped
                            }
                            val prevTrack = currentMainTrack.value
                            val newTrack = mainVideoTrack
                            if (prevTrack != newTrack) {
                                prevTrack?.removeSink(renderer)
                                newTrack?.addSink(renderer)
                                currentMainTrack.value = newTrack
                            }
                        },
                        onRelease = { renderer ->
                            currentMainTrack.value?.removeSink(renderer)
                            currentMainTrack.value = null
                            renderer.release()
                        },
                        modifier = Modifier.fillMaxSize()
                    )
                }
            }
        }

        // --- Karsi taraf kamerasini kapattiysa overlay ---
        if (isVideoActive && !remoteCameraEnabled) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color(0xDD3A3A3A)),
                contentAlignment = Alignment.Center
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(
                        imageVector = Icons.Default.VideocamOff,
                        contentDescription = null,
                        modifier = Modifier.size(64.dp),
                        tint = Color.White.copy(alpha = 0.6f)
                    )
                    Spacer(modifier = Modifier.height(16.dp))
                    Text(
                        text = "Karsi kullanici kamerasini duraklatti",
                        style = MaterialTheme.typography.bodyLarge,
                        color = Color.White.copy(alpha = 0.8f),
                        textAlign = TextAlign.Center
                    )
                }
            }
        }

        // --- [3] Video aktifken sure pill badge (sol ust kose) — her zaman gorunur ---
        if (isVideoActive) {
            Text(
                text = getCallStateText(callSession?.state, callDuration),
                style = MaterialTheme.typography.bodyMedium,
                color = Color.White.copy(alpha = 0.9f),
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .padding(start = 16.dp, top = 16.dp)
                    .background(
                        Color.Black.copy(alpha = 0.5f),
                        shape = androidx.compose.foundation.shape.RoundedCornerShape(16.dp)
                    )
                    .padding(horizontal = 14.dp, vertical = 6.dp)
            )
        }

        // Arama bilgisi ve kontroller — video aktifken AnimatedVisibility ile gizlenebilir
        AnimatedVisibility(
            visible = if (isVideoActive) controlsVisible else true,
            enter = fadeIn(animationSpec = tween(300)),
            exit = fadeOut(animationSpec = tween(300))
        ) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = 24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.SpaceBetween
            ) {
                // Ust kisim: sifreleme gostergesi ve avatar — yalnizca video aktif DEGILSE goster
                if (!isVideoActive) {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        modifier = Modifier.padding(top = 48.dp)
                    ) {
                        // Sifreleme gostergesi
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.Center
                        ) {
                            Icon(
                                imageVector = Icons.Default.Lock,
                                contentDescription = null,
                                modifier = Modifier.size(12.dp),
                                tint = Color(0xFF2979FF).copy(alpha = 0.6f)
                            )
                            Spacer(modifier = Modifier.width(4.dp))
                            Text(
                                text = "Uctan uca sifreli",
                                style = MaterialTheme.typography.labelSmall,
                                color = Color(0xFF2979FF).copy(alpha = 0.6f),
                                fontSize = 11.sp
                            )
                        }

                        Spacer(modifier = Modifier.height(40.dp))

                        // Avatar — premium animasyonlu
                        CallAvatar(
                            name = peerId,
                            isRinging = isRinging,
                            isConnecting = isConnecting,
                            isActive = isActive
                        )

                        Spacer(modifier = Modifier.height(24.dp))

                        // Peer ismi veya grup bilgisi
                        if (isGroupCall) {
                            Text(
                                text = "Grup Arama",
                                style = MaterialTheme.typography.headlineMedium,
                                color = Color.White,
                                fontWeight = FontWeight.SemiBold,
                                textAlign = TextAlign.Center
                            )
                            val connectedCount = callSession?.connectedPeerIds?.size ?: 0
                            val totalCount = callSession?.peerIds?.size ?: 0
                            Text(
                                text = "$connectedCount / $totalCount katilimci",
                                style = MaterialTheme.typography.bodyMedium,
                                color = Color(0xFF2979FF).copy(alpha = 0.8f),
                                textAlign = TextAlign.Center
                            )
                        } else {
                            Text(
                                text = peerId,
                                style = MaterialTheme.typography.headlineMedium,
                                color = Color.White,
                                fontWeight = FontWeight.SemiBold,
                                textAlign = TextAlign.Center
                            )
                        }

                        Spacer(modifier = Modifier.height(8.dp))

                        // Arama tipi ikonu ve durum
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.Center
                        ) {
                            Icon(
                                imageVector = if (callType == CallType.VIDEO) Icons.Default.Videocam else Icons.Default.Phone,
                                contentDescription = null,
                                modifier = Modifier.size(16.dp),
                                tint = Color.White.copy(alpha = 0.6f)
                            )
                            Spacer(modifier = Modifier.width(6.dp))

                            if (isRinging || callSession?.state == CallState.INITIATING) {
                                AnimatedCallStateText(
                                    text = getCallStateText(callSession?.state, callDuration)
                                )
                            } else if (isActive) {
                                AnimatedDurationText(
                                    text = getCallStateText(callSession?.state, callDuration)
                                )
                            } else {
                                Text(
                                    text = getCallStateText(callSession?.state, callDuration),
                                    style = MaterialTheme.typography.bodyLarge,
                                    color = Color.White.copy(alpha = 0.7f)
                                )
                            }
                        }
                    }
                } else {
                    // Video aktifken ust kisimda bosluk birak (sure pill ayri gosteriliyor)
                    Spacer(modifier = Modifier.height(48.dp))
                }

                // Alt kisim: kontrol butonlari
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier.padding(bottom = 40.dp)
                ) {
                    if (isIncomingRinging) {
                        // Gelen arama: Kabul / Reddet butonlari
                        IncomingCallControls(
                            onAccept = { viewModel.acceptCall() },
                            onReject = { viewModel.endCall() }
                        )
                    } else {
                        CallControls(
                            isMuted = callSession?.isMuted ?: false,
                            isSpeakerOn = callSession?.isSpeakerOn ?: false,
                            isCameraEnabled = callSession?.isCameraEnabled ?: true,
                            isVideoCall = callType == CallType.VIDEO,
                            onToggleMute = { viewModel.toggleMute() },
                            onToggleSpeaker = { viewModel.toggleSpeaker() },
                            onToggleCamera = { viewModel.toggleCamera() },
                            onSwitchCamera = { viewModel.switchCamera() },
                            onEndCall = { viewModel.endCall() }
                        )
                    }
                }
            }
        }

        // --- [5] PIP gorunumu — dokunarak swap (sadece 1-to-1 video) ---
        if (isVideoActive && !isGroupCall && eglBaseContext != null) {
            val currentPipTrack = remember { mutableStateOf<VideoTrack?>(null) }
            val currentPipMirror = remember { mutableStateOf(true) }

            if (pipVideoTrack != null) {
                Box(
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .padding(top = 48.dp, end = 16.dp)
                        .size(width = 100.dp, height = 140.dp)
                        .clip(androidx.compose.foundation.shape.RoundedCornerShape(12.dp))
                        .border(
                            width = 2.dp,
                            color = Color(0xFF2979FF).copy(alpha = 0.6f),
                            shape = androidx.compose.foundation.shape.RoundedCornerShape(12.dp)
                        )
                        .pointerInput(Unit) {
                            detectTapGestures {
                                isVideoSwapped = !isVideoSwapped
                            }
                        }
                ) {
                    AndroidView(
                        factory = { ctx ->
                            SurfaceViewRenderer(ctx).apply {
                                init(eglBaseContext, null)
                                setScalingType(RendererCommon.ScalingType.SCALE_ASPECT_FILL)
                                setEnableHardwareScaler(true)
                                setMirror(!isVideoSwapped)
                                currentPipMirror.value = !isVideoSwapped
                                setZOrderMediaOverlay(true)
                            }
                        },
                        update = { renderer ->
                            // Mirror durumu degistiyse guncelle
                            val newMirror = !isVideoSwapped
                            if (currentPipMirror.value != newMirror) {
                                renderer.setMirror(newMirror)
                                currentPipMirror.value = newMirror
                            }
                            // Sadece track degistiyse sink'i guncelle
                            val prevTrack = currentPipTrack.value
                            val newTrack = pipVideoTrack
                            if (prevTrack != newTrack) {
                                prevTrack?.removeSink(renderer)
                                newTrack?.addSink(renderer)
                                currentPipTrack.value = newTrack
                            }
                        },
                        onRelease = { renderer ->
                            currentPipTrack.value?.removeSink(renderer)
                            currentPipTrack.value = null
                            renderer.release()
                        },
                        modifier = Modifier.fillMaxSize()
                    )
                }
            }
        }
    }
}

// =====================================================================
// Grup Video Grid
// =====================================================================

/**
 * Grup aramasinda birden fazla remote video track'i grid olarak gosterir.
 * 2 kisi: yan yana, 3-4: 2x2, 5-6: 3x2, 7+: 4x2.
 * Yerel video her zaman sag alt kosede kucuk PIP olarak gosterilir.
 */
@Composable
private fun GroupVideoGrid(
    remoteVideoTracks: Map<String, VideoTrack>,
    localVideoTrack: VideoTrack?,
    eglBaseContext: EglBase.Context
) {
    val trackList = remoteVideoTracks.entries.toList()
    val columns = when {
        trackList.size <= 2 -> 1
        trackList.size <= 4 -> 2
        else -> 2
    }
    val rows = (trackList.size + columns - 1) / columns

    Box(modifier = Modifier.fillMaxSize()) {
        Column(modifier = Modifier.fillMaxSize()) {
            for (row in 0 until rows) {
                Row(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth()
                ) {
                    for (col in 0 until columns) {
                        val index = row * columns + col
                        if (index < trackList.size) {
                            val (peerId, track) = trackList[index]
                            GroupVideoCell(
                                peerId = peerId,
                                videoTrack = track,
                                eglBaseContext = eglBaseContext,
                                modifier = Modifier
                                    .weight(1f)
                                    .padding(1.dp)
                            )
                        } else {
                            Spacer(modifier = Modifier.weight(1f))
                        }
                    }
                }
            }
        }

        // Yerel video PIP — sag alt kose
        if (localVideoTrack != null) {
            val currentLocalTrack = remember { mutableStateOf<VideoTrack?>(null) }
            Box(
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .padding(bottom = 100.dp, end = 12.dp)
                    .size(width = 90.dp, height = 120.dp)
                    .clip(androidx.compose.foundation.shape.RoundedCornerShape(12.dp))
                    .border(
                        width = 2.dp,
                        color = Color(0xFF2979FF).copy(alpha = 0.6f),
                        shape = androidx.compose.foundation.shape.RoundedCornerShape(12.dp)
                    )
            ) {
                AndroidView(
                    factory = { ctx ->
                        SurfaceViewRenderer(ctx).apply {
                            init(eglBaseContext, null)
                            setScalingType(RendererCommon.ScalingType.SCALE_ASPECT_FILL)
                            setEnableHardwareScaler(true)
                            setMirror(true)
                            setZOrderMediaOverlay(true)
                        }
                    },
                    update = { renderer ->
                        val prev = currentLocalTrack.value
                        val next = localVideoTrack
                        if (prev != next) {
                            prev?.removeSink(renderer)
                            next?.addSink(renderer)
                            currentLocalTrack.value = next
                        }
                    },
                    onRelease = { renderer ->
                        currentLocalTrack.value?.removeSink(renderer)
                        currentLocalTrack.value = null
                        renderer.release()
                    },
                    modifier = Modifier.fillMaxSize()
                )
            }
        }
    }
}

/**
 * Tek bir grup video hucresini render eder.
 */
@Composable
private fun GroupVideoCell(
    peerId: String,
    videoTrack: VideoTrack,
    eglBaseContext: EglBase.Context,
    modifier: Modifier = Modifier
) {
    val currentTrack = remember { mutableStateOf<VideoTrack?>(null) }

    Box(modifier = modifier) {
        AndroidView(
            factory = { ctx ->
                SurfaceViewRenderer(ctx).apply {
                    init(eglBaseContext, null)
                    setScalingType(RendererCommon.ScalingType.SCALE_ASPECT_FILL)
                    setEnableHardwareScaler(true)
                    setMirror(false)
                }
            },
            update = { renderer ->
                val prev = currentTrack.value
                if (prev != videoTrack) {
                    prev?.removeSink(renderer)
                    videoTrack.addSink(renderer)
                    currentTrack.value = videoTrack
                }
            },
            onRelease = { renderer ->
                currentTrack.value?.removeSink(renderer)
                currentTrack.value = null
                renderer.release()
            },
            modifier = Modifier.fillMaxSize()
        )

        // Peer ID etiketi (sol alt kose)
        Text(
            text = peerId.take(8),
            style = MaterialTheme.typography.labelSmall,
            color = Color.White,
            modifier = Modifier
                .align(Alignment.BottomStart)
                .padding(4.dp)
                .background(
                    Color.Black.copy(alpha = 0.5f),
                    shape = androidx.compose.foundation.shape.RoundedCornerShape(4.dp)
                )
                .padding(horizontal = 6.dp, vertical = 2.dp)
        )
    }
}

// =====================================================================
// Animasyonlu Gradient Arka Plan
// =====================================================================

/**
 * Aurora borealis efektli, yavasca renk degistiren gradient arka plan.
 * Calma durumunda derin mavi tonlari; aktif durumda hafif nabizli koyu arka plan.
 */
@Composable
private fun AnimatedGradientBackground(
    isRinging: Boolean,
    isActive: Boolean
) {
    val infiniteTransition = rememberInfiniteTransition(label = "bgGradient")

    // 4 renk duragi icin animasyonlu pozisyonlar
    val colorShift1 by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(8000, easing = EaseInOut),
            repeatMode = RepeatMode.Reverse
        ),
        label = "colorShift1"
    )
    val colorShift2 by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(6000, easing = EaseInOut),
            repeatMode = RepeatMode.Reverse
        ),
        label = "colorShift2"
    )
    val colorShift3 by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(10000, easing = EaseInOut),
            repeatMode = RepeatMode.Reverse
        ),
        label = "colorShift3"
    )

    // Aktif durumda hafif parlaklik nabzi
    val activePulse by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(3000, easing = EaseInOut),
            repeatMode = RepeatMode.Reverse
        ),
        label = "activePulse"
    )

    Canvas(modifier = Modifier.fillMaxSize()) {
        val w = size.width
        val h = size.height

        if (isRinging) {
            // Aurora efekti — renk duraklari pozisyon degistirir
            val c1 = lerpColor(Color(0xFF0A1628), Color(0xFF0D2137), colorShift1)
            val c2 = lerpColor(Color(0xFF0D1B2A), Color(0xFF122A4A), colorShift2)
            val c3 = lerpColor(Color(0xFF091420), Color(0xFF0F2035), colorShift3)
            val c4 = lerpColor(Color(0xFF050A0F), Color(0xFF081218), colorShift1)

            drawRect(
                brush = Brush.verticalGradient(
                    colorStops = arrayOf(
                        0f to c1,
                        (0.3f + colorShift2 * 0.1f) to c2,
                        (0.6f + colorShift3 * 0.1f) to c3,
                        1f to c4
                    )
                )
            )
            // Yatay aurora isiklari
            drawRect(
                brush = Brush.horizontalGradient(
                    colorStops = arrayOf(
                        0f to Color.Transparent,
                        (0.2f + colorShift1 * 0.3f) to Color(0xFF2979FF).copy(
                            alpha = 0.03f + colorShift2 * 0.02f
                        ),
                        (0.5f + colorShift3 * 0.2f) to Color(0xFF448AFF).copy(
                            alpha = 0.02f + colorShift1 * 0.02f
                        ),
                        1f to Color.Transparent
                    )
                )
            )
        } else if (isActive) {
            // Aktif arama: hafif nabizli koyu arka plan
            val pulseAlpha = 0.02f + activePulse * 0.015f
            val c1 = Color(0xFF0D1B2A)
            val c2 = lerpColor(Color(0xFF091420), Color(0xFF0C1825), activePulse)
            val c3 = Color(0xFF050A0F)

            drawRect(
                brush = Brush.verticalGradient(
                    colors = listOf(c1, c2, c3)
                )
            )
            // Ince mavi glow ust orta
            drawCircle(
                color = Color(0xFF2979FF).copy(alpha = pulseAlpha),
                radius = w * 0.6f,
                center = Offset(w * 0.5f, h * 0.15f)
            )
        } else {
            // Varsayilan statik gradient
            drawRect(
                brush = Brush.verticalGradient(
                    colors = listOf(
                        Color(0xFF0D1B2A),
                        Color(0xFF091420),
                        Color(0xFF050A0F)
                    )
                )
            )
        }
    }
}

/**
 * Iki renk arasinda lineer interpolasyon.
 */
private fun lerpColor(start: Color, end: Color, fraction: Float): Color {
    return Color(
        red = start.red + (end.red - start.red) * fraction,
        green = start.green + (end.green - start.green) * fraction,
        blue = start.blue + (end.blue - start.blue) * fraction,
        alpha = start.alpha + (end.alpha - start.alpha) * fraction
    )
}

// =====================================================================
// Yuzen Parcacik Efekti (Bokeh / Atesboceği)
// =====================================================================

/**
 * Parcacik verisi: konum, boyut, hiz, faz gibi degerler.
 */
private data class Particle(
    val xFraction: Float,   // Yatay konum orani (0-1)
    val startY: Float,      // Baslangic Y orani (0-1)
    val sizeDp: Float,      // Parcacik boyutu (2-6)
    val speed: Float,       // Yukari kayma hizi (animasyon suresi carpani)
    val phase: Float,       // Faz farki (0-1)
    val color: Color        // Parcacik rengi
)

/**
 * Arkaplanda yukari suruklenen, parlayan kucuk noktalar.
 * 10 parcacik, her biri farkli hiz ve pozisyonda.
 */
@Composable
private fun FloatingParticles() {
    val particles = remember {
        val rng = Random(42) // Sabit seed ile deterministik
        val colors = listOf(
            Color(0xFF2979FF),
            Color(0xFF448AFF),
            Color(0xFF2979FF),
            Color(0xFF448AFF)
        )
        List(10) {
            Particle(
                xFraction = rng.nextFloat(),
                startY = rng.nextFloat(),
                sizeDp = 2f + rng.nextFloat() * 4f,
                speed = 0.6f + rng.nextFloat() * 0.8f,
                phase = rng.nextFloat(),
                color = colors[rng.nextInt(colors.size)]
            )
        }
    }

    val infiniteTransition = rememberInfiniteTransition(label = "particles")

    // Her parcacik icin tek bir master animasyon — faz farki ile ayrilir
    val masterProgress by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(12000, easing = LinearEasing),
            repeatMode = RepeatMode.Restart
        ),
        label = "masterParticle"
    )

    Canvas(modifier = Modifier.fillMaxSize()) {
        val w = size.width
        val h = size.height

        particles.forEach { p ->
            // Her parcacigin kendi ilerlemesi (faz farkli)
            val rawProgress = (masterProgress / p.speed + p.phase) % 1f

            // Y pozisyonu: asagidan yukariya kayma
            val y = h * (1f - rawProgress)

            // X pozisyonu: hafif yatay sallanma
            val xWobble = sin(rawProgress * 6.28f * 2f + p.phase * 6.28f).toFloat() * w * 0.02f
            val x = w * p.xFraction + xWobble

            // Alpha: ortada en parlak, kenarlarda soluk (fade in/out)
            val alpha = if (rawProgress < 0.15f) {
                rawProgress / 0.15f
            } else if (rawProgress > 0.85f) {
                (1f - rawProgress) / 0.15f
            } else {
                1f
            } * 0.25f // Genel dusuk opasite

            drawCircle(
                color = p.color.copy(alpha = alpha),
                radius = p.sizeDp,
                center = Offset(x, y)
            )
            // Glow efekti (buyuk, daha saydam cember)
            drawCircle(
                color = p.color.copy(alpha = alpha * 0.3f),
                radius = p.sizeDp * 2.5f,
                center = Offset(x, y)
            )
        }
    }
}

// =====================================================================
// Gelistirilmis Avatar
// =====================================================================

/**
 * Premium animasyonlu avatar.
 * - Calma durumu: 3 kademeli genisleyen halkalar + yumusak glow golge
 * - Aktif durum: nefes olceklendirmesi + donen gradient border
 * - Baglanma durumu: hizli donen ince halka
 */
@Composable
private fun CallAvatar(
    name: String,
    isRinging: Boolean,
    isConnecting: Boolean,
    isActive: Boolean
) {
    val infiniteTransition = rememberInfiniteTransition(label = "avatarPremium")

    // --- Calma durumu: 3 kademeli halka ---
    val pulse1 by infiniteTransition.animateFloat(
        initialValue = 1f, targetValue = 1.7f,
        animationSpec = infiniteRepeatable(
            tween(2200, easing = FastOutSlowInEasing), RepeatMode.Restart
        ),
        label = "p1"
    )
    val alpha1 by infiniteTransition.animateFloat(
        initialValue = 0.5f, targetValue = 0f,
        animationSpec = infiniteRepeatable(
            tween(2200, easing = FastOutSlowInEasing), RepeatMode.Restart
        ),
        label = "a1"
    )
    val pulse2 by infiniteTransition.animateFloat(
        initialValue = 1f, targetValue = 1.9f,
        animationSpec = infiniteRepeatable(
            tween(2200, delayMillis = 700, easing = FastOutSlowInEasing), RepeatMode.Restart
        ),
        label = "p2"
    )
    val alpha2 by infiniteTransition.animateFloat(
        initialValue = 0.35f, targetValue = 0f,
        animationSpec = infiniteRepeatable(
            tween(2200, delayMillis = 700, easing = FastOutSlowInEasing), RepeatMode.Restart
        ),
        label = "a2"
    )
    val pulse3 by infiniteTransition.animateFloat(
        initialValue = 1f, targetValue = 2.1f,
        animationSpec = infiniteRepeatable(
            tween(2200, delayMillis = 1400, easing = FastOutSlowInEasing), RepeatMode.Restart
        ),
        label = "p3"
    )
    val alpha3 by infiniteTransition.animateFloat(
        initialValue = 0.2f, targetValue = 0f,
        animationSpec = infiniteRepeatable(
            tween(2200, delayMillis = 1400, easing = FastOutSlowInEasing), RepeatMode.Restart
        ),
        label = "a3"
    )

    // --- Aktif durum: nefes efekti + donen gradient border ---
    val breathScale by infiniteTransition.animateFloat(
        initialValue = 1f, targetValue = 1.04f,
        animationSpec = infiniteRepeatable(tween(2500, easing = EaseInOut), RepeatMode.Reverse),
        label = "breath"
    )
    val borderRotation by infiniteTransition.animateFloat(
        initialValue = 0f, targetValue = 360f,
        animationSpec = infiniteRepeatable(tween(4000, easing = LinearEasing), RepeatMode.Restart),
        label = "borderRot"
    )

    // --- Baglanma durumu: hizli donen ince halka ---
    val connectSpin by infiniteTransition.animateFloat(
        initialValue = 0f, targetValue = 360f,
        animationSpec = infiniteRepeatable(tween(1200, easing = LinearEasing), RepeatMode.Restart),
        label = "connectSpin"
    )

    // Glow nabzi (calma durumu icin)
    val glowPulse by infiniteTransition.animateFloat(
        initialValue = 0.3f, targetValue = 0.7f,
        animationSpec = infiniteRepeatable(tween(1800, easing = EaseInOut), RepeatMode.Reverse),
        label = "glowPulse"
    )

    val avatarGradient = callAvatarGradient(name)
    val avatarScale = if (isActive) breathScale else 1f

    Box(contentAlignment = Alignment.Center) {
        // Glow golge (calma ve aktif durumda)
        if (isRinging || isActive) {
            Box(
                modifier = Modifier
                    .size(160.dp)
                    .drawBehind {
                        drawCircle(
                            color = Color(0xFF2979FF).copy(
                                alpha = if (isRinging) glowPulse * 0.15f else 0.08f
                            ),
                            radius = size.minDimension / 2
                        )
                    }
            )
        }

        // Dalga halkalari (calma durumunda)
        if (isRinging) {
            Box(modifier = Modifier.size(130.dp).scale(pulse3).alpha(alpha3).clip(CircleShape)
                .background(Color(0xFF2979FF).copy(alpha = 0.08f)))
            Box(modifier = Modifier.size(130.dp).scale(pulse2).alpha(alpha2).clip(CircleShape)
                .background(Color(0xFF2979FF).copy(alpha = 0.12f)))
            Box(modifier = Modifier.size(130.dp).scale(pulse1).alpha(alpha1).clip(CircleShape)
                .background(Color(0xFF2979FF).copy(alpha = 0.18f)))
        }

        // Baglanma durumunda hizli donen ince halka
        if (isConnecting) {
            Canvas(
                modifier = Modifier
                    .size(142.dp)
                    .rotate(connectSpin)
            ) {
                drawArc(
                    color = Color(0xFF2979FF),
                    startAngle = 0f,
                    sweepAngle = 90f,
                    useCenter = false,
                    style = Stroke(width = 2.dp.toPx(), cap = StrokeCap.Round)
                )
                drawArc(
                    color = Color(0xFF448AFF).copy(alpha = 0.4f),
                    startAngle = 180f,
                    sweepAngle = 60f,
                    useCenter = false,
                    style = Stroke(width = 1.5.dp.toPx(), cap = StrokeCap.Round)
                )
            }
        }

        // Aktif aramada donen gradient border
        if (isActive) {
            Canvas(
                modifier = Modifier
                    .size(136.dp)
                    .scale(avatarScale)
                    .rotate(borderRotation)
            ) {
                drawArc(
                    brush = Brush.sweepGradient(
                        0f to Color(0xFF2979FF).copy(alpha = 0.8f),
                        0.25f to Color(0xFF448AFF).copy(alpha = 0.1f),
                        0.5f to Color(0xFF2979FF).copy(alpha = 0.8f),
                        0.75f to Color(0xFF448AFF).copy(alpha = 0.1f),
                        1f to Color(0xFF2979FF).copy(alpha = 0.8f)
                    ),
                    startAngle = 0f,
                    sweepAngle = 360f,
                    useCenter = false,
                    style = Stroke(width = 3.dp.toPx())
                )
            }
        }

        // Ana avatar
        Box(
            modifier = Modifier
                .size(126.dp)
                .scale(avatarScale)
                .clip(CircleShape)
                .background(avatarGradient),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = Icons.Default.Person,
                contentDescription = "Kişi",
                tint = Color.White,
                modifier = Modifier.size(64.dp)
            )
        }
    }
}

// =====================================================================
// Animasyonlu Sure Metni
// =====================================================================

/**
 * Arama suresi icin yumusak fade-in animasyonu.
 * Timer basladiginda metin yumusak bir sekilde gorulur olur.
 */
@Composable
private fun AnimatedDurationText(text: String) {
    var appeared by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        appeared = true
    }
    val alphaAnim by animateFloatAsState(
        targetValue = if (appeared) 0.7f else 0f,
        animationSpec = tween(800, easing = EaseInOut),
        label = "durationFade"
    )
    Text(
        text = text,
        style = MaterialTheme.typography.bodyLarge,
        color = Color.White.copy(alpha = alphaAnim)
    )
}

// =====================================================================
// Mevcut Yardimci Fonksiyonlar
// =====================================================================

/**
 * Avatar icin gradient renk paleti — koyu, canli tonlar.
 */
private fun callAvatarGradient(name: String): Brush {
    val colors = listOf(
        listOf(Color(0xFF1565C0), Color(0xFF0D47A1)),
        listOf(Color(0xFF1976D2), Color(0xFF0D3B82)),
        listOf(Color(0xFF2979FF), Color(0xFF1A237E)),
        listOf(Color(0xFF3F51B5), Color(0xFF1A237E)),
        listOf(Color(0xFF5C6BC0), Color(0xFF283593)),
        listOf(Color(0xFF448AFF), Color(0xFF1565C0))
    )
    val index = abs(name.hashCode()) % colors.size
    return Brush.linearGradient(colors[index])
}

/**
 * Animasyonlu arama durumu metni.
 * "Araniyor..." yazisini nokta animasyonu ile gosterir.
 */
@Composable
private fun AnimatedCallStateText(text: String) {
    val infiniteTransition = rememberInfiniteTransition(label = "dots")
    val dotCount by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 4f,
        animationSpec = infiniteRepeatable(
            animation = tween(1200, easing = LinearEasing),
            repeatMode = RepeatMode.Restart
        ),
        label = "dotAnimation"
    )

    // "..." kismindan sonra nokta animasyonu ekle
    val baseText = text.trimEnd('.')
    val dots = ".".repeat(dotCount.toInt().coerceIn(0, 3))

    Text(
        text = "$baseText$dots",
        style = MaterialTheme.typography.bodyLarge,
        color = Color.White.copy(alpha = 0.7f)
    )
}

/**
 * Arama durumuna gore gosterilecek metin.
 */
private fun getCallStateText(state: CallState?, durationMs: Long): String {
    return when (state) {
        CallState.INITIATING -> "Baslatiliyor..."
        CallState.RINGING -> "Araniyor..."
        CallState.CONNECTING -> "Baglaniyor..."
        CallState.ACTIVE -> TimeFormatter.formatDuration(durationMs)
        CallState.RECONNECTING -> "Yeniden baglaniyor..."
        CallState.ENDED -> "Arama sona erdi"
        CallState.REJECTED -> "Arama reddedildi"
        CallState.BUSY -> "Mesgul"
        CallState.FAILED -> "Arama basarisiz"
        CallState.IDLE, null -> ""
    }
}

// =====================================================================
// Arama Kontrol Butonlari — Animasyonlu Renk Gecisleri
// =====================================================================

/**
 * Arama kontrol butonlari.
 * Koyu surface arka plan, cyan/kirmizi vurgular — Midnight Teal stili.
 * Toggle butonlarinda animasyonlu renk gecisi.
 */
@Composable
fun CallControls(
    isMuted: Boolean,
    isSpeakerOn: Boolean,
    isCameraEnabled: Boolean,
    isVideoCall: Boolean,
    onToggleMute: () -> Unit,
    onToggleSpeaker: () -> Unit,
    onToggleCamera: () -> Unit,
    onSwitchCamera: () -> Unit,
    onEndCall: () -> Unit,
    modifier: Modifier = Modifier
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = modifier
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(28.dp),
            verticalAlignment = Alignment.Top
        ) {
            // Sessiz butonu
            AnimatedCallButton(
                icon = {
                    Icon(
                        if (isMuted) Icons.Default.MicOff else Icons.Default.Mic,
                        contentDescription = if (isMuted) "Sesi Ac" else "Sessiz",
                        modifier = Modifier.size(24.dp)
                    )
                },
                label = if (isMuted) "Sesi Ac" else "Sessiz",
                isActive = isMuted,
                onClick = onToggleMute
            )

            // Hoparlor butonu
            AnimatedCallButton(
                icon = {
                    Icon(
                        if (isSpeakerOn) Icons.AutoMirrored.Filled.VolumeUp else Icons.AutoMirrored.Filled.VolumeOff,
                        contentDescription = if (isSpeakerOn) "Hoparloru Kapat" else "Hoparloru Ac",
                        modifier = Modifier.size(24.dp)
                    )
                },
                label = "Hoparlor",
                isActive = isSpeakerOn,
                onClick = onToggleSpeaker
            )

            // Video arama icin kamera butonu
            if (isVideoCall) {
                AnimatedCallButton(
                    icon = {
                        Icon(
                            if (isCameraEnabled) Icons.Default.Videocam else Icons.Default.VideocamOff,
                            contentDescription = if (isCameraEnabled) "Kamerayi Kapat" else "Kamerayi Ac",
                            modifier = Modifier.size(24.dp)
                        )
                    },
                    label = "Kamera",
                    isActive = !isCameraEnabled,
                    onClick = onToggleCamera
                )

                AnimatedCallButton(
                    icon = {
                        Icon(
                            Icons.Default.Cameraswitch,
                            contentDescription = "Kamera Degistir",
                            modifier = Modifier.size(24.dp)
                        )
                    },
                    label = "Cevir",
                    isActive = false,
                    onClick = onSwitchCamera
                )
            }
        }

        Spacer(modifier = Modifier.height(36.dp))

        // Arama kapat butonu — nabizli kirmizi glow
        EndCallButton(onEndCall = onEndCall)
    }
}

/**
 * Animasyonlu renk gecisli arama kontrol butonu.
 * Toggle durumunda arka plan ve ikon rengi yumusak gecis yapar.
 */
@Composable
private fun AnimatedCallButton(
    icon: @Composable () -> Unit,
    label: String,
    isActive: Boolean,
    onClick: () -> Unit
) {
    val bgColor by animateColorAsState(
        targetValue = if (isActive) Color(0xFF2979FF).copy(alpha = 0.3f)
        else Color(0xFF21262D).copy(alpha = 0.8f),
        animationSpec = tween(300, easing = EaseInOut),
        label = "btnBg"
    )
    val contentColor by animateColorAsState(
        targetValue = if (isActive) Color(0xFF2979FF) else Color.White,
        animationSpec = tween(300, easing = EaseInOut),
        label = "btnContent"
    )

    Column(
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        IconButton(
            onClick = onClick,
            modifier = Modifier
                .size(56.dp)
                .clip(CircleShape)
                .background(bgColor),
            colors = IconButtonDefaults.iconButtonColors(
                contentColor = contentColor
            )
        ) {
            icon()
        }
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = Color.White.copy(alpha = 0.7f),
            fontSize = 11.sp,
            textAlign = TextAlign.Center
        )
    }
}

/**
 * Nabizli kirmizi glow efektli arama sonlandirma butonu.
 */
@Composable
private fun EndCallButton(onEndCall: () -> Unit) {
    // Basitleştirilmiş, animasyon yok - crash önlemi
    Column(
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        FilledIconButton(
            onClick = onEndCall,
            modifier = Modifier.size(64.dp),
            shape = CircleShape,
            colors = IconButtonDefaults.filledIconButtonColors(
                containerColor = Color(0xFFF85149),
                contentColor = Color.White
            )
        ) {
            Icon(
                Icons.Default.CallEnd,
                contentDescription = "Aramayi Sonlandir",
                modifier = Modifier.size(32.dp)
            )
        }
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = "Kapat",
            style = MaterialTheme.typography.labelSmall,
            color = Color.White.copy(alpha = 0.7f)
        )
    }
}

/**
 * Tek bir arama kontrol butonu (legacy — uyumluluk icin korunur).
 * Aktif durumdayken primaryContainer rengi ile vurgulanir.
 */
@Composable
fun CallControlButton(
    icon: @Composable () -> Unit,
    isActive: Boolean,
    onClick: () -> Unit
) {
    IconButton(
        onClick = onClick,
        modifier = Modifier
            .size(56.dp)
            .clip(CircleShape)
            .background(
                if (isActive) MaterialTheme.colorScheme.primaryContainer
                else MaterialTheme.colorScheme.surfaceVariant
            )
    ) {
        icon()
    }
}

/**
 * Gelen arama kontrolleri: Kabul Et (yesil glow) ve Reddet (kirmizi glow).
 * Her butonun altinda etiket bulunan, buyuk dairesel butonlar.
 */
@Composable
fun IncomingCallControls(
    onAccept: () -> Unit,
    onReject: () -> Unit,
    modifier: Modifier = Modifier
) {
    val infiniteTransition = rememberInfiniteTransition(label = "incomingGlow")

    // Yesil kabul butonu nabzi
    val acceptGlow by infiniteTransition.animateFloat(
        initialValue = 0.2f,
        targetValue = 0.5f,
        animationSpec = infiniteRepeatable(
            animation = tween(1000, easing = EaseInOut),
            repeatMode = RepeatMode.Reverse
        ),
        label = "acceptGlow"
    )
    val acceptScale by infiniteTransition.animateFloat(
        initialValue = 1f,
        targetValue = 1.06f,
        animationSpec = infiniteRepeatable(
            animation = tween(1000, easing = EaseInOut),
            repeatMode = RepeatMode.Reverse
        ),
        label = "acceptScale"
    )

    // Kirmizi reddet butonu hafif glow
    val rejectGlow by infiniteTransition.animateFloat(
        initialValue = 0.1f,
        targetValue = 0.25f,
        animationSpec = infiniteRepeatable(
            animation = tween(1500, easing = EaseInOut),
            repeatMode = RepeatMode.Reverse
        ),
        label = "rejectGlow"
    )

    // Yukari ok ipucu animasyonu
    val arrowOffset by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 8f,
        animationSpec = infiniteRepeatable(
            animation = tween(800, easing = EaseInOut),
            repeatMode = RepeatMode.Reverse
        ),
        label = "arrowHint"
    )
    val arrowAlpha by infiniteTransition.animateFloat(
        initialValue = 0.3f,
        targetValue = 0.7f,
        animationSpec = infiniteRepeatable(
            animation = tween(800, easing = EaseInOut),
            repeatMode = RepeatMode.Reverse
        ),
        label = "arrowAlpha"
    )

    Column(
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(80.dp),
            verticalAlignment = Alignment.Top,
            modifier = modifier
        ) {
            // Reddet
            Column(
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Box(contentAlignment = Alignment.Center) {
                    // Kirmizi glow
                    Box(
                        modifier = Modifier
                            .size(78.dp)
                            .drawBehind {
                                drawCircle(
                                    color = Color(0xFFF85149).copy(alpha = rejectGlow),
                                    radius = size.minDimension / 2
                                )
                            }
                    )
                    FilledIconButton(
                        onClick = onReject,
                        modifier = Modifier.size(64.dp),
                        colors = IconButtonDefaults.filledIconButtonColors(
                            containerColor = Color(0xFFF85149),
                            contentColor = Color.White
                        )
                    ) {
                        Icon(
                            Icons.Default.CallEnd,
                            contentDescription = "Reddet",
                            modifier = Modifier.size(32.dp)
                        )
                    }
                }
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = "Reddet",
                    style = MaterialTheme.typography.labelMedium,
                    color = Color.White.copy(alpha = 0.8f)
                )
            }

            // Kabul Et
            Column(
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Box(contentAlignment = Alignment.Center) {
                    // Yesil parlayan glow
                    Box(
                        modifier = Modifier
                            .size(82.dp)
                            .scale(acceptScale)
                            .drawBehind {
                                drawCircle(
                                    color = Color(0xFF4ECDC4).copy(alpha = acceptGlow),
                                    radius = size.minDimension / 2
                                )
                            }
                    )
                    FilledIconButton(
                        onClick = onAccept,
                        modifier = Modifier.size(64.dp),
                        colors = IconButtonDefaults.filledIconButtonColors(
                            containerColor = Color(0xFF4ECDC4),
                            contentColor = Color(0xFF0D1117)
                        )
                    ) {
                        Icon(
                            Icons.Default.Call,
                            contentDescription = "Kabul Et",
                            modifier = Modifier.size(32.dp)
                        )
                    }
                }
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = "Kabul Et",
                    style = MaterialTheme.typography.labelMedium,
                    color = Color.White.copy(alpha = 0.8f)
                )
            }
        }

        // "Kabul etmek icin kaydir" ipucu
        Spacer(modifier = Modifier.height(20.dp))
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier.alpha(arrowAlpha)
        ) {
            Text(
                text = "\u2191", // Yukari ok
                fontSize = 18.sp,
                color = Color(0xFF4ECDC4).copy(alpha = 0.6f),
                modifier = Modifier.offset(y = (-arrowOffset).dp)
            )
            Text(
                text = "Kabul etmek icin dokun",
                style = MaterialTheme.typography.labelSmall,
                color = Color.White.copy(alpha = 0.4f),
                fontSize = 10.sp
            )
        }
    }
}
