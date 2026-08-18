# SecureChat Flutter

Bu dizin, mevcut Kotlin/Android kaynaklarina dokunmadan uretilen ortak
Flutter Android+iOS hedefidir. Uygulama ozellikleri, veri/wire kararlari ve hata
davranislari 271 Kotlin/Java kaynagin tamamiyla dosya seviyesinde eslenir.

## Gizlilik siniri

- Peer mesajlari Signal V3 ile E2EE'dir; encrypt/session/prekey hatasinda mesaj
  `FAILED` olur ve plaintext fallback yapilmaz.
- Grup adi/kimligi ve kontrol metadata'si recipient-specific direct Signal
  zarfinin icindedir; hardened server kalici grup grafigi tutmaz.
- Mesaj gecmisi, rehber eslesmesi, medya ve davranis analitigi sunucuda kalici
  tutulmaz. Kisa offline teslim yalniz ciphertext olarak, persistence-kapali
  Redis RAM'de AEAD + opaque key + sert TTL ile kalir.
- Cihaz verisi Keystore/Keychain anahtariyla authenticated encrypted storage'da
  kalir. Client bundle'ina server secret veya signing private key konmaz.
- Production server hedefi yalniz `server_hardened` dizinidir; kok Kotlin server
  davranis referansidir ve privacy release artefakti degildir.

Ayrintili ve baglayici sozlesme:
[`docs/SERVER_DATA_PRIVACY_AUDIT.md`](docs/SERVER_DATA_PRIVACY_AUDIT.md).

## Yerel dogrulama

```bash
flutter pub get --offline
flutter analyze --no-pub
flutter test --no-pub
dart tool/smoke_test.dart
dart tool/audit_ios_readiness.dart
```

Android offline release ve hardened AAB:

```bash
(cd android && ./gradlew assembleRelease --offline --no-daemon)
SECURECHAT_OFFLINE=1 tool/build_hardened_android_release.sh
```

Hardened server:

```bash
(cd server_hardened && \
  ./gradlew :signaling-server:test :bot-api:test --offline --no-daemon)
```

Guncel kanit 194/194 Flutter, 64/64 hardened server, temiz analyze/iOS statik
audit, 663-gorevli offline Android release ve stripped/server-secret-audited
AAB'dir. Imza, production endpoint ve private pin rotasyon girdileri build
ortamindan saglanir.

## Mimari

- `lib/src/features`: route ve presentation katmani
- `lib/src/domain`, `lib/src/chat`, `lib/src/groups`: use-case/domain davranisi
- `lib/src/services`: composition ve uygulama servis sozlesmeleri
- `lib/src/crypto`, `lib/src/storage`, `lib/src/network`, `lib/src/media`:
  altyapi implementasyonlari
- `lib/src/platform`, `android`, `ios`: typed native sinirlar
- `server_hardened`: veri-minimize signaling ve bot production hedefi

Production server yalniz
`server_hardened/deploy/deploy_privacy_stack.sh --check-only` gizlilik
preflight'i gectikten sonra deploy edilir. Root `infra/` hedefi production icin
kullanilmaz.

Ana ilerleme kaynagi
[`docs/MIGRATION_TRACKER.md`](docs/MIGRATION_TRACKER.md), calisma kurallari
[`docs/AUTONOMOUS_MIGRATION_PLAYBOOK.md`](docs/AUTONOMOUS_MIGRATION_PLAYBOOK.md),
degisiklik gerekceleri ise
[`docs/MIGRATION_NOTES.md`](docs/MIGRATION_NOTES.md) icindedir.

## Harici kapanis kapilari

iOS fiziksel build/signing, PushKit entitlement+server `.voip` sender,
production HSM tatbikati, ilk telefon sahipligi politikasi ve hardened server
registry/gercek altyapi tatbikati dis hesap/donanima baglidir. Mevcut
`build/offline_bundle` final degildir; eski Gradle cache ara
ciktisi kaldirilmistir. Mac/iOS supplement'i hazirlandiginda Android ve iOS
cache'leri tek final checksum manifestiyle yeniden uretilmelidir.
