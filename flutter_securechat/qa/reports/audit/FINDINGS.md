# SecureChat — Tam Proje Denetimi (2026-09-14)

Cihaz: SM-S921B (Galaxy S24), Android 14, seri RFCY601MDPT
Temel durum: `flutter analyze` temiz · 340 test gecti · stub/TODO yok

---

## Duzeltilenler

### D-01 [KRITIK] `/permissions` ekrani dar telefonda hic cizilemiyordu
Kurulumun ilk ekrani. 320 px genislikte %200 metin olceginde `ListTile`
layout assert'i atiyordu:

```
Trailing widget consumes the entire tile width (including ListTile.contentPadding).
ListTile:.../lib/src/features/onboarding/launch_flow.dart:351
```

"Izin ver" butonu metin olcegiyle buyuyup satirin tamamini yutuyordu. Yazi
boyutunu erisilebilirlik icin buyutmus bir kullanici kuruluma devam edemiyordu.

**Duzeltme:** `ListTile` yerine `_PermissionRow`. Eylemin genisligi
`TextPainter` ile olculur; yanina sigmiyorsa metnin altina iner.
Almanca/Arapca gibi uzun etiketlerde de guvenli.

**Kalkan:** `test/full_screen_stress_audit_test.dart` — 15 ekran x 3 senaryo
(dar-telefon %200, normal, Arapca RTL %150) = 45 test.

### D-02 [YUKSEK] Cozulemeyen mesaj sessizce kayboluyordu
`_encrypted` catch bloğu mesaji dusuruyordu; kullaniciya hicbir iz kalmiyordu.
Gonderen "gonderdim", alan "gelmedi" diyordu.

Grup yolunda kalici: `_recoverFromDecryptFailure` yalniz 1:1 oturumu
onariyor (`SignalSessionUnusableException` + `peerId`). `decryptGroup` ham
libsignal istisnasi firlatiyor, bu tipe girmiyor. Sender key yeniden isteme
mekanizmasi da yok (kod tabaninda hic yok).

**Duzeltme:** `onUndecryptableMessage` geri cagrisi → `SecurityNoticeService
.messageUnreadable()` sohbete gorunur sistem mesaji yazar (gun basina bir kez).

### D-03 [YUKSEK] Bozuk sender key dagitimi tamamen yutuluyordu
`_acceptSenderKey` icinde iki adet `catch (_) {}`. Basarisiz olursa o
gondericinin grup mesajlari cozulemez hale geliyor, teshis izi de kalmiyordu.

**Duzeltme:** `_reportSenderKeyFailure` → `AsyncOperationTracker`.

**Kalkan:** `test/undecryptable_message_notice_test.dart` (3 test). Duzeltme
kaldirilinca basarisiz olduklari ayri ayri dogrulandi.

### D-04 [ORTA] Cevaplamak icin kaydirmanin siniri yoktu (sizin madde 1)
`Dismissible` + `confirmDismiss: false` kullanilmisti. Balon birakilana kadar
ekranin sonuna kadar suruklenebiliyordu; esik belirsizdi.

**Duzeltme:** `_SwipeToReply` — en fazla 72 px, esik 52 px, esikte haptik
geri bildirim, birakinca yaylanma. RTL'de ters yon.

