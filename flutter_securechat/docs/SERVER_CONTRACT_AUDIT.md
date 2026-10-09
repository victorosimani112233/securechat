# Hardened Ktor Server Contract Audit

Bu dosya `tool/generate_server_contract_audit.dart` ile uretilir; elle duzenlenmez.

Otorite sunucudur. Her route icin **kodda calisan guard** ayristirilir ve tablodaki beyanla karsilastirilir; ayrilirsa arac hata koduyla doner. Guard'siz bir route, neden guard'siz oldugu yazilana kadar denetimi kirar.

## HTTP ve WebSocket route eslemesi

| Server route | Guard | Durum | Flutter kaniti | Karar |
|---|---|---|---|---|
| `GET /` | `public` | SERVER_ONLY | `flutter_securechat/server_hardened/signaling-server/src/main/kotlin/com/securechat/signaling/HttpRoutes.kt` | Servis karsilama yolu; sabit cevap, kimlik tasimaz. |
| `GET /api/v1/admin/reports` | `adminToken` | SERVER_ONLY | `flutter_securechat/server_hardened/docs/ABUSE_REPORTS.md` | Moderasyon listesi; istemci cagirmaz, kullanici token'i gecmez. |
| `GET /api/v1/directory/config` | `public` | COVERED | `flutter_securechat/lib/src/contacts/private_contact_discovery.dart` | Pinlenmis blind-RSA OPRF acik yapilandirmasi; kayit oncesi gerektigi icin public. |
| `GET /api/v1/directory/snapshot` | `auth` | COVERED | `flutter_securechat/lib/src/contacts/private_contact_discovery.dart` | Token-etiketli ve token-sealed uyelik anlik goruntusu. |
| `GET /api/v1/ice/config` | `auth` | COVERED | `flutter_securechat/lib/src/media/ice_server_fetcher.dart` | Kisa omurlu TURN yapilandirmasi. |
| `GET /api/v1/latest-version` | `public` | SERVER_ONLY | `flutter_securechat/server_hardened/signaling-server/src/main/kotlin/com/securechat/signaling/HttpRoutes.kt` | Magaza/surum politikasi yolu; Flutter istemcisinde cagiran yok. |
| `GET /api/v1/prekeys/status` | `auth` | SERVER_ONLY | `flutter_securechat/server_hardened/signaling-server/src/main/kotlin/com/securechat/signaling/HttpRoutes.kt` | libsignal v1 prekey yolu. Istemci fa0320c ile birakti (mesaj ve kurtarma Olm kullanir); route eski istemciler icin sunucuda acik. Kaldirma, libsignal kolonlarini dusuren migration ile birlikte. |
| `GET /api/v1/sfu/room/{groupId}` | `auth` | WS_EQUIVALENT | `flutter_securechat/lib/src/media/call_manager.dart` | Istemci ayni bilgiyi WebSocket grup cagri sinyalleriyle alir; HTTP yolu operasyon/kurtarma gorunumu. |
| `GET /api/v1/users/{userId}/prekeys` | `auth` | COVERED | `flutter_securechat/lib/src/crypto/vodozemac/olm_pre_key_bundle_api.dart` | Peer bundle cekimi. Guard `requireServicePrincipal` IDI ve o haliyle kullanici token'ini kabul etmiyordu, yani hicbir istemci peer bundle'i cekemiyordu; tek prekey yolu haline gelince bu, oturum kurmayi tumuyle imkansiz kilardi. Kaldirilan v2 esdegeri zaten requirePrincipal kullaniyordu. Bot API kaldirilinca servis principal'i da kalkti; artik yalniz kullanici token'i. Numaralandirmanin siniri rate limit (120/saat), erisimi kapatmak degil. |
| `GET /api/v1/version` | `bearerToken` | SERVER_ONLY | `flutter_securechat/server_hardened/signaling-server/src/main/kotlin/com/securechat/signaling/HttpRoutes.kt` | Build kimligi operator bilgisidir; surum/commit anonim sizdirilmaz. |
| `GET /health` | `public` | COVERED | `flutter_securechat/lib/src/network/socket_diagnostics.dart` | Redakte edilmis uyumluluk yoklamasi; anonim cagrilabilir olmasi kasitli, stack ayrintisi dondurmez. |
| `GET /metrics` | `bearerToken` | SERVER_ONLY | `flutter_securechat/server_hardened/signaling-server/src/main/kotlin/com/securechat/signaling/HttpRoutes.kt` | Prometheus; istemciye acilmaz. |
| `GET /ready` | `bearerToken` | SERVER_ONLY | `flutter_securechat/server_hardened/signaling-server/src/main/kotlin/com/securechat/signaling/HttpRoutes.kt` | Readiness; bagimlilik durumu operator bilgisidir, bu yuzden metrics bearer token ardinda. |
| `POST /api/v1/account/delete` | `auth` | COVERED | `flutter_securechat/lib/src/auth/auth_api.dart` | Kimlik dogrulamali hesap silme. |
| `POST /api/v1/account/recovery-email/request` | `recoveryPrincipal` | COVERED | `flutter_securechat/lib/src/auth/auth_api.dart` | Kurtarma e-postasi kaydi baslatir; hesap sahibi olmak gerekir. |
| `POST /api/v1/account/recovery-email/status` | `recoveryPrincipal` | COVERED | `flutter_securechat/lib/src/auth/auth_api.dart` | Yalniz cagiranin KENDI hesabi icin bagli/bagli degil doner. Guard sart: guard'siz olsaydi hangi hesabin kurtarma e-postasi oldugunu soyleyen bir numaralandirma kehaneti olurdu. |
| `POST /api/v1/account/recovery-email/verify` | `recoveryPrincipal` | COVERED | `flutter_securechat/lib/src/auth/auth_api.dart` | Kurtarma e-postasi kaydini dogrular. |
| `POST /api/v1/admin/accounts/{userId}/remove` | `adminToken` | SERVER_ONLY | `flutter_securechat/server_hardened/docs/ABUSE_REPORTS.md` | Moderasyonla hesap kaldirma; kullanici silme yoluyla ayni temizlik. |
| `POST /api/v1/admin/reports/{reportId}/close` | `adminToken` | SERVER_ONLY | `flutter_securechat/server_hardened/docs/ABUSE_REPORTS.md` | Moderasyon karari kaydi. |
| `POST /api/v1/auth/login/complete` | `preAuth` | COVERED | `flutter_securechat/lib/src/auth/auth_api.dart` | Dogrulanmis giristen sonra access+refresh basar. |
| `POST /api/v1/auth/login/request` | `preAuth` | COVERED | `flutter_securechat/lib/src/auth/auth_api.dart` | E-posta ile giris baslatir. Token'i olmayan bir istemci cagirdigi icin guard yok; siniri rate limit (`recovery_request`) ve sunucunun hesap varligini sizdirmayan sabit cevabi kuruyor. |
| `POST /api/v1/auth/login/verify` | `preAuth` | COVERED | `flutter_securechat/lib/src/auth/secure_account_recovery_coordinator.dart` | Giris kodunu tuketir. Guard yerine gecen sey kodun kendisi. |
| `POST /api/v1/auth/logout` | `auth` | COVERED | `flutter_securechat/lib/src/auth/auth_api.dart` | Refresh tokeni iptali. |
| `POST /api/v1/auth/refresh` | `preAuth` | COVERED | `flutter_securechat/lib/src/auth/auth_api.dart` | Refresh tokeni tuketir ve dondurur. Access token gecerli olmadiginda da cagrilabilmesi gerekir, bu yuzden requireAuth yok. |
| `POST /api/v1/directory/evaluate` | `auth` | COVERED | `flutter_securechat/lib/src/contacts/private_contact_discovery.dart` | Sabit boyutlu korlenmis kisi degerlendirmesi. |
| `POST /api/v1/fcm/register` | `auth` | COVERED | `flutter_securechat/lib/src/push/push_service.dart` | FCM/APNs tasima tokeni kaydi. |
| `POST /api/v1/fcm/unregister` | `auth` | COVERED | `flutter_securechat/lib/src/push/push_service.dart` | Tasima tokeni silme. |
| `POST /api/v1/otp/request` | `public` | COVERED | `flutter_securechat/lib/src/auth/auth_api.dart` | OTP istegi; henuz hesap yok, bu yuzden guard yok. Kotuye kullanim siniri rate limit ile. |
| `POST /api/v1/otp/verify` | `preAuth` | COVERED | `flutter_securechat/lib/src/auth/auth_api.dart` | OTP tuketir ve kayit tokeni basar. Guard yerine gecen sey OTP'nin kendisidir. |
| `POST /api/v1/prekeys/refresh` | `auth` | SERVER_ONLY | `flutter_securechat/server_hardened/signaling-server/src/main/kotlin/com/securechat/signaling/HttpRoutes.kt` | libsignal v1 prekey yolu. Istemci fa0320c ile birakti (mesaj ve kurtarma Olm kullanir); route eski istemciler icin sunucuda acik. Kaldirma, libsignal kolonlarini dusuren migration ile birlikte. |
| `POST /api/v1/prekeys/upload` | `auth` | SERVER_ONLY | `flutter_securechat/server_hardened/signaling-server/src/main/kotlin/com/securechat/signaling/HttpRoutes.kt` | libsignal v1 prekey yolu. Istemci fa0320c ile birakti (mesaj ve kurtarma Olm kullanir); route eski istemciler icin sunucuda acik. Kaldirma, libsignal kolonlarini dusuren migration ile birlikte. |
| `POST /api/v1/reports` | `auth` | COVERED | `flutter_securechat/lib/src/auth/auth_api.dart` | Kotuye kullanim bildirimi; icerik tasimaz, bilinmeyen alan reddedilir. Anonim yazma yolu olmasin diye kimlik zorunlu. |
| `POST /api/v1/users/directory-token` | `auth` | COVERED | `flutter_securechat/lib/src/contacts/private_contact_discovery.dart` | Hesap sahibinin dizin anahtari gocu. |
| `POST /api/v1/users/register` | `preAuth` | COVERED | `flutter_securechat/lib/src/auth/auth_api.dart` | Kayit tokeni tuketir, access+refresh basar. Telefon yalniz geri cevrilemez ozet olarak girer. |
| `WS /ws` | `auth` | COVERED | `flutter_securechat/lib/src/services/signaling_service.dart` | Bearer dogrulamali sinyalleme; reconnect, boyut siniri ve codec yolu. |

