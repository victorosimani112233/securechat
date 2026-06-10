package com.securechat.app.ui.screen.call

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.viewinterop.AndroidView
import org.webrtc.EglBase
import org.webrtc.RendererCommon
import org.webrtc.SurfaceViewRenderer
import org.webrtc.VideoTrack

/**
 * PiP modu icin minimalist video render — control overlay'ler yok,
 * sadece uzak video track tum alani kaplar.
 *
 * Track yoksa (audio veya remote camera kapali): koyu arka plan + "Çağrı devam ediyor"
 * etiketi.
 */
@Composable
fun PipCallContent(
    remoteVideoTrack: VideoTrack?,
    eglBaseContext: EglBase.Context?,
    isVideoActive: Boolean
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
    ) {
        if (isVideoActive && remoteVideoTrack != null && eglBaseContext != null) {
            val currentTrack = remember { mutableStateOf<VideoTrack?>(null) }
            AndroidView(
                modifier = Modifier.fillMaxSize(),
                factory = { ctx ->
                    SurfaceViewRenderer(ctx).apply {
                        init(eglBaseContext, null)
                        setScalingType(RendererCommon.ScalingType.SCALE_ASPECT_FILL)
                        setEnableHardwareScaler(true)
                    }
                },
                update = { renderer ->
                    val prev = currentTrack.value
                    if (prev != remoteVideoTrack) {
                        prev?.removeSink(renderer)
                        try { remoteVideoTrack.addSink(renderer) } catch (_: Exception) {}
                        currentTrack.value = remoteVideoTrack
                    }
                },
                onRelease = { renderer ->
                    currentTrack.value?.removeSink(renderer)
                    currentTrack.value = null
                    renderer.release()
                }
            )
        } else {
            Text(
                "Çağrı devam ediyor",
                color = Color.White,
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.align(Alignment.Center)
            )
        }
    }
}
