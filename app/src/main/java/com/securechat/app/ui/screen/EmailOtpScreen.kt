package com.securechat.app.ui.screen

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Email
import androidx.compose.material3.*
import androidx.compose.runtime.*
import kotlinx.coroutines.launch
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.securechat.app.ui.theme.AzureDoodleBackdrop
import com.securechat.app.ui.theme.LocalDarkTheme

/**
 * E-posta OTP doğrulama ekranı.
 *
 * Akış:
 *   1. Kullanıcı e-posta girer → "Kod Gönder" → /otp/request
 *   2. 6-haneli OTP girer → "Doğrula" → /otp/verify → registrationToken
 *   3. registrationToken üst seviyeye iletilir (register akışında kullanılır)
 *
 * SMTP yapılandırılmamışsa /otp/request 503 döner — UI bunu gösterir ve
 * kullanıcının "Atla" butonuyla geçmesine izin verir (development modu).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EmailOtpScreen(
    onVerified: (registrationToken: String) -> Unit,
    onSkip: () -> Unit, // SMTP yoksa development modu — atlamaya izin ver
    onBackClick: () -> Unit,
    apiBaseUrl: String
) {
    var email by remember { mutableStateOf("") }
    var otpCode by remember { mutableStateOf("") }
    var step by remember { mutableStateOf(1) } // 1=email, 2=otp
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var info by remember { mutableStateOf<String?>(null) }
    var smtpDisabled by remember { mutableStateOf(false) }

    val scope = rememberCoroutineScope()
    val keyboardController = LocalSoftwareKeyboardController.current

    /**
     * Submit aksiyonu — Button'un onClick'inin ic mantigini tekrar kullanmak icin
     * cikarildi. Hem buton tikinda hem klavyenin Done aksiyonunda cagrilir.
     */
    fun submitCurrentStep() {
        if (loading) return
        keyboardController?.hide()
        if (step == 1) {
            if (!email.matches(Regex("^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"))) {
                error = "Geçerli bir e-posta girin"
                return
            }
            loading = true
            error = null
            scope.launch {
                val result = OtpApiClient.requestOtp(apiBaseUrl, email)
                loading = false
                when (result) {
                    OtpApiClient.OtpResult.Sent -> {
                        step = 2
                        info = "Kod e-postanıza gönderildi"
                    }
                    OtpApiClient.OtpResult.SmtpDisabled -> {
                        smtpDisabled = true
                        error = "Sunucuda e-posta servisi yapılandırılmamış. Lütfen yöneticiyle iletişime geçin veya geliştirme modunda 'Atla' butonunu kullanın."
                    }
                    OtpApiClient.OtpResult.RateLimited -> {
                        error = "Çok fazla deneme. Lütfen birkaç dakika bekleyin."
                    }
                    is OtpApiClient.OtpResult.Error -> {
                        error = "Kod gönderilemedi: ${result.message}"
                    }
                }
            }
        } else {
            if (otpCode.length != 6) {
                error = "6 haneli kodu eksiksiz girin"
                return
            }
            loading = true
            error = null
            scope.launch {
                val token = OtpApiClient.verifyOtp(apiBaseUrl, email, otpCode)
                loading = false
                if (token != null) {
                    onVerified(token)
                } else {
                    error = "Kod hatalı veya süresi dolmuş"
                    otpCode = ""
                }
            }
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("E-posta Doğrulama", fontWeight = FontWeight.SemiBold) },
                navigationIcon = {
                    IconButton(onClick = onBackClick) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Geri")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Transparent)
            )
        },
        containerColor = Color.Transparent
    ) { padding ->
        Box(modifier = Modifier.fillMaxSize()) {
            AzureDoodleBackdrop(modifier = Modifier.fillMaxSize())

            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .padding(horizontal = 24.dp)
                    .verticalScroll(rememberScrollState())
                    .imePadding(),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Spacer(modifier = Modifier.height(48.dp))

                Icon(
                    Icons.Default.Email,
                    contentDescription = null,
                    modifier = Modifier.size(64.dp),
                    tint = MaterialTheme.colorScheme.primary
                )

                Spacer(modifier = Modifier.height(16.dp))

                Text(
                    text = if (step == 1) "E-posta Adresiniz" else "Doğrulama Kodu",
                    fontSize = 24.sp,
                    fontWeight = FontWeight.Bold,
                    textAlign = TextAlign.Center
                )

                Spacer(modifier = Modifier.height(8.dp))

                Text(
                    text = if (step == 1)
                        "Hesabınızı doğrulamak için e-posta adresinizi girin. Kodu e-postanıza göndereceğiz."
                    else
                        "$email adresine gönderilen 6 haneli kodu girin.",
                    fontSize = 14.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center
                )

                Spacer(modifier = Modifier.height(32.dp))

                if (step == 1) {
                    OutlinedTextField(
                        value = email,
                        onValueChange = { email = it.trim(); error = null },
                        label = { Text("E-posta") },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(
                            keyboardType = KeyboardType.Email,
                            imeAction = ImeAction.Send
                        ),
                        keyboardActions = KeyboardActions(onSend = { submitCurrentStep() }),
                        modifier = Modifier.fillMaxWidth(),
                        isError = error != null,
                        supportingText = if (error != null) {
                            { Text(error!!) }
                        } else null
                    )
                } else {
                    OutlinedTextField(
                        value = otpCode,
                        onValueChange = {
                            if (it.length <= 6 && it.all { c -> c.isDigit() }) {
                                otpCode = it; error = null
                            }
                        },
                        label = { Text("6 Haneli Kod") },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(
                            keyboardType = KeyboardType.Number,
                            imeAction = ImeAction.Done
                        ),
                        keyboardActions = KeyboardActions(onDone = { submitCurrentStep() }),
                        modifier = Modifier.fillMaxWidth(),
                        isError = error != null,
                        supportingText = if (error != null) {
                            { Text(error!!) }
                        } else null
                    )
                }

                if (info != null) {
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        text = info!!,
                        color = MaterialTheme.colorScheme.primary,
                        fontSize = 13.sp
                    )
                }

                Spacer(modifier = Modifier.height(24.dp))

                Button(
                    onClick = { submitCurrentStep() },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(52.dp)
                        .clip(RoundedCornerShape(12.dp)),
                    enabled = !loading
                ) {
                    if (loading) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(20.dp),
                            color = Color.White,
                            strokeWidth = 2.dp
                        )
                    } else {
                        Text(
                            text = if (step == 1) "Kod Gönder" else "Doğrula",
                            fontSize = 16.sp,
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                }

                if (step == 2) {
                    Spacer(modifier = Modifier.height(8.dp))
                    TextButton(
                        onClick = {
                            step = 1
                            otpCode = ""
                            error = null
                            info = null
                        }
                    ) { Text("Farklı e-posta kullan") }
                }

                if (smtpDisabled) {
                    Spacer(modifier = Modifier.height(16.dp))
                    OutlinedButton(
                        onClick = onSkip,
                        modifier = Modifier.fillMaxWidth()
                    ) { Text("Geliştirme Modu — Atla") }
                }

                Spacer(modifier = Modifier.height(32.dp))
            }
        }
    }
}

