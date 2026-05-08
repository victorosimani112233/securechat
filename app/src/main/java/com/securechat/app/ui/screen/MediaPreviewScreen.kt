package com.securechat.app.ui.screen

import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.InsertDriveFile
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import coil.request.ImageRequest

/**
 * Medya/dosya onizleme ekrani.
 *
 * Kullanici dosya/fotograf/video sectikten sonra gonderim oncesi onizleme gosterir.
 * Resimler buyuk onizleme, diger dosyalar ikon + bilgi olarak gosterilir.
 * Birden fazla secimde yatay kaydirma (pager) ile gecis yapilir.
 *
 * @param items Onizlenecek medya listesi (URI + metadata)
 * @param onSend Kullanici "Gonder" e bastiginda cagirilir
 * @param onDismiss Kullanici geri/iptal butonuna bastiginda cagirilir
 */
@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
fun MediaPreviewScreen(
    items: List<MediaPreviewItem>,
    onSend: (List<MediaPreviewItem>, String, Boolean) -> Unit,
    onDismiss: () -> Unit
) {
    var captionText by remember { mutableStateOf("") }
    var isViewOnce by remember { mutableStateOf(false) }
    val context = LocalContext.current

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFF0A0F18))
            .statusBarsPadding()
            .navigationBarsPadding()
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            // Ust bar — kapat butonu ve dosya sayisi
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 8.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(onClick = onDismiss) {
                    Icon(
                        Icons.Default.Close,
                        contentDescription = "Kapat",
                        tint = Color.White
                    )
                }
                if (items.size > 1) {
                    Text(
                        text = "${items.size} dosya seçildi",
                        color = Color(0xFF94A3B8),
                        fontSize = 14.sp
                    )
                }
            }

            // Onizleme alani — icerik tipine gore
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth(),
                contentAlignment = Alignment.Center
            ) {
                if (items.size == 1) {
                    // Tek dosya — dogrudan goster
                    MediaPreviewContent(item = items[0], context = context)
                } else {
                    // Birden fazla — pager ile kaydirma
                    val pagerState = rememberPagerState(pageCount = { items.size })
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        HorizontalPager(
                            state = pagerState,
                            modifier = Modifier.weight(1f)
                        ) { page ->
                            MediaPreviewContent(item = items[page], context = context)
                        }

                        // Sayfa gostergesi (noktalar)
                        Row(
                            modifier = Modifier.padding(vertical = 12.dp),
                            horizontalArrangement = Arrangement.Center
                        ) {
                            repeat(items.size) { index ->
                                Box(
                                    modifier = Modifier
                                        .padding(horizontal = 3.dp)
                                        .size(if (index == pagerState.currentPage) 8.dp else 6.dp)
                                        .clip(CircleShape)
                                        .background(
                                            if (index == pagerState.currentPage) Color(0xFF0EA5E9)
                                            else Color(0xFF475569)
                                        )
                                )
                            }
                        }
                    }
                }
            }

            // Alt kisim — chat ekranindaki MessageInputBar ile birebir ayni gorunum.
            // Sol: ataşman placeholder (yok burada), Orta: caption alani, Sag: "1" view-once
            // toggle (WhatsApp tarzi), en sag: gonder dairesi.
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 8.dp, vertical = 6.dp)
                    .clip(RoundedCornerShape(28.dp))
                    .background(Color(0xFF1E293B))
                    .padding(start = 12.dp, end = 6.dp, top = 4.dp, bottom = 4.dp)
                    .imePadding(),
                verticalAlignment = Alignment.Bottom
            ) {
                // Caption alani — chat input gibi BasicTextField
                androidx.compose.foundation.text.BasicTextField(
                    value = captionText,
                    onValueChange = { captionText = it.take(1000) },
                    modifier = Modifier
                        .weight(1f)
                        .padding(vertical = 10.dp),
                    textStyle = androidx.compose.ui.text.TextStyle(
                        color = Color.White,
                        fontSize = 16.sp
                    ),
                    cursorBrush = androidx.compose.ui.graphics.SolidColor(Color(0xFF3E7BFA)),
                    maxLines = 4,
                    decorationBox = { inner ->
                        if (captionText.isEmpty()) {
                            Text(
                                "Açıklama ekle...",
                                color = Color(0xFF64748B),
                                fontSize = 16.sp
                            )
                        }
                        inner()
                    }
                )

                Spacer(modifier = Modifier.width(6.dp))

                // "1" view-once toggle — WhatsApp tarzi dairesel rozet, gonder butonunun solunda
                Box(
                    modifier = Modifier
                        .size(40.dp)
                        .clip(CircleShape)
                        .background(
                            if (isViewOnce) Color(0xFF3E7BFA).copy(alpha = 0.18f)
                            else Color.White.copy(alpha = 0.06f)
                        )
                        .border(
                            width = 1.5.dp,
                            color = if (isViewOnce) Color(0xFF3E7BFA) else Color.White.copy(alpha = 0.25f),
                            shape = CircleShape
                        )
                        .clickable { isViewOnce = !isViewOnce },
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = "1",
                        color = if (isViewOnce) Color(0xFF3E7BFA) else Color.White.copy(alpha = 0.7f),
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Bold
                    )
                }

                Spacer(modifier = Modifier.width(6.dp))

                // Gonder butonu — chat ekranindaki ile birebir ayni
                Box(
                    modifier = Modifier
                        .size(40.dp)
                        .clip(CircleShape)
                        .background(Color(0xFF3E7BFA))
                        .clickable { onSend(items, captionText.trim(), isViewOnce) },
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        Icons.AutoMirrored.Filled.Send,
                        contentDescription = "Gönder",
                        tint = Color.White,
                        modifier = Modifier.size(20.dp)
                    )
                }
            }
        }
    }
}