## Signal codec

- Sunucunun siniflandirdigi tur: 11 (`MessageTypes.kt`: TRANSIENT, PENDING_CALL, FILE_TRANSFER)
- Flutter istemcisinin urettigi tur: 33
- Sunucu siniflandiriyor ama istemci uretmiyor: audio_data, video_data

### Acikca reddedilen turler

- `group_notification`: Sabit grup tokeni dis zarfta tasinmaz; grup kontrolu her aliciya ayri ordinary encrypted_message olarak gider.
- `group_directory_sync_v2`: Grup dizini sunucuda tutulmaz.
- `group_message_fanout`: Fanout sunucuya grup grafigi verirdi; istemci her aliciya ayri zarf gonderir.
- `admin_encrypted_log`: Dis eventType yalniz PRIVATE_EVENT olabilir; gercek olay turu recipient-specific E2EE payload icindedir.

### Sunucu siniflandiriyor, istemci uretmiyor — gerekceler

- `audio_data`: Legacy Android istemcisinin bant-ici ses cercevesi. Flutter istemcisi sesi WebRTC ile tasir ve bu turu hic uretmez. Siniflandirma BILEREK duruyor: savunma amaclidir, sahadaki eski bir istemci gonderirse cerceve kalici offline kuyruga yazilmasin.
- `video_data`: Ayni gerekce; legacy bant-ici video cercevesi.

## Sonuc

- Route: 35/35 eslenmis
- Eslenmemis: yok
- Guard uyusmazligi: yok

## Gizlilik nedeniyle kasitli wire daraltmalari

- Grup kontrolu ve grup mesaji her aliciya ayri ordinary `encrypted_message` Signal zarfi olarak gider; sabit grup tokeni dis zarfta bulunmaz.
- Grup cagrisi group ID yerine cagri-basina 256-bit routing nonce kullanir; client `participants` listesini bos gonderir ve server state yalniz RAM'de ust sure siniriyla tutulur.
- Receipt, edit/delete/reaction/pin, typing ve disappearing timer typed frame'leri server tarafindan plaintext kabul edilmez; sabit 16 KiB `CHATCTRL:v2` payload'i ordinary direct Signal `encrypted_message` icinde tasir.
- Sealed Sender mimarisi kaldirildi. `SEALED:v1:` zarfi artik uretilmiyor; kimlik dogrulamali socket uzerinde gelirse reddedilir.
