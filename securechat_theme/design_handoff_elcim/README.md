# Handoff: Elçim — P2P Mesajlaşma Uygulaması

## Overview
Elçim, sunucusuz (peer-to-peer) çalışan bir mobil mesajlaşma uygulaması. Bu paket, uygulamanın yüksek-fideliteli UI tasarımını içeriyor — **Azure yönü**: Space Grotesk + Inter tipografi, nötr cam zemin + mavi primary, doodle art arkaplan. Tasarımlar iOS (390×844) ve Android (412×892) için hazırlandı.

## About the Design Files
Bu paketteki dosyalar **HTML ile oluşturulmuş tasarım referanslarıdır** — prototiplerdir, doğrudan kopyalanacak üretim kodu değildir. Görev, bu HTML tasarımları **hedef uygulamanın mevcut ortamında** (React Native, Flutter, SwiftUI, Jetpack Compose vb.) o ortamın yerleşik kalıp ve kütüphaneleriyle yeniden oluşturmaktır. Eğer bir ortam henüz yoksa, proje için en uygun framework seçilip tasarımlar orada uygulanmalıdır.

Önerilen stack:
- **React Native + Expo** (iOS + Android tek kod tabanı, P2P için WebRTC/libp2p uyumlu)
- veya **Flutter** (aynı avantaj)

## Fidelity
**Yüksek-fidelite (hi-fi).** Renkler, tipografi, boşluk, gölge, blur değerleri kesindir. Geliştirici UI'ı piksel seviyesinde uygulamalıdır.

## Screens / Views

Toplam 8 ekran tasarlandı. Her ekran hem iOS (390×844) hem Android (412×892) frame'lerinde gösteriliyor.

### 1. Kayıt / Kurulum (Register)
- **Amaç**: İlk açılışta yerel ed25519 kimliği oluşturulur, görünen isim + durum alınır
- **Layout**: Dikey akış, 3 adım progress bar (tek ekran ×3 adım)
- **Adımlar**: 01 Kimlik → 02 Ağ → 03 Yedek
- **Key bileşenler**:
  - Progress bar: 3 bölüm, aktif mavi (`#3E7BFA`), pasif glass border
  - Doodle arkaplan (AzDoodleBackdrop)
  - Kimlik kartı: transparan cam, mono font (`JetBrains Mono`) ile peer ID
  - Görünen isim input: alt border 2px mavi
  - CTA: dolu mavi pill button, tam genişlik

### 2. Ana Ekran (Home)
- **Amaç**: Sohbet listesi
- **Layout**:
  - Header: logo + wordmark, arama ikonu, yeni sohbet (mavi FAB)
  - Bağlantı şeridi: "Mesh bağlı · 14 peer · 42ms" transparan kart
  - Arama kutusu: transparan cam
  - Sohbet kartları: **her biri ayrı transparan cam kutu**, 8px dikey gap
  - FAB: sağ altta, mavi daire 56px
  - Alt tab bar: Sohbet · Ağ · Rehber · Ayarlar (blur glass, aktif sekme altında 26×3 mavi çizgi)
- **Sohbet kartı**: avatar (42-44px) + isim + grup üye badge + zaman + preview + unread badge + peer ID (mono, küçük gri)

### 3. Sohbet (Chat)
- **Amaç**: Tek kişiyle/grupla mesajlaşma
- **Layout**:
  - Header: geri + avatar + isim + "çevrimiçi · p2p direct" + sesli/görüntülü ikonları
  - Gövde: doodle art arkaplan
  - Mesaj balonları:
    - **Benim mesajım**: `rgba(62,123,250,0.28)` mavi transparan + `blur(18px)` + mavi border `rgba(94,163,255,0.35)` + beyaz text, sağ alt köşe 4px radius
    - **Karşı taraf**: `rgba(15,20,28,0.55)` koyu transparan + `blur(18px)` + beyaz %8 border + frost text, sol alt köşe 4px radius
    - Sistem mesajı: pill shape, kilit ikonu + "uçtan-uca şifrelendi"
  - Composer: transparan pill + mavi gönder butonu 36px

### 4. Kişi Bilgisi (Contact Info)
- Hero: 104px avatar + isim + peer ID + "uçtan-uca şifreli" + "çevrimiçi" chips
- 4'lü action grid: Mesaj · Ara · Video · Engel (her biri transparan cam tile)
- Güvenlik anahtarı kartı: mono 12 grup 4-char blok + "Doğrula" mavi pill
- Bilgi satırları: Telefon · Cihaz · Eklendi · Son görülme
- Paylaşılan medya: 4 kolonlu grid
- Engelleme CTA: danger `#FF5E87`

