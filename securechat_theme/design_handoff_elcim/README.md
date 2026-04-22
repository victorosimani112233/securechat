# Elçim — Azure Tema Uygulama Rehberi

Bu paket, **mevcut Kotlin + Jetpack Compose projenize** Azure temasını uygulamak için hazırlanmış bir tasarım referansıdır. Yeni proje kurulumu yoktur — amaç, sizin projenizdeki mevcut ekranların görünümünü bu tasarıma dönüştürmek.

## Ne Yapacaksın
1. `ui/theme/` altına 4 dosya ekle (tokens, typography, glass modifier, doodle backdrop)
2. Mevcut `Theme.kt` / `MaterialTheme` sarmalını Azure tema ile değiştir
3. Mevcut ekranlarda renkleri/fontları/köşe radius'larını token'lardan çek
4. Chat ekranındaki balonları, Home'daki sohbet kartlarını, FAB'ı ve tab bar'ı aşağıdaki spec'e göre güncelle

Mevcut business logic (ViewModel, navigation, P2P transport, Room, DataStore) değişmez — **sadece UI layer**.

---

## 1. Design Tokens

`ui/theme/AzureTokens.kt` olarak ekle:

```kotlin
package com.elcim.app.ui.theme

import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

@Immutable
data class AzureTokens(
    // Neutral base
    val night: Color = Color(0xFF0D1014),
    val nightRaise: Color = Color(0xFF151A21),
    val nightEdge: Color = Color(0xFF1E242D),
    val paper: Color = Color(0xFFF4F2EC),
    val paperDim: Color = Color(0xFFEAE7DD),

    // Ink (dark text on light)
    val ink: Color = Color(0xFF13161B),
    val inkMute: Color = Color(0xFF5D6570),
    val inkSoft: Color = Color(0xFF8A929C),

    // Frost (light text on dark)
    val frost: Color = Color(0xFFECEEF2),
    val frostMute: Color = Color(0xFF9BA3AE),
    val frostSoft: Color = Color(0xFF6B737D),

    // PRIMARY — yalnız CTA + aktif durumlar
    val azure: Color = Color(0xFF3E7BFA),
    val azureDeep: Color = Color(0xFF1E52D9),
    val azureGlow: Color = Color(0xFF5EA3FF),

    // Status
    val ok: Color = Color(0xFF22C55E),
    val warn: Color = Color(0xFFFFB800),
    val danger: Color = Color(0xFFFF5E87),

    // Spacing (base 4)
    val s1: Dp = 4.dp, val s2: Dp = 8.dp, val s3: Dp = 12.dp,
    val s4: Dp = 16.dp, val s5: Dp = 20.dp, val s6: Dp = 24.dp,

    // Radii
    val rCard: Dp = 16.dp,
    val rPill: Dp = 100.dp,
    val rBubble: Dp = 20.dp,
    val rBubbleTail: Dp = 4.dp,
)

val LocalAzureTokens = staticCompositionLocalOf { AzureTokens() }

// Kısayol: MaterialTheme.azure
val androidx.compose.material3.MaterialTheme.azure: AzureTokens
    @Composable @ReadOnlyComposable
    get() = LocalAzureTokens.current
```

Kullanım: `MaterialTheme.azure.azure`, `MaterialTheme.azure.frost`, `MaterialTheme.azure.s4`, vb.

---

## 2. Typography

Fontları `res/font/` altına ekle:
- `inter_regular.ttf`, `inter_medium.ttf`, `inter_semibold.ttf`, `inter_bold.ttf`
- `space_grotesk_semibold.ttf`, `space_grotesk_bold.ttf`
- `jetbrains_mono_regular.ttf`, `jetbrains_mono_medium.ttf`

`ui/theme/AzureType.kt`:

