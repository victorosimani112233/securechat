package com.securechat.app.ui.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Call
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.securechat.app.ui.viewmodel.OngoingCallBarViewModel
import com.securechat.network.model.CallType
import kotlinx.coroutines.delay

/**
 * Aktif arama gostergesi (persistent banner).
 *
 * Kullanim: CallScreen'de DEGILKEN ve aktif arama varsa NavHost ustune overlay
 * olarak gosterilir. Yesil/azure dolgu + sure + peer ismi + tap-to-return.
 *
 * onTap → call/{peerId}/{callType} route'una navigate eder.
 *
 * Animasyon: alttan asagi acilir (expandVertically), bittiginde yukari toplanir.
 */
@Composable
fun OngoingCallBar(
    onReturnToCall: (peerId: String, callType: CallType) -> Unit,
    modifier: Modifier = Modifier,
    viewModel: OngoingCallBarViewModel = hiltViewModel()
) {
    val info by viewModel.ongoingCall.collectAsStateWithLifecycle()
    val current = info

    AnimatedVisibility(
        visible = current != null,
        enter = expandVertically(),
        exit = shrinkVertically(),
        modifier = modifier
    ) {
        if (current != null) {
            OngoingCallBarContent(
                peerName = current.displayName,
                callType = current.callType,
                durationMs = current.durationMs,
                onClick = { onReturnToCall(current.peerId, current.callType) }
            )
        }
    }
}

@Composable
private fun OngoingCallBarContent(
    peerName: String,
    callType: CallType,
    durationMs: Long,
    onClick: () -> Unit
) {
    // Sure her saniye guncelleniyor — local ticker.
    var displaySeconds by remember(durationMs) {
        mutableStateOf(durationMs / 1000)
    }
    LaunchedEffect(durationMs) {
        // İlk render'da geçilen başlangıç değerinden başlayıp, +1sn artırarak yürüyoruz.
        while (true) {
            delay(1000)
            displaySeconds += 1
        }
    }

    val accent = Color(0xFF00C853)  // WhatsApp-like green for "ongoing"
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .background(accent)
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 8.dp)
            .height(40.dp),
        contentAlignment = Alignment.CenterStart
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
                imageVector = if (callType == CallType.VIDEO) Icons.Default.Videocam else Icons.Default.Call,
                contentDescription = null,
                tint = Color.White,
                modifier = Modifier.size(18.dp)
            )
            Box(modifier = Modifier.width(10.dp))
            Text(
                text = peerName,
                color = Color.White,
                fontWeight = FontWeight.SemiBold,
                fontSize = 14.sp,
                maxLines = 1
            )
            Box(modifier = Modifier.width(8.dp))
            Text(
                text = "·",
                color = Color.White.copy(alpha = 0.8f),
                fontSize = 14.sp
            )
            Box(modifier = Modifier.width(8.dp))
            Text(
                text = formatDuration(displaySeconds),
                color = Color.White,
                fontSize = 13.sp,
                fontWeight = FontWeight.Medium
            )
            Box(modifier = Modifier.fillMaxWidth())  // push remainder
        }
        Text(
            text = "Aramaya dön",
            color = Color.White.copy(alpha = 0.85f),
            fontSize = 12.sp,
            modifier = Modifier.align(Alignment.CenterEnd)
        )
    }
}

private fun formatDuration(totalSeconds: Long): String {
    val s = totalSeconds.coerceAtLeast(0)
    val m = s / 60
    val sec = s % 60
    return "%d:%02d".format(m, sec)
}
