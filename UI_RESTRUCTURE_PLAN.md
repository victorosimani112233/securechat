# SecureChat UI Yeniden Yapilandirma Plani

## 1. MEVCUT YAPI vs HEDEF YAPI

### MEVCUT (Sorunlu)
```
app/src/main/java/com/securechat/app/
├── ui/
│   ├── screen/                     # 13 dev dosya (2200 satira kadar)
│   │   ├── ChatScreen.kt           # 2212 satir - monolitik
│   │   ├── CallScreen.kt           # 1590 satir - monolitik
│   │   ├── ConversationsScreen.kt   # 1036 satir
│   │   ├── GroupInfoScreen.kt       # 984 satir
│   │   ├── ChatInfoScreen.kt        # 947 satir
│   │   ├── ContactsScreen.kt        # 826 satir
│   │   ├── SettingsScreen.kt        # 640 satir
│   │   ├── AddGroupMemberScreen.kt  # 537 satir
│   │   ├── CreateGroupScreen.kt     # 535 satir
│   │   ├── PhoneVerificationScreen.kt # 382 satir - tek fonksiyon!
│   │   ├── OtpVerificationScreen.kt # 340 satir
│   │   ├── CallHistoryScreen.kt     # 271 satir
│   │   └── SplashScreen.kt          # 181 satir
│   ├── components/                  # 11 dosya - iyi ama yetersiz
│   │   ├── GlassComponents.kt
│   │   ├── CallControls.kt
│   │   ├── TypingIndicator.kt
│   │   ├── ... (8 tane daha)
│   │   └── ThemeManager.kt          # YANLIS YER - component degil
│   └── theme/
│       ├── viewmodel/               # YANLIS YER - theme altinda olmamali
│       │   ├── ChatViewModel.kt     # 672 satir - god object
│       │   ├── CreateGroupViewModel.kt
│       │   ├── ... (8 tane daha)
│       ├── SecureChatTheme.kt
│       ├── AzureTokens.kt
│       ├── AzureType.kt
│       ├── Glass.kt
│       └── DoodleBackdrop.kt
├── navigation/
│   └── SecureChatNavHost.kt
├── domain/usecase/
├── data/
├── di/
└── util/
```

