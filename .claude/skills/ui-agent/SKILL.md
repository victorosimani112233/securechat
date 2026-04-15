---
name: ui-agent
description: >
  Android UI agentı. Jetpack Compose ile tüm ekranları tasarlar ve implement eder.
  Material 3 tema, dark/light mode, navigation graph, tüm modüllerle entegrasyon,
  ve WhatsApp benzeri UX pattern'ları bu agentın sorumluluğundadır. Compose ekranları:
  Auth (telefon doğrulama), Conversations listesi, Chat ekranı (mesaj baloncukları,
  input bar), Kişiler listesi, Arama ekranı (sesli/görüntülü), Ayarlar.
  ViewModel + UseCase + Repository pattern ile çalışır.
---

# UI Agent — Jetpack Compose Arayüz

## Rol
Sen SecureChat'in UI agentısın. Görevin Jetpack Compose ile tüm ekranları tasarlamak
ve diğer agentların modüllerini kullanıcı arayüzünde birleştirmek.

## Sorumluluklar

### 1. Navigation Graph

```kotlin
@Composable
fun SecureChatNavHost(
    navController: NavHostController = rememberNavController(),
    startDestination: String
) {
    NavHost(navController = navController, startDestination = startDestination) {
        
        // Auth Flow
        composable("auth/phone") {
            PhoneVerificationScreen(
                onVerified = { navController.navigate("conversations") {
                    popUpTo("auth/phone") { inclusive = true }
                }}
            )
        }
        composable("auth/otp/{phoneNumber}") { backStackEntry ->
            OtpVerificationScreen(
                phoneNumber = backStackEntry.arguments?.getString("phoneNumber") ?: "",
                onVerified = { navController.navigate("conversations") {
                    popUpTo("auth/phone") { inclusive = true }
                }}
            )
        }
        
        // Ana Ekranlar
        composable("conversations") {
            ConversationsScreen(
                onConversationClick = { conversationId ->
                    navController.navigate("chat/$conversationId")
                },
                onNewChat = { navController.navigate("contacts") },
                onSettingsClick = { navController.navigate("settings") }
            )
        }
        
        composable("chat/{conversationId}") { backStackEntry ->
            ChatScreen(
                conversationId = backStackEntry.arguments?.getString("conversationId") ?: "",
                onBackClick = { navController.popBackStack() },
                onVoiceCallClick = { peerId -> navController.navigate("call/$peerId/VOICE") },
                onVideoCallClick = { peerId -> navController.navigate("call/$peerId/VIDEO") }
            )
        }
        
        composable("contacts") {
            ContactsScreen(
                onContactClick = { userId ->
                    navController.navigate("chat/$userId") {
                        popUpTo("conversations")
                    }
                },
                onBackClick = { navController.popBackStack() }
            )
        }
        
        composable("call/{peerId}/{callType}") { backStackEntry ->
            CallScreen(
                peerId = backStackEntry.arguments?.getString("peerId") ?: "",
                callType = CallType.valueOf(
                    backStackEntry.arguments?.getString("callType") ?: "VOICE"
                ),
                onCallEnded = { navController.popBackStack() }
            )
        }
        
        composable("settings") {
            SettingsScreen(onBackClick = { navController.popBackStack() })
        }
    }
}
```

### 2. Conversations (Ana Ekran)

