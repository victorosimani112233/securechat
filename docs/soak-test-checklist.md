# Telecom Soak Test Checklist — SecureChat

> Çağrı yığını historik olarak kırılgan (2026-05-06 revert). Bu checklist tüm
> production release'lerden önce **manuel olarak** geçilmek üzere yazıldı.
>
> Hedef: Her test günlüğe bir cihaz başına ~15 dakika; tam matrix 1 günde tamamlanabilir.

## Cihaz matrisi

Minimum 5 OEM × 2 Android versiyonu × stock + battery saver state = 20 kombinasyon.

| OEM | Önerilen model | Android | Pain point |
|---|---|---|---|
| Samsung A | Galaxy A52/A54 | 12, 13 | One UI 5/6 Bluetooth audio route |
| Samsung S | Galaxy S22/S23/S24 | 13, 14 | One UI 7 SELF_MANAGED ConnectionService |
| Xiaomi | Redmi Note 12/13 | 13, 14 | **MIUI aggressive battery — AutoStart whitelist gerekir** |
| Huawei | Mate 50 / nova 11 | 12 (HMS) | **HMS push (FCM yok) — backup channel gerekir** |
| Pixel | Pixel 6/7/8 | 14, 15 | Stock referans, ideal davranış |
| Oppo | Reno 10/11 | 13, 14 | ColorOS aggressive doze |
| OnePlus | Nord/12 | 13, 14 | OxygenOS — Pixel'e yakın |
| Vivo | V29/V30 | 13, 14 | FunTouch UI — autostart whitelist |

> **Minimum**: Samsung A + Xiaomi + Pixel + (Huawei VEYA Oppo) — 4 cihaz.

## Test senaryoları

### S1 — Gelen çağrı + kabul + uzun konuşma

- [ ] Telefon kilitli ekran, gelen çağrı → full-screen intent ile aç
- [ ] Kabul et → 30dk konuşma
- [ ] Ses kalitesi OK (kesinti yok)
- [ ] 30dk sonunda kapat — call log'da görünüyor
- [ ] (Xiaomi/Huawei) AutoStart kapalıyken full-screen intent geliyor mu?

### S2 — Gelen çağrı + reddet

- [ ] Telefon kilitli, gelen çağrı → reddet
- [ ] Diğer cihazda "Reddedildi" mesajı
- [ ] Call log: "Cevapsız" değil "Reddedildi"

### S3 — Giden çağrı + diğer taraf cevap vermez

- [ ] Çağrı başlat → diğer cihaz arayan ekranını görür ama kabul etmez
- [ ] 60sn sonra otomatik "Cevapsız" → her iki tarafta da log'da görünür
- [ ] Çağrı banner kaybolur (stale "Katıl" banner kalmıyor — recent fix)

### S4 — Giden çağrı + meşgul

- [ ] Diğer cihaz başka çağrıda iken çağrı başlat
- [ ] "Meşgul" mesajı → her iki tarafta da log'da

### S5 — Network değişikliği (aktif çağrı sırasında)

- [ ] Aktif çağrı sırasında Wi-Fi → Mobile geçişi (Wi-Fi kapat)
- [ ] **Çağrı kopmuyor** (ICE candidate refresh)
- [ ] Tekrar Wi-Fi'a geç → çağrı devam ediyor

### S6 — Bluetooth headset

- [ ] Aktif çağrı sırasında BT headset bağla
- [ ] Ses headset'e route oluyor (otomatik veya manuel toggle)
- [ ] BT'i ayır → ses telefon hoparlörüne / kulak yakına döner
- [ ] (Samsung One UI 7) SELF_MANAGED + Bluetooth bilinen pain — ek dikkat

### S7 — Doze / Battery saver

- [ ] Battery saver ON
- [ ] 30dk app'i arka planda bırak (cihazı kullanma, ekran kapat)
- [ ] Çağrı geldiğinde **bildirim/full-screen intent geliyor mu?**
- [ ] (Xiaomi MIUI 14) Doze + AutoStart kapalı → çağrı KAÇIRILIRSA bilinen sorun
- [ ] (Huawei) HMS push fail → backup polling çalışıyor mu

### S8 — Push wake (uygulama tamamen kapalı)

