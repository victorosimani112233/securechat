# Kendi Mail Sunucusu — Kurulum Kaydı

**Son güncelleme:** 2026-09-15
**Durum:** Test kurulumu çalışıyor. Asıl domain ve uygulama bağlantısı bekliyor.

Bu dosya yapılanların kaydıdır. Aradan zaman geçtiğinde ya da yeni bir oturumda
devam ederken buradan okumaya başla.

---

## 1. Amaç

Uygulamanın OTP/doğrulama maillerini Google/Gmail SMTP yerine kendi altyapımızdan
göndermek. Kapsam **yalnızca giden transactional mail** — gelen kutusu, IMAP,
webmail yok.

**Uygulama kodunda değişiklik yapılmadı ve gerekmiyor.**
`server_hardened/signaling-server/src/main/kotlin/com/securechat/signaling/EmailService.kt`
zaten sağlayıcıdan bağımsız `SMTP_*` ortam değişkenleri kullanıyor. Geçiş sadece
`.env` değişikliği.

---

## 2. Ne kuruldu

`flutter_securechat/server_hardened/mailserver/` altında iki servislik bir stack:

| Servis | Görev |
|--------|-------|
| **postfix** | Send-only MTA. 587 submission dinler (STARTTLS + SASL zorunlu). 25/tcp **dinlemez**. |
| **opendkim** | Giden mailleri DKIM ile imzalar (milter, yalnız iç ağ). |

Host'a hiçbir port publish edilmiyor. Uygulama sunucusu postfix'e docker ağı
üzerinden `mail.<domain>` takma adıyla ulaşıyor.

### Dosyalar

| Yol | Ne |
|-----|-----|
| `compose.mail.yml` | Ana stack. Uygulama stack'inin `external` ağına bağlanır. |
| `compose.standalone.yml` | Override. Uygulama stack'i **olmadan** çalıştırmak için. |
| `.env.mail.example` | Ortam değişkeni şablonu |
| `.env.mail` | Gerçek yapılandırma. **gitignore'da**, chmod 600. |
| `postfix/` | Dockerfile, `main.cf` şablonu, `master.cf`, SASL config, entrypoint |
| `opendkim/` | Dockerfile, config şablonu, anahtar üreten entrypoint |
| `scripts/local-test.sh` | Domain/sunucu olmadan yerelde 15 testlik doğrulama |
| `scripts/preflight.sh` | VPS alındıysa: giden 25/tcp + PTR + blocklist kontrolü |
| `scripts/issue-cert.sh` | Let's Encrypt sertifikası + yenilenme hook'u |
| `scripts/print-dns-records.sh` | Eklenecek DNS kayıtlarını basar |
| `scripts/smoke-test.sh` | Uçtan uca gerçek gönderim testi |
| `README.md` | Adım adım kurulum kılavuzu |

Git: dizin `7a7995b` ile commit edilmiş. `compose.standalone.yml` henüz untracked,
birkaç dosya da commit sonrası değiştirildi.

---

## 3. Mevcut test kurulumu

### Değerler

