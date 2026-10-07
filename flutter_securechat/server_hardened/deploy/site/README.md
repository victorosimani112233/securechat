# Elçim halka açık site — gizlilik, şartlar, hesap silme

Her iki mağaza da erişilebilir bir **gizlilik politikası URL'si** şart koşuyor.
Google Play ayrıca uygulama dışından erişilebilir bir **hesap silme URL'si**
istiyor. Bu dizin o sayfaları ve dağıtım adımlarını içerir.

## Dosyalar

| Dosya | Mağazadaki karşılığı |
|---|---|
| `index.html` | Listelemedeki web sitesi adresi |
| `privacy.html` | Play: *Gizlilik politikası* · App Store: *Privacy Policy URL* |
| `delete-account.html` | Play: *Hesap silme URL'si* (zorunlu) |
| `terms.html` | App Store: *License Agreement / Terms* (opsiyonel ama istenir) |
| `style.css` | Tek stil dosyası; harici istek yok |
| `nginx-site.conf` | Yeni vhost — mevcut API vhost'una dokunmaz |

Sayfalar bilerek **self-contained**: harici font, CDN, analytics veya izleyici
yok. Bir gizlilik politikası sayfasının kendisi üçüncü tarafa istek atmamalı.

## Yayından önce doldurulması zorunlu alanlar

Sayfalarda `<mark>` ile işaretli her yer bir hukuki beyandır ve tahminle
yazılamaz. Mağaza incelemesine girmeden önce doldurun ve sarı uyarı
kutularını (`<div class="fill">`) silin:

- Veri sorumlusunun adı / unvanı ve adresi
- İletişim e-posta adresi (hesap silme talepleri buraya gelecek)
- Sunucunun bulunduğu ülke
- Yürürlük ve son güncelleme tarihleri
- `terms.html` içindeki uygulanacak hukuk, yetkili mahkeme ve ücret maddesi

`terms.html` bir şablondur, hukuki görüş değildir. Sorumluluk sınırı,
uygulanacak hukuk ve uyuşmazlık çözümü maddelerini bir avukata gözden
geçirtin.

## 1. DNS

Alan adı Cloudflare'de (`phoenix/ian.ns.cloudflare.com`). Şu an apex
Namecheap park sayfasına bakıyor (`162.255.119.54`), `www` de parking CNAME'i.

| Ad | Tip | Değer | Proxy |
|---|---|---|---|
| `tereaiqos.online` | A | `185.22.184.114` | **DNS only (gri bulut)** |
| `www` | CNAME | `tereaiqos.online` | **DNS only (gri bulut)** |

Mevcut `mail`, `r.mail`, `img.mail`, `brevo1/2._domainkey`, SPF ve DMARC
kayıtlarına **dokunmayın** — e-posta gönderimi onlara bağlı.

### Neden DNS-only

Turuncu bulut (Cloudflare proxy) TLS'i Cloudflare'de sonlandırır. Site için
bu zararsız olurdu, ama aynı hatayı API hostunda yapmak **sertifika
pinlemesini kırar**: uygulama sunucunun SPKI parmak izini gömülü tutuyor,
Cloudflare'in sertifikası eşleşmez ve sahadaki her kurulum bağlanamaz.
Alışkanlığı baştan doğru kurmak için site de DNS-only bırakılıyor.

### DMARC kaydı kontrol edin

Canlı `_dmarc` kaydı, Brevo'nun verdiği değerden farklı:

```
canlida:  v=DMARC1; p=none; rua=mailto:victorosim587@gmail.com; adkim=s; aspf=s; pct=100
```

`rua` adresi size ait değil — DMARC toplu raporları (gönderen kaynaklarınız ve
hacimleriniz) o adrese gidiyor. Kendi adresinizle değiştirin.

## 2. Dosyaları yükleyin

```bash
ssh root@185.22.184.114 'mkdir -p /var/www/elcim /var/www/certbot'
scp index.html privacy.html terms.html delete-account.html style.css \
    root@185.22.184.114:/var/www/elcim/
ssh root@185.22.184.114 'chown -R www-data:www-data /var/www/elcim && chmod -R 644 /var/www/elcim/* && chmod 755 /var/www/elcim'
```

## 3. nginx vhost

```bash
scp nginx-site.conf root@185.22.184.114:/etc/nginx/sites-available/elcim-site
ssh root@185.22.184.114 'ln -sf /etc/nginx/sites-available/elcim-site /etc/nginx/sites-enabled/elcim-site'
```

