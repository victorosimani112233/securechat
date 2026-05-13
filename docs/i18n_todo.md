# Internationalization (i18n) Yol Haritası

**Durum**: Dil değiştirme özelliği UI'da görünür ama **işlevsel değil**. Sebep: UI metinlerinin ~%96'sı Kotlin dosyalarında hardcoded Türkçe.

**Hedef**: `Settings → Dil` seçildiğinde uygulama gerçekten o dile geçsin (TR/EN/AR/DE).

---

## Mevcut durum

| Kategori | Değer |
|---|---|
| Toplam Türkçe string literal (Kotlin) | **~552** (grep ile sayım, Türkçe karakter içerenler) |
| Çevrilmiş `strings.xml` entry | **21** |
| Çeviri oranı | **~3.8%** |
| Desteklenen dil resource'ları | TR (default), EN, AR, DE — hepsi 21 string ile |

### En çok string içeren dosyalar

| Dosya | String sayısı | Öncelik |
|---|---|---|
| `ChatScreen.kt` | 75 | 🔴 Yüksek |
| `SettingsScreen.kt` | 64 | 🔴 Yüksek |
| `ConversationsScreen.kt` | 31 | 🔴 Yüksek |
| `ScheduledMessagesScreen.kt` | 29 | 🟡 Orta |
| `ChatInfoScreen.kt` | 27 | 🟡 Orta |
| `IncomingMessageHandler.kt` | 27 | 🔴 Yüksek (bildirim metinleri) |
| `GroupInfoScreen.kt` | 26 | 🟡 Orta |
| `ContactsScreen.kt` | 20 | 🟡 Orta |
| `CallHistoryScreen.kt` | 16 | 🟢 Düşük |
| `EmailOtpScreen.kt` | 15 | 🟡 Orta (onboarding) |
| `MissedCallTracker.kt` | 14 | 🔴 Yüksek (bildirim metinleri) |
| `PhoneVerificationScreen.kt` | 10 | 🟡 Orta (onboarding) |
| `CallScreen.kt` | 10 | 🟡 Orta |

---

## Eksik teknik altyapı

### 1. `AndroidManifest.xml` per-app locale metadata
```xml
<application ...>
    <meta-data
        android:name="android.app.locales"
        android:resource="@xml/locales_config" />
</application>
```

### 2. `res/xml/locales_config.xml`
```xml
<locale-config xmlns:android="http://schemas.android.com/apk/res/android">
    <locale android:name="tr"/>
    <locale android:name="en"/>
    <locale android:name="ar"/>
    <locale android:name="de"/>
</locale-config>
```

### 3. Activity recreate logic
`SettingsScreen.kt:349` `AppCompatDelegate.setApplicationLocales(locales)` sonrası current Activity recreate edilmeli — Compose context cache'lediği için stringResource recompose'da yenilenmez.

```kotlin
val activity = LocalContext.current as? Activity
activity?.recreate()
```

### 4. `build.gradle.kts` bundle config (AAB shrinking için)
```kotlin
android {
    bundle {
        language {
            enableSplit = false  // tüm diller tek APK/AAB'de kalsın
        }
    }
}
```

---

## Aşamalı migration planı

### Faz 1 — Teknik altyapı (1-2 saat)

- [ ] `res/xml/locales_config.xml` ekle
- [ ] `AndroidManifest.xml`'e meta-data
- [ ] `SettingsScreen` locale seçiminde `activity.recreate()` çağrısı
- [ ] `build.gradle.kts` bundle config

**Doğrulama**: Mevcut 21 string için locale değişimi çalışmalı (Grup Info başlıkları vb).

### Faz 2 — Yüksek öncelikli dosyalar (~3-5 gün)

Sıra: **görünürlük × frekans** matrisine göre

1. **`SettingsScreen.kt`** (64 string) — kullanıcının dil değiştirdiği yer, ilk burayı görür
2. **`ChatScreen.kt`** (75 string) — günde 100+ kez açılır
3. **`ConversationsScreen.kt`** (31 string) — ana giriş ekranı
4. **`IncomingMessageHandler.kt`** (27 string) — bildirim metinleri (cihaz dışı görünür)
5. **`MissedCallTracker.kt`** (14 string) — kaçırılan arama bildirimleri

### Faz 3 — Orta öncelikli (3-4 gün)

6. ChatInfoScreen / GroupInfoScreen (27 + 26)
7. CallScreen / CallHistoryScreen (10 + 16)
8. ScheduledMessagesScreen (29)
9. ContactsScreen / AddGroupMember / CreateGroup (20 + 11 + 11)
10. EmailOtpScreen / PhoneVerificationScreen (15 + 10)