```kotlin
val InterFamily = FontFamily(
    Font(R.font.inter_regular, FontWeight.Normal),
    Font(R.font.inter_medium, FontWeight.Medium),
    Font(R.font.inter_semibold, FontWeight.SemiBold),
    Font(R.font.inter_bold, FontWeight.Bold),
)
val DisplayFamily = FontFamily(
    Font(R.font.space_grotesk_semibold, FontWeight.SemiBold),
    Font(R.font.space_grotesk_bold, FontWeight.Bold),
)
val MonoFamily = FontFamily(
    Font(R.font.jetbrains_mono_regular, FontWeight.Normal),
    Font(R.font.jetbrains_mono_medium, FontWeight.Medium),
)

val AzureTypography = Typography(
    displayLarge = TextStyle(fontFamily = DisplayFamily, fontWeight = FontWeight.Bold, fontSize = 40.sp, letterSpacing = (-1.0).sp, lineHeight = 44.sp),
    headlineMedium = TextStyle(fontFamily = DisplayFamily, fontWeight = FontWeight.SemiBold, fontSize = 24.sp, letterSpacing = (-0.6).sp, lineHeight = 28.sp),
    titleLarge = TextStyle(fontFamily = InterFamily, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, letterSpacing = (-0.2).sp),
    titleMedium = TextStyle(fontFamily = InterFamily, fontWeight = FontWeight.SemiBold, fontSize = 15.sp),
    bodyLarge = TextStyle(fontFamily = InterFamily, fontWeight = FontWeight.Normal, fontSize = 15.sp, lineHeight = 22.sp),
    bodyMedium = TextStyle(fontFamily = InterFamily, fontWeight = FontWeight.Normal, fontSize = 14.sp, lineHeight = 20.sp),
    bodySmall = TextStyle(fontFamily = InterFamily, fontWeight = FontWeight.Normal, fontSize = 12.sp),
    labelMedium = TextStyle(fontFamily = MonoFamily, fontWeight = FontWeight.Medium, fontSize = 11.sp, letterSpacing = 0.5.sp),
)
```

**Mono kullanımı**: peer ID, zaman damgası, teknik veri gibi yerlerde `fontFamily = MonoFamily` explicit ver.

---

## 3. Azure Theme wrapper

`ui/theme/AzureTheme.kt`:

```kotlin
@Composable
fun AzureTheme(
    dark: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val tokens = AzureTokens()
    val colorScheme = if (dark) darkColorScheme(
        background = tokens.night,
        surface = tokens.nightRaise,
        primary = tokens.azure,
        onPrimary = Color.White,
        onBackground = tokens.frost,
        onSurface = tokens.frost,
        error = tokens.danger,
    ) else lightColorScheme(
        background = tokens.paper,
        surface = Color.White,
        primary = tokens.azure,
        onPrimary = Color.White,
        onBackground = tokens.ink,
        onSurface = tokens.ink,
        error = tokens.danger,
    )
    CompositionLocalProvider(LocalAzureTokens provides tokens) {
        MaterialTheme(colorScheme = colorScheme, typography = AzureTypography, content = content)
    }
}
```

Mevcut `MainActivity.kt` / `setContent { ... }` içindeki tema sarmalını `AzureTheme { ... }` ile değiştir.

---

## 4. Glass Modifier

`ui/theme/Glass.kt`:

```kotlin
fun Modifier.glass(
    dark: Boolean,
    strong: Boolean = false,
    shape: Shape = RoundedCornerShape(16.dp),
): Modifier = composed {
    val bg = if (dark) Color.White.copy(alpha = if (strong) 0.08f else 0.05f)
             else Color.White.copy(alpha = if (strong) 0.75f else 0.55f)
    val border = if (dark) Color.White.copy(alpha = if (strong) 0.14f else 0.09f)
                 else Color(0xFF13161B).copy(alpha = if (strong) 0.12f else 0.07f)

    this
        .clip(shape)
        .then(
            if (Build.VERSION.SDK_INT >= 31)
                Modifier.blur(18.dp, BlurredEdgeTreatment(shape))
            else Modifier
        )
        .background(bg, shape)
        .border(1.dp, border, shape)
}
```

**Önemli**: Compose'un `Modifier.blur` ikisini de blur'lar (foreground + background). Backdrop blur için alternatif: arkaplanı ayrı `Box` içinde `blur` modifier ile ver, üstüne yarı-saydam `Box`'ı bindir. Detay: [Android docs — blur](https://developer.android.com/jetpack/compose/graphics/draw/modifiers#blur). Hızlı yaklaşım için sadece yarı-saydam bg + border yeterli — doodle backdrop zaten görsel derinlik sağlıyor.

---

## 5. Doodle Backdrop

`res/drawable/doodle_tile.xml` olarak VectorDrawable ekle (280×280dp). İçerik: zarf, 3-nokta peer düğümü, dalga, kilit, konuşma balonu, @ işareti, dashed path, pulsing node (3 iç içe daire), anahtar, zigzag, yıldızlar, sinyal arkları. Stroke renkleri:

- **dark**: `#FFFFFF` @ alpha 0.055 ve mavi vurgu `#5EA3FF` @ alpha 0.07
- **light**: `#13161B` @ alpha 0.07 ve mavi vurgu `#1E52D9` @ alpha 0.10

`ui/theme/DoodleBackdrop.kt`:

```kotlin
@Composable
fun AzureDoodleBackdrop(
    modifier: Modifier = Modifier,
    dark: Boolean = isSystemInDarkTheme(),
) {
    val tokens = MaterialTheme.azure
    val base = if (dark) tokens.night else tokens.paper
    val wash = Color(0xFF3E7BFA).copy(alpha = 0.035f)
    val tile = ImageBitmap.imageResource(R.drawable.doodle_tile_280)

    Box(modifier.fillMaxSize().background(base)) {
        Canvas(Modifier.fillMaxSize()) {
            // tile'ı tekrar çiz
            val tileSize = 280.dp.toPx()
            var y = 0f
            while (y < size.height) {
                var x = 0f
                while (x < size.width) {
                    drawImage(tile, topLeft = Offset(x, y))
                    x += tileSize
                }
                y += tileSize
            }
            drawRect(wash)
        }
    }
}
```

**Bu backdrop şu ekranlarda olmalı**: Register, Home, Chat, ContactInfo, GroupInfo, Contacts. Transparanlık hissi ancak bu arkaplan olduğunda belirginleşir.

Kullanım:
```kotlin
Box(Modifier.fillMaxSize()) {
    AzureDoodleBackdrop()
    // ekran içeriği
    Column(Modifier.fillMaxSize()) { ... }
}
```

---

## 6. Ekran-Ekran Uyarlama

### Home (sohbet listesi)
- **Header**: `Row` — solda logo + wordmark (`DisplayFamily`, bold), sağda arama ikonu
- **Bağlantı şeridi**: `Modifier.glass(dark)` + `Row` → `"Mesh bağlı · 14 peer · 42ms"` (Mono font, 11sp, `frostMute`)
- **Arama kutusu**: `TextField` yerine custom `Modifier.glass(dark).height(44.dp)` + `BasicTextField`
- **Sohbet kartları**: `LazyColumn` + her item `Modifier.glass(dark).padding(14.dp)` — 8dp dikey gap
  - Row: `AzAvatar(42.dp)` → `Column(isim · preview) weight(1f)` → `Column(zaman · unreadBadge)`
  - Peer ID alt satırda mono, 10sp, `frostSoft`
- **FAB**: sağ altta 56dp daire, `MaterialTheme.azure.azure` bg, `shadow = 0 12dp 28dp rgba(62,123,250,0.5)`
  - Compose'da: `Modifier.shadow(12.dp, CircleShape, ambientColor = azure, spotColor = azure)`
- **Alt tab bar**: `Row` içinde 4 `TabItem` — her biri `glass(dark, strong = true)` bir container'da; aktif sekme altında `Box(Modifier.width(26.dp).height(3.dp).background(azure))` + `animateDpAsState` ile x offset

### Chat
- **Header**: geri ok + `AzAvatar(36.dp)` + isim/status (`"çevrimiçi · p2p direct"` — status Mono 11sp `frostMute`) + sesli/video ikonları
- **Gövde**: `LazyColumn` + `AzureDoodleBackdrop()` arkaplanda
- **MessageBubble**:
  ```kotlin
  // Me (dark)
  Modifier
    .background(Color(0xFF3E7BFA).copy(alpha = 0.28f), shape)
    .border(1.dp, Color(0xFF5EA3FF).copy(alpha = 0.35f), shape)
    // text: Color.White
  // shape: RoundedCornerShape(20.dp, 20.dp, 4.dp, 20.dp)
  
  // Them (dark)
  Modifier
    .background(Color(0xFF0F141C).copy(alpha = 0.55f), shape)
    .border(1.dp, Color.White.copy(alpha = 0.08f), shape)
    // text: frost
  // shape: RoundedCornerShape(20.dp, 20.dp, 20.dp, 4.dp)
  ```
  Light mode için alpha değerleri README'nin altındaki tablodan.
- **System message**: pill (`RoundedCornerShape(100.dp)`) + kilit ikonu + `"uçtan-uca şifrelendi"` (12sp, `frostMute`)
- **Composer**: `Modifier.glass(dark)` pill + sağda 36dp mavi daire gönder butonu