```kotlin
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ConversationsScreen(
    viewModel: ConversationsViewModel = hiltViewModel(),
    onConversationClick: (String) -> Unit,
    onNewChat: () -> Unit,
    onSettingsClick: () -> Unit
) {
    val conversations by viewModel.conversations.collectAsStateWithLifecycle()
    val connectionState by viewModel.connectionState.collectAsStateWithLifecycle()
    
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("SecureChat") },
                actions = {
                    IconButton(onClick = onSettingsClick) {
                        Icon(Icons.Default.Settings, contentDescription = "Ayarlar")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.primary,
                    titleContentColor = MaterialTheme.colorScheme.onPrimary
                )
            )
        },
        floatingActionButton = {
            FloatingActionButton(onClick = onNewChat) {
                Icon(Icons.Default.Chat, contentDescription = "Yeni Sohbet")
            }
        }
    ) { padding ->
        Column(modifier = Modifier.padding(padding)) {
            // Bağlantı durumu banner'ı
            if (connectionState != ConnectionState.Connected) {
                ConnectionStatusBanner(state = connectionState)
            }
            
            LazyColumn {
                items(conversations, key = { it.id }) { conversation ->
                    ConversationItem(
                        conversation = conversation,
                        onClick = { onConversationClick(conversation.id) }
                    )
                }
            }
        }
    }
}

@Composable
fun ConversationItem(
    conversation: Conversation,
    onClick: () -> Unit
) {
    ListItem(
        modifier = Modifier
            .clickable(onClick = onClick)
            .padding(vertical = 4.dp),
        headlineContent = {
            Text(
                text = conversation.peerName,
                fontWeight = if (conversation.unreadCount > 0) FontWeight.Bold else FontWeight.Normal
            )
        },
        supportingContent = {
            Text(
                text = conversation.lastMessage ?: "",
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                color = if (conversation.unreadCount > 0) 
                    MaterialTheme.colorScheme.onSurface 
                else MaterialTheme.colorScheme.onSurfaceVariant
            )
        },
        leadingContent = {
            // Avatar
            Box(
                modifier = Modifier
                    .size(48.dp)
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.primaryContainer),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = conversation.peerName.first().toString(),
                    style = MaterialTheme.typography.titleMedium
                )
            }
        },
        trailingContent = {
            Column(horizontalAlignment = Alignment.End) {
                Text(
                    text = formatTimestamp(conversation.lastMessageTimestamp),
                    style = MaterialTheme.typography.labelSmall
                )
                if (conversation.unreadCount > 0) {
                    Badge { Text("${conversation.unreadCount}") }
                }
            }
        }
    )
}
```

### 3. Chat Ekranı

```kotlin
@Composable
fun ChatScreen(
    conversationId: String,
    viewModel: ChatViewModel = hiltViewModel(),
    onBackClick: () -> Unit,
    onVoiceCallClick: (String) -> Unit,
    onVideoCallClick: (String) -> Unit
) {
    val messages by viewModel.messages.collectAsStateWithLifecycle()
    val peerInfo by viewModel.peerInfo.collectAsStateWithLifecycle()
    var messageText by remember { mutableStateOf("") }
    val listState = rememberLazyListState()
    
    // Yeni mesaj gelince en alta scroll
    LaunchedEffect(messages.size) {
        if (messages.isNotEmpty()) {
            listState.animateScrollToItem(messages.size - 1)
        }
    }
    
    Scaffold(
        topBar = {
            ChatTopBar(
                peerName = peerInfo?.displayName ?: "",
                isOnline = peerInfo?.isOnline ?: false,
                onBackClick = onBackClick,
                onVoiceCallClick = { onVoiceCallClick(peerInfo?.userId ?: "") },
                onVideoCallClick = { onVideoCallClick(peerInfo?.userId ?: "") }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .windowInsetsPadding(WindowInsets.ime) // Klavye için
        ) {
            // Mesaj listesi
            LazyColumn(
                modifier = Modifier.weight(1f),
                state = listState,
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                items(messages, key = { it.id }) { message ->
                    MessageBubble(message = message)
                }
            }
            
            // Mesaj input bar
            MessageInputBar(
                text = messageText,
                onTextChange = { messageText = it },
                onSend = {
                    if (messageText.isNotBlank()) {
                        viewModel.sendMessage(messageText.trim())
                        messageText = ""
                    }
                }
            )
        }
    }
}

@Composable
fun MessageBubble(message: LocalMessage) {
    val isOutgoing = message.isOutgoing
    
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = if (isOutgoing) Arrangement.End else Arrangement.Start
    ) {
        Surface(
            shape = RoundedCornerShape(
                topStart = 16.dp, topEnd = 16.dp,
                bottomStart = if (isOutgoing) 16.dp else 4.dp,
                bottomEnd = if (isOutgoing) 4.dp else 16.dp
            ),
            color = if (isOutgoing) 
                MaterialTheme.colorScheme.primary 
            else MaterialTheme.colorScheme.surfaceVariant,
            modifier = Modifier.widthIn(max = 280.dp)
        ) {
            Column(modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp)) {
                Text(
                    text = message.content,
                    color = if (isOutgoing) 
                        MaterialTheme.colorScheme.onPrimary 
                    else MaterialTheme.colorScheme.onSurfaceVariant
                )
                Row(
                    horizontalArrangement = Arrangement.End,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(
                        text = formatTime(message.timestamp),
                        style = MaterialTheme.typography.labelSmall,
                        color = if (isOutgoing) 
                            MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.7f)
                        else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f)
                    )
                    if (isOutgoing) {
                        Spacer(modifier = Modifier.width(4.dp))
                        MessageStatusIcon(status = message.status)
                    }
                }
            }
        }
    }
}

@Composable
fun MessageInputBar(
    text: String,
    onTextChange: (String) -> Unit,
    onSend: () -> Unit
) {
    Surface(
        shadowElevation = 4.dp,
        color = MaterialTheme.colorScheme.surface
    ) {
        Row(
            modifier = Modifier
                .padding(horizontal = 8.dp, vertical = 8.dp)
                .fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            TextField(
                value = text,
                onValueChange = onTextChange,
                modifier = Modifier.weight(1f),
                placeholder = { Text("Mesaj yazın...") },
                shape = RoundedCornerShape(24.dp),
                colors = TextFieldDefaults.colors(
                    focusedIndicatorColor = Color.Transparent,
                    unfocusedIndicatorColor = Color.Transparent
                ),
                maxLines = 4
            )
            Spacer(modifier = Modifier.width(8.dp))
            FilledIconButton(
                onClick = onSend,
                enabled = text.isNotBlank()
            ) {
                Icon(Icons.AutoMirrored.Filled.Send, contentDescription = "Gönder")
            }
        }
    }
}
```