### D-05 [ORTA] Alintiya dokununca kaynak mesaja gidilmiyordu (sizin madde 2)
`_scrollToMessage` zaten vardi (sabitlenmis mesaj banner'i kullaniyordu) ama
`_BubbleReplyPreview` dokunulabilir degildi.

**Duzeltme:** alinti `InkWell` + semantik etiket. Ayrica `_scrollToMessage`
artik cizilmemis hedefleri de bulabiliyor: sirasindan konum tahmin edip
atliyor, sonraki karede kesin hizaliyor (en fazla 4 deneme).

### D-06 [DUSUK] Sohbet listesi sonunda 112 px olu bosluk (sizin madde 4)
`EdgeInsets.fromLTRB(12, 8, 12, 112)`. Alt gezinme cubugu `Scaffold`
tarafindan zaten paylaniyor (`extendBody` kapali) ve ekranda yuzen oge yok.

**Duzeltme:** alt bosluk 16 px.

### D-07 [KRITIK] Android derlemesi kirikti
`flutter build apk` bagimlilik dogrulamasinda basarisiz oluyordu; APK/AAB
uretilemiyordu. `verification-metadata.xml` bazi BOM metadata dosyalarini
icermiyordu (kotlin-gradle-plugins-bom 2.2.0, kotlinx-coroutines-bom 1.8.0,
junit-bom ...). Git'te `android/` degismemis — yani kaynak degisikligi degil,
Gradle cozumlemesinin zamanla kaymasi.

**Duzeltme:** eksik artefaktlar tek tek eklendi. Guvenlik kurali korundu:
her artefakt ancak yerel Gradle cache kopyasi repo1.maven.org'daki resmi
kopyayla BIREBIR ayni oldugunda eklendi (`origin="Verified against
repo1.maven.org"`). `<trusted-artifacts>` KULLANILMADI.

---

## Duzeltilmeyenler — karar sizin

### F-01 [KRITIK] Depolama olcege dayanmiyor
"Veritabani" tek bir JSON dosyasi: tamami bellekte tutuluyor ve **her
degisiklikte tamami yeniden sifrelenip diske yaziliyor**.

Olculdu (masaustu; telefonda birkac kat yavas):

| gecmis | tek mesaj yazma |
|---|---|
| 50 | 7 ms |
| 500 | 32 ms |
| 1 000 | 57 ms |
| 2 000 | 120 ms |

Gercek gelen-mesaj akisi uc tam yazma yapiyor (`messages.insert` +
`conversations.updateLastMessage` + `incrementUnreadCount`): 2 000 mesajlik
gecmiste **338 ms**. Mesaj budama/retention yok, sinirsiz buyuyor.

Iyi tarafi: `_persist` atomik (tmp + flush + rename) ve yazma basarisiz
olursa bellekteki anlik goruntu geri aliniyor. Veri kaybi riski yok, sorun
tamamen olcek.

Secenekler:
1. **Gercek cozum:** artimli depolama (SQLCipher/sqflite veya mesaj basina
   ayri kayit). Buyuk is, en dogrusu.
2. **Ucuz hafifletme:** yazmalari kisa bir pencerede birlestirmek — gelen
   mesaj basina 3 yazma 1'e iner (~3x). Ama dayanikliligi azaltir: cokme
   aninda son yazmalar kaybolabilir. Urun karari.
3. Mesaj budama eklemek (orn. sohbet basina son N mesaj).

Not: `CLAUDE.md` "Room + SQLCipher" diyor; Flutter tarafi AEAD sifreli JSON
kullaniyor. Gizlilik hedefi karsilaniyor ama dokuman gercekle ortusmuyor.

### F-02 Mesaj duzenleme 15 dakikayla sinirli (sizin madde 5)
Ozellik **var**: `chat_screen.dart:1240` `_editMessage`, balonda
`chat_edited` etiketi, karsi tarafta `message_edit` kontrolu.

Menude gorunme kosulu:
```dart
message.isOutgoing &&
contentType == text &&
!isViewOnce &&
DateTime.now().difference(message.timestamp) <= Duration(minutes: 15)
```
Eski bir mesajda denediyseniz secenek gorunmez. WhatsApp da 15 dakika
kullaniyor; Signal 24 saat / 10 duzenleme. Pencereyi acmami isterseniz tek
satir.

### F-03 Cagri hatalarinda teshis izi yok
`call_manager.dart` icinde 14 `catch (_)`. Cogu dogru davraniyor
(`CallState.failed` + karsi tarafi bilgilendirme) ama hatanin kendisi
kayboluyor. Sahada "arama basarisiz" raporu geldiginde nedeni bulunamaz.
Dusuk riskli iyilestirme: bu bloklarda `AsyncOperationTracker`'a raporlamak.

### F-04 Ceviri bosluklari (onceki BUG-017)
`app_ar.arb` / `app_de.arb` 110/503 anahtar. Eksikler sablona (Ingilizce)
duser, yani Almanca/Arapca secen kullanici karisik dil gorur.

### F-05 Sunucu testleri kosulamadi
`server_hardened` icin `./gradlew test --offline`:
`org.jetbrains.kotlin.jvm:1.9.22` yerel depoda yok. Ortam kisiti (cevrimdisi
maven), kod hatasi degil. 72 Kotlin test dosyasi dogrulanmadan kaldi.

### F-06 Calisma agaci cok kalabalik
193 dosya commit edilmemis (117 degisiklik + 76 yeni). Yedeklenmemis emek
riski.

---

## Tasarim degerlendirmesi (sizin madde 3)

Somut, olculebilir eksikler:

1. **Grup ile kisi ayirt edilemiyor.** `_conversationCard` her ikisinde de
   `GeneratedAvatar(name: ...)` kullaniyor. Grup ikonu/gostergesi yok.
2. **Bas harfler ayirici degil.** `avatar.dart` yalniz BOSLUKTAN boluyor.
   "QA_Test_Mehmet", "QA_Grup_1", "qa-peer-01" hepsi tek "Q" harfi gosteriyor.
   `_`, `-`, `.` de bolme karakteri sayilmali.
3. **Sohbet listesinde teslim durumu yok.** Giden son mesajin tik durumu
   listede gorunmuyor.
4. **Derinlik yok.** `cardTheme.elevation: 0`, `appBarTheme.elevation: 0`.
   Her sey ayni duzlemde; ayrim yalnizca ince cerceve ve 7 px bosluk.
5. **Filtre cipleri sagdan kirpiliyor** ("Fa..." yarim gorunuyor).

1 ve 2 gercek islevsel eksik (yanlis sohbete girme riski). 3-5 gorsel tercih.