- [ ] `adb shell am force-stop com.securechat.app` (veya recents'tan swipe)
- [ ] Diğer cihazdan çağrı yap
- [ ] Bildirim geliyor mu? Full-screen intent açılıyor mu?

### S9 — Grup arama mesh (3 kişi)

- [ ] 3 kişilik grupta sesli arama başlat
- [ ] Hepsi katıldı → herkesin sesi diğerlerinde duyuluyor
- [ ] 1 kişi ayrılınca diğer 2 devam ediyor

### S10 — Grup arama SFU (4+ kişi, **kritik geçiş noktası**)

- [ ] 3 kişilik aktif aramaya 4. kişi katılır → mesh → SFU geçişi
- [ ] **Her 4 kişinin sesi de diğerlerinde duyulmalı** (bilinen risk: 4. kişi sessiz)
- [ ] Janus container log'larında SFU room created
- [ ] 1 kişi ayrılınca 3 kişiye dönüşte mesh'e geri geçiş (varsa) çalışmalı

### S11 — Çağrı sırasında ekran kilitle / uyandır

- [ ] Aktif çağrı + ekran kilitle (power button)
- [ ] Uyandır → CallScreen geri açıldı
- [ ] Ses kesilmedi
- [ ] Kilit ekranında call notification gösteriliyor

### S12 — Çağrı + push notification gelir

- [ ] Aktif çağrı sırasında üçüncü kişiden mesaj geldi → FCM push
- [ ] Push bildirimi çağrıyı kesmiyor
- [ ] Bildirim tıklanırsa → çağrı arka plana, sohbet açılır

## Recording + reporting

Her senaryo için:
1. **adb logcat** kaydet (`adb logcat -s CallManager:V WebRTC:V SignalingClient:V > soak-$device-$scenario.log`)
2. **Ekran kaydı** (Android Studio Logcat veya `adb shell screenrecord`)
3. **Sonuç**: ✓ Pass / ✗ Fail (postmortem aç) / ⚠ Marginal (kalite problemi)
4. `docs/soak-test-results-YYYY-MM-DD.md`'ye kaydet (template var)

## Bilinen pain point'ler ve workaround'lar

| Senaryo | Pain | Workaround |
|---|---|---|
| Xiaomi AutoStart kapalı | full-screen intent kaçıyor | UI'da "Pil ayarlarını ayarlayın" bilgilendirme banner'ı |
| Huawei HMS-only | FCM yok | OkHttp + long polling backup channel (TODO) |
| Samsung One UI 7 BT | SELF_MANAGED route bug | Manual toggle UI + ses route fallback |
| Mesh→SFU | 4. kişi sessiz olabilir | `securechat-call-reliability` skill diagnostic |

## Marble test (automated)

`media/src/test/.../CallManagerStateMarbleTest.kt` (yeni, Faz 4 follow-up):
```kotlin
@Test
fun `callSession state transitions — happy path`() = runTest {
    callManager.callSession.test {
        callManager.initiateCall(...)
        assertThat(awaitItem()?.state).isEqualTo(CallState.INITIATING)
        callManager.onCallAccepted(...)
        assertThat(awaitItem()?.state).isEqualTo(CallState.RINGING)
        callManager.onCallConnected(...)
        assertThat(awaitItem()?.state).isEqualTo(CallState.ACTIVE)
        callManager.endCall()
        assertThat(awaitItem()?.state).isEqualTo(CallState.ENDED)
    }
}
```
(Turbine library zaten projeye eklenebilir — `app.cash.turbine:turbine:1.0.0`)

## CrashReporter setup (production)

`CrashReporter` interface şu an no-op. Crashlytics aktif etmek için:

1. Firebase Console'da Crashlytics enable (proje zaten FCM kurulu)
2. `app/build.gradle.kts` plugins bloğuna:
   ```
   id("com.google.gms.google-services")
   id("com.google.firebase.crashlytics")
   ```
3. Root `build.gradle.kts` plugins bloğuna:
   ```
   id("com.google.gms.google-services") version "4.4.0" apply false
   id("com.google.firebase.crashlytics") version "2.9.9" apply false
   ```
4. `app/build.gradle.kts` dependencies:
   ```
   implementation("com.google.firebase:firebase-crashlytics")
   ```
5. `CrashlyticsCrashReporter` impl class yaz (CrashReporter.kt KDoc'unda template var)
6. `MonitoringModule.bindCrashReporter` → CrashlyticsCrashReporter
7. `SecureChatApplication.onCreate`'de:
   ```kotlin
   crashReporter.setCustomKey("commit", BuildConfig.VERSION_NAME)
   crashReporter.setCustomKey("buildType", BuildConfig.BUILD_TYPE)
   ```
8. ProGuard mapping upload (release build için Crashlytics plugin otomatik yapar)