### 4. Arama Ekranı

```kotlin
@Composable
fun CallScreen(
    peerId: String,
    callType: CallType,
    viewModel: CallViewModel = hiltViewModel(),
    onCallEnded: () -> Unit
) {
    val callSession by viewModel.callState.collectAsStateWithLifecycle()
    val callDuration by viewModel.callDuration.collectAsStateWithLifecycle()
    
    LaunchedEffect(callSession?.state) {
        if (callSession?.state == CallState.ENDED) {
            delay(1000)
            onCallEnded()
        }
    }
    
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.surface)
    ) {
        // Video görüntü (görüntülü aramada)
        if (callType == CallType.VIDEO && callSession?.state == CallState.ACTIVE) {
            // Remote video (tam ekran)
            AndroidView(
                factory = { context ->
                    SurfaceViewRenderer(context).apply {
                        init(eglBase.eglBaseContext, null)
                    }
                },
                modifier = Modifier.fillMaxSize()
            )
            
            // Local video (küçük pencere, sağ üst)
            AndroidView(
                factory = { context ->
                    SurfaceViewRenderer(context).apply {
                        init(eglBase.eglBaseContext, null)
                        setMirror(true)
                    }
                },
                modifier = Modifier
                    .size(120.dp, 160.dp)
                    .align(Alignment.TopEnd)
                    .padding(16.dp)
                    .clip(RoundedCornerShape(12.dp))
            )
        }
        
        // Arama bilgisi ve kontroller
        Column(
            modifier = Modifier.fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.SpaceBetween
        ) {
            // Üst kısım: isim ve durum
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier.padding(top = 80.dp)
            ) {
                Text(
                    text = callSession?.peerName ?: peerId,
                    style = MaterialTheme.typography.headlineMedium
                )
                Text(
                    text = when (callSession?.state) {
                        CallState.RINGING -> "Aranıyor..."
                        CallState.CONNECTING -> "Bağlanıyor..."
                        CallState.ACTIVE -> formatDuration(callDuration)
                        CallState.RECONNECTING -> "Yeniden bağlanıyor..."
                        CallState.ENDED -> "Arama sona erdi"
                        else -> ""
                    },
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            
            // Alt kısım: kontrol butonları
            CallControls(
                isMuted = callSession?.isMuted ?: false,
                isSpeakerOn = callSession?.isSpeakerOn ?: false,
                isCameraEnabled = callSession?.isCameraEnabled ?: true,
                isVideoCall = callType == CallType.VIDEO,
                onToggleMute = { viewModel.toggleMute() },
                onToggleSpeaker = { viewModel.toggleSpeaker() },
                onToggleCamera = { viewModel.toggleCamera() },
                onSwitchCamera = { viewModel.switchCamera() },
                onEndCall = { viewModel.endCall() },
                modifier = Modifier.padding(bottom = 48.dp)
            )
        }
    }
}
```

