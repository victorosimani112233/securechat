# SecureChat — İyileştirme Yol Haritası

> Bu döküman, mevcut değerlendirmedeki **güvenlik, reliability, mimari ve UX** başlıklarındaki açık iyileştirme alanlarını faz faz detaylandırır. **Grup E2EE (Sender Keys) + 1:1 E2EE entegrasyonu** ayrı bir prompt/session'da yürütülecektir, bu döküman onu kapsamaz.

## Genel değerlendirme özeti (durum tespiti)

| Kategori | Mevcut puan | Hedef puan |
|---|---|---|
| Feature genişliği | 8.5 / 10 | korunacak |
| Güvenlik | 7.0 / 10 | **9.0 / 10** |
| UI/UX | 8.0 / 10 | **9.0 / 10** |
| Reliability | 6.5 / 10 | **8.5 / 10** |
| Mimari/Kod kalitesi | 7.5 / 10 | **9.0 / 10** |

**Toplam ortalama:** 7.5 → **9.0** hedeflenir.

## Faz öncelik özeti

```
P0 (KRİTİK güvenlik):  Faz 1, 2, 3
P1 (yüksek):           Faz 4, 5, 6, 7
P2 (orta):             Faz 8, 9, 10
P3 (cilalama):         Faz 11, 12, 13
```

---

# KATEGORİ A — GÜVENLİK

## Faz 1 — WS auth gerçek JWT validasyonu

**Önem:** P0 (kritik) — şu an saldırgan istediği userId ile WebSocket açabilir.

### Mevcut durum

- `app/.../data/AppLifecycleObserver.kt`'da WS handshake `"token_$userId"` sahte string ile yapılıyor
- `UserSession.accessToken` (gerçek JWT) mevcut ama WS handshake'inde kullanılmıyor
- Server (`signaling-server/.../WebSocketRoutes.kt`) muhtemelen bu token'ı validate etmiyor — audit edilmeli

### Saldırı senaryosu

Saldırgan bir kullanıcının `userId` UUID'sini bilirse (grup üye listesinden, sızdırılmış logdan vs.) `?userId=X` parametresi ile WS açar, X'e gelen tüm mesajları alır + X adına mesaj gönderir. Tüm güvenlik mimarisini bypass eder.

### Yapılacaklar

1. **Client tarafı**: `AppLifecycleObserver.connect()` çağrısında `userSession.accessToken` (Bearer JWT) kullan, `"token_$userId"` yerine
2. **Server tarafı** (`signaling-server/.../WebSocketRoutes.kt`):
   - WS upgrade route'unda `Authorization` header'ı zorunlu yap
   - Nimbus JOSE+JWT ile EdDSA imza doğrulaması
   - JWT claim'inden `sub` (userId) okunup `?userId=X` query param'ı ile karşılaştır
   - Eşleşmiyorsa **401 Unauthorized**, eşleşmiyorsa connection drop
3. **JWT expire akışı**:
   - Token süresi dolunca client refresh token ile yeni access token al
   - Eski JWT'yi `JwtBlacklist`'e ekle (mevcut altyapı var)
   - WS reconnect yeni token ile
4. **Geriye uyumluluk dönemi (7 gün)**:
   - Server hem eski sahte hem yeni JWT'yi kabul etsin (header yoksa fall-through)
   - 7 gün sonra `BuildConfig.REQUIRE_JWT_WS = true` ile sahte token reddet
   - Log'da "legacy_ws_auth: $userId" sayacı ile geçişi izle

### Etkilenen dosyalar

- `app/.../data/AppLifecycleObserver.kt:64-92`
- `app/.../data/UserSession.kt:57-99` (accessToken kullanımı)
- `network/.../SignalingClient.kt:104-127` (connect handshake)
- `signaling-server/.../WebSocketRoutes.kt` (upgrade route)
- `signaling-server/.../EdDsaJwtVerifier.kt` (zaten var, kullan)

### Test

- Unit: JWT verify mock'la, sub mismatch → 401 assert
- Manuel: curl ile başka userId ile bağlanma denemesi → reject
- Regression: mevcut kullanıcılar 7 günlük hibrit dönemde sorun yaşamadığı

### Tahmini süre

3-5 gün

---

## Faz 2 — Multi-recipient admin log PreKeyBundle fetcher

**Önem:** P0 (kritik) — yeni atanan admin'ler şu an export log'larını alamıyor (session yok diye).

### Mevcut durum

- `app/.../domain/usecase/RecordExportEventUseCase.kt` her admin için `messageEncryptor.encrypt(adminId, ...)` çağırıyor
- Eğer admin ile Signal session henüz kurulmamışsa exception fırlıyor, o admin payload listesine eklenmiyor
- bot-api'de `PreKeyBundleFetcher` var ama app modülüne port edilmedi
- Yeni atanan admin = X3DH yapılmamış → log alamıyor (bu durum 1:1 E2EE Faz 0'da otomatik çözülecek ama o ayrı session'da)

### Yapılacaklar

1. **PreKeyBundleFetcher port** (yeni dosya): `app/.../crypto/PreKeyBundleFetcher.kt`
   - bot-api'deki `bot-api/.../signal/PreKeyBundleFetcher.kt`'i referans al
   - `suspend fun fetch(userId: String): Result<PreKeyBundle>`
   - Endpoint: `GET ${apiBaseUrl}/api/v1/users/{userId}/prekeys`
   - OkHttp + Bearer (UserSession.accessToken)
