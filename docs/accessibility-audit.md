# Accessibility (A11y) Audit Checklist — SecureChat

> WCAG 2.1 AA hedefi. Compose UI için `Modifier.semantics` + content descriptions
> + touch target 48dp + sufficient contrast.

## Hızlı tarama komutu (manuel)

```bash
# Tüm IconButton'larda contentDescription var mı
grep -rn "IconButton" app/src/main --include="*.kt" -A2 | grep -v "contentDescription"
```

## Otomatik audit (skill ile)

`auditing-accessibility` skill mevcut. Bir oturumda:
```
/auditing-accessibility
```
ile tüm ekranları tarayıp eksik label + küçük touch target + contrast issue raporu üretir.

## Manuel checklist (release öncesi)

### Content descriptions
- [ ] Tüm `IconButton`'larda `contentDescription` (null değil)
- [ ] Decorative iconlar için `Icon(contentDescription = null)` explicit
- [ ] Image (Coil) için `contentDescription` veya `null` (avatar = "X profil fotoğrafı")
- [ ] Anlık state'ler dinamik (örn. mute icon: muted ise "Sesi aç", değilse "Sustur")

### Touch targets (min 48dp)
- [ ] `IconButton` default 48dp (Material3 zaten sağlar) — küçültülmüşler varsa düzelt
- [ ] `Modifier.size(20.dp)` kullanan tıklanabilir alanlar — `Modifier.minimumInteractiveComponentSize()` ekle
- [ ] Mesaj baloncuğu long-press touch target 48dp+

### Reading order (TalkBack)
- [ ] MessageBubble: sender → timestamp → content → status (mantıklı sıra)
- [ ] Sohbet listesi row: avatar → name → preview → time → badge
- [ ] Form alanları: label → input → error message (her zaman bu sıra)

### Contrast (WCAG AA)
- [ ] Mesaj baloncuğu metin/arkaplan ≥ 4.5:1 (light + dark mode)
- [ ] System message text on backdrop ≥ 3:1
- [ ] Disabled state ≥ 3:1 (action affordance göstermez ama anlaşılır)
- [ ] Brand renkler (Azure mavi #3E7BFA): büyük metin için 3:1, küçük metin için 4.5:1

### State announcements
- [ ] Mesaj durumu (gönderiliyor/iletildi/okundu) screen reader'da duyuluyor mu
- [ ] Yeni mesaj geldiğinde TalkBack `LiveRegion` duyurusu (mesaj listesi bottom'unda)
- [ ] Bildirim banner'ları `polite` LiveRegion

### Navigation
- [ ] Geri tuşu mantıklı (her ekrandan)
- [ ] Pager swipe'larda sayfa numarası duyurulur ("3 / 3")
- [ ] Modal/dialog açılınca focus dialog'a gider, kapanınca geri döner

### Yazı boyutu / font scaling
- [ ] System font size 200% iken layout bozulmuyor
- [ ] Min font size 14sp (vücut metni)
- [ ] Compose `sp` kullanılıyor (`dp` değil) — text için

### Renk körlüğü
- [ ] Mesaj durumu (mavi/gri tik) tek başına renk ile ayrılmıyor — ikon farklı
  (mevcut: Check vs DoneAll, ✓)
- [ ] Hata state'leri kırmızı + ikon (sadece kırmızı YOK)

### Animasyon
- [ ] System "reduce motion" aktifse ağır animasyonlar kapanır
- [ ] Spinner/loading state alternatif text gösterir

## Hızlı fix önerileri

### `IconButton(onClick = {})` minimum pattern
```kotlin
IconButton(onClick = { /* action */ }) {
    Icon(
        Icons.Default.Send,
        contentDescription = "Mesaj gönder"  // ASLA null değil
    )
}
```

### `Image()` minimum pattern
```kotlin
Image(
    painter = painterResource(R.drawable.avatar),
    contentDescription = "$peerName profil fotoğrafı"  // dinamik
)
```

### `Modifier.semantics` ile zenginleştirme
```kotlin
Row(modifier = Modifier.semantics {
    contentDescription = "Mesaj: $sender, $time, $preview"
    role = Role.Button
}) {
    // ...
}
```

### Touch target garanti
```kotlin
Box(
    modifier = Modifier
        .size(20.dp)  // görsel boyut küçük
        .minimumInteractiveComponentSize()  // ama touch target 48dp
        .clickable { ... }
)
```

## Faz 15 follow-up

Bu checklist refactor sprint'leri (Faz 8/9/10) ile birlikte uygulanır.
Şu an WindowSizeClass infrastructure hazır (`ResponsiveLayout.kt`),
sonraki adım:
1. `SecureChatActivity` 'da `setContent`'in dışında `calculateWindowSizeClass`
2. ChatScreen, ConversationsScreen, GroupInfoScreen vb. ekranlarda
   `LocalWindowSizeClass.current` ile 2-pane karar
3. `auditing-accessibility` skill ile tam tarama → toplu fix
