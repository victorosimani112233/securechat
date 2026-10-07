# Kötüye kullanım bildirimleri ve moderasyon

Apple 1.2 ile Google Play'in UGC ve çocuk güvenliği (CSAE) politikaları,
herkese açık bir iletişim uygulamasında kullanıcının başkasını
**engelleyebilmesini**, **bildirebilmesini** ve bildirimlere **24 saat içinde**
yanıt verilmesini istiyor. Bu belge sunucu tarafını ve inceleme akışını anlatır.

## Ne saklanır, ne saklanmaz

| Alan | Saklanır mı | Not |
|---|---|---|
| Mesaj, arama, dosya içeriği | **Hayır** | İstemci eklemez; sunucu bilinmeyen alan içeren gövdeyi `400` ile reddeder. |
| Hedef hesap kimlikleri | Evet | İnceleme sonucu hesaba işlem yapabilmek için gerekli. Grup bildiriminde grubun yöneticileri, yönetici yoksa üyeler (en çok 32). |
| Sebep | Evet | `spam`, `harassment`, `inappropriate`, `child_safety`, `impersonation`, `other` |
| Bildirenin notu | Evet | En çok 500 karakter, isteğe bağlı. |
| Bildiren kişi | **Düz kimlikle hayır** | Amaca ayrılmış blind index (`abuse-reporter`). İnceleyen kişi bildireni göremez. |

Engelleme **sunucuya hiç gitmez**; engel listesi yalnızca cihazdadır.

**Saklama** (`PrivacyRetentionWorker`, 6 saatte bir): kapatılan bildirim 30 gün
sonra, hiçbir bildirim 180 günden uzun tutulmaz.

**Hesap silme:** silinen hesabın hedef olduğu satırlar gider. Silinen hesabın
açtığı bildirimler kalır ama bildirenle bağı koparılır.

## Uçlar

| Uç | Kimlik | Ne yapar |
|---|---|---|
| `POST /api/v1/reports` | Kullanıcı access token | Bildirim alır; `202`. Hesap başına günde 20. |
| `GET /api/v1/admin/reports` | `REPORTS_ADMIN_TOKEN` | Açık bildirimler, en eski önce. `?status=all` kapalıları da getirir. |
| `POST /api/v1/admin/reports/{id}/close` | `REPORTS_ADMIN_TOKEN` | `{"resolution":"no_action"}` veya `"account_removed"`. |
| `POST /api/v1/admin/accounts/{userId}/remove` | `REPORTS_ADMIN_TOKEN` | Hesabı, kullanıcının kendi silme yoluyla aynı şekilde kaldırır. |

`REPORTS_ADMIN_TOKEN` (veya `REPORTS_ADMIN_TOKEN_FILE`) en az 32 karakter
olmalıdır. Tanımlı değilse admin uçları `404` döner; yanlış token da `404`
alır ve kimliksiz `REPORTS_ADMIN_REJECTED` güvenlik sayacını artırır.

## Günlük inceleme

```bash
TOKEN=$(cat /run/secrets/reports_admin_token)   # veya env dosyasından
API=https://<alan-adı>

# Açık bildirimler
curl -s -H "Authorization: Bearer $TOKEN" "$API/api/v1/admin/reports" | jq

# İşlem gerekmiyorsa kapat
curl -s -X POST -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"resolution":"no_action"}' "$API/api/v1/admin/reports/<reportId>/close"

# İhlal varsa: hesabı kaldır, sonra bildirimi kapat
curl -s -X POST -H "Authorization: Bearer $TOKEN" \
  "$API/api/v1/admin/accounts/<userId>/remove"
curl -s -X POST -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"resolution":"account_removed"}' "$API/api/v1/admin/reports/<reportId>/close"
```

`child_safety` sebebiyle gelen ve ihlal içeren bir bildirimde hesabı kaldırmak
yetmez: `deploy/site/child-safety.html`'de taahhüt edildiği gibi yetkili
makamlara (EGM Siber, İhbar Web) bildirim yapılır.

**Bilinen sınır:** kaldırılan bir kişi aynı e-posta ile yeniden kayıt
olabilir. Kalıcı yasaklama listesi henüz yok.

## Bildirim alarmı (Grafana)

Sunucu kimliksiz `securechat_abuse_reports_total` sayacını yayınlar (bearer
korumalı `/metrics`). 24 saat sözünü kaçırmamak için Grafana'da bir alarm
kuralı:

```promql
increase(securechat_abuse_reports_total[15m]) > 0
```

Bildirim kanalı olarak e-posta veya telefon bildirimi seçilir. Sayaç
yalnızca toplamı tutar; sebep, hesap veya IP etiketi yoktur.
