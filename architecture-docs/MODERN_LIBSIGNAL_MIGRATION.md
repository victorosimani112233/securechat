# Modern libsignal V2 Migration

## Durum

SecureChat istemcisi artık Signal'in official Rust libsignal `v0.101.0`
uygulamasını `libsignal 7.1.0` / `libsignal_frb 6.1.1` üzerinden kullanabilen
bir V2 yola sahiptir. Eski saf-Dart V1 yol geçiş süresince yalnız henüz V2
bundle yayımlamamış kullanıcılarla uyumluluk için tutulur. Bu, V1 kodunun
silindiği bir final cutover değildir.

Android release AAB üç ABI native Rust kütüphanesiyle, 438 Flutter testi ve
gerçek PostgreSQL içeren 1.179 signaling + 190 bot testi geçmiştir. iOS binary link, simulator XCTest ve
no-codesign device release derlemesi Linux'ta doğrulanamaz;
`tool/verify_ios_on_macos.sh` ile Codemagic/macOS kapısında zorunludur.

## Kriptografik yol

- Direct oturumlar official Rust libsignal PQXDH + Double Ratchet kullanır.
- Her V2 initial bundle EC one-time prekey, aynı ID'li Kyber one-time prekey,
  signed prekey ve last-resort Kyber prekey taşır.
- Grup mesajları official SenderKey state'i kullanır. Dağıtım mesajı her üyeye
  ayrı direct Signal oturumuyla ulaştırılır.
- Wire zarfları direct için `E2EE:v2`, SenderKey dağıtımı için `SKDM:v2`, grup
  ciphertext'i için `GROUPSK:v3` sürüm etiketini taşır.
- V2 identity, EC prekey, signed prekey, Kyber prekey, session ve sender-key
  kayıtları V1 kayıtlarından ayrı encrypted namespace'lerde saklanır. Bir
  sürümün serialized state'i diğer sürüm adına okunmaz.
- One-time EC/Kyber çifti birlikte tüketilir. Last-resort Kyber tekrar
  kullanımı fingerprint ile algılanır; şüpheli replay oturumu fail-closed
  sıfırlar.

Sunucu yalnız public bundle tutar. V20 tablolarında private key, session,
ratchet state, plaintext veya message ciphertext yoktur. One-time EC/Kyber
çifti tek SQL transactionında `DELETE ... RETURNING` ile tüketilir ve tüketim
zaman çizelgesi saklanmaz.

## Protokol geçişi

Kayıt sırasında istemci hem V1 hem V2 public bundle yayımlar. Direct gönderim
önce V2 bundle ister. Hedef henüz hiç V2 bundle yayımlamamışsa kesin `404`
sonucu geçici olarak V1'e dönmeye izin verir. Timeout, TLS, parse, auth, rate
limit veya sunucu hatası fallback değildir ve mesaj gönderimini durdurur.

Bir peer için geçerli V2 bundle alındığında, V2 session bulunduğunda veya
geçerli V2 mesaj çözüldüğünde capability encrypted local state'e kalıcı
pinlenir. Pinlenmiş peer daha sonra `404` döndürürse V1'e dönülmez; downgrade
hatası üretilir. Sunucu veri tabanı hataları `bundle yok` sonucuna çevrilmez.

Rollout sırası zorunludur: önce V20 migration ve V2 endpointlerini taşıyan
hardened server tüm instance'lara dağıtılır, endpoint/DB health doğrulanır,
sonra V2 istemci yayınlanır. Eski servera yeni istemci göndermek kayıt akışını
fail-closed durdurur; istemci V2 public bundle upload hatasını görmezden gelmez.

Grup yükseltmesi all-members kuralına bağlıdır. Gönderici, kendisi dışındaki
tüm üyelerin V2 capability endpointinden olumlu sonuç almadığı sürece o grup
için V1 SenderKey kullanır. Grup V2 seçildikten sonra seçim encrypted state'te
tutulur. Karışık V1/V2 SenderKey state'i aynı grup sürümü adına kullanılmaz.

V2 istemci hem V1 hem V2 gelen zarfları okuyabilir. Eski V1 istemci V2 zarfı
okuyamayacağı için direct V2 seçimi hedefin yayımlanmış V2 bundle'ına, grup V2
seçimi tüm üyelerin capability sonucuna bağlıdır.

## API ve yaşam döngüsü

Hardened signaling server şu authenticated endpointleri sağlar:

- `POST /api/v2/prekeys/upload`
- `GET /api/v2/prekeys/status`
- `POST /api/v2/prekeys/refresh`
- `GET /api/v2/users/{id}/prekeys`
- `GET /api/v2/users/{id}/prekeys/capability`