### Faz 4 — Düşük öncelikli + cleanup (1-2 gün)

11. ViewModel'lerdeki user-facing string'ler (Context inject veya Resources string fetcher)
12. Worker / Receiver metinleri
13. Compose Preview'ler (ignore edilebilir)

---

## Çeviri yaklaşımı

### Adım 1: String çıkarma
Her dosya için:
```kotlin
// ÖNCE
Text("Sessize Al")

// SONRA
Text(stringResource(R.string.mute))
```

### Adım 2: Format string'leri
```kotlin
// ÖNCE
"$count yeni mesaj"

// SONRA — strings.xml
<string name="new_messages_count">%1$d yeni mesaj</string>

// SONRA — Kotlin
stringResource(R.string.new_messages_count, count)
```

### Adım 3: Çoğul (plurals)
```xml
<plurals name="member_count">
    <item quantity="one">%d üye</item>
    <item quantity="other">%d üye</item>
</plurals>
```
Kotlin:
```kotlin
pluralStringResource(R.plurals.member_count, count, count)
```

### Adım 4: ViewModel'lerde Context yok
ViewModel'lerde direkt string literal kullanılıyor. Çözüm:
- **A**: Resources object'i inject et (Hilt @ApplicationContext → resources)
- **B**: ViewModel sadece string KEY döndürsün, Composable resolve etsin (daha temiz)

Önerim: **B** — ViewModel'ler hiç string bilmemeli, sadece `MessageType.SCHEDULED_SENT` gibi enum/sealed döndürsün, UI bunu localize etsin.

---

## Dil ekleme stratejisi

### TR (default) → kalıcı
Kotlin'den çıkarılan her string → `values/strings.xml`'e ekle.

### EN
Profesyonel tercüme veya DeepL API:
```bash
# Örnek script (manuel review GEREK)
curl -X POST https://api-free.deepl.com/v2/translate \
    -d "auth_key=$DEEPL_KEY&text=Sessize Al&source_lang=TR&target_lang=EN"
# → "Mute"
```

### AR (right-to-left dikkat!)
- Manifest `android:supportsRtl="true"` ✅ (zaten var)
- RTL specific layout sorunları olabilir — Compose `LocalLayoutDirection` ile bazı yerler manuel düzenleme gerek
- Tarih/sayı formatları `Locale("ar")` ile otomatik

### DE
DeepL kalitesi yüksek, AR'a göre kolay.

---

## Test stratejisi

Her faz sonunda:
1. Cihazda Settings → Sistem → Diller → Elçim → seç
2. Tüm aşamalı ekranları gez (auth, conversations, chat, settings, call)
3. Bildirim metinlerini test et (cihazı kilitleyip arama gönder)
4. RTL test: Arapça'da metinler doğru yöne akıyor mu

---

## Tahmini iş gücü

| Faz | Süre | Risk |
|---|---|---|
| Faz 1 (teknik) | 2 saat | Düşük |
| Faz 2 (yüksek öncelik) | 3-5 gün | Orta (UI test gerekli) |
| Faz 3 (orta öncelik) | 3-4 gün | Düşük |
| Faz 4 (cleanup) | 1-2 gün | Düşük |
| Çeviri (4 dil × ~500 string) | 1-2 gün (DeepL + review) | Düşük |
| **TOPLAM** | **~10-15 gün** | — |

---

## Şu anki durumun kullanıcıya yansıması

- Kullanıcı `Settings → Dil → English` seçerse:
  - `Grup Bilgileri` → `Group Info` ✅ (21 string'den biri)
  - `Sohbetler` → hala `Sohbetler` ❌
  - `Sessize Al` → hala `Sessize Al` ❌
  - Bildirim "Kaçırılan arama" → hala Türkçe ❌

- Kullanıcı net olarak "dil değişmiyor" der — **doğru tespit**.

---

## Geçici çözüm (önerilmedi, ama opsiyonel)

`Settings → Dil` kartının altına küçük bir info text:

> "Tam dil desteği yakında — şu an temel UI çevrilmiş durumda."

Bu kullanıcı yanılmasını azaltır. Karar **kullanıcı tarafından alındı: feature kalsın, kullanıcıya bildirim eklenmedi.**

---

## Notlar

- **CLAUDE.md** "UI metinleri: Türkçe (strings.xml)" diyor — bu kural başlangıçta konmuş ama uygulanmamış. Migration sonrası bu kural **zorunlu** hale getirilmeli (lint check eklenebilir: hardcoded Türkçe string'i CI'de yakala).
- Plurals + format string'ler ile birlikte toplam i18n entry sayısı ~600-700 olur.
- AR için: bazı emojiler RTL bağlamda farklı görünür, test gerekli.
