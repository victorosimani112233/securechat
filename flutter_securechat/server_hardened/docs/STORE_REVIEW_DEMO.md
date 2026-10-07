# Store incelemesi için demo giriş

Apple ve Google inceleme ekipleri uygulamaya giriş yapabilmeli. Elçim e-posta
OTP'si kullandığı ve inceleyicinin e-posta kutusu olmadığı için sunucu,
**yalnızca listelenen adreslerde** e-posta göndermeden operatörün seçtiği
sabit kodu kabul eder. Kod `ReviewDemo.kt`'de uygulanır.

## Açma

Sunucu ortamına üçünü birden ekleyin (biri eksikse yol kapalıdır):

```bash
REVIEW_DEMO_EMAILS=review1@<alan-adı>,review2@<alan-adı>   # en çok 2 adres
REVIEW_DEMO_OTP=<6 haneli, tahmin edilmesi zor kod>       # veya REVIEW_DEMO_OTP_FILE
REVIEW_DEMO_UNTIL=2026-11-05                                # UTC gün sonunda kapanır
```

- **Süre:** `REVIEW_DEMO_UNTIL` geçince yol kendiliğinden kapanır.
  Production profilinde bu tarih başlangıçta en çok 30 gün ileride olabilir;
  değilse sunucu açılmaz.
- **Kota:** kod süreç ömrü boyunca en çok 30 kez verilir. Her kod en çok 5
  denemeye izin verdiği için tahmin şansı yaklaşık 150/1.000.000 ile
  sınırlıdır. Kota dolarsa demo adresine normal (rastgele, e-postalı) kod
  gider; sunucuyu yeniden başlatmak kotayı sıfırlar.
- **İz:** her verilen kod kimliksiz `REVIEW_DEMO_CODE_ISSUED` sayacını artırır.
- Hem kayıt OTP'sinde hem e-postayla giriş (hesap kurtarma) akışında çalışır.

İnceleme bitince değişkenleri kaldırıp sunucuyu yeniden başlatın.

## İnceleme notu (App Store Connect / Play Console)

İki adres verilir: biri inceleyiciye, diğeri sizin cihazınızda açık kalır ki
mesajlaşma ve arama test edilebilsin. Örnek not:

> Sign in with e-mail `review1@<alan-adı>` and code `<kod>` (no e-mail is sent
> for this address). To test messaging and calls, add the contact with phone
> number `<numara>`; a team device signed in as `review2@<alan-adı>` answers
> between <saatler> (UTC+3).
