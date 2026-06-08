package com.securechat.app.backup

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Backup
import androidx.compose.material.icons.filled.CloudDownload
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.TabRowDefaults.SecondaryIndicator
import androidx.compose.material3.TabRowDefaults.tabIndicatorOffset
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.securechat.app.ui.theme.AzureDoodleBackdrop
import com.securechat.app.ui.theme.LocalDarkTheme
import com.securechat.app.ui.theme.glass

/**
 * Yedekleme ve geri yukleme ekrani.
 * Iki sekmeli: "Yedekle" ve "Geri Yukle".
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BackupScreen(
    viewModel: BackupViewModel = hiltViewModel(),
    onBackClick: () -> Unit
) {
    val dark = LocalDarkTheme.current
    val snackbarHostState = remember { SnackbarHostState() }
    var selectedTab by remember { mutableIntStateOf(0) }

    // Events
    LaunchedEffect(Unit) {
        viewModel.toastEvent.collect { msg ->
            snackbarHostState.showSnackbar(msg)
        }
    }

    Box(Modifier.fillMaxSize()) {
        AzureDoodleBackdrop(dark = dark)

        Scaffold(
            containerColor = Color.Transparent,
            contentWindowInsets = WindowInsets(0),
            snackbarHost = { SnackbarHost(snackbarHostState) },
            topBar = {
                TopAppBar(
                    title = { Text("Yedekleme", fontWeight = FontWeight.SemiBold) },
                    navigationIcon = {
                        IconButton(onClick = onBackClick) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Geri")
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Transparent)
                )
            }
        ) { padding ->
            Column(
                modifier = Modifier
                    .padding(padding)
                    .fillMaxSize()
            ) {
                // Tab row
                TabRow(
                    selectedTabIndex = selectedTab,
                    containerColor = Color.Transparent,
                    contentColor = MaterialTheme.colorScheme.primary,
                    indicator = { tabPositions ->
                        if (selectedTab < tabPositions.size) {
                            SecondaryIndicator(
                                Modifier.tabIndicatorOffset(tabPositions[selectedTab]),
                                color = Color(0xFF3E7BFA)
                            )
                        }
                    }
                ) {
                    Tab(
                        selected = selectedTab == 0,
                        onClick = { selectedTab = 0 },
                        text = { Text("Yedekle") },
                        icon = { Icon(Icons.Default.Backup, contentDescription = null, Modifier.size(20.dp)) }
                    )
                    Tab(
                        selected = selectedTab == 1,
                        onClick = { selectedTab = 1 },
                        text = { Text("Geri Yükle") },
                        icon = { Icon(Icons.Default.CloudDownload, contentDescription = null, Modifier.size(20.dp)) }
                    )
                }

                when (selectedTab) {
                    0 -> CreateBackupTab(viewModel = viewModel, dark = dark)
                    1 -> RestoreBackupTab(viewModel = viewModel, dark = dark)
                }
            }
        }
    }
}

// ─── Yedekle Sekmesi ─────────────────────────────────────────────────

@Composable
private fun CreateBackupTab(viewModel: BackupViewModel, dark: Boolean) {
    val isCreating by viewModel.isCreating.collectAsStateWithLifecycle()
    val createdFile by viewModel.createdBackupFile.collectAsStateWithLifecycle()

    var password by remember { mutableStateOf("") }
    var passwordConfirm by remember { mutableStateOf("") }
    var showPassword by remember { mutableStateOf(false) }

    val passwordsMatch = password == passwordConfirm
    val isValid = password.length >= 6 && passwordsMatch

    Column(
        modifier = Modifier
            .fillMaxSize()
            .imePadding()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp, vertical = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        // Bilgi kutusu
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .glass(dark, shape = RoundedCornerShape(16.dp))
                .padding(20.dp)
        ) {
            Column {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        Icons.Default.Lock,
                        contentDescription = null,
                        tint = Color(0xFF3E7BFA),
                        modifier = Modifier.size(22.dp)
                    )
                    Spacer(Modifier.width(8.dp))
                    Text(
                        "Şifreli Yedek",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold
                    )
                }
                Spacer(Modifier.height(12.dp))
                Text(
                    "Tüm sohbetleriniz, mesajlarınız ve kişileriniz şifreli olarak yedeklenir. " +
                    "Yedeği başka bir cihazda geri yüklemek için bu şifreye ihtiyacınız olacak.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    lineHeight = 20.sp
                )
                Spacer(Modifier.height(8.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        Icons.Default.Warning,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.error,
                        modifier = Modifier.size(16.dp)
                    )
                    Spacer(Modifier.width(6.dp))
                    Text(
                        "Şifrenizi unutursanız yedeğe erişemezsiniz. 5 hatalı denemeden sonra yedek silinir.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error.copy(alpha = 0.8f),
                        lineHeight = 16.sp
                    )
                }
            }
        }

        Spacer(Modifier.height(24.dp))

        // Sifre alanlari
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .glass(dark, shape = RoundedCornerShape(16.dp))
                .padding(20.dp)
        ) {
            Column {
                OutlinedTextField(
                    value = password,
                    onValueChange = { password = it },
                    label = { Text("Yedek Şifresi") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    visualTransformation = if (showPassword) VisualTransformation.None else PasswordVisualTransformation(),
                    trailingIcon = {
                        IconButton(onClick = { showPassword = !showPassword }) {
                            Icon(
                                if (showPassword) Icons.Default.VisibilityOff else Icons.Default.Visibility,
                                contentDescription = null
                            )
                        }
                    },
                    shape = RoundedCornerShape(12.dp),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = Color(0xFF3E7BFA),
                        cursorColor = Color(0xFF3E7BFA)
                    )
                )

                Spacer(Modifier.height(12.dp))

                OutlinedTextField(
                    value = passwordConfirm,
                    onValueChange = { passwordConfirm = it },
                    label = { Text("Şifre Tekrar") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    visualTransformation = if (showPassword) VisualTransformation.None else PasswordVisualTransformation(),
                    isError = passwordConfirm.isNotEmpty() && !passwordsMatch,
                    supportingText = if (passwordConfirm.isNotEmpty() && !passwordsMatch) {
                        { Text("Şifreler eşleşmiyor") }
                    } else if (password.isNotEmpty() && password.length < 6) {
                        { Text("En az 6 karakter") }
                    } else null,
                    shape = RoundedCornerShape(12.dp),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = Color(0xFF3E7BFA),
                        cursorColor = Color(0xFF3E7BFA)
                    )
                )
            }
        }

        Spacer(Modifier.height(24.dp))

        // Yedekle butonu
        Button(
            onClick = {
                viewModel.createBackup(password)
                password = ""
                passwordConfirm = ""
            },
            enabled = isValid && !isCreating,
            modifier = Modifier
                .fillMaxWidth()
                .height(52.dp),
            shape = RoundedCornerShape(100.dp),
            colors = ButtonDefaults.buttonColors(
                containerColor = Color(0xFF3E7BFA),
                contentColor = Color.White
            )
        ) {
            if (isCreating) {
                CircularProgressIndicator(
                    modifier = Modifier.size(24.dp),
                    color = Color.White,
                    strokeWidth = 2.dp
                )
                Spacer(Modifier.width(8.dp))
                Text("Yedekleniyor...")
            } else {
                Icon(Icons.Default.Backup, contentDescription = null, Modifier.size(20.dp))
                Spacer(Modifier.width(8.dp))
                Text("Yedekle", fontWeight = FontWeight.SemiBold)
            }
        }

        // Olusturulan yedek — paylas butonu
        createdFile?.let { file ->
            Spacer(Modifier.height(20.dp))

            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .glass(dark, shape = RoundedCornerShape(16.dp))
                    .padding(16.dp)
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(
                        "Yedek hazır",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                        color = Color(0xFF4CAF50)
                    )
                    Spacer(Modifier.height(4.dp))
                    Text(
                        file.name,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Text(
                        formatFileSize(file.length()),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Spacer(Modifier.height(12.dp))

                    OutlinedButton(
                        onClick = { viewModel.shareBackupFile(file) },
                        shape = RoundedCornerShape(100.dp)
                    ) {
                        Icon(Icons.Default.Share, contentDescription = null, Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("Dosyayı Paylaş")
                    }
                }
            }
        }

        Spacer(Modifier.height(32.dp))
    }
}

// ─── Geri Yukle Sekmesi ──────────────────────────────────────────────

@Composable
private fun RestoreBackupTab(viewModel: BackupViewModel, dark: Boolean) {
    val isRestoring by viewModel.isRestoring.collectAsStateWithLifecycle()
    val restoreResult by viewModel.restoreResult.collectAsStateWithLifecycle()
    val remainingAttempts by viewModel.remainingAttempts.collectAsStateWithLifecycle()

    var selectedUri by remember { mutableStateOf<Uri?>(null) }
    var password by remember { mutableStateOf("") }
    var showPassword by remember { mutableStateOf(false) }

    val filePickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocument()
    ) { uri: Uri? ->
        if (uri != null) {
            selectedUri = uri
            viewModel.updateRemainingAttempts(uri)
            viewModel.clearRestoreResult()
            password = ""
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .imePadding()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp, vertical = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        // Bilgi kutusu
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .glass(dark, shape = RoundedCornerShape(16.dp))
                .padding(20.dp)
        ) {
            Column {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        Icons.Default.CloudDownload,
                        contentDescription = null,
                        tint = Color(0xFF3E7BFA),
                        modifier = Modifier.size(22.dp)
                    )
                    Spacer(Modifier.width(8.dp))
                    Text(
                        "Yedeği Geri Yükle",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold
                    )
                }
                Spacer(Modifier.height(12.dp))
                Text(
                    "Daha önce oluşturduğunuz şifreli yedek dosyasını (.elbk) seçin. " +
                    "Yedekleme sırasında belirlediğiniz şifreyi girmeniz gerekecek.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    lineHeight = 20.sp
                )
                Spacer(Modifier.height(8.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        Icons.Default.Warning,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.error,
                        modifier = Modifier.size(16.dp)
                    )
                    Spacer(Modifier.width(6.dp))
                    Text(
                        "5 hatalı şifre denemesinden sonra yedek dosyası kalıcı olarak silinir.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error.copy(alpha = 0.8f),
                        lineHeight = 16.sp
                    )
                }
            }
        }

        Spacer(Modifier.height(20.dp))

        // Dosya sec butonu
        OutlinedButton(
            onClick = { filePickerLauncher.launch(arrayOf("*/*")) },
            modifier = Modifier.fillMaxWidth().height(52.dp),
            shape = RoundedCornerShape(100.dp)
        ) {
            Icon(Icons.Default.CloudDownload, contentDescription = null, Modifier.size(20.dp))
            Spacer(Modifier.width(8.dp))
            Text(if (selectedUri != null) "Dosya Seçildi" else "Yedek Dosyası Seç")
        }

        if (selectedUri != null) {
            Spacer(Modifier.height(20.dp))

            // Sifre girisi
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .glass(dark, shape = RoundedCornerShape(16.dp))
                    .padding(20.dp)
            ) {
                Column {
                    OutlinedTextField(
                        value = password,
                        onValueChange = { password = it },
                        label = { Text("Yedek Şifresi") },
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true,
                        visualTransformation = if (showPassword) VisualTransformation.None else PasswordVisualTransformation(),
                        trailingIcon = {
                            IconButton(onClick = { showPassword = !showPassword }) {
                                Icon(
                                    if (showPassword) Icons.Default.VisibilityOff else Icons.Default.Visibility,
                                    contentDescription = null
                                )
                            }
                        },
                        shape = RoundedCornerShape(12.dp),
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedBorderColor = Color(0xFF3E7BFA),
                            cursorColor = Color(0xFF3E7BFA)
                        )
                    )

                    Spacer(Modifier.height(8.dp))

                    // Kalan hak gostergesi
                    Text(
                        "Kalan deneme hakkı: $remainingAttempts / 5",
                        style = MaterialTheme.typography.bodySmall,
                        color = if (remainingAttempts <= 2) MaterialTheme.colorScheme.error
                               else MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            Spacer(Modifier.height(20.dp))

            // Geri yukle butonu
            Button(
                onClick = {
                    selectedUri?.let { uri ->
                        viewModel.restoreBackup(uri, password)
                    }
                },
                enabled = password.isNotEmpty() && !isRestoring,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(52.dp),
                shape = RoundedCornerShape(100.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = Color(0xFF3E7BFA),
                    contentColor = Color.White
                )
            ) {
                if (isRestoring) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(24.dp),
                        color = Color.White,
                        strokeWidth = 2.dp
                    )
                    Spacer(Modifier.width(8.dp))
                    Text("Geri yükleniyor...")
                } else {
                    Icon(Icons.Default.CloudDownload, contentDescription = null, Modifier.size(20.dp))
                    Spacer(Modifier.width(8.dp))
                    Text("Geri Yükle", fontWeight = FontWeight.SemiBold)
                }
            }

            // Sonuc mesajlari
            restoreResult?.let { result ->
                Spacer(Modifier.height(16.dp))
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .glass(dark, shape = RoundedCornerShape(16.dp))
                        .padding(16.dp)
                ) {
                    when (result) {
                        is BackupManager.RestoreResult.Success -> {
                            Text(
                                "Yedek başarıyla geri yüklendi! Uygulamayı yeniden başlatmanız önerilir.",
                                color = Color(0xFF4CAF50),
                                style = MaterialTheme.typography.bodyMedium,
                                textAlign = TextAlign.Center,
                                modifier = Modifier.fillMaxWidth()
                            )
                        }
                        is BackupManager.RestoreResult.WrongPassword -> {
                            Text(
                                "Şifre hatalı. Kalan hak: $remainingAttempts",
                                color = MaterialTheme.colorScheme.error,
                                style = MaterialTheme.typography.bodyMedium,
                                textAlign = TextAlign.Center,
                                modifier = Modifier.fillMaxWidth()
                            )
                        }
                        is BackupManager.RestoreResult.AttemptsExhausted -> {
                            Column(
                                horizontalAlignment = Alignment.CenterHorizontally,
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Icon(
                                    Icons.Default.Warning,
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.error,
                                    modifier = Modifier.size(32.dp)
                                )
                                Spacer(Modifier.height(8.dp))
                                Text(
                                    "5 hatalı deneme!\nYedek dosyası güvenlik nedeniyle silindi.",
                                    color = MaterialTheme.colorScheme.error,
                                    style = MaterialTheme.typography.bodyMedium,
                                    textAlign = TextAlign.Center,
                                    fontWeight = FontWeight.SemiBold
                                )
                            }
                        }
                        is BackupManager.RestoreResult.Error -> {
                            Text(
                                result.message,
                                color = MaterialTheme.colorScheme.error,
                                style = MaterialTheme.typography.bodyMedium,
                                textAlign = TextAlign.Center,
                                modifier = Modifier.fillMaxWidth()
                            )
                        }
                    }
                }
            }
        }

        Spacer(Modifier.height(32.dp))
    }
}

/**
 * Dosya boyutunu insan-okunabilir bicimde formatlar.
 * Onceki "%.2f MB" sabit format'i 2 KB'lik dosyada "0.00 MB" gosteriyordu
 * (KB seviyesinde sifira yuvarlaniyor). Bu helper boyuta gore birim secer:
 *   < 1 KB   → "N B"
 *   < 1 MB   → "N.N KB"
 *   < 1 GB   → "N.NN MB"
 *   >= 1 GB  → "N.NN GB"
 */
private fun formatFileSize(bytes: Long): String {
    val kb = 1024.0
    val mb = kb * 1024
    val gb = mb * 1024
    return when {
        bytes < kb -> "$bytes B"
        bytes < mb -> "%.1f KB".format(bytes / kb)
        bytes < gb -> "%.2f MB".format(bytes / mb)
        else -> "%.2f GB".format(bytes / gb)
    }
}