**Sertifika gelmeden `nginx -t` başarısız olur**, çünkü 443 bloğu henüz
olmayan bir `fullchain.pem` dosyasına bakıyor. Sırayı şöyle yürütün:

1. 443 bloğunu geçici olarak yorumlayın, yalnızca 80 bloğu aktif kalsın.
2. `nginx -t && systemctl reload nginx`
3. Sertifikayı alın (adım 4).
4. 443 bloğunun yorumunu kaldırın, tekrar `nginx -t && systemctl reload nginx`.

## 4. Let's Encrypt sertifikası

```bash
ssh root@185.22.184.114 '
  apt-get update && apt-get install -y certbot
  certbot certonly --webroot -w /var/www/certbot \
    -d tereaiqos.online -d www.tereaiqos.online \
    --agree-tos -m ADRESINIZ@tereaiqos.online --no-eff-email
'
```

Yenileme certbot'un systemd timer'ı ile otomatik. Yenileme sonrası nginx'in
yeni sertifikayı alması için deploy hook ekleyin:

```bash
ssh root@185.22.184.114 '
  mkdir -p /etc/letsencrypt/renewal-hooks/deploy
  printf "#!/bin/sh\nsystemctl reload nginx\n" > /etc/letsencrypt/renewal-hooks/deploy/nginx-reload
  chmod +x /etc/letsencrypt/renewal-hooks/deploy/nginx-reload
'
```

### API hostuna geçerken dikkat

Daha sonra `api.tereaiqos.online` için sertifika alıp uygulamayı IP yerine
hostname'e pinlemek isteyeceksiniz. Let's Encrypt varsayılan olarak her
yenilemede **yeni anahtar** üretir ve bu, SPKI pinlemesini 90 günde bir
kırar. O geçişte `--reuse-key` zorunludur:

```bash
certbot certonly --reuse-key -d api.tereaiqos.online ...
```

Ayrıca gerçek bir **yedek pin** üretin: henüz dağıtılmamış ikinci bir anahtar
çiftinin SPKI özeti. Şu anda uygulamadaki iki pin aynı değer, yani sunucu
anahtarı değişirse her kurulum tuğlaya döner.

## 5. Doğrulama

```bash
curl -sI https://tereaiqos.online/privacy | head -3
curl -s  https://tereaiqos.online/health
curl -sI https://tereaiqos.online/ | grep -i strict-transport
# Pinlenen API vhost'u bozulmadi mi:
curl -skI https://185.22.184.114/health -H 'Host: 185.22.184.114' | head -2
```

Son komut önemli: site vhost'unu eklemek mevcut API vhost'unu etkilememeli.

## 6. Mağaza konsollarına girilecek adresler

| Alan | Değer |
|---|---|
| Play — Gizlilik politikası | `https://tereaiqos.online/privacy` |
| Play — Hesap silme URL'si | `https://tereaiqos.online/delete-account` |
| App Store — Privacy Policy URL | `https://tereaiqos.online/privacy` |
| App Store — Support URL | `https://tereaiqos.online/` |
| Her ikisi — Web sitesi | `https://tereaiqos.online/` |

## 7. Play Data Safety formu — politikayla tutarlı olması gerekenler

Form ile politika çelişirse ret gelir. Koddan doğrulanmış karşılıklar:

| Form sorusu | Cevap | Dayanak |
|---|---|---|
| Veri toplanıyor mu? | Evet | Hesap kimliği, telefon özeti, e-posta dizini, push jetonu |
| Veri şifrelenerek mi iletiliyor? | Evet | TLS + sertifika pinleme |
| Kullanıcı silme talep edebilir mi? | Evet | Uygulama içi + web sayfası |
| Kişiler (Contacts) | Toplanıyor — "App functionality" | Yalnızca geri çevrilemez özet gönderilir |
| Mesajlar | **Toplanmıyor** | Sunucu içeriği göremez; kalıcı saklama yok |
| Konum | Toplanmıyor | Konum izni yok |
| Üçüncü tarafla paylaşım | Evet | FCM (push jetonu), Brevo (e-posta) |
| Reklam / analitik | Hayır | Uygulamada SDK yok |

"Mesajlar toplanmıyor" beyanı, çevrimdışı kuyruğun yalnızca RAM'de ve 15
dakika tutulmasına dayanır. Bu süre `OFFLINE_QUEUE_TTL_SECONDS` ile
yapılandırılır; artırırsanız beyanı gözden geçirin.
