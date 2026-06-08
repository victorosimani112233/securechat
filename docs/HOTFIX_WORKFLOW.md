# Hotfix Workflow — SecureChat

> Production'da critical bug çıkınca uygulanacak hızlı düzeltme prosedürü.

## Kullanım koşulları

Bu workflow **sadece şu durumlarda** kullanılır:

- **P0 güvenlik açığı** (data leak, auth bypass, key compromise)
- **P0 broken core feature** (mesaj iletilmiyor, çağrı açılmıyor, app crash on startup)
- **P0 data loss bug** (DB corruption, mesaj/yedek silme)

P1-P3 sorunlar **normal release döngüsünde** çözülür (`docs/release-checklist.md`).

## Workflow

### 1. Triaj (15 dakika max)

- [ ] Bug doğrulandı (reproduce edildi)
- [ ] Severity P0 onayı (data/security/core feature)
- [ ] Etkilenen kullanıcı kapsamı (% kullanıcı, hangi cihazlar)
- [ ] **Geçici workaround mümkün mü?** (örn. server queue purge, manuel APK rollback) — varsa önce onu uygula

### 2. Hotfix branch (5 dakika)

```bash
# En son prod release tag'ini bul
PROD_TAG=$(git tag --list 'v*' | sort -V | tail -1)
echo "Prod tag: $PROD_TAG"

# Hotfix branch oluştur (tag'ten DAL, main'den DEĞİL — main'de yarım WIP olabilir)
git checkout -b "hotfix/${PROD_TAG}-fix1" "$PROD_TAG"
```

### 3. Fix uygula (1-4 saat)

- [ ] **Minimal değişiklik** — sadece bug fix, başka temizlik yok
- [ ] Regression test ekle (fix uygulanmadan önce fail, sonra yeşil)
- [ ] Manuel smoke test (etkilenen feature + 2-3 yakın feature)
- [ ] Conventional commit: `fix(<scope>): <ozet> [HOTFIX]`

### 4. Build + deploy (30 dakika)

```bash
# VERSION refresh (commit count artar)
./scripts/refresh-version.sh
git add VERSION && git commit -m "build: VERSION refresh (hotfix)"

# Build
./gradlew :app:assembleProdRelease

# APK doğrula
$ANDROID_HOME/build-tools/35.0.0/aapt2 dump badging \
  app/build/outputs/apk/prod/release/app-prod-release.apk | head -1

# Server-side hotfix gerekiyorsa
./gradlew -PincludeServer :signaling-server:fatJar
scp signaling-server/build/libs/signaling-server-all.jar root@94.73.180.226:/opt/securechat/signaling-server/build/libs/
ssh root@94.73.180.226 'cd /opt/securechat/infra && docker compose build backend && docker compose up -d --force-recreate backend'
```

### 5. Tag + dağıtım

```bash
# Hotfix tag oluştur
HOTFIX_TAG="${PROD_TAG}-fix1"
git tag -a "$HOTFIX_TAG" -m "Hotfix: <kısa açıklama>"
git push origin "$HOTFIX_TAG"

# CHANGELOG güncelle
./scripts/generate-changelog.sh "$PROD_TAG" "$HOTFIX_TAG"
git add CHANGELOG.md && git commit -m "docs: changelog $HOTFIX_TAG"
```

### 6. Cherry-pick to main (10 dakika)

```bash
# Hotfix branch'i main'e merge etmek YERINE cherry-pick yap
# (main'de aktif WIP varsa karışmasın)
git checkout main
git pull origin main
git cherry-pick <hotfix-commit-hash>
# Conflict çıkarsa çöz, sonra:
git push origin main
```

### 7. Postmortem (24 saat içinde)

```bash
cp docs/incidents/TEMPLATE.md "docs/incidents/$(date +%Y-%m-%d)-<konu>.md"
# Edit + commit
```

### 8. Monitoring (24 saat)

- [ ] Crashlytics dashboard — yeni crash gelmiyor
- [ ] Backend log — error pattern azaldı
- [ ] Kullanıcı bildirimleri — fix doğrulandı

## Hotfix sonrası

- [ ] Hotfix branch silinebilir: `git branch -D hotfix/...`
- [ ] Etkilenen kullanıcılara bilgi (varsa kanal)
- [ ] `IMPROVEMENT_ROADMAP.md`'ye preventive task ekle (aynı sınıf bug bir daha olmasın)
