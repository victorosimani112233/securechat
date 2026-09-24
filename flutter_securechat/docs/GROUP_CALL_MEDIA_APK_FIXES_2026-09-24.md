# Grup araması, sesli mesaj ve Android paketi

## Düzeltilenler

| Sorun | Değişiklik ve nedeni |
| --- | --- |
| Grup oluşturulunca üyeler haberdar olmuyordu | `ContactService`, ilk mesajı beklemeden her üyeye ayrı E2EE CREATE daveti hazırlıyor. Grup ve şifreli gönderim kuyruğu tek yerel işlemde kaydediliyor. Bir üyenin anahtarı alınamazsa yarım grup oluşturulmuyor. Çevrimdışı gönderimler mevcut kuyruğa bırakılıyor. |
| Davet alınıyor ama bildirim görünmüyordu | `IncomingMessageHandler` yeni grupta bildirim koordinatörüne olay yayımlıyor. İçerik gizleme, ön plandaki açık sohbeti bastırma ve okunmamış sayacı mevcut bildirim kurallarını kullanıyor. Tekrarlanan CREATE ikinci bildirim oluşturmuyor. |
| Grup çağrısı bağlantı hatası | Şifreli PREPARE_CALL çözülürken davet daha erken gelebiliyordu. `PrivateGroupCallRoutes`, rastgele çağrı anahtarını her bekleme adımında yeniden okuyor; eski kod yalnız ilk okumadan sonra eski tip grup özetini arıyordu. Bekleme sınırlı; bilinmeyen/gruptan çıkmış kullanıcıya çağrı açılmıyor. Erken HANGUP da grup davetiyle aynı işlem sırasına alındı. |
| Uygulama içindeki Cevapla düğmesi | `CallManager` ve native köprü artık aynı sistem cevaplama akışını kullanıyor. iOS'ta CXAnswerCallAction ve sağlayıcının ses hazırlığı; Android'de Telecom bağlantısının onAnswer işlemi devreye giriyor. Çift dokunma/native geri bildirimi yalnız bir kabul işlemi başlatıyor. |
| Aktif grup çağrısına sonradan katılım | Sohbetin üstünde sabit sesli/görüntülü çağrı bandı var. Katılmadan önce sunucudan güncel durum, çağrı kimliği ve kapasite tekrar kontrol ediliyor. Yerel üyelik doğrulanıyor, yeni medya anahtarı alınmadan medya yayımlanmıyor. Katılım sınırı 8 olarak kaldı. |
| İlk grup ses kaydında SenderKey hatası | Dosya aktarımında eksik olan SenderKey dağıtımı eklendi; metin ve dosya ortak yardımcıyı kullanıyor. Alıcı, önceki şifreli anahtar olayları işlenmeden dosyayı çözmüyor. Bu düzeltme ses kaydı yanında diğer grup dosyalarını da kapsıyor. |
| A13 için küçük APK kurulamıyordu | Önceki küçük paket yalnız ARM64'tü. Yeni APK hem ARM32 hem ARM64 Flutter/WebRTC/SQLCipher kütüphanelerini içeriyor. Kullanılmayan x86_64 eklenti kütüphaneleri derlemede ayıklanıyor; özellik kaldırılmadı. A13'ün gerçek ABI'si ve önce denenen dosyanın imzası cihazda doğrulanmadığından önceki kurulum hatasının kesin nedeni henüz kanıtlanmış değil. |

## Sunucu ve gizlilik

