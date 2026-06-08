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
import androidx.compose.runtime.saveable.rememberSaveable
import kotlinx.coroutines.launch
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.securechat.app.R
import com.securechat.app.ui.theme.AzureDoodleBackdrop
import com.securechat.app.ui.theme.LocalDarkTheme

/**
 * E-posta OTP doğrulama ekranı.
 *
 * Akış:
 *   1. Kullanıcı e-posta girer → [email_otp_send] → /otp/request
 *   2. 6-haneli OTP girer → [otp_verify] → /otp/verify → registrationToken
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
    // Form girdileri + UI ilerleme saveable — rotation/process death dayanikli.
    // `loading` saveable degil — coroutine rotation'da restart edilmez, eski spinner
    // zombi kalir.
    var email by rememberSaveable { mutableStateOf("") }
    var otpCode by rememberSaveable { mutableStateOf("") }
    var step by rememberSaveable { mutableStateOf(1) } // 1=email, 2=otp
    var loading by remember { mutableStateOf(false) }
    var error by rememberSaveable { mutableStateOf<String?>(null) }
    var info by rememberSaveable { mutableStateOf<String?>(null) }
    var smtpDisabled by rememberSaveable { mutableStateOf(false) }

    val scope = rememberCoroutineScope()
    val keyboardController = LocalSoftwareKeyboardController.current

    // Lokalize string'leri Composable scope'ta tek seferlik resolve et — submit
    // lambda'sindan kullanilabilsin (onClick non-composable).
    val invalidEmailMsg = stringResource(R.string.email_otp_invalid_email)
    val sentMsg = stringResource(R.string.email_otp_sent)
    val smtpDisabledMsg = stringResource(R.string.email_otp_smtp_disabled)
    val rateLimitedMsg = stringResource(R.string.email_otp_rate_limited)
    val sendErrorTemplate = stringResource(R.string.email_otp_send_error)
    val verifyFailedMsg = stringResource(R.string.email_otp_verify_failed)
    val incompleteMsg = stringResource(R.string.email_otp_incomplete)

    /**
     * Submit aksiyonu — Button'un onClick'inin ic mantigini tekrar kullanmak icin
     * cikarildi. Hem buton tikinda hem klavyenin Done aksiyonunda cagrilir.
     */
    fun submitCurrentStep() {
        if (loading) return
        keyboardController?.hide()
        if (step == 1) {
            if (!email.matches(Regex("^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"))) {
                error = invalidEmailMsg
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
                        info = sentMsg
                    }
                    OtpApiClient.OtpResult.SmtpDisabled -> {
                        smtpDisabled = true
                        error = smtpDisabledMsg
                    }
                    OtpApiClient.OtpResult.RateLimited -> {
                        error = rateLimitedMsg
                    }
                    is OtpApiClient.OtpResult.Error -> {
                        error = sendErrorTemplate.format(result.message)
                    }
                }
            }
        } else {
            if (otpCode.length != 6) {
                error = incompleteMsg
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
                    error = verifyFailedMsg
                    otpCode = ""
                }
            }
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.email_otp_title), fontWeight = FontWeight.SemiBold) },
                navigationIcon = {
                    IconButton(onClick = onBackClick) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.nav_back))
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
                    text = if (step == 1)
                        stringResource(R.string.email_otp_step_email)
                    else
                        stringResource(R.string.email_otp_step_code),
                    fontSize = 24.sp,
                    fontWeight = FontWeight.Bold,
                    textAlign = TextAlign.Center
                )

                Spacer(modifier = Modifier.height(8.dp))

                Text(
                    text = if (step == 1)
                        stringResource(R.string.email_otp_description_email)
                    else
                        stringResource(R.string.email_otp_description_code, email),
                    fontSize = 14.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center
                )

                Spacer(modifier = Modifier.height(32.dp))

                if (step == 1) {
                    OutlinedTextField(
                        value = email,
                        onValueChange = { email = it.trim(); error = null },
                        label = { Text(stringResource(R.string.email_otp_email_label)) },
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
                        label = { Text(stringResource(R.string.email_otp_code_label)) },
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
                            text = if (step == 1)
                                stringResource(R.string.email_otp_send)
                            else
                                stringResource(R.string.otp_verify),
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
                    ) { Text(stringResource(R.string.email_otp_change_email)) }
                }

                if (smtpDisabled) {
                    Spacer(modifier = Modifier.height(16.dp))
                    OutlinedButton(
                        onClick = onSkip,
                        modifier = Modifier.fillMaxWidth()
                    ) { Text(stringResource(R.string.email_otp_dev_skip)) }
                }

                Spacer(modifier = Modifier.height(32.dp))
            }
        }
    }
}