| Ayar | Değer |
|------|-------|
| Domain | `tereaiqos.online` (Namecheap, ~1 $, 2026-09-15 alındı, 2027-09-15'te biter) |
| Mail hostname | `mail.tereaiqos.online` |
| Gönderen | `noreply@tereaiqos.online` |
| DNS | Cloudflare (`ian.ns.cloudflare.com`, `phoenix.ns.cloudflare.com`) |
| DKIM selector | `mail` |
| Submission kullanıcısı | `elcim-otp` |
| Relay | Brevo — `[smtp-relay.brevo.com]:587` |
| Relay login | `b9731f001@smtp-brevo.com` |
| Docker ağı | `elcim-mail-standalone` |
| Sertifika | `~/.elcim/letsencrypt/live/mail.tereaiqos.online`, **2026-12-14**'e kadar |

### Secret dosyaları

Hiçbiri repoda değil. `/etc/elcim/secrets/`, kullanıcıya ait, `chmod 600`:

- `smtp_password` — postfix submission SASL parolası (rastgele üretildi)
- `cloudflare_token` — Cloudflare API token, `Zone:DNS:Edit` yetkili
- `relay_password` — Brevo SMTP key (`xsmtpsib-` ile başlar)

### Neden relay kullanıyoruz

Kendi makinemizde çalışıyoruz, giden 25/tcp yok. Relay (Brevo, ücretsiz 300/gün)
son teslimatı yapıyor. **Domain, DKIM anahtarı ve SPF/DMARC yine bizde** —
bağımsızlık korunuyor, sadece son bacak Brevo'nun IP'sinden çıkıyor.

Bu sayede **VPS satın almadan** gerçek teslimat testi yapılabildi.

---

## 4. DNS kayıtları (Cloudflare'de aktif)

| Tip | Ad | Değer | Kim için |
|-----|-----|-------|----------|
| TXT | `@` | `v=spf1 include:spf.efwd.registrar-servers.com include:spf.brevo.com ~all` | SPF — Namecheap forward + Brevo birleşik |
| TXT | `mail._domainkey` | `v=DKIM1;h=sha256;k=rsa;p=MIIBIjANBg...` | Bizim OpenDKIM |
| TXT | `_dmarc` | `v=DMARC1; p=none; rua=mailto:victorosim587@gmail.com; adkim=s; aspf=s; pct=100` | DMARC |
| CNAME | `brevo1._domainkey` | `b1.tereaiqos-online.dkim.brevo.com` | Brevo DKIM |
| CNAME | `brevo2._domainkey` | `b2.tereaiqos-online.dkim.brevo.com` | Brevo DKIM |
| CNAME | `mail`, `r.mail`, `img.mail` | `*.brand.brevosend.com` | Brevo takip — **gereksizdi, eklendi, zararsız** |
| MX ×5 | `@` | `eforward1-5.registrar-servers.com` | Namecheap mail yönlendirme (DMARC raporu okumak için) |

**Kurallar:**
- Tek bir SPF kaydı olmalı. İkinci `v=spf1` eklenirse SPF tamamen çöker.
- Tek bir DMARC kaydı olmalı. Brevo'nun önerdiği `_dmarc` **eklenmedi** — bizimki duruyor.
- Relay kullanıldığı için `mail` için **A kaydı gerekmiyor** ve PTR de gerekmiyor.

---

## 5. Test sonuçları

### Yerel doğrulama — `./scripts/local-test.sh`

**15/15 geçti.** Domain ve sunucu gerektirmez, kendini temizler.

DKIM anahtar üretimi + imzalama, STARTTLS, SASL, 25/tcp dinlenmemesi, open relay
reddi, TLS'siz AUTH reddi, hatalı parola reddi, sertifika doğrulaması, kuyruk
politikası, `postfix check` uyarısız.

### Gerçek gönderim

Brevo üzerinden teslim edildi:

```
to=<...>, relay=smtp-relay.brevo.com[172.246.243.66]:587,
dsn=2.0.0, status=sent (250 2.0.0 OK)
```

### mail-tester sonucu

| | 1. test | 2. test (gövde uzatıldıktan sonra) |
|---|---|---|
| Toplam | 4.3/10 | 4.4/10 |
| SpamAssassin | −5.2 | **−4.1** |

**Kimlik doğrulaması tamamen geçiyor:**

```
+0.1   DKIM_VALID      Message has at least one valid DKIM signature
+0.1   DKIM_VALID_AU   valid DKIM signature from author's domain
+0.001 SPF_PASS        sender matches SPF record
+0.001 SPF_HELO_PASS   HELO matches SPF record
```

`DKIM_VALID_AU` kritik olan: imza **yazar domain'inden** ve hizalı.

**Puanı düşüren:**

```
-0.5    FROM_SUSPICIOUS_NTLD
-1.999  FROM_SUSPICIOUS_NTLD_FP
-1.0    PDS_OTHER_BAD_TLD      URI: r.mail.tereaiqos.online (online)
------
-3.5    = sadece .online uzantısı
-0.7    HTML_IMAGE_ONLY_20     = Brevo takip pikseli
-0.1    gerisi (ihmal edilebilir)
```

**Sonuç: −4.1'in −3.5'i uzantıdan.** Yapılandırmayla düzeltilebilecek her şey
düzeldi. `.com` gibi itibarlı bir uzantıda o −3.5 hiç olmayacak; SpamAssassin
~−0.6'ya iner, mail-tester 9/10 bandına çıkar.

### Bilinen açık konu

SpamAssassin 1.1 puan iyileşti ama mail-tester toplamı 4.3 → 4.4 kaldı. Demek ki
mail-tester'ın başka bir kalemi (muhtemelen takip linkleri) puan kırıyor. Sayfanın
SpamAssassin dışındaki bölümleri henüz incelenmedi.

---

## 6. Yol boyunca bulunup düzeltilen hatalar

Hepsi test sırasında ortaya çıktı, hepsi düzeltildi.

1. **`opendkim-genkey` `openssl` CLI'ına muhtaç.** Image'da yoktu, anahtar üretimi
   `status 127` ile çöküyordu. → Dockerfile'a `openssl` eklendi.

2. **`cap_drop: [ALL]` CAP_FSETID'yi de düşürüyor.** Entrypoint'teki
   `postfix set-permissions`, `postqueue`/`postdrop` setgid bitini sessizce
   siliyordu. → Çağrı kaldırıldı, izinler build sırasında sabitlendi.

3. **Config dosyaları build host'unun umask'ıyla `664` kopyalanıyordu**,
   `postfix check` uyarı veriyordu. → Dockerfile'da izinler açıkça sabitlendi.

4. **`main.cf.tmpl` `/etc/postfix` içindeydi**, `postfix check` tanımadığı dosya
   için uyarıyordu. → `/usr/local/share/elcim/` altına taşındı.

5. **`smoke-test.sh`'te `docker run` `-i` bayrağı yoktu.** stdin attach edilmiyor,
   `python -` boş program okuyup **sessizce başarıyla çıkıyordu**.

6. **Bash alıntı ayrıştırma hatası — en sinsisi.**
   `${CERT_EMAIL:?... Let's Encrypt ...}` içindeki kesme işareti bash'in alıntı
   ayrıştırıcısını açıyordu; aşağıdaki `certbot'a` kazara kapatıyordu. `bash -n`
   geçiyor ama aradaki satırlar yanlış ayrıştırılıyordu. → Kontrol `${VAR:?}`
   dışına taşındı. **Kural: `${VAR:?mesaj}` içinde kesme işareti kullanma.**

7. **`. "./$ENV_FILE"` mutlak yolu bozuyordu.** Üç script'te aynı hata. → `case`
   ile mutlak/göreli ayrımı yapıldı.

8. **`.env.mail`'de `<<DOLDUR>>` yer tutucuları heredoc operatörü olarak
   ayrıştırılıyordu**, dosyayı `source` eden her script kırılıyordu. → `DOLDUR_`
   önekine çevrildi. **Kural: env dosyalarında `<`, `>`, tırnak kullanma.**

9. **Let's Encrypt + Docker symlink tuzağı.** `live/<domain>` içindeki dosyalar
   `archive/`'e giden sembolik link. Sadece `live/<domain>` mount edilince linkler
   kırılıyordu. → Entrypoint artık hem düz dizini hem letsencrypt kökünü tanıyor,
   `cp -L` ile kopyalıyor. `MAIL_TLS_DIR` artık **letsencrypt kökünü** gösteriyor.

10. **Relay bloğu `smtp_tls_security_level`'i ikinci kez tanımlıyordu**,
    "overriding earlier entry" uyarısı üretiyordu. → Taban değerler `sed` ile
    silinip sonra ekleniyor.

11. **`print-dns-records.sh` relay'den habersizdi.** Doğrudan teslimat varsayıp
    `v=spf1 a:mail.<domain> -all` ve gereksiz bir A kaydı basıyordu. → Artık
    `MAIL_RELAYHOST` varsa relay'in SPF include'unu üretiyor, A/PTR bölümünü
    "gerekmez" diye işaretliyor, ve **canlı DNS'i sorgulayıp mevcut SPF kaydını
    tespit ederek birleştirilmiş değeri kendisi öneriyor.**

12. **Sistem certbot'u bozuk** (`ImportError: cannot import name 'implements'
    from 'zope.interface'` — `~/.local` altındaki yeni sürüm sistemdekini
    gölgeliyor). → `issue-cert.sh` artık `CERTBOT_RUNTIME=auto` ile otomatik
    Docker'a düşüyor. Sertifikalar `~/.elcim/letsencrypt` altına **kullanıcıya
    ait** yazılıyor, sudo gerekmiyor.

13. **Brevo SMTP login hesap e-postası DEĞİL.** `victorosim587@gmail.com` ile
    `535 5.7.8 Authentication failed` alındı. Doğrusu Brevo'nun ürettiği
    `b9731f001@smtp-brevo.com`.

---

## 7. Günlük kullanım

Hepsi `flutter_securechat/server_hardened/mailserver/` içinden:

```bash
# Stack'i ayağa kaldır (uygulama stack'i olmadan)
docker compose --env-file .env.mail \
    -f compose.mail.yml -f compose.standalone.yml up -d --build

# Durum
docker compose --env-file .env.mail \
    -f compose.mail.yml -f compose.standalone.yml ps

# Log
docker compose --env-file .env.mail \
    -f compose.mail.yml -f compose.standalone.yml logs -f postfix

# Kuyruk
docker compose --env-file .env.mail \
    -f compose.mail.yml -f compose.standalone.yml exec postfix postqueue -p

# Test maili
./scripts/smoke-test.sh hedef@ornek.com

# DNS kayıtlarını bas
./scripts/print-dns-records.sh

# Sertifika (dry-run ile önce dene)
CERTBOT_EXTRA_ARGS=--dry-run ./scripts/issue-cert.sh
./scripts/issue-cert.sh

# Yerel tam doğrulama
./scripts/local-test.sh
```

**DKIM anahtarını kaybetme.** `dkim-keys` volume'u silinirse yeni anahtar üretilir,
DNS'teki public key ile eşleşme kopar, tüm mailler DKIM'den düşer:

```bash
docker compose --env-file .env.mail -f compose.mail.yml -f compose.standalone.yml \
  exec -T opendkim tar cf - /var/lib/opendkim/keys > dkim-keys-backup.tar
```

---

## 8. Kalan işler

### Kısa vadede

- [ ] mail-tester'ın SpamAssassin dışındaki bölümlerini incele (4.3 → 4.4 neden
      yerinde saydı)
- [ ] İstenirse Brevo takibini kapat — `HTML_IMAGE_ONLY_20` (−0.7) gider ve bizim
      OpenDKIM imzamız Brevo'nun HTML değiştirmesinden korunur. Brevo'daki
      "Anonymous email tracking" ayarı **bu değil**, o sadece veriyi kişilerle
      ilişkilendirmeyi kapatıyor.

### Asıl kuruluma geçerken

- [ ] **Asıl domain'i al.** `elcim.com` ve `elcim.org` alınmış. Müsait olanlar
      (2026-09-15 itibarıyla): `elcim.net`, `elcim.app`, `elcim.dev`,
      `elcimapp.com`, `getelcim.com`. Natro'da `elcimapp.com` 3 $ görülmüştü.
      **Erken al** — domain yaşı gönderim itibarında sinyal, kullanmasan da yaşlansın.
- [ ] `.env.mail`'de `MAIL_DOMAIN`, `MAIL_HOSTNAME`, `SMTP_FROM`, `MAIL_TLS_DIR`
      güncelle; yeni domain için sertifika al; DNS kayıtlarını yeniden bas ve ekle.
- [ ] DMARC'ı sıkılaştır: birkaç gün `p=none` raporu topla, hizalamayı doğrula,
      sonra `p=quarantine`, en son `p=reject`.
- [ ] **Uygulamayı bağla.** Uygulama stack'inin `.env` dosyasında:
      ```dotenv
      SMTP_HOST=mail.<domain>
      SMTP_PORT=587
      SMTP_USERNAME=elcim-otp
      SMTP_FROM=noreply@<domain>
      SMTP_TLS=starttls
      SMTP_PASSWORD_FILE=/etc/elcim/secrets/smtp_password
      ```
      `compose.standalone.yml` olmadan, `APP_NETWORK` uygulama stack'inin ağına
      ayarlanmış olarak çalıştır.
      `SMTP_TLS` **starttls veya ssl olmalı** — `ProductionDeploymentPolicy`
      başka değer kabul etmez, sunucu açılışta durur.

### VPS kararı (opsiyonel)

Relay yerine doğrudan teslimat istenirse **giden 25/tcp açık ve PTR
düzenlenebilir** bir VPS gerekir. OVH/Netcup varsayılan açık; Hetzner/Contabo
ticket ile açıyor; DigitalOcean/Vultr/Linode/AWS pratikte açmıyor. Sunucuyu alır
almaz ilk iş `./scripts/preflight.sh`.

Relay yolu kişisel kullanım için zaten yeterli — Brevo ücretsiz katmanı 300
mail/gün, OTP trafiği bunun çok altında.

---

## 9. Öğrenilen dersler

- **Ucuz TLD mail için pahalıya patlıyor.** `.online` tek başına −3.5 SpamAssassin
  puanı götürdü. `.xyz`, `.site`, `.top` aynı kovada. Mail gönderilen domain
  `.com`/`.net` gibi eski bir TLD olmalı.
- **mail-tester, Gmail'in vermediği bilgiyi veriyor.** Gmail maili sessizce
  düşürdüğünde sebebini söylemez; mail-tester kimlik doğrulamayı itibar cezasından
  ayırdığı için kurulumun doğru olduğunu kanıtlayabildik.
- **Relay, bağımsızlıktan taviz vermeden sunucu masrafını sıfırlıyor.** Domain,
  DKIM ve DNS bizde kalıyor.
- **DNS-01 sayesinde public sunucu olmadan gerçek sertifika alınabiliyor.**
- Teorik riskleri test et: `mail` CNAME'inin sertifika yenilemesini bozacağından
  şüphelenildi, dry-run ile denendi, bozmadığı görüldü.
