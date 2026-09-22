# Aktif JAR ve Yerel Sunucu Duzeltmelerinin Birlestirilmesi

## Girdiler

- Kullanici tarafindan aktif olarak belirtilen, degistirilmeden korunan dosya:
  `/home/user497/Desktop/signaling-server-all.jar`.
- Orijinal SHA-256:
  `ae850bb2f310c4c38adb90b526ca860ee27be76fd2047d4216162b1347fc5630`.
- Yerel taban: `bc210a45674f2162197003434c64d0cf2ccad50a` ve bu commit
  uzerindeki commit edilmemis istemci/sunucu duzeltmeleri.
- Onceki statik inceleme:
  [ACTIVE_SERVER_JAR_REVIEW_2026-09-21.md](ACTIVE_SERVER_JAR_REVIEW_2026-09-21.md).
- Birlestirme oncesi sunucu kaynak/test yedegi:
  `/tmp/securechat-jar-merge-0Vsqyl/server-pre-merge.tgz`.

Bu islem bir Git dalini digerinin uzerine yazmak veya decompile edilmis Java'yi
Kotlin kaynaklarinin yerine koymak degildir. JAR'a ozel davranislar, mevcut
Kotlin duzeltmeleri korunarak uc dosyada birlestirildi. Istemci dosyalari,
eski Kotlin uygulamasi ve diger calisma degisiklikleri bu turda degistirilmedi.

## Korunan davranislar

| Davranis | Birlestirme karari |
| --- | --- |
| Ayni token anahtarsiz yenilendiginde mevcut anahtari koruma | JAR'daki islev korundu; yereldeki atomik `compute` ve retention denetimi geri alinmadi. |
| Farkli tokena onceki cihazin anahtarini aktarmama | Korundu. Acik yeni anahtar verilirse yeni kayit kullanilir. |
| `hint_key=received/preserved/dropped_token_changed/absent` kayitlari | JAR'daki seviye, mesaj kalibi ve durum adlari geri eklendi. Karar atomik guncelleme icinde hesaplanir. |
| Suresi dolan anahtari yeniden kullanmama | Yerel koruma aynen duruyor. JAR'daki eski davranisi geri getirmek yerine yeni `dropped_expired` tanisi eklendi. |
| Yerel `Token kaydedildi; hint=true/false` kaydi | Korundu; eski ve yeni tani okuyucularinin ikisi de kullanilabilir. |
| API'deki `hint_key_field=present/absent` kaydi | `HttpRoutes.kt` icine, kimlik ve kullanici eslesme kontrollerinden sonra geri eklendi. |
| Eksik anahtar uyarisi ve `Sifreli tur ipucu eklendi` kaydi | `FcmPushSender.kt` icine JAR'daki sirayla geri eklendi. Ipucunun eklenmesi, FCM'ye gonderim basarisi olarak raporlanmaz. |
| Token ve anahtarin tek tutarli kopyadan okunmasi | Yerel duzeltme korundu; JAR'daki iki ayri okuma geri getirilmedi. |
| Kontrol push'u ile yeni arama push'unun ayri hiz sinirlari | Yerel duzeltme korundu. |
| Arka plan soketinin arama paketini tuketmemesi | `X-SecureChat-Call-Capable` sozlesmesi ve on plan baglanti korumalari korundu. |
| FCM data payload ve AEAD/Signal davranisi | Degistirilmedi; tani kayitlari ham token, anahtar, kimlik, SDP veya mesaj govdesi tasimaz. |

Bu turdaki uretim kaynak eklemeleri yalniz `FcmTokenStore.kt`,
`FcmPushSender.kt`, `HttpRoutes.kt` icindedir. Onceki `ConnectionManager.kt`,
`MessageTypes.kt`, `WebSocketRoutes.kt` duzeltmeleri oldugu gibi korunmustur.

## JAR dosya karsilastirmasi

Yalniz uygulama siniflari degil, iki JAR'in **tum dosya girdileri** ZIP API'si
ile okunarak SHA-256 uzerinden karsilastirildi. JAR'lar calistirilmadi.

| Sonuc | Sayi |
| --- | ---: |
| Orijinal dosya girdisi | 33,585 |
| Birlesik dosya girdisi | 33,586 |
| Birebir ayni | 33,466 |
| Icerigi farkli | 117 |
| Yalniz birlesik JAR'da | 3 |
| Yalniz orijinal JAR'da | 2 |

**Uygulama paketi disinda tek fark `build-info.properties` dosyasidir.**
Bagimliliklar, migrasyon SQL'leri, manifest ve diger paketlenmis kaynaklar
birebir aynidir. Yeni tablo veya migrasyon eklenmedi.

