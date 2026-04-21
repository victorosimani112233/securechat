package com.securechat.app.ui.screen

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.securechat.app.R
import kotlinx.coroutines.delay

/**
 * Splash ekrani — uygulama acilisinda ~2 saniye gosterilir.
 * Logo pulse animasyonu, parlayan halka efekti ve app ismi icerir.
 */
@Composable
fun SplashScreen(
    onSplashFinished: () -> Unit
) {
    // Logo giris animasyonu
    val logoScale = remember { Animatable(0.6f) }
    val logoAlpha = remember { Animatable(0f) }
    val textAlpha = remember { Animatable(0f) }

    // Halka pulse animasyonu
    val infiniteTransition = rememberInfiniteTransition(label = "splash_pulse")
    val pulseScale by infiniteTransition.animateFloat(
        initialValue = 1f,
        targetValue = 1.15f,
        animationSpec = infiniteRepeatable(
            animation = tween(800, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "pulse"
    )
    val pulseAlpha by infiniteTransition.animateFloat(
        initialValue = 0.6f,
        targetValue = 0.15f,
        animationSpec = infiniteRepeatable(
            animation = tween(800, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "pulseAlpha"
    )

    LaunchedEffect(Unit) {
        // Logo animasyonu — hızlandırıldı
        logoAlpha.animateTo(1f, animationSpec = tween(200))
        logoScale.animateTo(1f, animationSpec = tween(250, easing = FastOutSlowInEasing))
        // Metin animasyonu
        textAlpha.animateTo(1f, animationSpec = tween(200))
        // Kısa bekleme
        delay(350)
        onSplashFinished()
    }

    // Tema renkleri — dark/light mod'a uyum saglar
    val backgroundColor = MaterialTheme.colorScheme.background
    val primaryColor = MaterialTheme.colorScheme.primary
    val onBackgroundColor = MaterialTheme.colorScheme.onBackground

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(backgroundColor),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Box(
                contentAlignment = Alignment.Center
            ) {
                // Dis halka — pulse efekti
                Box(
                    modifier = Modifier
                        .size(140.dp)
                        .scale(pulseScale)
                        .alpha(pulseAlpha)
                        .clip(CircleShape)
                        .background(
                            Brush.radialGradient(
                                colors = listOf(
                                    primaryColor.copy(alpha = 0.4f),
                                    primaryColor.copy(alpha = 0f)
                                )
                            )
                        )
                )

                // Ic halka — sabit gradient
                Box(
                    modifier = Modifier
                        .size(110.dp)
                        .scale(logoScale.value)
                        .alpha(logoAlpha.value)
                        .clip(CircleShape)
                        .background(
                            Brush.linearGradient(
                                colors = listOf(
                                    primaryColor.copy(alpha = 0.8f),
                                    primaryColor
                                )
                            )
                        ),
                    contentAlignment = Alignment.Center
                ) {
                    // App logosu
                    Image(
                        painter = painterResource(id = R.mipmap.ic_launcher_foreground),
                        contentDescription = "ELÇİM",
                        modifier = Modifier.size(80.dp)
                    )
                }
            }

            Spacer(modifier = Modifier.height(28.dp))

            // App ismi
            Text(
                text = "ELÇİM",
                fontSize = 28.sp,
                fontWeight = FontWeight.Bold,
                color = primaryColor,
                modifier = Modifier.alpha(textAlpha.value),
                letterSpacing = 4.sp
            )

            Spacer(modifier = Modifier.height(8.dp))

            // Alt yazi
            Text(
                text = "Guvenli Haberlesme",
                fontSize = 14.sp,
                color = onBackgroundColor.copy(alpha = 0.6f),
                modifier = Modifier.alpha(textAlpha.value),
                letterSpacing = 1.sp
            )
        }
    }
}