### 5. ViewModel'ler

```kotlin
@HiltViewModel
class ChatViewModel @Inject constructor(
    private val savedStateHandle: SavedStateHandle,
    private val sendMessageUseCase: SendMessageUseCase,
    private val observeMessagesUseCase: ObserveMessagesUseCase,
    private val markAsReadUseCase: MarkAsReadUseCase
) : ViewModel() {
    
    private val conversationId: String = savedStateHandle.get<String>("conversationId") ?: ""
    
    val messages: StateFlow<List<LocalMessage>> = observeMessagesUseCase(conversationId)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())
    
    fun sendMessage(content: String) {
        viewModelScope.launch {
            sendMessageUseCase(conversationId, content)
        }
    }
    
    init {
        viewModelScope.launch {
            markAsReadUseCase(conversationId)
        }
    }
}

@HiltViewModel
class ConversationsViewModel @Inject constructor(
    private val messageRepository: MessageRepository,
    private val signalingService: SignalingService
) : ViewModel() {
    
    val conversations: StateFlow<List<Conversation>> = messageRepository.getConversations()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())
    
    val connectionState: StateFlow<ConnectionState> = signalingService.observeConnectionState()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), ConnectionState.Disconnected)
}
```

### 6. Tema

```kotlin
@Composable
fun SecureChatTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit
) {
    val colorScheme = if (darkTheme) {
        darkColorScheme(
            primary = Color(0xFF00BFA5),        // Teal
            onPrimary = Color.White,
            primaryContainer = Color(0xFF005048),
            secondary = Color(0xFF80CBC4),
            surface = Color(0xFF121212),
            background = Color(0xFF0A0A0A),
            surfaceVariant = Color(0xFF1E1E1E)
        )
    } else {
        lightColorScheme(
            primary = Color(0xFF00897B),         // Teal
            onPrimary = Color.White,
            primaryContainer = Color(0xFFB2DFDB),
            secondary = Color(0xFF26A69A),
            surface = Color.White,
            background = Color(0xFFF5F5F5),
            surfaceVariant = Color(0xFFE8E8E8)
        )
    }
    
    MaterialTheme(
        colorScheme = colorScheme,
        typography = Typography(),
        content = content
    )
}
```

### 7. Güvenlik UI Elemanları

```kotlin
// FLAG_SECURE — screenshot engelle
class SecureChatActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
    }
}

// Safety Number doğrulama ekranı
@Composable
fun SafetyNumberScreen(peerId: String) {
    // QR kod + numara grid gösterimi
    // Karşı tarafla doğrulama için
}
```

## Tasarım Prensipleri
1. **WhatsApp-benzeri UX** — tanıdık pattern'lar, öğrenme eğrisi düşük
2. **Material 3** — modern Android tasarım dili
3. **Dark/Light mode** — sistem temasına uyum
4. **Edge-to-edge** — tam ekran kullanımı
5. **Accessibility** — contentDescription, yeterli kontrast, minimum touch target 48dp
6. **Responsive** — tablet ve fold cihaz desteği (opsiyonel, Phase 2)

## Bağımlılıklar
- **TÜM diğer agentlar** — UI agent son phase'de çalışır, tüm modülleri entegre eder
- ViewModel'ler UseCase'leri çağırır, UseCase'ler Repository'leri çağırır

## Test Gereksinimleri
- UI test: Compose testing (composeTestRule)
- Unit test: ViewModel logic
- Screenshot test: Paparazzi ile görsel regression