Uygulama tarafindaki farklar mevcut alti sunucu kaynak dosyasinin duzeltmeleri
ve Kotlin'in urettigi siniflardir. Eski iki uretilmis sinif
`FcmPushSender$3` ve `FcmPushSender$Companion$forGateTest$3`, token/anahtar
okumasinin tek kayit okumasinda birlestirilmesiyle yeniden numaralanan/azalan
lambdalardir; push silme veya anahtar okuma islevinin kaldirilmasi degildir.
Test yardimcisi ve test siniflari release JAR'a eklenmemistir.

## Derleme ve artefakt

- `:signaling-server:compileKotlin`: basarili.
- `:signaling-server:fatJar`: basarili, offline bagimliliklarla derlendi.
- Birlesik JAR: `server_hardened/signaling-server/build/libs/signaling-server-all.jar`.
- Boyut: 86,399,177 bayt.
- SHA-256:
  `888c2c29a7093404aa4481fe7053577e665ec8f6b30f5b81c0a01abd77fef442`.
- Build commit etiketi:
  `bc210a45674f2162197003434c64d0cf2ccad50a-dirty-jar-merge`.
- Build zamani: `2026-09-21T14:25:46Z`; migration hedefi `V22`.

`dirty-jar-merge` eki, artefaktin yalniz kayitli commit'ten degil mevcut
commit edilmemis duzeltmelerden derlendigini belirtir. Yeni bir commit
olusturulmus gibi sunulmaz. Commit/push sonrasinda uretim artefakti gercek
commit kimligiyle yeniden uretilmelidir.

## Test kapsami

Tum `:signaling-server:test` gorevi basariyla tamamlandi: **53 test sinifi,
1.222 test, 0 basarisizlik, 0 hata, 0 atlanan test**. Sure 2 dakika 11 saniye.
Sonuc, Gradle XML raporlarinin yapisal olarak okunmasiyla ayrica sayildi.
PostgreSQL/Redis entegrasyonlari ve eszamanlilik testleri bu sonuca dahil.
Testler gecici yerel test servislerini kullanir; canli sunucuya baglanmaz.

Tekrar uretme komutu (`server_hardened` dizininde):

```sh
JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:+$JAVA_TOOL_OPTIONS }-Dapi.version=1.44" \
  ./gradlew :signaling-server:test --offline --no-daemon --console=plain \
  -PsourceCommit=bc210a45674f2162197003434c64d0cf2ccad50a-dirty-jar-merge \
  -PsourceBuiltAt=2026-09-21T14:25:46Z
```

Docker API secimi yalniz bu test process'ine verildi; makinenin ayarlari veya
uretim konfigurasyonu degistirilmedi. `git diff --check` de temiz.

- `FcmTokenPrivacyIntegrationTest`: sifreli DB tekrar acilisi, anahtar
  yenileme/degistirme, retention siniri, durum etiketleri ve log gizliligi.
- `FcmPushSenderTest`: ipucu ekleme ile gonderim basarisinin ayrilmasi,
  eksik/gecersiz anahtar, gercek SDK mesajinin alanlari, ayri arama kontrol
  siniri ve loglarda kimlik/anahtar/sifreli ipucu bulunmamasi.
- `EndToEndServerTest`: HTTP kayit yolu, anahtarsiz yenileme, yetkisiz veya
  farkli kullaniciya ait isteklerde FCM kayit logu uretilmemesi.
- `BackgroundCallDeliveryIntegrationTest`: onceki yedi arka plan arama
  teslimi regresyonu degistirilmeden korunuyor.
- `TestLogCapture`: yalniz testte logger'a baglanir, kapanista eski log
  seviyesini geri yukler; uretim bagimlilik grafigine eklenmez.

## Sinirlar

Canli sunucuya kopyalama, servis restart, `KUR.sh`, commit veya push
calistirilmadi. Orijinal JAR'in SHA-256 degeri tekrar kontrol edildi ve
degismedi. Gercek FCM teslimi, canli Android aramasi veya fiziksel iPhone
aramasi bu yerel birlestirme testlerinin yerine gecmez.

Onceki raporda belirtilen, eski tokena ait gecikmis FCM hatasinin yeni kaydi
silmesi riski bu birlestirmenin kapsaminda degistirilmedi. iOS PushKit
hatti da eklenmedi. Bu rapor, bilinen tum cagri sorunlarinin bittigi veya
kriptografik denetimin tamamlandigi iddiasini tasimaz.

Kaynak yedegi, archive karsilastirmasi ve test/derleme loglari
`/tmp/securechat-jar-merge-0Vsqyl/` altindadir; `/tmp` kalici arsiv degildir.
