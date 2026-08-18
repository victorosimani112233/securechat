# Private Contact Directory Runbook

Bu belge blind-RSA contact discovery protokolunun production anahtar, migration
ve incident kurallarini tanimlar. Ana gizlilik sozlesmesi
`SERVER_DATA_PRIVACY_AUDIT.md`, istemci/sunucu kodu ise sirasiyla
`lib/src/contacts/private_contact_discovery.dart` ve
`server_hardened/signaling-server/.../PrivateDirectoryOprf.kt` icindedir.

## Degistirilemez veri siniri

- Cihaz rehberindeki telefon, SHA-256 handle veya eslesme sonucu server loguna,
  metric'ine, PostgreSQL'e, Redis'e ya da process cache'ine yazilmaz.
- Evaluate istegi authenticated ve tam 256 fixed-width blind RSA elemanidir.
  Server bir batch icindeki gercek girdi sayisini ve degerleri ayiramaz.
- Snapshot her hesap icin aynidir. DB finalized OPRF token + key ID tutar;
  response token-turevi label + token-AEAD sealed user ID tasir.
- Eslesen gorunen ad, telefon ve sosyal grafik yalniz cihazdaki encrypted
  database'e yazilir.
- Server halen IP, istek zamani ve 256'lik batch sayisini gorur. Bu protokol
  anonim iletisim, mixnet veya kotu niyetli server'a karsi tam PSI degildir.

## Anahtar politikasi

`DIRECTORY_OPRF_PRIVATE_KEY`, yalniz bu protokol icin uretilmis en az 3072-bit
RSA CRT key'dir; exponent 65537 olmalidir. TLS, JWT, push, queue, imza veya baska
bir sifreleme amaciyla yeniden kullanilmaz. Mobil/offline bundle, container
image, Git, PostgreSQL backup ve loglara girmez.

Izole development key'i:

```bash
umask 077
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 \
  -pkeyopt rsa_keygen_pubexp:65537 -out directory-oprf.pem
openssl pkcs8 -topk8 -nocrypt -in directory-oprf.pem -outform DER \
  | base64 -w0 > directory-oprf.pkcs8.b64
```

Bu dosyalar development hostundan disari cikmaz ve test fixture'i production'da
kullanilmaz. Production zorunlulugu export edilemeyen HSM/KMS key'i, RSA private
operation icin dar purpose policy ve kimliksiz aggregate abuse limitidir. JVM
backend'i preconfigured JCA PKCS#11 provider, key alias, token PIN ve alias
certificate public key'ini kullanir; private key byte'i process'e cikmaz.
Provider/key/op hatasi PKCS#8 fallback acmadan listener startup'ini durdurur.
Fiziksel HSM provider/config ve failover testi deployment release kapisidir;
Linux'taki unit test bunu varmis gibi isaretlemez.

Production degiskenleri:

```text
DIRECTORY_OPRF_KEY_BACKEND=PKCS11
DIRECTORY_OPRF_PKCS11_PROVIDER=<preconfigured JCA provider name>
DIRECTORY_OPRF_KEY_ALIAS=<HSM alias>
DIRECTORY_OPRF_KEYSTORE_PIN=<secret injection; never image or shell history>
```

## Rotation

Key ID, DER SubjectPublicKeyInfo SHA-256 degeridir. Plansiz key degisimi eski
directory tokenlarini yeni snapshot'tan dusurur. Rotation sirasinda:

1. PostgreSQL encrypted backup'i ve mevcut HSM key backup/restore tatbikati
   dogrulanir; key plaintext export edilmez.
2. Yeni public config uygulama canary'sinde key-ID/SPKI dogrulamasindan gecirilir.
3. Server tek instance ile yeni key'e alinir. Eski authenticated cihazlar kendi
   telefon handle'ini `/api/v1/users/directory-token` ile yeniden indeksler.
4. V13 `directory_key_id` coverage yalniz aggregate sayi olarak izlenir; UUID,
   telefon, token veya migration zamani loglanmaz.
5. Coverage urun politikasinin esigine ulasmadan eski key imha edilmez. Bir
   rollback eski key+DB snapshot ciftini birlikte geri getirmeyi gerektirir.

Current implementation snapshot'ta yalniz aktif key'i yayinlar. Kesintisiz
dual-key rotation tamamlanmadan rutin rotation otomatiklestirilmez.

## Abuse ve fail-closed davranisi

- Evaluate limiti hesap basina 32 batch/gun (8192 aday); snapshot 12/saat,
  self-migration 4/gundur. Redis limit storage'i yoksa istek reddedilir.
- Key ID, RSA width/group, batch count, duplicate snapshot label, AEAD tag,
  user-ID bicimi ve response boyutu hatalari istemcide fail-closed'dur.
- Eski `/api/v1/users/check` route'u ve raw `hashes` request modeli release
  statik testinde yasaktir.
- E-posta OTP telefon sahipligi kaniti degildir. Hardened registration mevcut
  directory identity icin UUID/JWT dondurmez; boylece bilinen telefonla hesap
  devralma kapanir. Ancak yeni bir telefon identity'sini ilk kaydeden kisinin
  gercek hat sahibi oldugu halen kanitlanmaz. Production otomatik telefon
  discovery acilmadan once ya privacy-degerlendirmeli SMS/arama sahiplik kaniti
  ya da yüksek entropili invite/QR capability akisi zorunludur.

## Dogrulama

```bash
./gradlew :signaling-server:test --offline
flutter test test/private_contact_discovery_test.dart \
  test/server_privacy_gate_test.dart --no-pub
dart tool/generate_server_contract_audit.dart
```

Kotlin testi iki bagimsiz blind'in ayni tokene acilmasini, fixed batch ve
snapshot AEAD binding'ini; Flutter testi 3072-bit capraz protokol, 256 cover
degeri, key-ID pinning ve yalniz-local eslesmeyi kanitlar.