Body boyutları ve key ID/material sınırları request parse edilmeden önce
kısıtlanır. Aynı key ID ve aynı byte'larla belirsiz upload tekrarına izin
verilir; aynı ID'nin farklı materyalle yeniden kullanımı transactionı geri
alır. Paralel fetch'ler aynı one-time çifti alamaz.

V1 ve V2 istemci signed prekeyleri 7 günde döndürür, başarılı server ACK
gelmeden pending anahtarı değiştirmez ve eski private signed prekeyi gecikmiş
mesajlar için 30 gün saklar. Foreground/background bakım aynı state machine'i
kullanır. Bot henüz official Rust V2'ye taşınmamıştır; mevcut Java Signal V1
yolunda aynı 7/30 günlük, exact-retry yaşam döngüsü başlangıçta ve her 6 saatte
çalışır.

## Test kapıları

- İki bağımsız istemci arasında gerçek Rust PQXDH initial message ve ratchet
  cevabı.
- One-time EC/Kyber tüketimi, last-resort replay ve ayrı V1/V2 storage.
- Rust SenderKey dağıtım, encrypt/decrypt ve kalıcı state.
- V2 direct/grup wire parserları, capability gate ve pinned-peer downgrade
  reddi.
- Upload exact-retry, aynı ID/farklı materyal reddi, havuz sınırı, paralel SQL
  tüketimi ve identity rotasyonunda atomik eski-pool temizliği.
- Android APK içinde arm64-v8a, armeabi-v7a ve x86_64
  `liblibsignal_frb.so`; iOS için device/simulator native checksum provision,
  release compile ve XCTest.

## Tedarik zinciri ve lisans engeli

`tool/libsignal_native_assets.sha256` tüm desteklenen `libsignal_frb 6.1.1`
release arşivlerini sabitler. `tool/provision_modern_libsignal_assets.sh`
checksum ve tar path kontrolü geçmeden native dosyayı hook cache'ine kurmaz;
doğrulanmamış-download bayrağını reddeder. Offline derleme pinli arşivleri
`SECURECHAT_LIBSIGNAL_ARCHIVE_DIR` altında hazır bulmak zorundadır.

Binding ve official upstream AGPL-3.0 lisanslıdır. Binding'in ek App Store
izni yalnız binding ile `libsignal_frb` wrapper'ını kapsar; official Signal
libsignal adına ek izin vermez. `assets/licenses/libsignal_DISTRIBUTION_NOTICE.txt`
kullanıcıya gösterilir, fakat hukuki izin yerine geçmez. Exact mağaza binary'si
için yazılı hukuk/uyum kararı alınana kadar App Store ve Play release'i
blokludur.

## Bilinen sınırlar

- Official Sealed Sender + anonim mailbox sonraki doğrudan iletimlerden sender
  credential'ini kaldırır. Sunucu hedef mailbox/hesap, IP, zaman ve boyut kovasını;
  ilk authenticated capability bootstrap'ında ise temas ilişkisini hâlâ korele
  edebilir. Ayrıntı `SEALED_SENDER_METADATA_PRIVACY.md` içindedir.
- İlk identity teması halen TOFU'dur. Safety number kullanıcı onayı veya key
  transparency olmadan aktif ilk-bundle substitution engellenmez.
- Bot V2 cutover ayrı iş paketidir.
- Linux doğrulaması iOS için Xcode/link/runtime kanıtı değildir.

## Rollback ve V1 kaldırma koşulları

Rollback, V2 private state'i V1 formatına dönüştürmez. Sorunlu release'te V2
gönderim kapatılabilir; V2 state korunur ve V2 zarf alımı açık kalır. Daha önce
V2 pinlenmiş peer için sessiz V1 fallback açılmaz. Acil uyumluluk istisnası
ancak açık kullanıcı/admin güvenlik kararı ve yeni migration sürümüyle yapılır.

V1 dependency ve server endpointleri ancak şu kanıtlarla kaldırılabilir:

1. Desteklenen istemci filosunun tamamı V2 okuyup yazıyor.
2. Bot official Rust V2'ye taşındı veya protokolden çıkarıldı.
3. Telemetri içerik/kimlik sızdırmadan V1 bundle kullanımının belirlenen
   emniyet süresi boyunca sıfır olduğunu gösteriyor.
4. Android ve iOS release, restore, upgrade ve air-gapped kapıları geçiyor.
5. AGPL/mağaza dağıtım kararı yazılı olarak kapanmış durumda.
