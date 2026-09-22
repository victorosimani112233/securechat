# Android arka plan arama denemesi: 22 Eylul 2026

## Cihazda gozlenen

- Bagli Samsung SM-S731B, uygulama surumu 1.0.78+78.
- Kullanici "ariyorum" dedigi denemenin zaman araliginda, cihaz saatiyle
  **11:27:03.921 (UTC+03)**: `SecureChatPushHint: wake_no_hint`.
- **11:27:03.939**: `FLTFireBGExecutor: Creating background FlutterEngine instance.`
- Uygulama bu denemede on planda degildi. Ardindan kontrol edilen bildirim
  kayitlarinda uygulamanin gelen arama bildirimi (ID 1200) bulunmadi.
- Bildirim izni acik, RUN_ANY_IN_BACKGROUND allow. Gelen arama kanali
  `incoming_call_channel_v2` importance=4, ses/titresim acik. Onceki kontrolde
  uygulama stopped=false idi; zorla durdurma yapilmadi.
- Daha once **11:12:35.552** ve **11:12:36.092**'de istemci
  `PUSH-REGISTRATION hint_submitted` yazmis. Bu, kayit HTTP isteginin basarili
  sayildigini gosterir; anahtarin sunucuda saklandigini veya ayni process'in
  push olusturdugunu kanitlamaz.

## Kesin sinir ve henuz bilinmeyen

`SecureChatFirebaseMessagingReceiver.kt:22`, gelen `securechat_wake_v2`
Intent'inde `getStringExtra("k")` null oldugunda `wake_no_hint` yazar ve
yerel arama bildirimi yolundan doner. FlutterFire arka plan isleyicisi yine
baslatilir. Bu, anahtarla cozum hatasi degildir: mevcut anahtar eksikliginde
`wake_no_local_key`, cozum hatasinda `wake_invalid_hint` yazilirdi.

Bu denemede gozlenen push sifreli tur ipucunu icermiyor. Arama zamaniyla
eslesen cihaz bulgusu var; push kimligi/icerigi loglanmadigindan, eszamanli
baska push ihtimali sunucu kaydiyla ayrica dislanmali. Aktif sunucu process'i,
JAR'i ve token deposu bu incelemede okunmadi; belirli bir sunucu fonksiyonunu
kesin kok neden ilan etmiyoruz.

## Sunucuyu yoneten kisi/AI icin kontrol

1. Aktif process'in JAR hash'i ve API/push isteklerini karsilayan process'in
   ayni oldugunu dogrula. Depodaki dosya ile calisan JAR'i ayni varsayma.
2. Kayit yolunda `pushHintKey` alaninin geldigini ve kayit sonrasinda
   `hint=true` oldugunu kontrol et. Kaydin 2xx donmesi tek basina yeterli degil.
3. **11:27:03 UTC+03 / 08:27:03 UTC** civarindaki arama teklifinin push yolunu
   izle. `sdp_offer` icin ture ozel AES-GCM ipucu `c` olmali; FCM data
   govdesinde `type=securechat_wake_v2` ve sifreli string `k` bulunmali.
4. Depodaki `FcmPushSender.kt` anahtar null ise `k` eklemeden gonderiyor.
   Aktif kod da ayniysa null nedenini bul: eski/keyless kayit, farkli tokenla
   degisim, kayit yukleme sorunu, suresi dolma veya ayri process onbellegi.
   Ayni tokenin anahtarsiz tekrar kaydi mevcut anahtari silmemeli.
5. Yalniz alan varligi, HTTP sonucu, hint=true/false, kod hash'i ve test
   sonucu paylas. Token, anahtar, ham push govdesi, kullanici/arama kimligi,
   SDP veya tum ortam dosyasini loglama/paylasma.
6. Duzeltme sonrasi ayni testi tekrarla: cihazda `wake_call_hint`, ardindan
   `incoming_notification_posted`, gercek zil/ekran ve cevaplama dogrulansin.
   Yalniz bildirim API basarisi kullanicinin aramayi gorebildigi anlami tasimaz.

Bu incelemede uygulama/sunucu calisma kodu degistirilmedi, deployment veya
sunucu restart yapilmadi. Eksik ipucunu acik arama turu gondererek veya her
mesaj push'unda sahte arama bildirimi acarak telafi etmiyoruz.
