# Mesaj gonderim teshisi - 23 Eylul 2026

## Dogrulanan durum

- Bagli Samsung'da 1.0.85 kurulu. Kullanici gonderdigi iki mesajda
  `Basarisiz` goruyor. Bu incelemede mesaj silinmedi/gonderilmedi,
  hesap kapatilmadi, Signal anahtarlari sifirlanmadi.
- Kullanici sorunun yalniz iOS test kisisiyle degil, butun sohbetlerde
  oldugunu bildirdi. Ortak gonderim/yerel kripto yolu incelenecek;
  bu tek basina kok neden kaniti degildir.
- Cihaz logunda 12:06:41'de `PUSH-REGISTRATION hint_submitted` var.
  Bu satir HTTP push kaydi kabul edildikten sonra uretiliyor.
- Sohbet listesinde baglanti hata gostergesi yok; mevcut UI kaynagi bu
  gostergeyi yalniz baglanti acik degilken ciziyor. Bu gozlem mesaj
  sifreleme veya alici tesliminin basarili oldugunu kanitlamaz.
- Gelistirme bilgisayarindan HTTPS `/health`, APK'daki aktif/yedek SPKI
  pinleri zorunlu tutularak 200 yaniti verdi. Kendi imzali sertifika
  nedeniyle standart CA denetimi tek basina basarisizdi; uygulamanin
  pinleme politikasinda herhangi bir gevsetme yapilmadi.
- Telefon inceleme sirasinda USB'den ayrildi; ADB cihaz listesi bosaldi.
  Asil mesaj hatasinin nedeni henuz yakalanmadi; cozuldu denmiyor.

## Degisiklik

`SendMessageUseCase` sifreleme/hazirlik hatasini eskiden yalniz `failed`
durumuna ceviriyordu. Opsiyonel `onAsyncFailure` ile asil hata ve stack
mevcut ozel tanilama servisine aktariliyor. Bildirici hata verirse
gonderim sonucu degismiyor; acik metin gonderme alternatifi yok.
Ana uygulama ve arka plan runtime bu callback'i bagliyor.

`PrivacyCrashReporter`, yalniz derlemede acikca
`SECURECHAT_LOCAL_DIAGNOSTICS=true` verildiginde yerel loga operasyon,
hata sinifi ve sinirli/redakte stack yaziyor. Varsayilan kapalidir.
Exception mesaji, request, mesaj icerigi, hesap/telefon, token ve anahtar
yazdirilmaz. Ag uzerinden rapor gonderilmez.

## Cihaz test paketi

- Surum: 1.0.86+86, yerel tanilama acik, onceki cihaz test imzasi.
- Dosya: `build/app/outputs/flutter-apk/app-release-1.0.86-device-diagnostics-signed.apk`.
- SHA-256: `5dc9d34b8fe82d22345df5b354ee8875d11c0ba5a36f3aa7d7bdb2bcefec42c1`.
- Release derlemesi, v2/v3 imza ve 16 KB zipalign denetimi gecti.
- Tanilama acikken 19 hedefli test gecti; yerel loglarda mesaj, token,
  telefon, kullanici kimligi/hash'i ve ozel dosya yolu olmamasi denetlendi.
- Telefon ayrildigi icin bu paket henuz cihaza kurulmus degil.
- Sonraki adim: ayni cihaza verileri koruyarak kurulum, kullanicinin
  ayni sohbetten yeniden denemesi, `SC-DIAG`/arka plan hata kaydinin
  incelenmesi. Guvenlik numarasi degisimi varsa otomatik onay verilmeyecek.

Sunucu degistirilmedi. Commit/push yapilmadi.

## Yeniden baglanan cihazda kayit/giris

- Kullanici hesabi sildigini ve ayni numarayla yeniden kaydolamadigini
  bildirdi. Mevcut hesap varligi varsayilmadi; tekrar hesap silme yapilmadi.
- Telefonda `auth_setup_failed` metni goruldu. UI bu mesaji yalniz OTP
  dogrulamasi basarili olduktan sonraki kurulum hatasinda gosterir.
  1.0.85 bu yakalanan hatayi loglamadigi icin tam neden belirlenemedi.