### HEDEF (Temiz)
```
app/src/main/java/com/securechat/app/
├── ui/
│   ├── screen/
│   │   ├── chat/                         # Feature-based grouping
│   │   │   ├── ChatScreen.kt            # ~120 satir (sadece scaffold + state wiring)
│   │   │   ├── ChatTopBar.kt            # ~80 satir
│   │   │   ├── MessageList.kt           # ~60 satir (LazyColumn wrapper)
│   │   │   ├── MessageBubble.kt         # ~150 satir (balon + icerik)
│   │   │   ├── MessageInputBar.kt       # ~100 satir
│   │   │   ├── ChatDialogs.kt           # ~80 satir (disappearing, forward picker)
│   │   │   └── ChatSearchBar.kt         # ~50 satir
│   │   ├── call/
│   │   │   ├── CallScreen.kt            # ~150 satir (scaffold + state)
│   │   │   ├── CallAvatar.kt            # ~100 satir (pulse animasyonlari)
│   │   │   ├── CallBackground.kt        # ~120 satir (gradient + particles)
│   │   │   ├── IncomingCallOverlay.kt    # ~80 satir
│   │   │   └── GroupVideoGrid.kt        # ~60 satir
│   │   ├── conversations/
│   │   │   ├── ConversationsScreen.kt    # ~100 satir
│   │   │   ├── ConversationItem.kt       # ~80 satir
│   │   │   ├── SwipeActions.kt           # ~70 satir (archive/delete ortak)
│   │   │   └── FilterChipRow.kt          # ~40 satir
│   │   ├── contacts/
│   │   │   ├── ContactsScreen.kt         # ~100 satir
│   │   │   └── ContactItem.kt            # ~50 satir
│   │   ├── group/
│   │   │   ├── CreateGroupScreen.kt      # ~120 satir
│   │   │   ├── AddGroupMemberScreen.kt   # ~100 satir
│   │   │   ├── GroupInfoScreen.kt        # ~120 satir
│   │   │   └── GroupInfoTabs.kt          # ~100 satir (media/docs/starred)
│   │   ├── info/
│   │   │   ├── ChatInfoScreen.kt         # ~100 satir
│   │   │   └── InfoTabs.kt              # ~100 satir (media/docs/starred)
│   │   ├── auth/
│   │   │   ├── PhoneVerificationScreen.kt # ~80 satir
│   │   │   ├── OtpVerificationScreen.kt   # ~80 satir
│   │   │   └── SplashScreen.kt            # ~100 satir
│   │   ├── settings/
│   │   │   ├── SettingsScreen.kt          # ~100 satir
│   │   │   └── ThemeSelectionDialog.kt    # ~60 satir
│   │   └── callhistory/
│   │       └── CallHistoryScreen.kt       # ~120 satir (bu zaten kucuk)
│   │
│   ├── components/
│   │   ├── common/                        # Genel amacli, her yerde kullanilan
│   │   │   ├── GlassSection.kt           # YENi - glass card wrapper
│   │   │   ├── MenuRow.kt               # YENi - icon+title+subtitle+arrow
│   │   │   ├── ContactRow.kt            # YENi - avatar+name+status row
│   │   │   ├── PhoneInputRow.kt         # YENi - country code + phone + button
│   │   │   ├── EmptyState.kt            # YENi - bos sayfa gosterimi
│   │   │   ├── SectionHeader.kt         # YENi - bolum basliklari
│   │   │   ├── ConfirmDialog.kt         # YENi - onay dialoglari (silme, cikma vb.)
│   │   │   └── SearchBar.kt             # YENi - glass search bar
│   │   ├── chat/                          # Sohbete ozel componentler
│   │   │   ├── MessageDateDivider.kt     # MEVCUT (tasinacak)
│   │   │   ├── TypingIndicator.kt        # MEVCUT (tasinacak)
│   │   │   ├── MessageStatusIcon.kt      # YENi - tick/double-tick/clock
│   │   │   ├── ReplyPreview.kt           # YENi - yanit on izleme
│   │   │   └── FileMessageCard.kt        # YENi - dosya mesaji karti
│   │   ├── call/                          # Aramaya ozel componentler
│   │   │   ├── CallControls.kt           # MEVCUT (tasinacak)
│   │   │   ├── VideoRenderer.kt          # MEVCUT (tasinacak)
│   │   │   ├── CallControlButton.kt      # YENi - tek buton component
│   │   │   └── PulseRing.kt             # YENi - nabiz animasyonu
│   │   ├── media/                         # Medya paylasimli componentler
│   │   │   ├── MediaGrid.kt             # YENi - ChatInfo + GroupInfo ortak
│   │   │   ├── DocumentItem.kt          # YENi - ChatInfo + GroupInfo ortak
│   │   │   └── StarredMessageItem.kt    # YENi - ChatInfo + GroupInfo ortak
│   │   ├── avatar/
│   │   │   └── GeneratedAvatar.kt        # MEVCUT (tasinacak, AvatarGenerator.kt'den rename)
│   │   ├── status/
│   │   │   ├── ConnectionStatusIndicator.kt  # MEVCUT (tasinacak)
│   │   │   └── SecurityBadge.kt              # MEVCUT (tasinacak)
│   │   └── dialog/
│   │       ├── ErrorDialog.kt            # MEVCUT (tasinacak)
│   │       ├── GlassDialog.kt           # MEVCUT (GlassComponents.kt parcalanacak)
│   │       ├── GlassPopup.kt            # MEVCUT (GlassComponents.kt parcalanacak)
│   │       └── GlassDropdownMenu.kt     # MEVCUT (GlassComponents.kt parcalanacak)
│   │
│   ├── viewmodel/                         # TASINACAK: theme/viewmodel/ -> viewmodel/
│   │   ├── chat/
│   │   │   ├── ChatViewModel.kt          # ~250 satir (mesaj gonderme/alma)
│   │   │   └── MessageSearchViewModel.kt # YENi - arama logic'i ayrilacak
│   │   ├── call/
│   │   │   ├── CallViewModel.kt
│   │   │   └── CallHistoryViewModel.kt
│   │   ├── conversations/
│   │   │   └── ConversationsViewModel.kt
│   │   ├── contacts/
│   │   │   └── ContactsViewModel.kt
│   │   ├── group/
│   │   │   ├── CreateGroupViewModel.kt
│   │   │   ├── AddGroupMemberViewModel.kt
│   │   │   └── GroupInfoViewModel.kt
│   │   ├── info/
│   │   │   └── ChatInfoViewModel.kt
│   │   └── settings/
│   │       └── SettingsViewModel.kt
│   │
│   └── theme/                             # SADECE tema dosyalari (viewmodel KALKACAK)
│       ├── SecureChatTheme.kt
│       ├── AzureTokens.kt
│       ├── AzureType.kt
│       ├── Glass.kt
│       ├── DoodleBackdrop.kt
│       └── ThemeManager.kt               # TASINACAK: components/ -> theme/
│
├── navigation/
│   ├── SecureChatNavHost.kt
│   └── Routes.kt                          # YENi - route string sabitleri
│
├── domain/usecase/
│   ├── ... (mevcut use case'ler)
│   └── ResolvePhoneToUserUseCase.kt       # YENi - ortak telefon cozumleme
│
├── data/
├── di/
└── util/
```

