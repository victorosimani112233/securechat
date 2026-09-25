# Mesgulken Gelen Aramalar

## Sorun

Devam eden birebir gorusme sirasinda baska bir kisinin aramasi gorunmeyen
bir ikincil oturuma alinabiliyordu. Mesgul reddedilen grup davetinde de
arama kaydi veya cevapsiz arama bildirimi uretilmiyordu.

## Degisiklik

- Ikinci arayana BUSY yaniti verilir. Aktif oturum, medya baglantisi ve
  sifreleme anahtarlari degistirilmez; ikinci bir sistem arama ekrani acilmaz.
- Aranan cihazda gelen/mesgul arama kaydi ve sessiz cevapsiz arama
  bildirimi olusur. Android'de ayri sessiz kanal kullanilir; iOS'ta
  bildirim sesi kapatilir. Android kilit ekrani gizliligi korunur.
- Gelen/mesgul kayitlar Cevapsiz filtresine de dahil edilir. Giden/mesgul
  kayitlar bu filtreye dahil edilmez.
- Yinelenen teklifler bildirim ve kayit cogaltmaz. Basarisiz bildirim
  denemesi yeniden iletimde tekrar denenebilir; okunmamis sayisi yeniden
  artirilmaz.
- Grup davetindeki bildirim ilgili grup sohbetine gider. Grubu arayan
  kisiye yanlislikla birebir geri arama baslatan bildirim aksiyonu konmaz.
- Eski grup daveti aktif grubun uyeligini sonlandiramaz. Grup kontrol
  mesajlari devam eden birebir aramayi sonlandiramaz.
- Sohbet onizlemesi ve okunmamis sayisi mevcut kayit uzerinden atomik
  guncellenir; ayni anda degisen gizlilik/sohbet ayarlari ezilmez.

## Kapsam ve Sinir

Sunucu veya protokol bu degisiklikte degistirilmedi. SDP teklifinin grup
baglamini tasimamasi nedeniyle, devam eden grup aramasindaki bir grup
uyesinden gelen bagimsiz birebir teklif ile geciken grup baglanti teklifi
her durumda ayirt edilemiyor. Bu mevcut protokol siniri ayrica ele alinmali;
iki kisilik gorusme sirasinda ucuncu kisinin aramasi icin bu belirsizlik yok.

Otomatik testler ile gercek uc telefon denemesi ayri dogrulamalardir.
iOS derlemesi ve uc fiziksel cihazla ucuncu arayan denemesi bu ortamda
henuz yapilmadi.

## Dogrulama

- Tam Flutter test taramasi: **1033/1033 gecti**.
- Yeni CallManager regresyonlari: **17/17 gecti**. Birebir/grup aktif
  gorusme, yinelenen davet, kayit tekilligi, bildirim hatasi ve yeniden
  deneme, eski kontrol mesajlari ve grup uyeliginin korunmasi kapsandi.
- Android/iOS bildirim ayrintilari, atomik okunmamis sayisi ve grup
  yonlendirmesi dahil bildirim testleri: **38/38 gecti**.
- 320/390/768 genisliklerindeki arama filtresi testleri gecti.
- Ilk statik analiz temizdi; son tekrarlar Linux inotify/dosya izleyici
  sinirinda `Too many open files` ile kesildi. Son analiz komutu basarili
  sayilmadi; test derlemesi ve release APK derlemesi basarili.
- **1.0.104 (2104)** ARM32+ARM64 release APK olusturuldu. Mevcut test
  sertifikasi ile imzalandi; magaza dagitim imzasi degildir. Iki bagli
  Android'e `adb install -r` ile yuklendi ve surumleri dogrulandi.

APK: `build/app/outputs/flutter-apk/elcim-1.0.104-arm32-arm64-signed.apk`

SHA-256: `f2c90ddd99e69ec2c81430fa6d3643da259d32d3471862f364596402831e078d`
