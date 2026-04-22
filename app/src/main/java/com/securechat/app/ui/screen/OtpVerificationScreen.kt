package com.securechat.app.ui.screen

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.securechat.app.R
import com.securechat.app.ui.theme.AzureDoodleBackdrop
import com.securechat.app.ui.theme.LocalDarkTheme
import com.securechat.app.ui.theme.glass
import com.securechat.app.ui.theme.MonoFamily
import com.securechat.app.ui.theme.DisplayFamily
import kotlinx.coroutines.delay

/**
 * OTP doğrulama ekranı.
 * 6 haneli doğrulama kodu girişi, otomatik odaklanma, geri sayım ve tekrar gönderme.
 * Azure glassmorphism tasarım.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OtpVerificationScreen(
    phoneNumber: String,
    onVerified: () -> Unit,
    onBackClick: () -> Unit = {}
) {
    var otpCode by remember { mutableStateOf("") }
    var isLoading by remember { mutableStateOf(false) }
    var countdown by remember { mutableStateOf(60) }
    var canResend by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf("") }

    // Geri sayım timer
    LaunchedEffect(Unit) {
        while (countdown > 0) {
            delay(1000)
            countdown--
        }
        canResend = true
    }

    val dark = LocalDarkTheme.current

    Box(Modifier.fillMaxSize()) {
        AzureDoodleBackdrop(dark = dark)

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Doğrulama") },
                navigationIcon = {
                    IconButton(onClick = onBackClick) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Geri",
                            tint = MaterialTheme.colorScheme.onSurface
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = Color.Transparent,
                    titleContentColor = MaterialTheme.colorScheme.onSurface
                )
            )
        },
        containerColor = Color.Transparent
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .imePadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            Spacer(modifier = Modifier.height(48.dp))

            // Güvenlik ikonu
            Box(
                modifier = Modifier
                    .size(120.dp)
                    .clip(RoundedCornerShape(24.dp))
                    .background(
                        Brush.radialGradient(
                            colors = listOf(
                                Color(0xFF3E7BFA).copy(alpha = 0.2f),
                                Color(0xFF3E7BFA).copy(alpha = 0.05f)
                            )
                        )
                    ),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Default.Shield,
                    contentDescription = null,
                    modifier = Modifier.size(64.dp),
                    tint = Color(0xFF3E7BFA)
                )
            }

            Spacer(modifier = Modifier.height(32.dp))

            // Başlık
            Text(
                text = "Doğrulama Kodu",
                style = MaterialTheme.typography.headlineMedium,
                color = MaterialTheme.colorScheme.onSurface,
                fontWeight = FontWeight.Bold
            )

            Spacer(modifier = Modifier.height(16.dp))

            // Açıklama
            Text(
                text = "$phoneNumber numarasına gönderilen\n6 haneli doğrulama kodunu girin",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
                lineHeight = 24.sp
            )

            Spacer(modifier = Modifier.height(48.dp))

            // OTP input
            OtpInputField(
                value = otpCode,
                onValueChange = { newCode ->
                    if (newCode.length <= 6 && newCode.all { it.isDigit() }) {
                        otpCode = newCode
                        errorMessage = ""

                        // 6 hane tamamlandığında otomatik doğrula
                        if (newCode.length == 6) {
                            isLoading = true
                            // Simulated verification
                            // Gerçek implementasyonda burada API çağrısı olacak
                            otpCode = ""
                            isLoading = false
                            onVerified()
                        }
                    }
                }
            )

            if (errorMessage.isNotEmpty()) {
                Spacer(modifier = Modifier.height(16.dp))
                Text(
                    text = errorMessage,
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodyMedium
                )
            }

            Spacer(modifier = Modifier.height(32.dp))

            // Loading indicator
            if (isLoading) {
                CircularProgressIndicator(
                    color = Color(0xFF3E7BFA),
                    modifier = Modifier.size(24.dp)
                )
            }

            Spacer(modifier = Modifier.height(32.dp))

            // Tekrar gönder
            if (canResend) {
                TextButton(
                    onClick = {
                        // Kod tekrar gönderildi
                        canResend = false
                        countdown = 60

                        // Geri sayımı yeniden başlat
                        // LaunchedEffect burada çalışacak
                    }
                ) {
                    Text(
                        "Kodu Tekrar Gönder",
                        color = Color(0xFF3E7BFA),
                        fontWeight = FontWeight.Medium
                    )
                }
            } else {
                Text(
                    text = "Kodu tekrar gönder: ${countdown}s",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            Spacer(modifier = Modifier.height(64.dp))

            // Manuel doğrula butonu — azure pill
            Button(
                onClick = {
                    if (otpCode.length == 6) {
                        isLoading = true
                        // Simulated verification
                        isLoading = false
                        onVerified()
                    } else {
                        errorMessage = "Lütfen 6 haneli kodu tamamen girin"
                    }
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(56.dp),
                enabled = otpCode.length == 6 && !isLoading,
                colors = ButtonDefaults.buttonColors(
                    containerColor = Color(0xFF3E7BFA),
                    contentColor = Color.White
                ),
                shape = RoundedCornerShape(100.dp)
            ) {
                Text(
                    "Doğrula",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold
                )
            }

            Spacer(modifier = Modifier.height(32.dp))
        }
    }
    } // Box
}

/**
 * 6 haneli OTP giriş alanı.
 * Her haneli kutucuk ayrı ayrı görünür, odaklanma animasyonları ile.
 */
@Composable
private fun OtpInputField(
    value: String,
    onValueChange: (String) -> Unit
) {
    val focusRequester = remember { FocusRequester() }
    val dark = LocalDarkTheme.current

    LaunchedEffect(Unit) {
        focusRequester.requestFocus()
    }

    Row(
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        BasicTextField(
            value = value,
            onValueChange = onValueChange,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            modifier = Modifier.focusRequester(focusRequester),
            decorationBox = { _ ->
                Row(
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    repeat(6) { index ->
                        val digit = value.getOrNull(index)?.toString() ?: ""
                        val isFocused = value.length == index

                        Box(
                            modifier = Modifier
                                .size(56.dp)
                                .glass(dark, shape = RoundedCornerShape(12.dp))
                                .then(
                                    if (isFocused) Modifier.border(
                                        width = 2.dp,
                                        color = Color(0xFF3E7BFA),
                                        shape = RoundedCornerShape(12.dp)
                                    ) else Modifier
                                ),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(
                                text = digit,
                                style = MaterialTheme.typography.headlineMedium,
                                color = if (digit.isNotEmpty()) MaterialTheme.colorScheme.onSurface
                                else MaterialTheme.colorScheme.onSurfaceVariant,
                                fontWeight = FontWeight.Bold
                            )
                        }
                    }
                }
            }
        )
    }
}