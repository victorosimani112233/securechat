package com.securechat.app.ui.components

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.VolumeOff
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.filled.CallEnd
import androidx.compose.material.icons.filled.Cameraswitch
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MicOff
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material.icons.filled.VideocamOff
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import com.securechat.network.model.CallType

/**
 * Arama kontrol butonları.
 * Mute, speaker, kamera, kamera değiştir, aramayi sonlandır butonları.
 */
@Composable
fun CallControls(
    isMuted: Boolean,
    isSpeakerOn: Boolean,
    isCameraEnabled: Boolean,
    callType: CallType,
    onToggleMute: () -> Unit,
    onToggleSpeaker: () -> Unit,
    onToggleCamera: () -> Unit,
    onSwitchCamera: () -> Unit,
    onEndCall: () -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Mikrofon
        CallControlButton(
            icon = if (isMuted) Icons.Default.MicOff else Icons.Default.Mic,
            isActive = !isMuted,
            onClick = onToggleMute,
            contentDescription = if (isMuted) "Mikrofonu aç" else "Mikrofonu kapat"
        )

        // Hoparlör (sadece sesli aramada)
        if (callType == CallType.VOICE) {
            CallControlButton(
                icon = if (isSpeakerOn) Icons.AutoMirrored.Filled.VolumeUp else Icons.AutoMirrored.Filled.VolumeOff,
                isActive = isSpeakerOn,
                onClick = onToggleSpeaker,
                contentDescription = if (isSpeakerOn) "Hoparlörü kapat" else "Hoparlörü aç"
            )
        }

        // Kamera (sadece görüntülü aramada)
        if (callType == CallType.VIDEO) {
            CallControlButton(
                icon = if (isCameraEnabled) Icons.Default.Videocam else Icons.Default.VideocamOff,
                isActive = isCameraEnabled,
                onClick = onToggleCamera,
                contentDescription = if (isCameraEnabled) "Kamerayı kapat" else "Kamerayı aç"
            )

            // Kamera değiştir
            CallControlButton(
                icon = Icons.Default.Cameraswitch,
                isActive = true,
                onClick = onSwitchCamera,
                contentDescription = "Kamerayı değiştir"
            )
        }

        Spacer(modifier = Modifier.width(8.dp))

        // Aramayı sonlandır - daha büyük, kırmızı
        CallEndButton(onClick = onEndCall)
    }
}

@Composable
private fun CallControlButton(
    icon: ImageVector,
    isActive: Boolean,
    onClick: () -> Unit,
    contentDescription: String
) {
    val animatedScale by animateFloatAsState(
        targetValue = if (isActive) 1f else 0.9f,
        animationSpec = tween(150),
        label = "buttonScale"
    )

    val backgroundColor by animateColorAsState(
        targetValue = if (isActive) {
            MaterialTheme.colorScheme.primaryContainer
        } else {
            MaterialTheme.colorScheme.surfaceVariant
        },
        animationSpec = tween(200),
        label = "buttonColor"
    )

    FilledIconButton(
        onClick = onClick,
        modifier = Modifier
            .size(56.dp)
            .scale(animatedScale),
        colors = IconButtonDefaults.filledIconButtonColors(
            containerColor = backgroundColor
        )
    ) {
        Icon(
            imageVector = icon,
            contentDescription = contentDescription,
            tint = if (isActive) {
                MaterialTheme.colorScheme.onPrimaryContainer
            } else {
                MaterialTheme.colorScheme.onSurfaceVariant
            },
            modifier = Modifier.size(24.dp)
        )
    }
}

@Composable
private fun CallEndButton(onClick: () -> Unit) {
    FilledIconButton(
        onClick = onClick,
        modifier = Modifier.size(64.dp),
        shape = CircleShape,
        colors = IconButtonDefaults.filledIconButtonColors(
            containerColor = Color(0xFFEF4444) // Red-500
        )
    ) {
        Icon(
            imageVector = Icons.Default.CallEnd,
            contentDescription = "Aramayı sonlandır",
            tint = Color.White,
            modifier = Modifier.size(28.dp)
        )
    }
}