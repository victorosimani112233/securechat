# Release Checklist — SecureChat

> Her production release öncesi bu checklist'i geç. **Atlama**.
> Estimated time: 30-45 dakika tam pass.

## 0. Pre-flight (kod hazırlığı)

- [ ] `main` branch en güncel: `git pull origin main`
- [ ] Çalışan WIP yok: `git status` temiz
- [ ] Son commit'leri review: `git log --oneline -20`
- [ ] **VERSION dosyası güncel** (online makinede): `./scripts/refresh-version.sh && git add VERSION && git commit -m "build: VERSION refresh"`
- [ ] **CHANGELOG.md güncel**: `./scripts/generate-changelog.sh` (bkz. Faz 7)

## 1. Build doğrulama

- [ ] `./gradlew clean` (önceki cache temizle)
- [ ] `./gradlew :app:assembleDevDebug` — geçti
- [ ] `./gradlew :app:assembleProdRelease` — geçti (eğer release çıkıyorsa)
- [ ] APK boyutu beklenen aralıkta (~85-95 MB). Aniden büyüdüyse `./gradlew :app:bundleProdRelease` ile bundle deneyerek nedeni araştır.
- [ ] APK versionName Settings → Hakkında'da doğru görünüyor

## 2. Test pass

- [ ] `./gradlew :app:testDevDebugUnitTest` — yeşil
- [ ] `./gradlew :crypto:test :storage:test :network:test :media:test` — yeşil (geçtikçe ekle)
- [ ] **JaCoCo coverage** %70+ (`build/reports/jacoco/`)
- [ ] Mevcut bilinen test fail'leri (eğer var) `docs/known-failures.md`'de açıklanmış

## 3. Manuel smoke test (30 dakika, gerçek cihaz)

### Auth + onboarding
- [ ] Yeni cihazda uninstall + install
- [ ] Splash → onboarding → permission walkthrough akıyor
- [ ] Telefon doğrulama OTP geliyor + giriş başarılı

### Sohbet — 1:1
- [ ] İki cihaz arasında karşılıklı mesaj at — gri çift tik → mavi çift tik geçişi belirgin
- [ ] Foto + caption gönder, alıcıda görünüyor
- [ ] Voice note gönder, kayıt + play çalışıyor
- [ ] Anket oluştur, oy ver
- [ ] Mesaj reply et
- [ ] Mesaj edit et (15dk içinde)
- [ ] Mesaj sil (herkesten sil)
- [ ] React ekle/kaldır
- [ ] View-once foto + view-once metin: bir kez görünüyor sonra "Açıldı"
- [ ] Süreli mesaj 30sn timer kur, mesaj at → her iki tarafta da 30sn'de gidiyor

### Sohbet — grup
- [ ] Grup oluştur (3+ üye)
- [ ] Grup mesajı tüm üyelerde görünüyor
- [ ] Admin atama / çıkarma
- [ ] Üye ekle / çıkar
- [ ] Grup adı değiştir
- [ ] "Sohbet dışa aktarma" toggle (admin), kapalıyken kopya menüsü gizli
- [ ] Export al, admin geçmişinde görünüyor

### Arama
- [ ] 1:1 sesli arama (mesh) — 30sn konuş
- [ ] 1:1 görüntülü arama — 30sn
- [ ] Grup arama 3 kişi (mesh)
- [ ] Grup arama 4+ kişi (SFU geçişi) — son katılımcı sessiz değil
- [ ] Bluetooth headset bağla/ayır, ses route doğru
- [ ] Aktif çağrı sırasında Wi-Fi → Mobile geçişi, çağrı kopmuyor

### Bildirimler
- [ ] App arka planda iken mesaj geldi → bildirim göründü
- [ ] App kapalı iken mesaj geldi → FCM bildirim göründü
- [ ] Bildirime tıklayınca doğru sohbet açıldı
- [ ] Mute edilmiş grupta bildirim gelmiyor

### Edge cases
- [ ] Cihazı kapatıp aç, mesajlar drain oluyor (`docker logs securechat-backend | grep "offline mesaj iletildi"`)
- [ ] Ağ kopuk iken mesaj at — outbox'a düştü, ağ gelince gitti
- [ ] Yedek al → import → mesajlar geri geldi

## 4. Server-side kontroller

- [ ] `ssh root@94.73.180.226 'docker ps'` — tüm container'lar healthy
- [ ] `docker logs --tail 50 securechat-backend` — Critical/Error log yok
- [ ] Redis offline queue boyut normal: ZCARD sayıları abartısız
- [ ] PostgreSQL disk kullanımı tedirgin değil: `docker exec securechat-postgres df -h`
- [ ] Prometheus/Grafana dashboard'da anomali yok

## 5. Güvenlik kontrolleri

- [ ] APK signing config doğru (release keystore kullanılıyor)
- [ ] BuildConfig.DEBUG = false (release build için)
- [ ] FLAG_SECURE aktif (ekran görüntüsü engelli) — test cihazda screenshot çek, "uygulama engelliyor" çıkmalı
- [ ] Certificate pinning aktif (debug build hariç)
- [ ] Yeni bağımlılık eklendiyse: `./gradlew :app:dependencyInsight --dependency <yeni-lib>` ile transitif zinciri kontrol et, suspicious bir şey yok

## 6. Release artefact'leri

- [ ] APK signed: `app/build/outputs/apk/prod/release/app-prod-release.apk`
- [ ] Bundle (Play Store): `app/build/outputs/bundle/prodRelease/app-prod-release.aab`
- [ ] APK hash kaydet: `sha256sum app-prod-release.apk` → CHANGELOG.md'de
- [ ] Release notes hazır (CHANGELOG.md güncel)
- [ ] Git tag oluştur: `git tag -a v1.0.X -m "release notes özet" && git push origin v1.0.X`

## 7. Deploy

- [ ] (Manuel dağıtım) APK'yı kullanıcılara ulaştırma kanalı hazır
- [ ] (Play Store) Internal track'e upload
- [ ] (Play Store) 24 saat sonra production'a promote (canary period)

## 8. Post-release (24 saat içinde)

- [ ] Crashlytics dashboard kontrolü (crash rate < %0.5)
- [ ] Backend log inspection (yeni hata pattern'i yok)
- [ ] Kullanıcı geri bildirimleri toplam (varsa)
- [ ] Memory entry: `project_YYYY_MM_DD_release.md` ile release özeti

---

## Hızlı rollback procedure (release sonrası critical bug)

1. **Backend rollback** (gerekirse):
   ```bash
   ssh root@94.73.180.226 'cd /opt/securechat/signaling-server/build/libs && \
     cp signaling-server-all.jar.bak_<TIMESTAMP> signaling-server-all.jar && \
     cd /opt/securechat/infra && docker compose build backend && \
     docker compose up -d --force-recreate backend'
   ```
2. **APK rollback** (manuel dağıtım): bir önceki tag'in APK'sını dağıt
3. **Play Store rollback**: Halt rollout → previous version promote
4. **Hot-fix branch**: `git checkout -b hotfix/v1.0.X-1 v1.0.X-1`
5. Postmortem aç: `docs/incidents/YYYY-MM-DD-<konu>.md`
