# Grup uye kimligi gosterimi

## Sorun

Grup bilgileri yalnizca `contacts` kayitlarina bakiyor, eslesmeyen uyelerde
UUID'yi ad olarak gosteriyordu. Bilinen kisilerin alt satirinda da UUID vardi.
Birebir E2EE tanitimi ile dogrulanip yerel sohbette saklanan numara burada
kullanilmiyordu. Grup mesaji balonlarinda gonderen etiketi yoktu; yanit
onizlemesi ise gonderen kisi yerine grup adini kullaniyordu.

## Degisiklikler

- `lib/src/contacts/contact_service.dart`: mevcut yerel kimlik cozumleyicisine
  toplu okuma eklendi. Rehber adi onceliklidir; rehber kaydi yoksa daha once
  dogrulanmis birebir sohbet numarasi kullanilir. Grup kaydinin `peerPhone`
  alani kisi numarasi olarak kabul edilmez.
- `lib/src/groups/group_management_service.dart`: grup uyelerinin yerel kimlik
  degisikliklerini izleyen akis eklendi. Kisi adi/numarasi degisince ekrani
  kapatip acmak gerekmez.
- `lib/src/features/groups/group_info_screen.dart`: uye adi, numara alt satiri
  ve cikarma onayi yerel kimlikle gosterilir. Yerel kullanici `you` etiketiyle
  gosterilir; UUID artik bu alanlarda kullaniciya yazdirilmaz.
- `lib/src/features/chat/chat_screen.dart` ve
  `chat_message_bubble.part.dart`: gelen grup mesajlarina gonderen kisi etiketi
  eklendi. Yanit balonu ve yanit yazma onizlemesi de ayni kisi adini kullanir.
- `lib/src/incoming/incoming_message_handler.dart`: yeni grup olaylari,
  grup bildirim basliklari ve grup sureli-mesaj duyurulari ayni yerel kimlik
  onceligini kullanir. Birebir sohbetlerin mevcut davranisi korunur.
- Dort ARB dosyasi ve uretilen yerellestirme dosyalari: bilgi bulunmayan
  kisiler icin `group_unknown_member` etiketi eklendi.

## Gizlilik ve Sinirlar

- Sunucuya UUID-numara sorgusu eklenmedi. Grup uyelerine telefon numarasi
  otomatik gonderilmiyor; birebir numara paylasim tercihi degismedi.
- UUID'ler protokol, sifreleme, yonetici yetkisi ve mesaj yonlendirmesi icin
  korunuyor. Yalnizca kullaniciya gosterilen etiketler degisti.
- Cihazda adi veya dogrulanmis numarasi olmayan uye `Bilinmeyen uye` olarak
  gorunur. Bu durumda gercek ad/numara tahmin edilmez.
- Eski sistem olaylari kaydedildikleri metinle korunur; gecmiste UUID ile
  yazilmis olay metinleri geri donuk yeniden yazilmaz.
- Degisiklik ortak Flutter kodundadir; Android ve iOS icin yeni uygulama
  derlemesi gerekir. Sunucu, veritabani semasi ve asil Kotlin uygulamasi
  bu gorevde degistirilmedi. Xcode derlemesi yapilmadi. Ayni gun sonraki
  bildirim duzeltmesiyle birlikte Android 1.0.77+77 derlenip bagli Samsung'a
  kuruldu; ayrinti [kurulum kaydinda](FOREGROUND_MESSAGE_NOTIFICATIONS_2026-09-22.md).

## Dogrulama

`flutter test --no-pub`: 503 test gecti. `git diff --check` temiz.

`test/group_member_identity_test.dart` yerel kimlik onceligini, canli ad/numara
guncellemelerini, yeni grup olaylarini, 390/768 piksel uye listelerini,
390x844 ekranda iki kat metin olcegini ve grup mesaji/yanit etiketlerini sinar.
Numara paylasiminin gruplara acilmadigi mevcut gizlilik testleriyle de denetlenir.

Statik analiz, bu makinedeki `Too many open files (errno = 24)` izleyici
siniri nedeniyle temiz olarak raporlanamadi. Yeni test dosyasinda bildirilen
gereksiz import kaldirildi. Gercek iPhone uzerinde UI testi yapilmadi.