---

## 2. YENI OLUSTURULACAK COMPONENTLER (Detayli)

### 2.1 GlassSection — En cok tekrarlanan pattern
```kotlin
// ui/components/common/GlassSection.kt
@Composable
fun GlassSection(
    modifier: Modifier = Modifier,
    shape: Shape = RoundedCornerShape(MaterialTheme.azure.rCard),
    strong: Boolean = false,
    content: @Composable ColumnScope.() -> Unit
)
// Kullanim yerleri: SettingsScreen (3x), ConversationsScreen (8x),
//   GroupInfoScreen (8x), ChatInfoScreen (5x) = ~24 kullanim
```

### 2.2 MenuRow — Ayar/Info satirlari
```kotlin
// ui/components/common/MenuRow.kt
@Composable
fun MenuRow(
    icon: ImageVector,
    title: String,
    subtitle: String? = null,
    iconTint: Color = MaterialTheme.colorScheme.onSurface,
    trailing: @Composable (() -> Unit)? = null,  // chevron, switch, badge vb.
    onClick: (() -> Unit)? = null,
    modifier: Modifier = Modifier
)
// Kullanim yerleri: SettingsScreen (10x), ChatInfoScreen (7x),
//   GroupInfoScreen (5x) = ~22 kullanim
```

### 2.3 ContactRow — Kisi satiri
```kotlin
// ui/components/common/ContactRow.kt
@Composable
fun ContactRow(
    name: String,
    subtitle: String? = null,           // telefon, son gorulen vb.
    avatarSize: Dp = 48.dp,
    isGroup: Boolean = false,
    trailing: @Composable (() -> Unit)? = null,  // checkbox, invite btn vb.
    onClick: (() -> Unit)? = null,
    modifier: Modifier = Modifier
)
// Kullanim yerleri: ContactsScreen (3 item type), ConversationsScreen,
//   GroupInfoScreen (member list), CreateGroupScreen, AddGroupMemberScreen
```

### 2.4 PhoneInputRow — Telefon girisi
```kotlin
// ui/components/common/PhoneInputRow.kt
@Composable
fun PhoneInputRow(
    phoneNumber: String,
    onPhoneChange: (String) -> Unit,
    selectedCountryCode: CountryCode,
    onCountryCodeChange: (CountryCode) -> Unit,
    onSubmit: () -> Unit,
    submitLabel: String = "Ekle",
    isLoading: Boolean = false,
    modifier: Modifier = Modifier
)
// Kullanim yerleri: CreateGroupScreen, AddGroupMemberScreen, PhoneVerificationScreen
```

### 2.5 MediaGrid — Medya izgarasi
```kotlin
// ui/components/media/MediaGrid.kt
@Composable
fun MediaGrid(
    mediaMessages: List<LocalMessage>,
    onMediaClick: (LocalMessage) -> Unit,
    modifier: Modifier = Modifier
)
// Kullanim yerleri: ChatInfoScreen, GroupInfoScreen (birebir ayni kod)
```

### 2.6 DocumentItem + DocumentList
```kotlin
// ui/components/media/DocumentItem.kt
@Composable
fun DocumentItem(
    fileName: String,
    fileSize: String,
    fileType: String,
    timestamp: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
)
// Kullanim yerleri: ChatInfoScreen, GroupInfoScreen
```