2. **SessionEnsurer** (yeni dosya): `app/.../crypto/SessionEnsurer.kt`
   - `suspend fun ensureSession(recipientId: String): Boolean`
   - `SessionManager.hasSession` → varsa true
   - Yoksa `PreKeyBundleFetcher.fetch` → `SessionManager.createSession` → true
   - **Mutex per-recipient**: aynı recipient için concurrent ensureSession çağrıları tek bir fetch'e merge olsun
3. **RecordExportEventUseCase güncelle**:
   - Her admin için önce `sessionEnsurer.ensureSession(adminId)` çağır
   - Başarısızsa skip (zaten kasıtlı davranış)
4. **Hilt DI**: PreKeyBundleFetcher + SessionEnsurer için @Inject + @Singleton

### Etkilenen dosyalar

- Yeni: `app/.../crypto/PreKeyBundleFetcher.kt`
- Yeni: `app/.../crypto/SessionEnsurer.kt`
- `app/.../domain/usecase/RecordExportEventUseCase.kt`
- Referans: `bot-api/.../signal/PreKeyBundleFetcher.kt`

### Test

- Unit: SessionEnsurer cache hit (Mutex davranışı)
- Integration: yeni admin ata, ona ilk export log gönder, decrypt başarılı

### Tahmini süre

2-3 gün

**NOT:** Bu faz, 1:1 E2EE çalışmasıyla (ayrı session) örtüşür. Eğer 1:1 E2EE Faz 0 önce bitirilirse SessionEnsurer zaten orada hazır olur, bu fazda sadece RecordExportEventUseCase güncellenir.

---

## Faz 3 — Memory zeroize sistematik

**Önem:** P0 (kritik) — hassas veri RAM'de uzun süre kalıyor, memory dump saldırılarına açık.

### Mevcut durum

- `MessageEncryptor.encrypt/decrypt` plaintext byte array'leri `fill(0)` yapmıyor
- Bazı yerlerde manuel `fill(0)` var (passphrase, RecordExportEventUseCase plaintext) — tutarsız
- LocalMessage objeleri Compose state'inde tutulduğu için sensitive content RAM'de uzun süre kalır
- Clipboard 60sn sonra temizleniyor ✓
- View-once metin DB'den siliniyor ✓ ama Compose state'inde snapshot kalıyor

### Yapılacaklar

