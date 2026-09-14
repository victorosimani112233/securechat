# Elçim — Kendi Mail Sunucusu (send-only)

Google/Gmail SMTP yerine kendi altyapından OTP/transactional mail gönderme.

Uygulama kodunda **değişiklik gerekmiyor**. `EmailService.kt` zaten sağlayıcıdan
bağımsız SMTP kullanıyor; tek yapılan `SMTP_*` ortam değişkenlerini bu stack'e
yönlendirmek.

Bu sunucu **yalnızca gönderim** yapar: 25/tcp dinlemez, gelen mail kabul etmez,
posta kutusu yoktur. Saldırı yüzeyi minimumda.

---

## 1. Satın alınacaklar

| # | Ne | Nereden | Yaklaşık maliyet | Zorunlu mu |
|---|----|---------|------------------|------------|
| 1 | **Domain** (`elcim.app`) | Cloudflare Registrar (maliyetine satar), Porkbun, Namecheap | `.app` için ~15–20 $/yıl | Evet |
| 2 | **VPS** — giden 25/tcp açık + PTR düzenlenebilir | aşağıdaki tabloya bak | ~5 €/ay | Evet |
| 3 | **DNS yönetimi** | Cloudflare (ücretsiz) veya registrar'ın kendi paneli | 0 | Evet |
| 4 | **TLS sertifikası** | Let's Encrypt | 0 | Evet |
| 5 | PTR / reverse DNS kaydı | VPS panelinden, ücretsiz | 0 | Evet |

**Toplam: ~20 $/yıl domain + ~60 €/yıl VPS.** Başka bir şey satın almana gerek yok.

### VPS seçimi — tek kritik kriter: giden 25/tcp

Sağlayıcıların çoğu spam nedeniyle giden 25/tcp'yi kapatır. Kapalıysa kendi
sunucundan **doğrudan teslimat imkânsızdır**.

| Sağlayıcı | Giden 25/tcp | PTR düzenleme |
|-----------|--------------|---------------|
| **OVH / SoYouStart VPS** | Varsayılan **açık** | Panelden, self-servis |
| **Netcup** | Kimlik doğrulaması sonrası açık | Panelden |
| **Hetzner Cloud** | Kapalı; destek talebiyle açılır (genelde onaylanır) | Console'dan, self-servis |
| **Contabo** | Kapalı; talep üzerine açılır | Panelden |
| DigitalOcean / Vultr / Linode / AWS / GCP / Azure / Oracle | Kapalı, açtırmak çok zor | değişir |
| Türkiye'deki paylaşımlı hosting'lerin çoğu | Kapalı | genelde yok |

**Öneri: OVH VPS veya Hetzner Cloud.** En düşük paket yeterli (1 vCPU / 2 GB).

Uygulama sunucusuyla **aynı VPS'e** kurabilirsin — kaynak tüketimi çok düşük,
ayrı sunucu almana gerek yok.

> **Satın almadan önce**: sunucuyu aldıktan sonra ilk iş `scripts/preflight.sh`
> çalıştır. 25/tcp kapalı çıkarsa iade süresi içinde sağlayıcı değiştir.

---

## 2. Dürüst uyarı: teslim edilebilirlik

Taze bir IP'nin gönderim itibarı sıfırdır. SPF + DKIM + DMARC + PTR'yi doğru
kursan bile Gmail ilk mailleri spam'e atabilir, Outlook/Hotmail doğrudan
reddedebilir. OTP maili spam'e düşerse **kayıt akışı kırılır.**

Bunu azaltmak için:

