package com.securechat.app.ui.screen

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.securechat.app.ui.theme.AzureDoodleBackdrop
import com.securechat.app.ui.theme.LocalDarkTheme
import kotlinx.coroutines.launch

/**
 * 3 sayfalik onboarding intro — ilk acilista bir kez gosterilir.
 * Kullanici "Atla" veya "Devam"/"Baslat" ile bitirir; OnboardingAckStore
 * tamamlanma durumunu kaydeder. Sonra PermissionWalkthrough akar.
 *
 * Sayfalar:
 *  1. E2EE — Signal Protocol vurgusu
 *  2. P2P arama — WebRTC + Janus SFU vurgusu
 *  3. Gizlilik kontrolu — view-once / disappearing / export toggle vurgusu
 */
private data class OnboardingPage(
    val icon: ImageVector,
    val accent: Color,
    val title: String,
    val subtitle: String,
    val body: String
)

private val pages = listOf(
    OnboardingPage(
        icon = Icons.Default.Lock,
        accent = Color(0xFF1F8E3D),
        title = "Uçtan uca şifreli",
        subtitle = "Mesajlarınız sadece sizin aranızda",
        body = "Signal Protocol ile her mesaj cihazınızda şifrelenir. Sunucu içeriği göremez, dinleyemez, saklayamaz."
    ),
    OnboardingPage(
        icon = Icons.Default.Phone,
        accent = Color(0xFF3E7BFA),
        title = "Doğrudan arama",
        subtitle = "Sesli ve görüntülü, P2P",
        body = "WebRTC ile cihazlar arası doğrudan ses/görüntü akışı. Aramalarınızın içeriği sunucudan geçmez."
    ),
    OnboardingPage(
        icon = Icons.Default.Shield,
        accent = Color(0xFFEF6C00),
        title = "Tam gizlilik kontrolü",
        subtitle = "Siz karar verirsiniz",
        body = "Tek gösterimlik mesaj, süreli mesaj, ekran görüntüsü engeli, grup dışa aktarma kontrolü — her sohbette ayrı."
    )
)

@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
fun OnboardingScreen(
    onFinished: () -> Unit
) {
    val dark = LocalDarkTheme.current
    val pagerState = rememberPagerState(pageCount = { pages.size })
    val scope = rememberCoroutineScope()
    val isLastPage = pagerState.currentPage == pages.size - 1

    Box(Modifier.fillMaxSize()) {
        AzureDoodleBackdrop(dark = dark)

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 24.dp)
        ) {
            // Üst — Atla butonu
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 12.dp),
                horizontalArrangement = Arrangement.End
            ) {
                if (!isLastPage) {
                    TextButton(onClick = onFinished) {
                        Text(
                            "Atla",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f)
                        )
                    }
                }
            }

            // Pager — içerik
            HorizontalPager(
                state = pagerState,
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth(),
                contentPadding = PaddingValues(horizontal = 8.dp)
            ) { pageIndex ->
                OnboardingPageContent(pages[pageIndex])
            }

            // Alt — indicators + buton
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = 32.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                PageIndicators(pagerState.currentPage, pages.size)
                Spacer(Modifier.height(24.dp))
                Button(
                    onClick = {
                        if (isLastPage) {
                            onFinished()
                        } else {
                            scope.launch { pagerState.animateScrollToPage(pagerState.currentPage + 1) }
                        }
                    },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(52.dp),
                    shape = RoundedCornerShape(26.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.primary
                    )
                ) {
                    Text(
                        if (isLastPage) "Başlayalım" else "Devam",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold
                    )
                }
            }
        }
    }
}

@Composable
private fun OnboardingPageContent(page: OnboardingPage) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(vertical = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        // Büyük accent ikon
        Box(
            modifier = Modifier
                .size(128.dp)
                .background(page.accent.copy(alpha = 0.18f), CircleShape),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                page.icon,
                contentDescription = null,
                tint = page.accent,
                modifier = Modifier.size(64.dp)
            )
        }
        Spacer(Modifier.height(48.dp))
        Text(
            page.title,
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.onSurface,
            textAlign = TextAlign.Center
        )
        Spacer(Modifier.height(8.dp))
        Text(
            page.subtitle,
            style = MaterialTheme.typography.titleMedium,
            color = page.accent,
            fontWeight = FontWeight.Medium,
            textAlign = TextAlign.Center
        )
        Spacer(Modifier.height(20.dp))
        Text(
            page.body,
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
            lineHeight = 24.sp,
            modifier = Modifier.padding(horizontal = 16.dp)
        )
    }
}

@Composable
private fun PageIndicators(currentPage: Int, totalPages: Int) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        repeat(totalPages) { index ->
            val isActive = index == currentPage
            val width by animateFloatAsState(
                targetValue = if (isActive) 24f else 8f,
                animationSpec = tween(220),
                label = "indicatorWidth"
            )
            Box(
                modifier = Modifier
                    .width(width.dp)
                    .height(8.dp)
                    .background(
                        if (isActive) MaterialTheme.colorScheme.primary
                        else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f),
                        RoundedCornerShape(4.dp)
                    )
            )
        }
    }
}