1. **Crypto API'leri zeroize ile sarmala**:
   - `MessageEncryptor.encrypt(recipientId, plaintext: ByteArray)`: encrypt sonrası `plaintext.fill(0)` (eğer caller verdi ise yapmalı; doc string'e ekle)
   - `MessageEncryptor.decrypt(...)` dönüş byte array'i kullanım sonrası caller'ın `fill(0)` yapması gerektiğini doc'la
   - Yeni `inline fun <R> ByteArray.useAndZeroize(block: (ByteArray) -> R): R` extension yarat → `try { block(this) } finally { fill(0) }`
2. **String yerine ByteArray kullan** (sensitive yerlerde):
   - SQLCipher passphrase ✓ (zaten ByteArray)
   - Crypto round-trip'ler ✓
   - Mesaj envelope plaintext — bu refactor daha büyük, dikkatli yap
3. **Compose state lifecycle**:
   - `ChatViewModel.onCleared`'da:
     - `messages` StateFlow'una `emptyList()` emit et (referansları drop)
     - search query, draft, conversationInfo sıfırla ✓ (zaten var ama audit et)
     - readReceiptSentIds.clear()
   - App background'a inince (`AppLifecycleObserver.onStop`):
     - Aktif ChatViewModel varsa mesaj cache'i drop et
     - Foreground'a dönünce DB'den re-load
4. **Audit**: `find app/src/main -name "*.kt" -exec grep -l "ByteArray\|password\|passphrase\|private.*key" {} \;` ile tüm sensitive yerleri tara, eksik fill(0) varsa düzelt
5. **LeakCanary entegrasyonu** (debug build only): build.gradle.kts'de `debugImplementation` ile LeakCanary 2.x ekle, dev/debug build'lerde leak detect

### Etkilenen dosyalar

- `crypto/.../MessageEncryptor.kt`
- `app/.../ui/theme/viewmodel/ChatViewModel.kt:287-307` (onCleared genişlet)
- `app/.../data/AppLifecycleObserver.kt:96-111` (onStop'a state drop ekle)
- Yeni: `crypto/.../ByteArrayExt.kt` (extension)
- `app/build.gradle.kts` (LeakCanary dependency)

### Test

- Unit: extension `useAndZeroize` davranışı (exception case dahil)
- Manuel: LeakCanary ile chat ekranı açıp kapatınca leak yok

### Tahmini süre

3-4 gün

---

# KATEGORİ B — RELIABILITY

## Faz 4 — Call/telecom soak test + crash reporting

**Önem:** P1 — telecom yığını revert geçmişi olan kırılgan bölge.

### Mevcut durum

- 2026-05-06: Signal-pattern refactor regresyon → revert (memory'de yazılı)
- Telecom Framework A+B+C+D entegrasyonu (gelen+giden+audio routing) eklendi ama gerçek cihaz testi yapılmadı
- **Crash reporting yok** — production crash'leri görünmüyor
- Skill mevcut: `securechat-call-reliability`

### Yapılacaklar

1. **Crash reporting kur** (Firebase Crashlytics önerilir):
   - `app/build.gradle.kts`'e `firebase-crashlytics` + `firebase-analytics` (gerekli)
   - `SecureChatApplication.onCreate`'te `Firebase.crashlytics.setCustomKey("commit", BuildConfig.VERSION_NAME)`
   - ProGuard mapping upload (release builds için)
   - Sentry alternatifi: self-hosted, GDPR daha kolay
2. **Soak test matrisi** (manuel + skill ile):
   - **Cihazlar**: Samsung A series, Samsung S series, Xiaomi Redmi, Pixel, Huawei (HMS), Oppo, OnePlus, Vivo — minimum 5 OEM
   - **Android versiyonları**: 9, 10, 11, 12, 13, 14
   - **Senaryolar**:
     - Gelen çağrı + kabul + 30dk konuşma
     - Gelen çağrı + reddet
     - Giden çağrı + diğer taraf cevap vermez (busy, no answer)
     - Aktif çağrı sırasında Wi-Fi → Mobile geçişi
     - Aktif çağrı sırasında Bluetooth headset bağla/ayır
     - Aktif çağrı sırasında ekran kilitle / uyandır
     - Aktif çağrı sırasında push notification gel
     - Doze mode (Battery saver) açıkken gelen çağrı (Xiaomi/Huawei'de pain point)
     - 4. katılımcı join'de mesh→SFU geçişi
3. **Bilinen pain point checklist**:
   - **Xiaomi/Huawei aggressive battery**: full-screen intent gelmeyebilir → AutoStart whitelist talimatı (UI'da bilgi)
   - **Samsung One UI 7**: SELF_MANAGED ConnectionService Bluetooth route bug → workaround uygula
   - **Mesh→SFU geçişi**: 4. katılımcı join'inde sessizlik testi
4. **Test recorder**: `securechat-call-reliability` skill'i ile cihaz otomasyonu — her senaryo için screenshot + UI tree snapshot + crash log
5. **State machine determinismi**: `CallManager.callSession` Flow için marble test'ler (kotlinx-coroutines-test + Turbine)
6. **Postmortem doc**: Her fail eden senaryo için `docs/incidents/YYYY-MM-DD-<topic>.md` aç

### Etkilenen dosyalar

- `app/build.gradle.kts` (crashlytics dep)
- `app/.../SecureChatApplication.kt`
- `media/.../CallManager.kt` (varsa marble test'ler)
- `app/google-services.json` (Firebase)
- Yeni: `docs/incidents/`
- Yeni: `docs/soak-test-results.md`

### Test

- Otomatik smoke test (cihaz emülasyon yok, gerçek cihaz lazım)
- Crashlytics dashboard'da 1 hafta gözlem

### Tahmini süre

5-7 gün (test sürecini dahil)

---

## Faz 5 — Test compile hataları + coverage hedef

**Önem:** P1 — şu an `:network:test :storage:test :media:test` compile bile etmiyor.

### Mevcut durum

```
network/.../PeerConnectionManagerTest.kt:33  No value passed for parameter 'stunUrl'
storage/.../CryptoIdentityStoreImplTest.kt:49  No value passed for parameter 'keyStoreManager'
media/.../CallManagerTest.kt:83  No value passed for parameter 'messageRepository' + 'sharedOkHttpClient'
```

- 53 test dosyası / 66K LOC Kotlin → tahmini coverage **%30-40**
- JaCoCo kurulu değil, gerçek rakam yok
- CI'da test gate yok

### Yapılacaklar

#### Adım 1 — Mevcut test'leri yeşil yap (1 saat)

1. `network/src/test/.../PeerConnectionManagerTest.kt:33` — `stunUrl = "stun:test:3478"` ekle
2. `storage/src/test/.../CryptoIdentityStoreImplTest.kt:49` — `keyStoreManager = mockk()` ekle
3. `media/src/test/.../CallManagerTest.kt:83` — `messageRepository = mockk()`, `sharedOkHttpClient = mockk()` ekle
4. Tüm test modüllerini çalıştır: `./gradlew test`
5. CI workflow'a `test` ekle (zaten yoksa)

#### Adım 2 — JaCoCo kur (yarım gün)

1. Root `build.gradle.kts`'e JaCoCo plugin ekle
2. Her modülde `jacocoTestReport` task'ı (Android module'lar için JaCoCo Android plugin variant)
3. `./gradlew jacocoTestReport` → `build/reports/jacoco/` HTML rapor
4. CI'da rapor artifact olarak yükle

#### Adım 3 — Crypto modülü coverage %95 (3-5 gün)

**Hedef testler:**

- `crypto/src/test/.../MessageEncryptorTest.kt`:
  - encrypt/decrypt round-trip (PREKEY + SIGNAL)
  - session yokken `NoSessionException`
  - identity key tamper detection (`UntrustedIdentityException`)
  - empty plaintext, çok büyük plaintext
- `crypto/src/test/.../SessionManagerTest.kt`:
  - X3DH key agreement
  - `hasSession` + `createSession` + concurrent access (Mutex test)
- `crypto/src/test/.../PreKeyBundleTest.kt`:
  - bundle serialization/deserialization
  - signed prekey signature verification
- `crypto/src/test/.../ProtocolStoreIntegrationTest.kt`:
  - DB-backed store, persistence (Room in-memory)
  - Restore after app restart

#### Adım 4 — Network modülü coverage %80 (3 gün)

- `network/src/test/.../SignalMessageSerializationTest.kt`: 31 tip için JSON round-trip
- `network/src/test/.../OfflineMessageQueueTest.kt`: queue/flush/clear, concurrent safety (ConcurrentLinkedQueue)
- `network/src/test/.../StuckMessageRecoveryTest.kt`: 2dk eşiği, status transitions
- `network/src/test/.../SignalingClientTest.kt`: reconnect backoff, MockWebServer ile

#### Adım 5 — Storage modülü coverage %80 (2 gün)

- Tüm DAO'lar için in-memory Room test
- `MigrationTest.kt`: v17→v18→v19 zinciri (schema export verification)
- `MessageRepository.recalculateLastMessage` edge case'leri

#### Adım 6 — App/domain/usecase coverage %90 (3 gün)

Her UseCase için happy + edge + error path:
- `SendMessageUseCase`
- `MarkAsReadUseCase`
- `AddGroupMemberUseCase`, `RemoveGroupMemberUseCase`, `PromoteToAdminUseCase`
- `UpdateGroupNameUseCase`
- `ToggleExportPolicyUseCase`
- `RecordExportEventUseCase`
- `ObserveMessagesUseCase`

#### Adım 7 — ViewModel testleri (2-3 gün)

- `kotlinx.coroutines.test.runTest` + `MainDispatcherRule`
- `Turbine` library StateFlow emission test'leri
- ChatViewModel, GroupInfoViewModel, ChatInfoViewModel için en az 5 test her birinde

#### Adım 8 — CI threshold (1 saat)

- `jacocoTestCoverageVerification` ile %70 minimum
- CI build düşerse merge'i reject

### Etkilenen dosyalar

- 3 mevcut test dosyası fix
- 15-20 yeni test dosyası
- Root `build.gradle.kts` (JaCoCo)
- CI workflow (varsa `.github/workflows/` veya `.gitlab-ci.yml`)

### Tahmini süre

3-4 hafta solo full-time (kapsamlı). Veya: feature freeze + 2 hafta yoğun test sprint.

---

## Faz 6 — Bug postmortem disiplini

**Önem:** P1 — bug pattern history yoğun (sureli-mesaj 5 fazda fix, okundu tikleri 2 deneme).

### Mevcut sorun

- Sureli-mesaj 5 fazda fix: ilk versiyon race window + senkron sorunu → **kök neden: test-first yapılmadı**
- Okundu tikleri 2 fix: ilk fix Flow emit hızını hesaba katmadı → **kök neden: UX manuel cihaz testi olmadan ölçeklendirildi**
- 14-bug dalga 1: medya + anket + arama UI çakışmaları → **kök neden: integration test yok**

### Yapılacaklar

1. **PR gate'leri kur**:
   - Her yeni feature için min 1 unit test + 1 integration test zorunlu
   - CI hook: yeni `.kt` dosya eklendiğinde karşılığı `.kt` test dosyası yoksa reject
2. **Manuel test checklist** (`docs/release-checklist.md`):
   - 30 dakikalık smoke test senaryosu, yazılı
   - Her release öncesi 1 cihazda mutlaka geç
   - `controlling-mobile-devices` skill ile otomatize edilebilir
3. **Feature flag pattern**:
   - Yeni özellikler `BuildConfig.FEATURE_X_ENABLED` ile default-off merge edilsin
   - Dogfood'da test edip aç
   - `update-config` skill bunun için kullanılabilir
4. **Postmortem template** (`docs/incidents/TEMPLATE.md`):
   ```markdown
   # YYYY-MM-DD — <konu>
   ## Ne oldu
   ## Neden (root cause)
   ## Nasıl tespit edildi
   ## Geçici çözüm
   ## Kalıcı çözüm
   ## Önleme (test/process)
   ```
5. **Regression test pool**:
   - Her fix için en az 1 regression test ekle
   - Test sınıf adı: `<BugName>RegressionTest` ki bug geri gelmesin
6. **Memory entry**: Her major bug için memory'e kayıt (zaten yapılıyor kısmen, formalize et)

### Etkilenen dosyalar

- Yeni: `docs/incidents/TEMPLATE.md`
- Yeni: `docs/release-checklist.md`
- Yeni: `.github/workflows/pr-gates.yml` (varsa CI'a)
- CONTRIBUTING.md (yoksa oluştur)

### Tahmini süre

2 gün (setup) + sürekli disiplin

---

## Faz 7 — Release discipline + versioning policy

**Önem:** P1 — versionCode=1'i 4 ay güncelleme bug'ından ders.

### Mevcut durum

- versionCode auto-increment yapıldı (commit `7b4c3d7`) ✓
- VERSION dosyası + refresh script yapıldı (commit `59d036f`) ✓
- Tag-based release süreci yok
- CHANGELOG.md yok
- Release notes manuel

### Yapılacaklar

1. **Tag bazlı release**:
   - Her prod release `git tag v1.0.X -a -m "release notes"` ile
   - CI tag'i görünce signed APK + release notes üretsin
2. **App Bundle migration**:
   - Play Store için `.aab` formatı zorunlu olacak (eğer Play Store hedefliyorsan)
   - `./gradlew bundleProdRelease` ekle
3. **Release notes otomasyonu**:
   - `git log --oneline tag1..tag2` → CHANGELOG.md
   - Yeni: `scripts/generate-changelog.sh`
4. **Hot-fix branch pattern**:
   - prod tag'ten branch çıkar, fix yap, sonra main'e cherry-pick
   - `docs/HOTFIX_WORKFLOW.md`
5. **"Güncelleme var" indikatörü** (manuel APK dağıtımı için):
   - Server'da `/api/v1/latest-version` endpoint
   - Client'ta Hakkında ekranında "Güncel" / "Güncelleme var: 1.0.55" göster
6. **APK signing strategy**:
   - Release keystore güvenli yerde (offline veya hardware-backed)
   - `app/build.gradle.kts:signingConfigs` zaten var, audit et
   - keystore backup procedure

### Etkilenen dosyalar

- `app/build.gradle.kts` (bundleProdRelease)
- Yeni: `scripts/generate-changelog.sh`
- Yeni: `CHANGELOG.md`
- Yeni: `docs/HOTFIX_WORKFLOW.md`
- `signaling-server/.../HttpRoutes.kt` (latest-version endpoint)
- `app/.../ui/screen/SettingsScreen.kt` (versiyon güncelleme indikatörü)

### Tahmini süre

2-3 gün

---

# KATEGORİ C — MİMARİ / KOD KALİTESİ

## Faz 8 — ChatScreen.kt refactor (3600+ satır → modüler)

**Önem:** P2 — single-file dev maintenance riski.

### Mevcut durum

- `ChatScreen.kt` 3600+ satır
- Single Composable function 700+ satır, içinde 20+ helper composable inline
- Recomposition pahalı (`@Stable` audit yapılmamış)

### Yapılacaklar

#### Hedef dosya yapısı

```
ui/screen/chat/
├── ChatScreen.kt              (orchestrator, 300-400 LOC)
├── ChatTopBar.kt              (topbar + overflow menü, ~200 LOC)
├── ChatMessageList.kt         (LazyColumn + scroll mantığı, ~400 LOC)
├── ChatInputBar.kt            (input + attachment + send, ~300 LOC)
├── ChatBanners.kt             (export, group-call, typing, search banner'ları, ~200 LOC)
├── ChatDialogs.kt             (disappearing, view-once viewer, delete confirm, ~300 LOC)
└── bubble/
    ├── MessageBubble.kt           (~500 LOC)
    ├── MessageBubbleMenu.kt       (long-press dropdown, ~400 LOC)
    ├── MessageStatusIcon.kt       (~50 LOC)
    ├── SystemMessageBanner.kt     (~150 LOC)
    ├── PollMessageContent.kt      (~200 LOC)
    └── ViewOnceContent.kt         (image + text viewers, ~250 LOC)
```

#### Adım adım

1. **Fiziksel extract** (1-2 gün):
   - Composable'ları yeni dosyalara taşı, davranış değiştirme
   - Import'lar düzelt
   - Build doğrula
2. **Compose stable parameter audit** (1 gün):
   - Her composable parametrelerini `@Stable` veya `@Immutable` yap
   - `data class` yerine `@Stable class` (mutable state varsa)
3. **derivedStateOf ile pahalı hesaplamalar memoize** (1 gün):
   - Format edilmiş timestamp'ler
   - Filter'lanmış mesaj listeleri
4. **Bubble recomposition optimization** (1 gün):
   - `key()` block her mesaja unique key
   - `Modifier.composed` kullanımı azalt
   - Layout inspector ile recomp count ölç
5. **Snapshot testler** (1 gün):
   - Compose UI test framework ile her composable için ekran görüntüsü test

### Etkilenen dosyalar

- `app/.../ui/screen/ChatScreen.kt` → split into 12+ files

### Test

- `./gradlew :app:assembleDevDebug` her adımdan sonra
- Compose UI testleri (Espresso/Compose Test)
- Manuel: chat ekranını aç, tüm aksiyonları test et (reply, edit, react, star, forward, delete, view-once)

### Tahmini süre

5-7 gün

---

## Faz 9 — ChatViewModel.kt refactor (1200+ satır → manager'lar)

**Önem:** P2

### Mevcut durum

- 30+ method, 15+ StateFlow, init bloğunda 8 launch
- Tek class çok fazla sorumluluk

### Hedef yapı

```
ui/viewmodel/chat/
├── ChatViewModel.kt              (orchestrator + delegate manager'lar, ~300 LOC)
├── ChatMessageState.kt           (mesaj listesi + paging + scroll state, ~200 LOC)
├── ChatReceiptManager.kt         (markIncomingMessagesAsRead, ~150 LOC)
├── ChatSearchManager.kt          (in-chat search, ~150 LOC)
├── ChatDisappearingManager.kt    (timer cleanup + flush, ~150 LOC)
├── ChatExportManager.kt          (export + admin log entegrasyonu, ~200 LOC)
└── ChatPresenceManager.kt        (peer presence + typing, ~100 LOC)
```

### Yaklaşım

Her Manager `@AssistedInject` ile `conversationId` alıp `viewModelScope`'a bağlanır. ViewModel sadece UI state'i ve callback dispatch yapar.

### Etkilenen dosyalar

- `app/.../ui/theme/viewmodel/ChatViewModel.kt` → split into 7 files

### Tahmini süre

3-4 gün

---

## Faz 10 — IncomingMessageHandler.kt refactor (2000+ satır → handler registry)

**Önem:** P2

### Mevcut durum

- Tek `when` bloğu 31 SignalMessage tipi handle ediyor
- Her tip için inline handler

### Hedef yapı

```
data/incoming/
├── IncomingMessageHandler.kt          (dispatcher, ~200 LOC)
├── handlers/
│   ├── EncryptedMessageHandler.kt     (direct + grup envelope parsing, ~400 LOC)
│   ├── FileTransferHandler.kt         (chunk birleştirme + DB save, ~300 LOC)
│   ├── CallSignalHandler.kt           (SDP/ICE/CallControl + ringtone + telecom, ~400 LOC)
│   ├── GroupNotificationHandler.kt    (CREATE/ADD/REMOVE/LEAVE/UPDATE_ADMIN/EXPORT, ~300 LOC)
│   ├── ReceiptHandler.kt              (DeliveryReceipt status promotion, ~80 LOC)
│   ├── ReactionHandler.kt             (~80 LOC)
│   ├── TypingPresenceHandler.kt       (~120 LOC)
│   ├── DisappearingTimerHandler.kt    (~80 LOC)
│   └── AdminEncryptedLogHandler.kt    (~100 LOC)
└── parser/
    └── MessageEnvelopeParser.kt       (MSGID/REPLY/EXP/VIEWONCE/POLL prefix'leri, ~150 LOC)
```

### Yaklaşım

```kotlin
interface SignalHandler<T : SignalMessage> {
    suspend fun handle(signal: T)
}

@Singleton
class IncomingMessageHandler @Inject constructor(
    private val handlers: Map<Class<out SignalMessage>, @JvmSuppressWildcards SignalHandler<*>>
) {
    fun handle(signal: SignalMessage) {
        @Suppress("UNCHECKED_CAST")
        (handlers[signal::class.java] as? SignalHandler<SignalMessage>)?.handle(signal)
    }
}
```

Hilt @IntoMap @MapKey ile registry.

### Etkilenen dosyalar

- `app/.../data/IncomingMessageHandler.kt` → 10+ handler dosyası
- Hilt module: `MessageHandlerModule.kt`

### Tahmini süre

3-4 gün

---

## Faz 11 — bot-api Shadow plugin alternatifi

**Önem:** P2 — offline build'lerde 8 MB BOM zinciri sorun çıkarıyor.

### Mevcut sorun

- Shadow plugin transitif deps'i (jackson-bom, junit-bom, spring-bom, jakartaee-bom, log4j-bom, ant-parent vs.) offline cache'te yoksa configuration fail
- `-PandroidOnly` flag'i ile bypass edildi ama bot-api build için tam çözüm değil

### Yapılacaklar

**Seçenek A — Native application plugin (önerilen)**:
1. Shadow plugin'i kaldır
2. Gradle 8.5+'ta native `application` plugin + `distTar`/`distZip`
3. Docker'da multi-layer JAR:
   ```dockerfile
   FROM eclipse-temurin:17-jre AS builder
   COPY build/distributions/bot-api.tar /tmp/
   RUN tar -xf /tmp/bot-api.tar -C /opt/
   
   FROM eclipse-temurin:17-jre
   COPY --from=builder /opt/bot-api/lib/*.jar /app/lib/
   COPY --from=builder /opt/bot-api/bin/bot-api /app/bin/
   ENTRYPOINT ["/app/bin/bot-api"]
   ```
4. Build hızlanır, image size düşer (layered caching)

**Seçenek B — Offline-friendly mirror script**:
1. `./scripts/sync-offline-deps.sh` — `~/.gradle/caches`'tan `local-repo`'ya tam mirror
2. Online makinede USB transferi öncesi çalıştırılır
3. Tüm transitif deps garantili

**Seçenek C — bot-api'yi ayrı submodule/repo**:
1. bot-api'yi ayrı bir repo'ya taşı
2. Ana proje build'iyle gevşek bağ
3. Android APK developer'ı bot-api'yi clone etmeye mecbur değil

### Etkilenen dosyalar

- `bot-api/build.gradle.kts` (Shadow kaldır)
- `infra/Dockerfile.bot-api` (multi-stage)
- `settings.gradle.kts` (bot-api include şartı değişir)
- Yeni: `scripts/sync-offline-deps.sh`

### Tahmini süre

1-2 gün (Seçenek A)

---

# KATEGORİ D — UI / UX

## Faz 12 — Disappearing media düzelt + UX cilası

**Önem:** P2 — medya için süreli mesaj davranışı belirsiz.

### Mevcut sorun

- `FileTransfer.absoluteExpiresAt` zaten var, grup file branch'inde set ediliyor (audit et)
- Cleanup worker'ın FILE/IMAGE tipinde fiziksel dosyayı da silip silmediği belirsiz
- Süreli mesaj timer DB row silindikten sonra dosya cihazda kalıyor mu?

### Yapılacaklar

1. **Audit**: `IncomingMessageHandler.handleFileTransfer` her dalında `absoluteExpiresAt` doğru set ediliyor mu kontrol et (file:line ile rapor)
2. **CleanupWorker düzelt**:
   - `MessageRepository.deleteExpiredMessages` çağrılırken FILE/IMAGE/VOICE_NOTE mesajları için önce fiziksel dosyayı sil, sonra DB row'u sil
   - `FileSystemCleaner.deleteFile(path)` helper (var değilse oluştur)
   - Error handling: dosya yoksa sessizce devam (idempotent)
3. **View-once medya zaten doğru** (`markViewOnceAsViewed` + `consumeViewOnceText`) ama medya için fiziksel dosya silinmesi kontrol et
4. **Test**:
   - Unit: süreli mesaj + dosya, expire sonrası dosya yok
   - Manuel: 10 sn timer ile foto gönder, sayaç bitince dosya gerçekten silindi mi (file explorer'da check)

### Etkilenen dosyalar

- `app/.../data/IncomingMessageHandler.kt:296-462` (file transfer dalı)
- `storage/.../repository/MessageRepositoryImpl.kt:deleteExpiredMessages`
- Yeni veya mevcut: `media/.../FileSystemCleaner.kt`

### Tahmini süre

1-2 gün

---

## Faz 13 — Splash / onboarding cilası

**Önem:** P3 (cilalama)

### Mevcut durum

- SplashScreen var ama minimal (logo + loading)
- Onboarding yok — kullanıcı uygulamayı açar açmaz phone verification ekranı

### Yapılacaklar

1. **Animated splash**:
   - Logo entry animation (fade + scale)
   - Background azure gradient subtle animation
   - 1.5sn min süre (UX feel)
2. **Onboarding flow** (ilk açılışta):
   - 3 sayfalık intro:
     - Sayfa 1: "🔒 Uçtan uca şifreli" — Signal Protocol kullanıyoruz vurgusu
     - Sayfa 2: "📞 P2P sesli/görüntülü arama" — WebRTC vurgusu
     - Sayfa 3: "🛡️ Gizlilik kontrolü" — view-once, disappearing, export kontrolü
   - "Atla" butonu (sağ üst)
   - "Devam" butonu (alt)
3. **Permission walkthrough** (onboarding sonrası):
   - Notif, Contacts, Mic, Cam permission'larını sırayla iste
   - Her permission için açıklama kart: "Neden gerekli"
   - Reddedilirse "Ayarlardan açabilirsiniz" snackbar
4. **First-launch flag**: SharedPreferences `onboarding_completed: Boolean`
5. **Settings'te "Tekrar göster"**: Geliştirme amaçlı, kullanıcı onboarding'i tekrar görmek isterse

### Etkilenen dosyalar

- `app/.../ui/screen/SplashScreen.kt` (genişlet)
- Yeni: `app/.../ui/screen/OnboardingScreen.kt`
- Yeni: `app/.../ui/screen/PermissionWalkthroughScreen.kt`
- `app/.../navigation/SecureChatNavHost.kt` (yeni route'lar)
- `res/drawable/` (intro illüstrasyonları)

### Tahmini süre

3-4 gün (illüstrasyon hazırlık dahil)

---

## Faz 14 — Generic snackbar yerine somut hata mesajları

**Önem:** P2 — UX iyileştirme + debugging kolaylığı.

### Mevcut sorun

- Birçok yerde generic "Hata oluştu, tekrar deneyin" snackbar'lar
- Kullanıcı ne yapması gerektiğini bilmiyor
- Crash/log'da context yok

### Yapılacaklar

1. **`sealed class ChatError`** (yeni): `app/.../domain/error/ChatError.kt`
   ```kotlin
   sealed class ChatError(val userMessage: String, val cause: Throwable? = null) {
       object NetworkUnavailable : ChatError("İnternet bağlantısı yok")
       object NotAuthorized : ChatError("Bu işlem için yetkiniz yok")
       object NotGroupMember : ChatError("Grup üyesi değilsiniz")
       data class FileTooLarge(val maxMb: Int) : ChatError("Dosya çok büyük (maks $maxMb MB)")
       data class RecipientBlocked(val name: String) : ChatError("$name sizi engellemiş")
       data class ServerError(val code: Int) : ChatError("Sunucu hatası ($code)")
       data class Unknown(val ex: Throwable) : ChatError("Beklenmedik hata", ex)
   }
   ```
2. **UseCase'ler `Result<T, ChatError>` döndürsün**:
   ```kotlin
   suspend operator fun invoke(...): Result<Unit, ChatError>
   ```
3. **ViewModel snackbar dispatcher**:
   ```kotlin
   private val _snackbar = MutableSharedFlow<String>()
   val snackbar: SharedFlow<String> = _snackbar.asSharedFlow()
   
   private suspend fun emitError(error: ChatError) {
       _snackbar.emit(error.userMessage)
       error.cause?.let { android.util.Log.e("ChatVM", error.userMessage, it) }
   }
   ```
4. **Tüm `catch (e: Exception) { _error.value = "..." }` pattern'lerini tara, ChatError dispatch'e çevir**

### Etkilenen dosyalar

- Yeni: `app/.../domain/error/ChatError.kt`
- Tüm UseCase'ler (~9 dosya)
- Tüm ViewModel'ler (~13 dosya) — error handling refactor

### Tahmini süre

3-4 gün

---

## Faz 15 — Tablet/foldable UI + A11y audit

**Önem:** P3 (cilalama, kullanıcı tablet kullanmıyorsa düşük öncelik)

### Mevcut durum

- Sadece telefon UI'sı düşünülmüş
- WindowSizeClass entegrasyonu yok
- A11y/TalkBack auditi yapılmamış

### Yapılacaklar

#### Adım 1 — WindowSizeClass entegrasyonu (2 gün)

1. `androidx.compose.material3:material3-window-size-class` dependency
2. `LocalWindowSizeClass.current` ile her ana ekranda layout dallandır
3. Layout dağılımı:
   - **Compact** (telefon): mevcut (tek pane)
   - **Medium** (foldable yarı açık, küçük tablet): mevcut + daha geniş padding
   - **Expanded** (tablet 10"+): **2-pane layout** — sol conversations listesi + sağ chat (WhatsApp tablet UX'i)
4. Foldable hinge support: input bar alt yarıya, mesaj listesi üst yarıya (PostureType.HALF_OPENED)

#### Adım 2 — A11y audit (1-2 gün)

1. `auditing-accessibility` skill'i çağır → tüm ekranları otomatik tara
2. Rapor topla:
   - Eksik content description'lar
   - Min touch target 48dp altında elementler
   - Contrast issue'ları (WCAG AA)
   - Reading order yanlış olan composable'lar
3. Toplu fix:
   - Tüm IconButton'lara `contentDescription` ekle
   - Min touch target 48dp garanti (`Modifier.size(48.dp)` veya semantics ile)
   - TalkBack için MessageBubble reading order: sender → timestamp → content → status
4. Manuel TalkBack test: 30 dakikalık senaryo (login, chat aç, mesaj at, profil aç)

#### Adım 3 — Settings ekranında erişilebilirlik bölümü

- Yazı boyutu ayarı (system override)
- Yüksek kontrast tema
- Animations toggle (reduced motion)

### Etkilenen dosyalar

- Tüm ana ekranlar (~20 dosya layout refactor)
- `app/build.gradle.kts` (material3-window-size-class)
- Yeni: `app/.../ui/theme/ResponsiveLayout.kt` (window class helper)

### Tahmini süre

4-5 gün

---

# UYGULAMA SIRASI ÖNERİSİ

## Sprint 1 (1 hafta) — KRİTİK GÜVENLİK
- Faz 1: WS auth JWT
- Faz 2: PreKeyBundleFetcher port (eğer 1:1 E2EE çalışması bitmediyse standalone)
- Faz 3: Memory zeroize

## Sprint 2 (1 hafta) — RELIABILITY TEMELİ
- Faz 5: Test compile fix + JaCoCo + crypto coverage
- Faz 6: Postmortem disiplini setup
- Faz 7: Release versioning policy

## Sprint 3 (1 hafta) — TELECOM + KOD KALİTESİ
- Faz 4: Call/telecom soak test + Crashlytics
- Faz 8: ChatScreen refactor

## Sprint 4 (1 hafta) — KOD KALİTESİ TAMAMLAMA
- Faz 9: ChatViewModel refactor
- Faz 10: IncomingMessageHandler refactor
- Faz 11: bot-api Shadow alternatifi

## Sprint 5 (1 hafta) — UX CİLASI
- Faz 12: Disappearing media fix
- Faz 14: Generic snackbar → ChatError
- Faz 13: Splash/onboarding

## Sprint 6 (1 hafta) — KAPANIŞ
- Faz 15: Tablet/foldable + A11y
- Test coverage geri kalan modülleri tamamla
- Full regression pass

**Toplam tahmini süre: 6 hafta solo full-time**

Paralel olarak: **Grup E2EE + 1:1 E2EE** ayrı bir sprint olarak (2-3 hafta).

Genel toplam: **8-9 hafta** ile production-ready, "9 / 10" puanlı bir ürün.

---

# ÖNEMLİ NOTLAR

## Genel kurallar (her faz için)

1. Her fazdan önce **TaskCreate** ile alt-task'lar oluştur
2. Her commit conventional commit formatında, Türkçe açıklama
3. Her faz sonunda **build doğrula**: `./gradlew :app:assembleDevDebug`
4. Build kırıksa faz tamamlanmış sayılmaz
5. Memory leak / context leak / regression check her faz sonunda
6. `git push origin main` her faz sonunda

## Önemli "gotcha"lar

- **JDK 17 toolchain**: signaling-server'a dokunursan JDK 17 zorunlu (build.gradle.kts'te ayar)
- **Hilt KSP cache**: refactor sırasında `./gradlew --stop && ./gradlew clean build` deneyebilirsin
- **Room schema**: her DB değişikliğinde `storage/schemas/` altında JSON export oluşur, commit et
- **APK install downgrade**: yeni APK yüklerken `adb uninstall com.securechat.app.debug` sonra install (signing değiştiyse)
- **VERSION dosyası**: offline build için `scripts/refresh-version.sh` çalıştırmadan USB transferi yapma

## Bu döküman dışındaki çalışma

- **Grup E2EE + 1:1 E2EE**: ayrı session/prompt'ta yürütülüyor — bu döküman onu kapsamaz
- **Yeni feature istekleri**: bu döküman tamamlanmadan yeni feature ekleme, teknik borç birikir