### 5. Grup Bilgisi (Group Info)
- Aynı pattern + grup avatar (Çv2 monogramı, transparan cam) + üye sayısı
- 3'lü action: Üye ekle · Sesli · Görüntülü
- Açıklama kartı
- **Üyeler**: **her üye ayrı transparan cam kart**; admin rozeti mavi tint
- Seçenekler: Bildirim · Kayboluyor mesaj · Medya
- "Gruptan ayrıl" danger

### 6. Rehber (Contacts)
- Header: "Rehber" başlık + peer sayısı + mavi ekle FAB
- Arama
- Quick actions: QR ile ekle · Yakındakiler (transparan cam tile'lar)
- Kişi listesi: **her kişi ayrı transparan cam kutu** 8px gap (alfabetik grup YOK — düz liste)
- Her satırda: avatar + isim + status + sağda peer ID (mono) + "● aktif" (yeşil)

## Interactions & Behavior
- Tema toggle: localStorage'a `theme: light|dark` kaydedilmeli
- Tab bar: aktif sekme altında animasyonlu 3px mavi highlight
- Sohbet balonlarında read/delivered tiki: gri → mavi
- Composer'da typing indicator: 3 nokta, opacity pulse animasyonu
- FAB: scale on press 0.95
- Long-press: kişi/sohbet kartında context menu (tasarlanmadı — standart)

## State Management
Önerilen state (Redux/Zustand):
- `currentUser` (peer ID, name, status, avatar seed)
- `peers[]` (online/offline, RTT, direct/relay)
- `conversations[]` (peer/group ID, messages, unread, pinned, lastSeen)
- `contacts[]` (name, peer ID, status, verified)
- `groups[]` (members, admins, description, ephemeral TTL)
- `networkState` (mesh bağlı mı, kaç peer, ortalama RTT)
- `settings` (theme, notifications, ephemeral default)

## Design Tokens

### Colors
```
// Neutral base
night:        #0D1014   // dark bg
nightRaise:   #151A21
nightEdge:    #1E242D
paper:        #F4F2EC   // light bg
paperDim:     #EAE7DD

// Ink (text on light)
ink:          #13161B
inkMute:      #5D6570
inkSoft:      #8A929C

// Frost (text on dark)
frost:        #ECEEF2
frostMute:    #9BA3AE
frostSoft:    #6B737D

// PRIMARY ACCENT — blue; yalnız CTA + aktif durumlarda
azure:        #3E7BFA
azureDeep:    #1E52D9
azureGlow:    #5EA3FF

// Status
ok:           #22C55E
warn:         #FFB800
danger:       #FF5E87
```

### Glass surface
```
dark:
  bg:             rgba(255,255,255,0.05)
  bgStrong:       rgba(255,255,255,0.08)
  border:         rgba(255,255,255,0.09)
  borderStrong:   rgba(255,255,255,0.14)
  backdropFilter: blur(18px) saturate(160%)
  shadow:         0 4px 20px rgba(0,0,0,0.35)

light:
  bg:             rgba(255,255,255,0.55)
  bgStrong:       rgba(255,255,255,0.75)
  border:         rgba(19,22,27,0.07)
  borderStrong:   rgba(19,22,27,0.12)
  shadow:         0 4px 18px rgba(19,22,27,0.07)
```

### Chat bubbles (dark)
- Me: bg `rgba(62,123,250,0.28)` border `rgba(94,163,255,0.35)` text `#FFFFFF`
- Them: bg `rgba(15,20,28,0.55)` border `rgba(255,255,255,0.08)` text `#ECEEF2`
- Blur: `18px saturate(160%)` her ikisinde

### Chat bubbles (light)
- Me: bg `rgba(62,123,250,0.18)` border `rgba(62,123,250,0.35)` text `#1E52D9`
- Them: bg `rgba(19,22,27,0.06)` border `rgba(19,22,27,0.09)` text `#13161B`

### Typography
- Sans: `Inter` (varsayılan gövde, 400/500/600/700)
- Display: `Space Grotesk` (başlıklar, wordmark, 600/700)
- Mono: `JetBrains Mono` (peer ID, teknik veri, zaman damgaları, 400/500)
- Letter-spacing başlıklarda -0.6 ila -1.0

### Radii
- Kartlar: 14-18px
- Pill / tab bar: 100px (fully rounded) veya 30px
- Avatar: tam daire
- Bubble: 20px, karşı köşe 4px

### Spacing (base 4)
4, 6, 8, 10, 12, 14, 16, 20, 24

### Shadows
Bkz. `Glass surface`. Mavi primary FAB: `0 12px 28px rgba(62,123,250,0.5)`

## Doodle Art Backdrop
`AzDoodleBackdrop` bileşeni: 280×280 tile'lık SVG pattern. İçerik: zarf, peer düğümleri (3 dot + dashed bağlantılar), dalga, kilit, konuşma balonu, @ işareti, dashed path, pulsing node (3 iç içe daire), anahtar, zigzag, küçük yıldızlar, sinyal arkları.

Stroke renkleri:
- dark: `rgba(255,255,255,0.055)` ve strong `rgba(94,163,255,0.07)`
- light: `rgba(19,22,27,0.07)` ve strong `rgba(30,82,217,0.10)`

Taban: `night` veya `paper` rengi + çok hafif mavi wash (`rgba(62,123,250,0.035)`).

**Önemli**: Sohbet, Kurulum, Kişi bilgisi, Grup bilgisi, Rehber ekranlarının **hepsinde** bu doodle arkaplan olmalı — transparanlık hissi ancak bu arkaplan olduğunda belirginleşir.

## P2P Vurgusu
Orta seviye — kullanıcıyı korkutmayacak ama gizlilik/şifreleme her yerde hissedilecek:
- Ana ekranda "Mesh bağlı · 14 peer · 42ms" şeridi
- Sohbet header'ında "çevrimiçi · p2p direct"
- Sistem mesajı olarak "uçtan-uca şifrelendi · <peer>"
- Kişi/grup bilgisinde güvenlik anahtarı bloğu + "Doğrula"
- Peer ID (`7ab3·9f02·e4c1·8d0a`) mono font ile her yerde ince gri
- Kayıt akışında "Sunucusuz. Sadece sen ve cihazın."

## Assets
Üretim için gerekli dosyalar: hiçbir raster asset yok; tüm ikonlar inline SVG (stroke-based, 24×24 viewBox). Avatarlar harf + nötr gri tonları (tek mavi tonlu avatar kullanılabilir primary kişiler için).

## Files
- `src/Elcim.html` — ana canvas, tüm Azure ekranlarını toplar
- `src/azure-brand.jsx` — Azure tasarım sistemi: `AZ` (tokens), `azTheme`, `AzDoodleBackdrop`, `Glass`, `AzureMark`, `AzureWordmark`, `AzAvatar`, `AzChip`, `AzLock`, `AzPrimary`
- `src/azure-screens.jsx` — Azure ekranları: `AzHome`, `AzChat`, `AzContactInfo`, `AzGroupInfo`, `AzContacts`, `AzRegister`, `AzTabs`
- `src/ios-frame.jsx`, `src/android-frame.jsx` — cihaz çerçeveleri (yalnız mockup için, gerçek uygulamada gerekmez)
- `src/design-canvas.jsx` — tasarım canvas'ı (yalnız mockup için)

## Kullanıcı Tercihleri
- Dil: Türkçe
- Tema: light + dark (toggle)
- Chat style: Modern kart tarzı (gölgeli, boşluklu)
- Ton: Teknik / cyber / privacy-first
- P2P vurgusu: Orta

## Nasıl Başlanmalı
1. React Native + Expo projesi kur (`npx create-expo-app`)
2. Fontları yükle: `@expo-google-fonts/inter`, `@expo-google-fonts/space-grotesk`, `@expo-google-fonts/jetbrains-mono`
3. `azure-brand.jsx`'teki tokenları `theme.ts`'ye taşı
4. `AzDoodleBackdrop`'u `react-native-svg` ile port et — Pattern yerine tek bir tile `ImageBackground` ile tekrar ettir
5. `expo-blur` ile `<BlurView intensity={80}>` — glass kartları için
6. Ekranları `azure-screens.jsx`'deki markup'ı referans alarak sırayla uygula: Register → Home → Chat → ContactInfo → GroupInfo → Contacts

## P2P Transport (Referans)
Tasarımlar ağ katmanına agnostic. Öneriler:
- `libp2p-js` (JS/RN)
- `matrix-rust-sdk` ile P2P Matrix
- `Automerge` + `WebRTC` data channels (CRDT ile offline-first)
- `Briar` protokolü (Tor üzerinden)