### ContactInfo
- **Hero**: 104dp avatar (Circle), isim (`headlineMedium`), peer ID altında (Mono 12sp), iki chip: `"uçtan-uca şifreli"` + `"çevrimiçi"`
- **Action grid**: 4 kolonlu `Row` — her tile `glass(dark).size(72.dp)` + ikon + 10sp label
- **Güvenlik anahtarı kartı**: `glass` + 12 grup × 4-char Mono blok + sağda "Doğrula" mavi pill
- **Info satırları**: ince separator ile dikey liste — label (inkMute/frostMute) + value
- **Paylaşılan medya**: 4 kolon grid, 8dp gap, köşe `rCard`
- **Engelleme CTA**: full-width, danger bg

### GroupInfo
Aynı pattern + grup avatar (monogram, `glass(dark)` içinde) + üye sayısı. **Üyeler: her üye ayrı `glass` kart**, admin rozeti `azure.copy(alpha = 0.2f)` bg.

### Contacts
- Header: `"Rehber"` başlık + peer sayısı + mavi ekle FAB
- Quick actions: 2 tile yan yana (`"QR ile ekle"` + `"Yakındakiler"`)
- Liste: **her kişi ayrı `glass` kutu**, 8dp gap, alfabetik gruplama YOK
- Sağda peer ID Mono + `"● aktif"` yeşil (`ok`)

### Register (3 adım)
Tek `RegisterScreen` composable, `step: Int` state'i:
- Üstte 3 bölümlü progress bar: `Row` + her bölüm `Modifier.weight(1f).height(4.dp)` — aktif `azure`, pasif `glass(dark)` border
- 01 Kimlik · 02 Ağ · 03 Yedek başlıkları
- Kimlik kartı: `glass(dark, strong = true)` + peer ID (Mono)
- Görünen isim input: `BasicTextField` + alt 2dp `azure` border
- CTA: `Button` yerine custom — full-width pill, `azure` bg

---

## 7. Chat Bubble Renkleri (tam referans)

### Dark
- **Me**: bg `rgba(62,123,250,0.28)`, border `rgba(94,163,255,0.35)`, text `#FFFFFF`
- **Them**: bg `rgba(15,20,28,0.55)`, border `rgba(255,255,255,0.08)`, text `#ECEEF2`

### Light
- **Me**: bg `rgba(62,123,250,0.18)`, border `rgba(62,123,250,0.35)`, text `#1E52D9`
- **Them**: bg `rgba(19,22,27,0.06)`, border `rgba(19,22,27,0.09)`, text `#13161B`

---

## 8. Küçük İyileştirmeler

- **Tab bar aktif highlight**: `animateDpAsState(targetValue = selectedTabIndex * tabWidth)` ile x offset animasyonu
- **FAB press**: `Modifier.pointerInput { awaitPointerEventScope { ... } }` + `animateFloatAsState(if (pressed) 0.95f else 1f)` → `Modifier.scale(scale)`
- **Typing indicator**: `InfiniteTransition` + 3 nokta, her biri `animateFloat` ile opacity offset 150ms
- **Read/delivered tiki**: `Crossfade` ile `tick_gray` → `tick_blue` (azure)
- **Theme toggle**: `DataStore` ile persist; `AzureTheme(dark = settings.dark)` sarmalında kullan

---

## 9. Tasarım Referansı

`src/Elcim.html` dosyasını tarayıcıda aç — canvas'ta tüm ekranların Azure versiyonlarını iOS + Android frame'inde görebilirsin. Sağ üstte Tweaks'ten tema değiştirilebilir. Her ekranın tam renk/layout/boşluk değerleri bu tasarımda görülebilir.

Kaynak dosyalar:
- `src/azure-brand.jsx` — tokens (`AZ`), tema helper (`azTheme`), bileşenler (`AzureMark`, `Glass`, `AzAvatar`, `AzChip`, `AzLock`, `AzPrimary`, `AzDoodleBackdrop`)
- `src/azure-screens.jsx` — ekranlar (`AzHome`, `AzChat`, `AzContactInfo`, `AzGroupInfo`, `AzContacts`, `AzRegister`)

JSX sadece referans — Compose'a port et. Bileşen isimleri 1-1 eşleşir (`Glass` → `Modifier.glass()`, `AzAvatar` → `AzAvatar` composable, vb.).
