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
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material3.AlertDialog
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
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
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
    onBackupRestore: (() -> Unit)? = null,
    onBackClick: () -> Unit = {}
) {
    // Form girdileri + UI ilerleme + dialog flag = rememberSaveable.
    // isLoading saveable degil — devam eden coroutine rotation'i restart eder,
    // spinner'i kalintidan tasimak yaniltici (gercek istek devam etmiyor olabilir).
    var otpCode by rememberSaveable { mutableStateOf("") }
    var isLoading by remember { mutableStateOf(false) }
    var countdown by rememberSaveable { mutableStateOf(60) }
    var canResend by rememberSaveable { mutableStateOf(false) }
    var errorMessage by rememberSaveable { mutableStateOf("") }
    var showBackupPrompt by rememberSaveable { mutableStateOf(false) }

    // Geri sayım timer
    LaunchedEffect(Unit) {
        while (countdown > 0) {
            delay(1000)
            countdown--
        }
        canResend = true
    }

    // Yedek geri yukleme prompt'u — yeni cihazda mevcut yedek var mi diye sorar
    if (showBackupPrompt) {
        AlertDialog(
            onDismissRequest = {
                showBackupPrompt = false
                onVerified()
            },
            title = { Text("Mevcut bir yedeginiz var mi?") },
            text = {
                Text(
                    "Daha once sifreli bir yedek olusturduysaniz, sohbetlerinizi geri yukleyebilirsiniz."
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    showBackupPrompt = false
                    // Yedek geri yukleme akisina yonlendir
                    if (onBackupRestore != null) {
                        onBackupRestore()
                    } else {
                        onVerified()
                    }
                }) {
                    Text("Evet, yedegi geri yukle", color = Color(0xFF3E7BFA))
                }
            },
            dismissButton = {
                TextButton(onClick = {
                    showBackupPrompt = false
                    onVerified()
                }) {
                    Text("Hayir, yeni basla")
                }
            }
        )
    }

    val dark = LocalDarkTheme.current

    Box(Modifier.fillMaxSize()) {
        AzureDoodleBackdrop(dark = dark)

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Dogrulama") },
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

                        // 6 hane tamamlandiginda otomatik dogrula
                        if (newCode.length == 6) {
                            isLoading = true
                            // Simulated verification
                            // Gercek implementasyonda burada API cagrisi olacak
                            otpCode = ""
                            isLoading = false
                            // Yedek prompt'unu goster
                            showBackupPrompt = true
                        }
                    }
                },
                // Klavyede "Bitti" basildiginda 6 hane tamamsa otomatik dogrulamayi tetikle.
                // Aksi takdirde inline errorMessage gosterilir.
                onSubmit = {
                    if (otpCode.length == 6) {
                        isLoading = true
                        isLoading = false
                        showBackupPrompt = true
                    } else {
                        errorMessage = "Lütfen 6 haneli kodu tamamen girin"
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

            // Manuel dogrula butonu — azure pill
            Button(
                onClick = {
                    if (otpCode.length == 6) {
                        isLoading = true
                        // Simulated verification
                        isLoading = false
                        // Yedek prompt'unu goster
                        showBackupPrompt = true
                    } else {
                        errorMessage = "Lutfen 6 haneli kodu tamamen girin"
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
    onValueChange: (String) -> Unit,
    onSubmit: () -> Unit = {}
) {
    val focusRequester = remember { FocusRequester() }
    val keyboardController = LocalSoftwareKeyboardController.current
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
            keyboardOptions = KeyboardOptions(
                keyboardType = KeyboardType.Number,
                imeAction = ImeAction.Done
            ),
            keyboardActions = KeyboardActions(
                onDone = {
                    keyboardController?.hide()
                    onSubmit()
                }
            ),
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