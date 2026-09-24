# iOS rehber, grup ve ses kaydi duzeltmeleri

## iOS'ta sekme degistirirken kapanma

`ios/Runner/AppDelegate.swift`: rehber okurken yalnizca ad/soyad alanlari
isteniyor, sonra `CNContactFormatter` ile tam ad olusturuluyordu. Bicimleyicinin
istedigi diger alanlar yuklenmediginde iOS bir Objective-C exception uretebilir;
Swift `do/catch` bunu yakalamaz. Rehber bosken gorunmeyen hata, kisi eklenince
sekme gecisinde yapilan rehber senkronizasyonunda uygulamayi kapatabilir.

Fetch istegi artik `descriptorForRequiredKeys(for: .fullName)` kullaniyor.
iOS 18 ve ustunde sinirli rehber izni de kabul ediliyor; sadece kullanicinin
izin verdigi kisiler okunuyor. Daha genis izin istenmiyor.

Bu, kaynakta dogrulanan bir hata ve kullanicinin belirttigi kapanma ile uyumlu.
Cihaz crash raporu olmadan bildirilen kapanmanin kesin sebebi oldugu soylenemez.

Kaynaklar: [Apple Contacts](https://developer.apple.com/documentation/contacts),
[rehber erisimi](https://developer.apple.com/documentation/contacts/accessing-the-contact-store).

## Gruptan ayrilma ve arsivden silme

- `group_management_service.dart`: ayrilmadan once signaling baglantisi beklenir.
  Soket gonderimi basarisizsa ayni sifreli zarf bir kez yeniden denenir.
  Gonderim basarisiz kalirsa yerel uyelik korunur; kullanici tekrar deneyebilir.
- Ayni anda gelen cikis istekleri tek islemde birlesir. Zaten ayrilmis hesap
  tekrar cikis bildirimi gondermez ve eski yonetici kaydiyla islem yapamaz.
- `secure_chat_database.dart`: basarili gonderimden sonra yerel uyelik,
  yoneticilik, arsiv durumu ve SenderKey temizligi tek yazmada guncellenir.
- `conversation_repository.dart` ve sohbet listesi: hala uyesi olunan grupta
  sadece yerel gecmis temizlenir. Ayrilinmis grupta sohbet arsivden veya normal
  listeden silinebilir. Yeni tablo/migrasyon gerekmez; mevcut uye listesi kullanilir.
- Grup bilgileri tekrar cikis sunmaz; ayrilinmis sohbetin yazma ve arama
  kontrolleri kapatilir. Ham `Bad state` yerine yerellestirilmis hata gosterilir.

Sinir: soketin gonderimi kabul etmesi, tum alicilarin bildirimi aldigini
kanitlamaz. Bu degisiklik yeni bir kalici ACK kuyrugu eklemez. Kismi fanout
hatasi sonrasinda tekrar gonderilen LEAVE bildirimi alicida mevcut uyelik
kontrolu sayesinde ikinci kez uygulanmaz. Sunucuya acik grup bilgisi eklenmez.

## Ses kaydinin dosya bulunamadi hatasi

`media_message_service.dart`: tamamlanmis ses kaydi aktarimi belge olarak
degerlendiriliyor, belge otomatik indirmesi kapaliysa yerel dosya siliniyordu.
Gecerli ses kaydi metadata'si olan `audio/*` aktarimlari artik bu kuralla
silinmiyor. Normal belgeler ve gecersiz ses metadata'si eski politikayi korur.
Sifreleme ve aktarim boyut kontrolleri degistirilmedi.

Bu duzeltme alici cihazda da bulunmali. Onceden silinmis ses dosyalarini
geri getirmez; bu kayitlar yeniden gonderilmelidir.

## Dogrulama

- Son tam Flutter test kosusu: **850/850 gecti** (2 dakika 48 saniye).
  Komut: `flutter test --no-pub --concurrency=2 --reporter=expanded`.
- Hedefli Dart/widget testleri: 53 test gecti. Wi-Fi, mobil ve diger aglarda
  ses baytlari ve veritabani tekrar acildiginda dosya varligi kontrol edildi.
- Grup bilgisi test taklidine yeni uyelik metodu eklendikten sonra ilgili
  18 gezinme testi de gecti.
- Statik analiz: `lib`, `test`, `integration_test`, `tool` altindaki 305 Dart
  dosyasinda 0 diagnostic. Normal `flutter analyze`, bu makinede Linux inotify
  instance sinirina takildi. Flutter SDK'nin mevcut analyzer paketi ile
  `AnalysisContextCollection/getErrors` kullanilarak dosya izleyicisiz tek
  seferlik analiz yapildi; sistem limitleri veya bagimliliklar degistirilmedi.
- Grup: baglanti hatasi ve tekrar deneme, eszamanli cikis, son uyenin ayrilmasi,
  eski yonetici yetkisi, arsivden silme ve uye olunan grubu koruma test edildi.
- `RunnerTests.swift` icine native rehber izin/descriptor testleri eklendi.
  Linux ortaminda Xcode/iPhone testleri calistirilamadi.
- Mac'te yeni derleme ile iki rehber kaydi varken tum sekmeler, sinirli rehber
  izni, gruptan ayrilip arsivden silme ve yeni ses kaydini dinleme denenmeli.
  Uygulamayi silmek veya rehber kayitlarini kaldirmak gerekmiyor.

## Push oncesi ikinci inceleme

- Acik sohbet ekrani yalniz kisi adini yeniliyordu. Uyelik, yoneticilik ve
  grup politikasi degisiklikleri artik ekrana da yansir; gruptan cikarilan
  kullanicinin yazma ve arama kontrolleri eski durumda kalmaz.
- Metin gonderimi, veritabanindaki grup uyeligini mesaj kaydi veya sifreli
  kontrol gonderimi olusturmadan once denetler. Ayrilmis hesap reddedilir.
- Medya gonderimi dosya secicinin eski uye listesini kullanmaz. Her dosya icin
  guncel uyelik ve alici listesi veritabanindan okunur. Ayrilmis uyeye yeni
  medya anahtari gonderilmesini onleyen regresyon testi eklendi.
- Ek hedefli testler: 39/39. Bunlar son 850 testlik tam kosuya dahildir.
- Secili sunucu testleri: 96 test, 93 basarili, 3 basarisiz. Uc hata
  `GroupJanusGatewayTest` icinde Netty test sunucusu kapanirken Ktor'un
  `LinuxWatchService` acmasindan gelir: `User limit of inotify instances
  reached or too many open files`. Bu testler basarili kabul edilmedi.
- Ilk, daha genis sunucu denemesi `GroupCallSessionStoreLincheckTest`
  sirasinda JVM heap sinirina takildi. Ardindan mevcut izole test-worker
  ayariyla kurtarma, pre-key, grup aramasi ve SFU testleri secilerek kosuldu;
  Lincheck'in bu oturumda basariyla tamamlandigi iddia edilmiyor.
- Canli sunucu degistirilmedi. iOS native testleri icin Mac/Xcode ve gercek
  iPhone denemesi halen gerekli. Bu inceleme bagimsiz guvenlik auditi degildir.