/**
 * Tek bir medya ogesinin onizleme icerigi.
 * Resimler buyuk onizleme, diger dosyalar ikon + ad/boyut bilgisi gosterir.
 */
@Composable
private fun MediaPreviewContent(
    item: MediaPreviewItem,
    context: android.content.Context
) {
    if (item.isImage) {
        // Resim onizlemesi
        AsyncImage(
            model = ImageRequest.Builder(context)
                .data(item.uri)
                .crossfade(true)
                .build(),
            contentDescription = item.fileName,
            modifier = Modifier
                .fillMaxSize()
                .padding(16.dp),
            contentScale = ContentScale.Fit
        )
    } else if (item.isVideo) {
        // Video: thumbnail + oynat ikonu
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(16.dp),
            contentAlignment = Alignment.Center
        ) {
            AsyncImage(
                model = ImageRequest.Builder(context)
                    .data(item.uri)
                    .crossfade(true)
                    .build(),
                contentDescription = item.fileName,
                modifier = Modifier.fillMaxSize(),
                contentScale = ContentScale.Fit
            )
            // Video ikonu
            Box(
                modifier = Modifier
                    .size(64.dp)
                    .clip(CircleShape)
                    .background(Color.Black.copy(alpha = 0.6f)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Default.PlayArrow,
                    contentDescription = null,
                    tint = Color.White,
                    modifier = Modifier.size(36.dp)
                )
            }
        }
    } else {
        // Dosya onizlemesi — ikon + bilgi
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            Box(
                modifier = Modifier
                    .size(96.dp)
                    .clip(RoundedCornerShape(20.dp))
                    .background(Color(0xFF1E293B)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    Icons.AutoMirrored.Filled.InsertDriveFile,
                    contentDescription = null,
                    tint = Color(0xFF0EA5E9),
                    modifier = Modifier.size(48.dp)
                )
            }

            Spacer(modifier = Modifier.height(16.dp))

            Text(
                text = item.fileName,
                color = Color.White,
                fontSize = 18.sp,
                fontWeight = FontWeight.Medium,
                textAlign = TextAlign.Center,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )

            Spacer(modifier = Modifier.height(8.dp))

            Text(
                text = formatFileSize(item.fileSize),
                color = Color(0xFF64748B),
                fontSize = 14.sp
            )

            if (item.mimeType.isNotEmpty()) {
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = item.mimeType,
                    color = Color(0xFF475569),
                    fontSize = 12.sp
                )
            }
        }
    }
}

/**
 * Onizleme ekraninda gosterilecek medya ogesi.
 */
data class MediaPreviewItem(
    val uri: Uri,
    val fileName: String = "",
    val mimeType: String = "",
    val fileSize: Long = 0L
) {
    val isImage: Boolean get() = mimeType.startsWith("image/")
    val isVideo: Boolean get() = mimeType.startsWith("video/")
}

private fun formatFileSize(bytes: Long): String {
    return when {
        bytes < 1024 -> "$bytes B"
        bytes < 1024 * 1024 -> "${bytes / 1024} KB"
        bytes < 1024 * 1024 * 1024 -> String.format("%.1f MB", bytes / (1024.0 * 1024.0))
        else -> String.format("%.2f GB", bytes / (1024.0 * 1024.0 * 1024.0))
    }
}