- Bu stack SPF/DKIM/DMARC/PTR'nin dördünü de kuruyor — dördü de şart.
- İlk gün yüksek hacim gönderme; OTP trafiği zaten düşük hacimli, bu iyi.
- Ücretsiz kaydol: [Google Postmaster Tools](https://postmaster.google.com) ve
  Microsoft [SNDS](https://sendersupport.olc.protection.outlook.com/snds/) +
  [JMRP](https://sendersupport.olc.protection.outlook.com/pm/).
- Kurduktan sonra [mail-tester.com](https://www.mail-tester.com) ile **10/10** hedefle.
- Yine de reddedilirsen: `MAIL_RELAYHOST` ile smarthost'a geç. Domain, DKIM
  imzası ve DNS yine senin kalır; sadece son teslimat başkasının IP'sinden
  yapılır. Kod bunu destekliyor (bkz. bölüm 6).

---

## 3. Ne kurulur

```
                 ┌──────────────────┐
   signaling ───▶│ postfix          │──── 25/tcp ───▶ Gmail / Outlook MX
   (587, SASL,   │ send-only        │
    STARTTLS)    │ mail.elcim.app   │
                 └────────┬─────────┘
                          │ milter 8891
                 ┌────────▼─────────┐
                 │ opendkim         │  DKIM imzalama
                 └──────────────────┘
```

- Host'a **hiçbir port publish edilmez.** Postfix'e yalnızca uygulama
  stack'inin docker ağından, `mail.elcim.app` takma adıyla ulaşılır.
- Submission (587) **SASL zorunlu + STARTTLS zorunlu**. Kimlik doğrulamayan
  hiçbir istemci mail veremez (`permit_sasl_authenticated, reject`).
- `mydestination` ve `relay_domains` boş → open relay riski yok.
- OpenDKIM çökerse `milter_default_action = tempfail`: mail **imzasız
  gitmez**, kuyrukta bekler.

Dosyalar:

| Yol | Ne |
|-----|-----|
| `compose.mail.yml` | iki servislik stack |
| `.env.mail.example` | ortam değişkeni şablonu |
| `postfix/` | Dockerfile, `main.cf` şablonu, `master.cf`, SASL, entrypoint |
| `opendkim/` | Dockerfile, config şablonu, anahtar üreten entrypoint |
| `scripts/local-test.sh` | domain/VPS olmadan yerelde tam doğrulama |
| `scripts/preflight.sh` | **kurulumdan önce** uygunluk kontrolü |
| `scripts/issue-cert.sh` | Let's Encrypt sertifikası + yenilenme hook'u |
| `scripts/print-dns-records.sh` | eklenecek DNS kayıtlarını basar |
| `scripts/smoke-test.sh` | uçtan uca gönderim testi |

---

## 3.5 Ücretsiz deneme seçenekleri

Satın alma yapmadan önce denemek istersen.

**Önce şunu bil: giden 25/tcp veren ücretsiz VPS yoktur.** Oracle Cloud Always
Free, GCP free tier, AWS free tier ve Azure 25/tcp'yi kalıcı bloklar, istisna
vermezler. Ücretsiz her yol smarthost'tan (bölüm 6) geçer.

### A) Yerel test — domain yok, sunucu yok, 0 TL
```bash
./scripts/local-test.sh
```
İzole bir docker ağında self-signed sertifikayla stack'i ayağa kaldırır,
15 testi koşar, sonra her şeyi temizler. Doğruladıkları: DKIM anahtar
üretimi ve imzalama, STARTTLS, SASL, 25/tcp'nin dinlenmemesi, open relay
reddi, hatalı parola reddi, sertifika doğrulaması, kuyruk politikası.

Doğrulayamadıkları: gerçek teslimat, SPF/DMARC hizası, PTR — bunlar gerçek
domain ve gerçek IP ister.

### B) Ücretsiz relay ile gerçek teslimat — domain gerekli
`MAIL_RELAYHOST` ile ücretsiz bir SMTP relay'e bağlan. Domain, DKIM anahtarı
ve SPF/DMARC senin kalır; Gmail'de gerçek `SPF: PASS, DKIM: PASS, DMARC: PASS`
görürsün.

| Relay | Ücretsiz kota | Kendi domain + DKIM |
|-------|---------------|---------------------|
| Brevo | 300 mail/gün, süresiz | Evet |
| Mailjet | 6.000/ay (200/gün) | Evet |
| MailerSend | 3.000/ay | Evet |
| SMTP2GO | 1.000/ay | Evet |

Domain tarafı: gerçek bedava domain artık yok (Freenom kapandı).
**afraid.org FreeDNS** ücretsiz subdomain verir ve TXT kaydı desteklediği için
SPF/DKIM/DMARC kurulabilir. Alternatif: `.xyz` gibi bir TLD ilk yıl ~1–2 $.

> DuckDNS ve nip.io **işe yaramaz** — `mail._domainkey.<ad>` altına TXT
> koyamazsın, DKIM kurulamaz.

### C) Oracle Cloud Always Free VM — süresiz 0 TL barındırma
4 ARM çekirdek / 24 GB RAM, gerçekten süresiz ücretsiz. Image'lar
`debian:12-slim` tabanlı, ARM64'te sorunsuz çalışır. 25/tcp kapalı olduğu
için B'deki relay ile birleştirmen gerekir.

---

## 4. Kurulum

### 4.0 — Ön koşullar
Domain alınmış, VPS alınmış, Docker + Docker Compose kurulu, uygulama stack'i
ayakta (mail stack onun ağına bağlanacak).

### 4.1 — Uygunluk kontrolü (satın alma sonrası İLK iş)
```bash
apt-get update && apt-get install -y dnsutils openssl curl
MAIL_HOSTNAME=mail.elcim.app ./scripts/preflight.sh
```
Giden 25/tcp "ENGELLI" derse önce onu çöz. Bölüm 6'ya bak.

### 4.2 — DNS: A kaydı ve PTR
```
A     mail.elcim.app   ->  <VPS IP>      (Cloudflare kullanıyorsan proxy KAPALI)
PTR   <VPS IP>         ->  mail.elcim.app  (VPS panelinden, DNS panelinden değil)
```
Yayılmasını bekle, sonra doğrula:
```bash
dig +short A mail.elcim.app
dig +short -x <VPS IP>
```
İkisi birbirini tutmalı.

### 4.3 — Ortam dosyası ve parolalar
```bash
cp .env.mail.example .env.mail
chmod 600 .env.mail
$EDITOR .env.mail          # MAIL_DOMAIN, MAIL_HOSTNAME, SMTP_FROM, CERT_EMAIL

mkdir -p /etc/elcim/secrets && chmod 700 /etc/elcim/secrets
openssl rand -base64 32 | tr -d '\n' > /etc/elcim/secrets/smtp_password
chmod 600 /etc/elcim/secrets/smtp_password
```

### 4.4 — TLS sertifikası
```bash
./scripts/issue-cert.sh
```
`MAIL_TLS_DIR`'in `/etc/letsencrypt/live/mail.elcim.app` olduğunu doğrula.
Script yenilenme sonrası postfix'i yeniden başlatan deploy hook'u da kurar.

> Sertifika **zorunlu**. İstemci tarafı `starttls.required=true` ile bağlanıp
> hostname doğrular; self-signed sertifikayla OTP gönderimi çalışmaz.

### 4.5 — Stack'i başlat
```bash
docker network ls | grep egress          # APP_NETWORK adını doğrula
docker compose --env-file .env.mail -f compose.mail.yml up -d --build
docker compose --env-file .env.mail -f compose.mail.yml logs -f
```
DKIM anahtarı ilk açılışta üretilir ve `dkim-keys` volume'unda kalıcı olur.

### 4.6 — Kalan DNS kayıtları
```bash
./scripts/print-dns-records.sh
```
Bastığı SPF, DKIM ve DMARC TXT kayıtlarını DNS paneline ekle.

> SPF'te dikkat: domain'de zaten bir `v=spf1` kaydı varsa **ikincisini ekleme**,
> mevcut olanı düzenle. İki SPF kaydı SPF'i tamamen geçersiz kılar.

### 4.7 — Test
```bash
./scripts/smoke-test.sh kendi-adresin@gmail.com
```
Gmail'de gelen maili aç → "Orijinali göster" → `SPF: PASS`, `DKIM: PASS`,
`DMARC: PASS` görmelisin. Ardından mail-tester.com ile 10/10 hedefle.

### 4.8 — Uygulamayı bağla
Uygulama stack'inin `.env` dosyasında Gmail ayarlarını bunlarla değiştir:

```dotenv
SMTP_HOST=mail.elcim.app
SMTP_PORT=587
SMTP_USERNAME=elcim-otp
SMTP_FROM=noreply@elcim.app
SMTP_TLS=starttls
# compose.privacy.yml bu yolu HOST yolu olarak okur ve container icine
# /run/secrets/smtp_password olarak baglar. Mail stack'iyle AYNI dosya olmali.
SMTP_PASSWORD_FILE=/etc/elcim/secrets/smtp_password
```

- `SMTP_HOST` docker ağ takma adıyla çözülür; SMTP trafiği hiç internete çıkmaz.
- Kullanıcı adı ve parola dosyası mail stack'indekiyle **birebir aynı** olmalı.
- `SMTP_TLS=starttls` zorunlu: `ProductionDeploymentPolicy` yalnızca
  `starttls` veya `ssl` kabul eder, aksi halde sunucu açılışta durur.

Yeniden başlat ve gerçek kayıt akışıyla bir OTP iste:
```bash
docker compose -f compose.privacy.yml up -d --force-recreate signaling
docker compose --env-file .env.mail -f compose.mail.yml logs -f postfix
```

---

## 5. İşletme

```bash
# Kuyruk
docker compose --env-file .env.mail -f compose.mail.yml exec postfix postqueue -p
# Kuyruğu hemen dene
docker compose --env-file .env.mail -f compose.mail.yml exec postfix postqueue -f
# Teslimat günlüğü
docker compose --env-file .env.mail -f compose.mail.yml logs -f postfix
```

**DKIM anahtarını kaybetme.** `dkim-keys` volume'u silinirse yeni anahtar
üretilir ve DNS'teki eski public key ile eşleşme kopar; tüm mailler DKIM'den
düşer. Yedek:
```bash
docker compose --env-file .env.mail -f compose.mail.yml exec -T opendkim \
  tar cf - /var/lib/opendkim/keys > dkim-keys-backup.tar
```

**DMARC sıkılaştırma.** Birkaç gün `p=none` raporu topla, SPF+DKIM'in hizalı
geçtiğini doğrula, sonra sırasıyla `p=quarantine` → `p=reject`.

---

## 6. Giden 25/tcp açılmıyorsa — smarthost

`MAIL_RELAYHOST` doldurulursa Postfix teslimatı bir relay üzerinden yapar.
Domain, DKIM imzası ve SPF/DMARC hizası **yine sende kalır**; sadece son
bacak başkasının IP'sinden çıkar. Relay bağlantısında TLS zorunludur
(`smtp_tls_security_level = encrypt`).

`.env.mail`:
```dotenv
MAIL_RELAYHOST=[smtp.saglayici.com]:587
RELAY_USERNAME=...
RELAY_PASSWORD_FILE=/etc/elcim/secrets/relay_password
```
SPF kaydını da relay'i kapsayacak şekilde güncelle (sağlayıcının `include:`
değerini ekle).

---

## 7. Sorun giderme

| Belirti | Sebep | Çözüm |
|---------|-------|-------|
| `postfix check basarisiz` | Sertifika `MAIL_HOSTNAME`'i kapsamıyor | `issue-cert.sh`'ı doğru FQDN ile çalıştır |
| İstemcide `Could not connect to SMTP host` | Postfix app ağında değil | `APP_NETWORK` doğru mu, `docker network inspect` |
| `535 Authentication failed` | Parola iki tarafta farklı | Aynı `smtp_password` dosyasını kullan, postfix'i yeniden başlat |
| Mail kuyrukta kalıyor, `Connection timed out` | Giden 25/tcp engelli | `preflight.sh`, sonra bölüm 6 |
| Gmail spam'e atıyor | SPF/DKIM/DMARC/PTR'den biri eksik | "Orijinali göster" ile hangisinin FAIL olduğuna bak |
| Outlook `550 5.7.1 ... blocked` | Yeni IP itibarı | SNDS + JMRP kaydı, ya da bölüm 6 |
| DKIM `permerror` | TXT kaydı bölünmüş/eksik | `print-dns-records.sh` çıktısını tek parça yapıştır |

---

## 8. Bu stack üzerinde doğrulananlar

Kod, self-signed sertifikayla izole bir docker ağında uçtan uca çalıştırılıp
test edildi. Doğrulanan davranışlar:

| Test | Sonuç |
|------|-------|
| Postfix + OpenDKIM image build | Geçti |
| DKIM anahtar üretimi + TXT kaydının basılması | Geçti |
| Submission (587) STARTTLS + SASL PLAIN ile mail kabulü | Geçti |
| Giden maile DKIM imzası eklenmesi (`d=`, `s=` doğru) | Geçti |
| **25/tcp dinlenmiyor** (send-only) | Geçti — `ConnectionRefused` |
| **STARTTLS öncesi AUTH sunulmuyor** | Geçti — `AUTH extension not supported` |
| **Open relay reddi** (auth'suz gönderim) | Geçti — `554 5.7.1` |
| **Hatalı parola reddi** | Geçti — `535 5.7.8` |
| **Sertifika doğrulaması** (güvenilmeyen CA) | Geçti — `CERTIFICATE_VERIFY_FAILED` |
| Teslim edilemeyen NDR'lerin kuyrukta birikmemesi | Geçti — kuyruk boş |
| `postfix check` uyarısız | Geçti |
| `docker compose config` render | Geçti |

Gerçek teslimat (Gmail/Outlook'a ulaşma, SPF/DKIM/DMARC PASS) yalnızca gerçek
domain, gerçek IP ve PTR ile ölçülebilir — bunu 4.7'deki adımlarla sen
doğrulayacaksın.

### Test sırasında bulunup düzeltilen kusurlar

1. `opendkim-genkey` `openssl` CLI'ına ihtiyaç duyuyor; image'da yoktu,
   anahtar üretimi `status 127` ile çöküyordu.
2. `cap_drop: [ALL]` **CAP_FSETID**'yi de düşürdüğü için entrypoint'teki
   `postfix set-permissions` çağrısı `postqueue`/`postdrop` üzerindeki setgid
   bitini sessizce siliyordu. Çağrı kaldırıldı; izinler build sırasında
   sabitleniyor.
3. Config dosyaları build host'unun umask'ıyla `664` kopyalanıp `postfix check`
   uyarısı üretiyordu; Dockerfile'da izinler açıkça sabitlendi.
4. `main.cf.tmpl` `/etc/postfix` içindeydi ve `postfix check` onu tanımadığı
   için uyarıyordu; `/usr/local/share/elcim/` altına taşındı.
5. `smoke-test.sh` içindeki `docker run` `-i` bayrağı olmadan stdin'i attach
   etmiyordu; `python -` boş program okuyup **sessizce başarıyla çıkıyordu**.
