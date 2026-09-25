# Elcim Sunum Akisi

Sunum icin ayri bir grup kullanilir: **Elcim Sunum**.
Mevcut sohbetler ve hesaplar silinmez. Ornek icerikler sunum verisidir.

## 1. Acilis

Telefon ana ekranindaki Elcim logosunu goster, uygulamayi ac.
Sunum grubuna gir; Android ve iOS katilimcilarini goster.

## 2. Mesajlasma

Iki Android arasindaki ornek karsilikli mesajlari ve grup yazismasini goster.
Bir mesaja yanit ver, emoji tepkisini ve okundu bilgisini goster.

## 3. Anket

"Sunumda once neyi gorelim?" anketini ac.
Iki telefondan farkli seceneklere oy verildigini goster.

## 4. Icerik Paylasimi

Elcim logosunu gorsel olarak ac. Kisa ornek videoyu ve ses dosyasini oynat.
`Sunum_Ajandasi.txt` dosyasini ac.
Tek gosterimlik ornegi sunumda acmak uzere tuketmeden birak.

## 5. Aramalar

Androidler arasindaki sesli ve goruntulu test aramalarinin kayitlarini goster.
Canli aramada iki cihaz ayni ortamdaysa hoparlor geri beslemesini onlemek
icin birinin mikrofonunu kapat veya cihazlari birbirinden uzaklastir.

## 6. iOS

iOS kisisi sunum grubuna eklenir ve bir ornek mesaj gonderilir.
iPhone bu bilgisayardan yonetilemiyor: iPhone'daki goruntu, medya oynatma
ve arama cevaplama sonucu o cihazda ayrica kontrol edilmelidir.

## Hazirlik Sonuclari

- Iki Android telefonda 1.0.100 kurulu. Android ve iOS uygulama ikonlari
  mevcut Elcim logosundan uretildi.
- Elcim Sunum grubu iki Android hesabi ve kayitli iOS kisisiyle olusturuldu.
  Eski hesaba ait ayni isimli uye duzeltildi; grupta uc uye var.
- Androidlerde karsilikli mesajlar, alinti yanit, tek emoji tepkisi ve
  ankette iki farkli secenege verilen iki oy goruldu.
- Normal gorsel, kisa video, ses dosyasi ve TXT dosyasi Android alicida
  alindi. Video dosyasinin goruntuleyicisi acildi; sesin duyulmasi ve
  video oynatimi bagimsiz olarak dogrulanmadi.
- Tek gosterimlik gorsel alicida acilmadan birakildi.
- Androidler arasinda birebir sesli ve goruntulu aramalar baglandi;
  iki cihazda da aktif gorusme sayaci goruldu ve aramalar sonlandirildi.

### Acik Sorunlar

- Uc dosya ayni secimde gruba gonderildiginde ilk iki dosyada alici
  logunda DuplicateMessageException goruldu. Son dosya alindi. Ilk iki
  dosyanin ayri ayri tekrar gonderimi Android alicida basarili oldu.
  Bu, toplu grup gonderiminin duzeldigi anlamina gelmez.
- Grup sesli arama denemesi "Baglanti kurulamadi" ile basarisiz oldu.
- Kullanici iOS'a dosyalarin ulasmadigini bildirdi. iOS yeni kaynaklarla
  yeniden derlenip tekrar denenmeli; bu cihazda teslim/oynatim ve arama
  cevaplama dogrulanmadi. Bu sunum tum platformlar icin basarili kabul
  testi olarak kullanilamaz.
