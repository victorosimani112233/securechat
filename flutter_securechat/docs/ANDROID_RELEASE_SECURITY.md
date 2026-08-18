# Android Play Release Security

## Gercekci tehdit modeli

Play Store'a yuklenen AAB cihazda APK'lara donusur. Saldirgan endpointleri,
route adlarini, JSON alanlarini ve public certificate pinlerini statik analiz
veya calisan prosese instrumentation uygulayarak ogrenebilir. Obfuscation bunu
pahali hale getirir; bilgi-guvenlik siniri veya server secret kasasi degildir.

Bu nedenle:

- Client icine JWT signing secret, Redis/Postgres parolasi, Janus admin secret,
  Apple/Google service-account private key veya genel kullanima acik olmayan bir
  API master key gomulmez.
- Her HTTP/WS istegi Ktor tarafinda JWT imzasi, `typ`, expiry, revocation ve
  token `sub` degeriyle dogrulanir. Body/query icindeki `userId` yetki kaynagi
  kabul edilmez.
- Mesaj icerigi Signal Protocol ile uctan uca sifrelidir. TLS/SPKI pinleme ag
  katmanini korur; ikisi farkli tehditleri kapatir.
- Rate limit ve frame/byte limitleri istemciye degil Redis/Ktor'a uygulanir.
  Taklit bir istemci bu kontrolleri atlayamaz.

## Uygulanan release sertlestirmesi

- Android release'te R8 minification ve resource shrinking aciktir.
- Flutter AOT isim obfuscation'i `tool/build_hardened_android_release.sh`
  tarafindan `--obfuscate --split-debug-info` ile zorunlu tutulur.
- Split Dart symbol ve R8 mapping dosyalarinin release sahibine ait kopyasi
  `build/private_symbols/android` altina yazilir ve checksum'lanir. Android App
  Bundle formati ayrica Play'in crash/symbol isleme hatti icin R8 map ile
  native `.sym` dosyalarini `BUNDLE-METADATA` altinda tasir. Bu metadata Play'in
  cihazlara uretecegi split APK'lara konmaz; buna karsilik AAB'nin kendisi
  de-obfuscation materyali tasidigi icin public binary gibi dagitilamaz ve
  private release artefakti olarak korunur.
- Manifest uygulama backup/device-transfer'i ve cleartext HTTP/WS'yi kapatir.
- Network security config yalniz sistem trust store'una izin verir. Uygulama
  katmanindaki birincil+yedek SPKI pin kontrolu ayrica devam eder.
- Release `AppConfig` HTTP veya WS endpoint ile baslatilamaz; HTTPS/WSS
  fail-fast zorunludur.
- Hassas ekranlarda Android `FLAG_SECURE`, local master key icin Android
  Keystore ve kalici veride authenticated encryption kullanilir.
- Build sonunda `tool/audit_android_release.sh`, cihaz payload'indaki native
  kutuphanelerde debug/symbol section kalmadigini, R8/NOTICE kanitlarini ve
  keystore/server-private-key sizintisi olmadigini fail-closed denetler.

## Imzali AAB uretimi

Play upload key ayari air-gapped build ortaminda `signing.properties` veya CI
secret olarak saglanmalidir; repoya keystore/parola konmaz. Ardindan:

```bash
FLUTTER_BIN=/path/to/flutter \
SECURECHAT_API_BASE_URL=https://chat.example.com \
SECURECHAT_SIGNALING_URL=wss://chat.example.com \
SECURECHAT_CERT_PIN_HOST=chat.example.com \
SECURECHAT_CERT_PIN_SHA256='PRIMARY_BASE64' \
SECURECHAT_CERT_PIN_SHA256_BACKUP='BACKUP_BASE64' \
tool/build_hardened_android_release.sh
```

Air-gapped ortamda cache hazirsa `SECURECHAT_OFFLINE=1` eklenir. Uretilen
`app-release.aab.sha256` teslim artefaktiyla birlikte saklanir. Private symbol
dizini kendi `SHA256SUMS` manifestine sahiptir ve erisimi sinirli crash-analysis
arsivinde tutulur. AAB de ayni erisim sinirina tabidir; Play Console'a upload
disinda son kullaniciya veya public download alanina verilmez. Magaza
kullanicisi AAB'yi degil, Play'in AAB'den urettigi ve `BUNDLE-METADATA`
icermeyen imzali split APK'lari alir.

## Bilincli sinirlar ve sonraki savunma

Root edilmis ve runtime-hook uygulanmis bir cihazda certificate pinning veya
root detection tek basina mutlak guvence vermez. Uygulamayi bu cihazlarda
aniden kapatmak guvenilir bir savunma degildir ve erisilebilirlik/yanlis-pozitif
sorunu yaratir.

Google Play Integrity ek bir abuse/risk sinyali olarak kullanilabilir; sonuc
mutlaka server tarafinda nonce, package name, signing certificate digest,
request hash ve freshness ile dogrulanmalidir. Bu, Play Console/Google Cloud
proje baglantisi ve server credential gerektirdigi icin yayin altyapisi
hazirlanirken ayri entegrasyon olarak yapilacaktir. Integrity karari E2EE veya
normal JWT authorization'in yerine gecmez.