- SPKI pinli, bos JSON'lu ve kod/e-posta uretmeyen sunucu problari:
  `/api/v1/auth/login/request` 404; `/api/v1/otp/request` 400
  `invalid_json`; `/health` 200. Login servisi bu canli adreste mevcut
  degil; bu kayit hatasinin da ayni nedenden oldugunu kanitlamaz.
- AuthApi tanilama build'inde sabit endpoint ve HTTP durumunu yazar;
  response/body/token/email yazmaz. Kayit UI'si kod isteme, kod dogrulama
  ve dogrulama sonrasi kurulum hatalarini mevcut ozel raporlayiciya verir.
- Ilgili 25 test gecti. Bu eklemeleri iceren 1.0.87 tanilama paketi
  ayni telefona veriler silinmeden kuruldu; paket yoneticisi surum 87'yi
  dogruladi. Son sonuc henuz canli kayit denemesiyle dogrulanmadi.
- 1.0.87 APK SHA-256:
  `0449f7d20e9f75248254e0e4f3a6f7894635d2c89b1b6f46506bae1db3893465`.

### 1.0.87 canli kayit sonucu

- 14:22:34 OTP request 200; 14:22:47 OTP verify ve users/register 200;
  14:22:51 prekeys/upload 200. Ilk kayit kurulum adimlari basarili.
- 14:23:01 auth/logout 200; hemen sonraki iki logout istegi 401.
  Bu aralikta account/delete istegi yok. Bu gozlem kullanicinin daha once
  yaptigi hesap silmeyi reddetmez; yeni olusturulan hesaptan cikis goruluyor.
- 14:23:46 yeni OTP request 200; 14:23:57 verify ve register 200.
- 14:24:14 `auth.setup-after-code DirectoryOwnershipException`:
  `PrivateContactDiscoveryApi.checkUsers` satir 323, ardindan
  `AuthCoordinator.registerAndLogin` satir 78. Dizin goruntusunde numaranin
  sahibi yeni kaydin UUID'sinden farkli; istemci hakli olarak sahipligi
  devralmiyor. Yeni kayit istegi bu sahiplik denetiminden once gerceklesiyor.
- UI silme ve cikis akislarinin ayri oldugu kaynak kodundan denetlendi:
  hesap silme `deleteAccountOnServer` kullanir; logout hesap silmez.
- Mevcut hesaba giris endpoint'i canli sunucuda 404 oldugu icin logout
  sonrasi tekrar kayit, giris yerine kullanilamaz. Kurtarma servisi ve
  guvenilir cihazdan e-posta baglama devreye alinmadan normal kurtarma
  tamamlanamaz. Sahiplik denetimi kaldirilmadi, hesap/dizin kaydi silinmedi.
- Onceki tum sohbetlerde mesaj gonderememe sorununun ayni nedenden oldugu
  bu logla kanitlanmis degildir; bu kayit akisinin teshisidir.

### Onayli test hesabi sifirlama

- Kullanici hesap sifirlamayi onayladi ve SSH ControlMaster baglantisini acti.
- Canli JAR V22, SHA-256 `8f925fddf04aa7d74d42027b7f2983a8e682a8ed322a0bc117ed4ae6c0ea12f1`.
- Numara sunucuda mevcut OPRF anahtariyla eslestirildi; tam token/key-id
  sorgusu tek hesap dondurdu. Numara/hash/token siradan sunucu loguna yazilmadi.
- Yalniz dogrulanan hesap, UUID eslesmesini tekrar zorunlu tutan gecici yonetim
  yardimcisiyla mevcut `account/delete` endpoint'inden silindi (HTTP 200).
  Yetki tokeni sunucuda bellekte tutuldu; disariya veya diske aktarilmadi.
- Hedefin yoklugu ve diger tum mevcut hesaplarin yerinde kaldigi dogrulandi.
  Toplu tablo/Redis temizligi, uygulama verisi silme veya baska hesap silme yok.
- Bu islem yeni kimlikle yeniden kayda izin verir; eski sohbetleri geri getirmez
  ve onceki mesaj gonderim sorununun cozuldugunu tek basina kanitlamaz.