- Sunucu değişikliği: `GroupCallSessionStore` ve `WebSocketRoutes`.
- Çağrıya davet edilmiş kişi ile şu anda katılmış kişi ayrıldı. Reddeden/ayrılan davetli, aynı çağrı sürüyorsa tekrar katılabiliyor. Davetsiz kişi kabul edilmiyor; şifreleme gereksinimi düşürülmüyor.
- Davet bilgisi yalnız mevcut çağrının RAM kaydında kalıyor; çağrı bitince veya mevcut 4 saatlik üst süre dolunca kaldırılıyor. Yeni PostgreSQL tablosu/migrasyonu yok; hedef V23 değişmedi.
- Sunucu durum yanıtı çağrının medya şifreleme gereksinimini bildiriyor. Koordinatör, yerel grup üyeliğini ayrıca kontrol ediyor; medya anahtarı yine E2EE ile dağıtılıyor.
- Bu değişiklikler sunucunun yönlendirme metaverilerini göremediği anlamına gelmez. Kimlik/telefon numarası push gövdesine eklenmedi.
- iOS uygulama içi cevaplama, [Apple CXAnswerCallAction](https://developer.apple.com/documentation/callkit/cxanswercallaction) üzerinden yapılır. Bu çalışma iOS kapalı uygulama için PushKit/APNs VoIP dağıtımını kendiliğinden yapılandırmaz.

## Doğrulama

- Tam Flutter turu: **860 test başarılı**.
- Statik analiz: **310 Dart dosyası, 0 bulgu**. Makinenin inotify sınırı nedeniyle mevcut tek-seferlik analyzer aracı kullanıldı.
- Sunucu: **21 grup çağrısı testi başarılı**; kapasite, davet, yeniden katılım, şifreleme ve gizlilik testleri.
- Gerçek Signal ratchetiyle ilk grup ses dosyası, SenderKey sıfırlamasından sonra tekrar gönderim ve eksik alıcı anahtarında kapalı kalma test edildi.
- Sesli/görüntülü çağrıya yeniden katılım, native cevaplama geri bildirimi ve geciken şifreli çağrı hazırlığı test edildi.
- Çağrı bandı 320 piksel genişlikte widget testinden geçti; katıl düğmesi ve çağrı bitince gizlenmesi kontrol edildi.
- Android release derlemesi, v2/v3 imza, 16 KB ZIP hizalama, iki ABI'nin gerekli kütüphaneleri ve 13 native ses kaynağı doğrulandı.
- Bağlı **SM-S731B** telefona veriler silinmeden kuruldu; paket 1.0.89 / 2089 olarak doğrulandı. Telefon kilitli olduğundan canlı arama/UI testi yapılmadı. Bu cihaz, bildirilen Galaxy A13 değil.
- `audit_ios_readiness.dart`: PASS. Linux ortamında Xcode/RunnerTests/iPhone canlı araması çalıştırılmadı. iOS bağlantı sorununun cihazda tamamen giderildiği henüz doğrulanmış değil.

## Kurulacak dosyalar

APK: `build/app/outputs/flutter-apk/elcim-1.0.89-arm32-arm64-signed.apk`

- Boyut: 74.569.110 bayt, yaklaşık **74,6 MB / 71,1 MiB**.
- Sürüm: 1.0.89, versionCode 2089; önceki ARM64 paketin 2088 değerinden yüksek.
- Minimum Android: 8.0 (API 26). Android 14 sürüm şartını karşılıyor.
- Önceki cihaz test sertifikası kullanıldı; mağaza dağıtım sertifikası değildir. Ek `.idsig` gerekmez.
- SHA-256: `8a7ba85b04a087a9814260b829eee1e76a6fa17952d849966836d6a89a53f39f`

Sunucu: `server_hardened/signaling-server/build/libs/signaling-server-all.jar`

- SHA-256: `7a15cfe4d0b1d89ba96bd360549b42669a124d707cf020e79af3ca17ebc5f343`
- Build etiketi: `d511597-dirty-group-calls-20260924`; zaman: `2026-09-24T12:40:28Z`.
- JAR üretildi; canlı sunucuya yüklenmedi/servis yeniden başlatılmadı.
- Yeni katılım akışı için bu sunucu sürümü ve güncel istemciler birlikte kullanılmalı. Eski sunucuya karşı yeniden katılım doğrulanmış değildir.

Kaynak değişiklikleri, testler ve dağıtım betiği aynı commit kapsamında tutulur. Yukarıdaki JAR commit öncesinde üretildiği için build etiketi `dirty` içerir; dosyanın doğrulaması belirtilen SHA-256 ile yapılır. Mac'te güncel kaynaklar çekildikten sonra iOS uygulaması yeniden derlenmelidir.