### 2.7 StarredMessageItem
```kotlin
// ui/components/media/StarredMessageItem.kt
@Composable
fun StarredMessageItem(
    senderName: String,
    content: String,
    timestamp: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
)
// Kullanim yerleri: ChatInfoScreen, GroupInfoScreen
```

### 2.8 EmptyState
```kotlin
// ui/components/common/EmptyState.kt
@Composable
fun EmptyState(
    icon: ImageVector,
    title: String,
    subtitle: String? = null,
    action: @Composable (() -> Unit)? = null,
    modifier: Modifier = Modifier
)
// Kullanim yerleri: ContactsScreen, ConversationsScreen, CallHistoryScreen,
//   ChatInfoScreen (arama sonucu bos), GroupInfoScreen
```

### 2.9 SectionHeader
```kotlin
// ui/components/common/SectionHeader.kt
@Composable
fun SectionHeader(
    title: String,
    count: Int? = null,                 // "Uyeler (5)" gibi
    action: @Composable (() -> Unit)? = null,
    modifier: Modifier = Modifier
)
// Kullanim yerleri: SettingsScreen, GroupInfoScreen, ContactsScreen, CreateGroupScreen
```

### 2.10 SearchBar (Glass)
```kotlin
// ui/components/common/SearchBar.kt
@Composable
fun GlassSearchBar(
    query: String,
    onQueryChange: (String) -> Unit,
    placeholder: String = "Ara...",
    onClose: (() -> Unit)? = null,
    modifier: Modifier = Modifier
)
// Kullanim yerleri: ConversationsScreen, ContactsScreen, ChatInfoScreen, ChatScreen
```

### 2.11 SwipeActionBackground
```kotlin
// ui/screen/conversations/SwipeActions.kt
@Composable
fun SwipeActionBackground(
    direction: SwipeDirection,      // LEFT (sil) veya RIGHT (arsivle)
    modifier: Modifier = Modifier
)
// + SwipeableItem wrapper composable
// Kullanim yerleri: ConversationsScreen (2 kez ayni kod), potansiyel ChatScreen
```

---

## 3. SCREEN PARCALAMA DETAYLARI

### 3.1 ChatScreen.kt (2212 -> ~7 dosya)

