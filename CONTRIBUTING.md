# Katkıda Bulunma — SecureChat

## Hızlı başlangıç

```bash
git clone <repo>
cd securechat
./gradlew :app:assembleDevDebug
```

APK: `app/build/outputs/apk/dev/debug/app-dev-debug.apk`

## Geliştirme prensipleri

### 1. Güvenlik öncelikli

- **Plaintext mesaj içeriği ASLA loglanmaz.** `Log.d`/`Log.w` çağrılarında ham mesaj içeriği geçirme.
- **Private key'ler yalnızca Android Keystore'da saklanır.** SharedPreferences/file system'e key kaydetme.
- **SQLCipher passphrase deterministik** (`KeyStoreManager.getOrCreateDbPassphrase`). Değiştirme; aksi takdirde kullanıcıların DB'leri açılmaz.
- **FLAG_SECURE varsayılan açık** (SecureChatActivity). Yeni Activity ekleyeceksen bu flag'i ayarlamayı unutma.
- **Sensitive byte array'ler kullanım sonrası `fill(0)`** (passphrase, plaintext mesajlar).
- **Yeni bağımlılık eklerken** transitif dep zinciri audit et — supply chain riski.

### 2. Kod stili

- Kotlin coding conventions (Android Studio default formatter)
- Sınıf/fonksiyon/değişken isimleri **İngilizce**
- Yorum ve dokümantasyon **Türkçe** (içerik bağlamı ile tutarlı)
- UI metinleri **Türkçe** (`strings.xml`)
- KDoc her public API için (özellikle UseCase, Repository, ViewModel)

### 3. Conventional commits (Türkçe)

```
feat(scope): yeni ozellik tanitma
fix(scope): bug duzeltmesi
refactor(scope): davranis degismez yeniden duzenleme
docs(scope): sadece dokuman
test(scope): test ekleme/duzeltme
build: build config / dependency
chore: kod disi tutorial isleri
```

Örnekler:
- `feat(view-once): tek gosterimlik metin destegi`
- `fix(receipt): READ marking 800ms gecikme — DELIVERED tiki gozlenebilsin`
- `build(signaling-server): JDK 17 toolchain`

### 4. PR gates (zorunlu)

Her PR aşağıdaki kontrollerden geçmek zorundadır:

- [ ] **Build geçer**: `./gradlew :app:assembleDevDebug`
- [ ] **Yeni `.kt` dosyalar için test eklenmiş** (Hilt module / DAO / Entity hariç)
- [ ] **Yeni davranış için unit test** (UseCase/ViewModel/Repository)
- [ ] **Bug fix için regression test** — fix uygulanmadan önce fail, sonra yeşil
- [ ] **`docs/release-checklist.md` etkilenen kısımları manuel test edildi**
- [ ] **Conventional commit message + Türkçe açıklama**
- [ ] **Sensitive bilgi (key, token, hash) commit'lenmedi** — `.gitignore` audit

### 5. Mimari kurallar

- **Clean Architecture**: UI → ViewModel → UseCase → Repository → DataSource
- **Multi-module**: bağımlılık yönü her zaman aşağı doğru (app → crypto/network/storage/media/contacts → common)
- **Hilt DI**: yeni provider'lar @Module + @InstallIn(SingletonComponent::class) ile
- **Compose**: state hoisting, `@Stable`/`@Immutable` parametreler, `derivedStateOf` ile memoize
- **Coroutines**: `viewModelScope` UI işleri için, `applicationScope` background için

### 6. Test pratikleri

- **Unit test**: pure Kotlin, hiç Android dep yok (Hilt mock'la)
- **Integration test**: Room in-memory + Hilt test runner
- **UI test**: Compose UI test framework (Espresso yok)
- **Coverage hedefleri**: crypto %95, network %80, storage %80, domain %90, ui %50

### 7. Feature flag pattern

Yeni özellikler `BuildConfig.FEATURE_X_ENABLED` ile default-off merge edilsin. Dogfood'da test edip aç.

```kotlin
android {
    buildTypes {
        debug {
            buildConfigField("boolean", "FEATURE_GROUP_E2EE", "true")
        }
        release {
            buildConfigField("boolean", "FEATURE_GROUP_E2EE", "false")
        }
    }
}
```

### 8. Bug bulundu mu? Önce kontrol et

1. **`docs/incidents/` altında benzer postmortem var mı?**
2. **Memory'de kayıt var mı?** (`~/.claude/projects/.../memory/`)
3. **Git log'da yakın zaman fix var mı?** (`git log --oneline | grep -i "<keyword>"`)
4. Yoksa yeni postmortem aç: `cp docs/incidents/TEMPLATE.md docs/incidents/YYYY-MM-DD-<konu>.md`

### 9. Release süreci

`docs/release-checklist.md`'de tam liste. Özet:
1. VERSION refresh
2. Build + test geçti
3. Smoke test 30dk
4. Server health check
5. Tag + APK signed
6. Deploy
7. 24 saat sonra crashlytics check

### 10. Server-side değişiklik?

`signaling-server/` veya `infra/` dokunduysan:
1. **JDK 17 toolchain** zorunlu (lokal JDK 21 ile derlersen `UnsupportedClassVersionError` alır)
2. `./gradlew -PincludeServer :signaling-server:fatJar`
3. Deploy procedure: `~/.claude/projects/.../memory/reference_server_deploy.md`
4. Backend container restart sonrası 10sn sağlık check

## Faydalı komutlar

```bash
# Sadece app modülü hızlı build (offline-friendly)
./gradlew :app:assembleDevDebug

# Tüm modüller dahil full build (server build için)
./gradlew -PincludeServer build

# APK version doğrula
$ANDROID_HOME/build-tools/35.0.0/aapt2 dump badging \
  app/build/outputs/apk/dev/debug/app-dev-debug.apk | head -1

# JaCoCo coverage rapor (kuruldu ise)
./gradlew jacocoTestReport
open build/reports/jacoco/index.html

# Hızlı server log inspection
ssh root@94.73.180.226 'docker logs --tail 50 securechat-backend'
```

## Soru / takıldın

- `docs/IMPROVEMENT_ROADMAP.md` — büyük resim + öncelikler
- `CLAUDE.md` — proje kuralları
- `docs/incidents/` — önceki postmortem'ler