| Yeni Dosya | Icerik | Tahmini Satir |
|------------|--------|---------------|
| ChatScreen.kt | Scaffold + state wiring + dialog triggers | ~120 |
| ChatTopBar.kt | Baslik, geri, arama, menu, arama butonlari | ~80 |
| MessageList.kt | LazyColumn + scroll logic + date separators | ~60 |
| MessageBubble.kt | Balon gorunumu + text/file/reply content | ~150 |
| MessageInputBar.kt | Text field + send/attach butonlari + reply preview | ~100 |
| ChatDialogs.kt | Disappearing timer + forward picker + message info | ~80 |
| ChatSearchBar.kt | Arama cubugu + prev/next navigasyon | ~50 |
| **Toplam** | | **~640** (2212'den %71 azalma) |

### 3.2 CallScreen.kt (1590 -> ~5 dosya)

| Yeni Dosya | Icerik | Tahmini Satir |
|------------|--------|---------------|
| CallScreen.kt | Permission + state routing + layout | ~150 |
| CallAvatar.kt | 3 pulse ring + gradient border + breath effect | ~100 |
| CallBackground.kt | AnimatedGradient + FloatingParticles + canvas | ~120 |
| IncomingCallOverlay.kt | Accept/reject butonlari + animasyonlar | ~80 |
| GroupVideoGrid.kt | LazyGrid + VideoRenderer cells | ~60 |
| **Toplam** | | **~510** (1590'dan %68 azalma) |

### 3.3 ConversationsScreen.kt (1036 -> ~4 dosya)

| Yeni Dosya | Icerik | Tahmini Satir |
|------------|--------|---------------|
| ConversationsScreen.kt | Scaffold + filter state + list wiring | ~100 |
| ConversationItem.kt | Single conversation row + badges | ~80 |
| SwipeActions.kt | Archive/delete swipe + background | ~70 |
| FilterChipRow.kt | 4 filter chip (parameterized) | ~40 |
| **Toplam** | | **~290** (1036'dan %72 azalma) |

### 3.4 GroupInfoScreen.kt (984) + ChatInfoScreen.kt (947) -> Ortak tablar

| Yeni Dosya | Icerik | Tahmini Satir |
|------------|--------|---------------|
| GroupInfoScreen.kt | Scaffold + header + member list | ~120 |
| GroupInfoTabs.kt | Media/Docs/Starred tab content | ~100 |
| ChatInfoScreen.kt | Scaffold + header + menu items | ~100 |
| InfoTabs.kt | Media/Docs/Starred (GroupInfoTabs ile paylasimli) | ~100 |
| **Toplam** | | **~420** (1931'den %78 azalma) |

### 3.5 SettingsScreen.kt (640 -> ~2 dosya)

| Yeni Dosya | Icerik | Tahmini Satir |
|------------|--------|---------------|
| SettingsScreen.kt | GlassSection + MenuRow kullanarak | ~100 |
| ThemeSelectionDialog.kt | Tema secim dialog'u | ~60 |
| **Toplam** | | **~160** (640'dan %75 azalma) |

### 3.6 Auth Ekranlari

| Yeni Dosya | Icerik | Tahmini Satir |
|------------|--------|---------------|
| PhoneVerificationScreen.kt | PhoneInputRow + AppHeader kullanarak | ~80 |
| OtpVerificationScreen.kt | OtpInputField ayri component | ~80 |
| SplashScreen.kt | Degisiklik yok (zaten 181 satir) | ~100 |

---

## 4. CHATVIEWMODEL BOLUNMESI (672 -> 3 parca)

### Mevcut ChatViewModel icindeki sorumluluklar:
```
1. Mesaj gonderme/alma (sendMessage, sendFile)
2. Mesaj arama (searchQuery, searchResultIds, navigateSearch)
3. Mesaj operasyonlari (delete, star, forward, disappearing)
4. Presence/typing tracking (peerIsTyping, peerPresence)
5. Draft yonetimi (draftMessages companion)
6. Conversation info (peerName, peerPhone, isGroup)
```

### Bolunme plani:

```kotlin
// ChatViewModel.kt (~250 satir)
// - Mesaj gonderme/alma
// - Conversation info
// - Presence/typing
// - Draft yonetimi

// MessageSearchViewModel.kt (~120 satir)  [YENi]
// - searchQuery, searchResultIds
// - navigateToNext/Prev
// - highlightedMessageId
// - debounce logic

// MessageOperationsHelper.kt (~100 satir)  [YENi - ViewModel degil, helper class]
// - deleteMessage, deleteForEveryone
// - toggleStarred
// - forwardMessages
// - disappearing timer setup
```

---

## 5. HARDCODED RENK TEMIZLIGI

### Degisiklik Tablosu

| Hardcoded Deger | AzureTokens Karsiligi | Kullanim Sayisi |
|-----------------|----------------------|-----------------|
| `Color(0xFF3E7BFA)` | `MaterialTheme.azure.azure` | ~50+ |
| `Color(0xFF0D1117)` / `Color(0xFF0D1014)` | `MaterialTheme.azure.night` | ~20+ |
| `Color(0xFF22C55E)` | `MaterialTheme.azure.ok` | ~10+ |
| `Color(0xFFFFB800)` / `Color(0xFFFFD700)` | `MaterialTheme.azure.warn` | ~8+ |
| `Color(0xFFFF5E87)` / `Color(0xFFEF4444)` | `MaterialTheme.azure.danger` | ~8+ |
| `Color(0xFF6B737D)` / `Color(0xFF5D6570)` | `MaterialTheme.azure.inkMute` / `frostSoft` | ~15+ |
| `Color(0xFF9BA3AE)` / `Color(0xFF8A929C)` | `MaterialTheme.azure.frostMute` / `inkSoft` | ~10+ |
| `Color(0xFF151A21)` | `MaterialTheme.azure.nightRaise` | ~5+ |
| `Color(0xFF1E242D)` | `MaterialTheme.azure.nightEdge` | ~5+ |
| `Color(0xFFF4F2EC)` | `MaterialTheme.azure.paper` | ~3+ |

### AzureTokens'a eklenecek eksik tokenlar:

```kotlin
// AzureTokens.kt'ye eklenecek:
val star: Color = Color(0xFFFFD700),        // yildiz rengi (warn'dan farkli)
val archive: Color = Color(0xFF00897B),      // arsiv/teal rengi
val verified: Color = Color(0xFF52C41A),     // dogrulanmis yesil
val link: Color = Color(0xFF2979FF),         // link mavisi (azure'dan farkli)

// Spacing eklemeleri:
val s7: Dp = 28.dp,
val s8: Dp = 32.dp,

// Ek radii:
val rInput: Dp = 12.dp,                     // text field radius
val rDialog: Dp = 20.dp,                    // dialog radius
val rSmall: Dp = 8.dp,                      // kucuk radius
```

---

## 6. NAVIGATION ROUTE SABITLERI

```kotlin
// navigation/Routes.kt  [YENi DOSYA]
object Routes {
    const val SPLASH = "splash"
    const val AUTH_PHONE = "auth/phone"
    const val AUTH_OTP = "auth/otp/{phoneNumber}"

    const val CONVERSATIONS = "conversations"
    const val CHAT = "chat/{conversationId}"
    const val CHAT_INFO = "chat_info/{conversationId}"

    const val CONTACTS = "contacts"
    const val CALL_HISTORY = "call_history"
    const val SETTINGS = "settings"

    const val CREATE_GROUP = "create_group"
    const val GROUP_INFO = "group_info/{groupId}"
    const val ADD_MEMBER = "add_member/{groupId}"

    const val CALL = "call/{peerId}/{callType}"

    // Builder fonksiyonlari
    fun chat(conversationId: String) = "chat/$conversationId"
    fun chatInfo(conversationId: String) = "chat_info/$conversationId"
    fun groupInfo(groupId: String) = "group_info/$groupId"
    fun addMember(groupId: String) = "add_member/$groupId"
    fun authOtp(phoneNumber: String) = "auth/otp/$phoneNumber"
    fun call(peerId: String, callType: String) = "call/$peerId/$callType"
}
```

---

## 7. STRINGS.XML TASIMA

### Mevcut: 30 string (sadece GroupInfo + 1-2 diger)
### Hedef: ~200+ string (tum UI text'leri)

Oncelikli eklenecek kategoriler:
```xml
<!-- Auth -->
<string name="app_title">ELCIM</string>
<string name="app_subtitle">Guvenli mesajlasma</string>
<string name="register">Kayit Ol</string>
<string name="your_name">Adiniz</string>
<string name="phone_number">Telefon Numarasi</string>
<string name="verification_code">Dogrulama Kodu</string>
<string name="enter_6_digit_code">6 haneli dogrulama kodunu girin</string>
<string name="resend_code">Kodu tekrar gonder</string>
<string name="resend_countdown">Kodu tekrar gonder: %1$ds</string>

<!-- Conversations -->
<string name="filter_all">Tumu</string>
<string name="filter_unread">Okunmamis</string>
<string name="filter_groups">Gruplar</string>
<string name="filter_favorites">Favoriler</string>
<string name="delete_conversation">Konusmayi Sil</string>
<string name="archive">Arsivle</string>
<string name="unarchive">Arsivden Cikar</string>
<string name="no_conversations">Henuz konusma yok</string>

<!-- Chat -->
<string name="type_message">Mesaj yaz...</string>
<string name="encrypted">Sifreli</string>
<string name="typing">Yaziyor</string>
<string name="user_typing">%1$s yaziyor</string>
<string name="reply">Yanitla</string>
<string name="forward">Ilet</string>
<string name="delete">Sil</string>
<string name="star_message">Yildizla</string>
<string name="copy">Kopyala</string>

<!-- Settings -->
<string name="appearance">Gorunum</string>
<string name="notifications">Bildirimler</string>
<string name="security">Guvenlik</string>
<string name="privacy">Gizlilik</string>
<string name="data_management">Veri Yonetimi</string>
<string name="about">Hakkinda</string>
<string name="version">Surum %1$s</string>
<string name="theme">Tema</string>

<!-- Call -->
<string name="call_history">Arama Gecmisi</string>
<string name="missed_call">Cevapsiz</string>
<string name="rejected_call">Reddedilen</string>
<string name="failed_call">Basarisiz</string>
<string name="incoming_call">Gelen Arama</string>
<string name="outgoing_call">Giden Arama</string>

<!-- Contacts -->
<string name="select_contact">Kisi Sec</string>
<string name="enter_number">Numara Gir</string>
<string name="recent_conversations">Gecmis Konusmalar</string>
<string name="invite">Davet Et</string>

<!-- Common -->
<string name="error">Hata</string>
<string name="ok">Tamam</string>
<string name="warning">Uyari</string>
<string name="search">Ara...</string>
<string name="close">Kapat</string>
<string name="confirm">Onayla</string>
```

---

## 8. ORTAK USE CASE CIKARIMI

### ResolvePhoneToUserUseCase [YENi]
```kotlin
// domain/usecase/ResolvePhoneToUserUseCase.kt
// CreateGroupViewModel ve AddGroupMemberViewModel'deki duplicate logic'i birlestir
class ResolvePhoneToUserUseCase @Inject constructor(
    private val phoneNormalizer: PhoneNumberNormalizer,
    private val discoveryApi: DiscoveryApiService
) {
    suspend operator fun invoke(
        phoneNumber: String,
        countryCode: String
    ): Result<String>  // UUID doner veya hata
}
```

---

## 9. UYGULAMA FAZLARI

### FAZ 1 — Temel Altyapi (Risksiz)
1. `Routes.kt` olustur (navigation sabitleri)
2. `AzureTokens`'a eksik tokenlari ekle
3. `ThemeManager.kt`'yi `components/` -> `theme/` altina tasi
4. ViewModel'leri `theme/viewmodel/` -> `viewmodel/` altina tasi (paket yolunu guncelle)
5. `strings.xml`'e tum stringleri ekle

### FAZ 2 — Ortak Componentler (Dusuk Risk)
6. `GlassSection` component'i olustur
7. `MenuRow` component'i olustur
8. `ContactRow` component'i olustur
9. `PhoneInputRow` component'i olustur
10. `EmptyState` component'i olustur
11. `SectionHeader` component'i olustur
12. `GlassSearchBar` component'i olustur
13. `MediaGrid`, `DocumentItem`, `StarredMessageItem` olustur
14. `GlassComponents.kt`'yi parcala (GlassDialog, GlassPopup, GlassDropdownMenu)

### FAZ 3 — Screen Parcalama (Orta Risk)
15. SettingsScreen parcala (en basit — sadece MenuRow'a gecis)
16. ContactsScreen parcala (ContactRow kullanarak)
17. ConversationsScreen parcala (ConversationItem, SwipeActions, FilterChipRow)
18. ChatInfoScreen + GroupInfoScreen parcala (ortak InfoTabs ile)
19. CreateGroupScreen + AddGroupMemberScreen parcala (PhoneInputRow ile)
20. Auth ekranlarini parcala (PhoneInputRow + strings.xml)

### FAZ 4 — Buyuk Parcalama (Yuksek Risk)
21. ChatScreen'i 7 dosyaya parcala
22. CallScreen'i 5 dosyaya parcala
23. ChatViewModel'i bol (ChatViewModel + MessageSearchViewModel + MessageOperationsHelper)
24. `ResolvePhoneToUserUseCase` olustur, ViewModel'lerden duplicate kodu cikar

### FAZ 5 — Temizlik
25. Tum hardcoded renkleri AzureTokens referanslariyla degistir
26. Tum hardcoded stringleri stringResource() ile degistir
27. Her componente @Preview fonksiyonu ekle
28. Padding degerlerini AzureTokens spacing ile degistir
29. SecureChatNavHost'u Routes.kt sabitlerini kullanacak sekilde guncelle

---

## 10. BEKLENEN SONUCLAR

| Metrik | Oncesi | Sonrasi | Degisim |
|--------|--------|---------|---------|
| En buyuk dosya | 2212 satir | ~250 satir | %89 azalma |
| Ortalama screen boyutu | ~770 satir | ~100 satir | %87 azalma |
| Hardcoded renk sayisi | 150+ | 0 | %100 azalma |
| Hardcoded string sayisi | 200+ | 0 | %100 azalma |
| Ortak component sayisi | 11 | 30+ | %170 artis |
| Tekrarlanan pattern | 200+ | ~10 | %95 azalma |
| Preview sayisi | 0 | 30+ | sifirdan |
| Dosya sayisi (UI) | ~39 | ~65 | Artis (ama her biri kucuk ve odakli) |
| Toplam UI satir sayisi | ~14,000 | ~8,000 | %43 azalma (tekrar kaldirilarak) |
