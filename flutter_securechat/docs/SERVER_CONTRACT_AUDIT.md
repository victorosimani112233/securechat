# Hardened Ktor Server Contract Audit

Bu dosya `tool/generate_server_contract_audit.dart` ile uretilir.
Server route veya Signal discriminator degisirse esleme eksigi CI-benzeri
kontrolde hata koduyla yakalanir.

## HTTP ve WebSocket route eslemesi

| Server route | Durum | Flutter kaniti | Karar |
|---|---|---|---|
| `GET /` | SERVER_ONLY | `flutter_securechat/server_hardened/signaling-server/src/main/kotlin/com/securechat/signaling/HttpRoutes.kt` | Service landing endpoint; mobile runtime does not consume it. |
| `GET /api/v1/directory/config` | COVERED | `flutter_securechat/lib/src/contacts/private_contact_discovery.dart` | Pinned blind-RSA OPRF public configuration. |
| `GET /api/v1/directory/snapshot` | COVERED | `flutter_securechat/lib/src/contacts/private_contact_discovery.dart` | Token-labeled and token-sealed private membership snapshot. |
| `GET /api/v1/ice/config` | COVERED | `flutter_securechat/lib/src/media/ice_server_fetcher.dart` | Authenticated short-lived TURN configuration. |
| `GET /api/v1/latest-version` | SERVER_ONLY | `flutter_securechat/server_hardened/signaling-server/src/main/kotlin/com/securechat/signaling/HttpRoutes.kt` | No Kotlin Android caller exists; store/version policy endpoint. |
| `GET /api/v1/sfu/room/{groupId}` | WS_EQUIVALENT | `flutter_securechat/lib/src/media/call_manager.dart` | Kotlin client also uses authenticated group status/SFU WebSocket messages; HTTP route is an operations/recovery view. |
| `GET /api/v1/users/{userId}/prekeys` | COVERED | `flutter_securechat/lib/src/crypto/signal_protocol_crypto_service.dart` | Authenticated peer bundle fetch. |
| `GET /health` | COVERED | `flutter_securechat/lib/src/network/socket_diagnostics.dart` | Redacted server compatibility probe. |
| `GET /metrics` | SERVER_ONLY | `flutter_securechat/server_hardened/signaling-server/src/main/kotlin/com/securechat/signaling/HttpRoutes.kt` | Prometheus operations endpoint; intentionally not exposed in the client. |
| `POST /api/v1/account/delete` | COVERED | `flutter_securechat/lib/src/auth/auth_api.dart` | Authenticated account deletion. |
| `POST /api/v1/auth/logout` | COVERED | `flutter_securechat/lib/src/auth/auth_api.dart` | Refresh-token revocation. |
| `POST /api/v1/auth/refresh` | COVERED | `flutter_securechat/lib/src/auth/auth_api.dart` | Access and refresh token rotation. |
| `POST /api/v1/directory/evaluate` | COVERED | `flutter_securechat/lib/src/contacts/private_contact_discovery.dart` | Authenticated fixed-size blinded contact evaluation. |
| `POST /api/v1/fcm/register` | COVERED | `flutter_securechat/lib/src/push/push_service.dart` | FCM/APNs transport token registration. |
| `POST /api/v1/fcm/unregister` | COVERED | `flutter_securechat/lib/src/push/push_service.dart` | Transport token removal. |
| `POST /api/v1/otp/request` | COVERED | `flutter_securechat/lib/src/auth/auth_api.dart` | OTP request. |
| `POST /api/v1/otp/verify` | COVERED | `flutter_securechat/lib/src/auth/auth_api.dart` | OTP verification and registration token. |
| `POST /api/v1/prekeys/refresh` | COVERED | `flutter_securechat/lib/src/crypto/pre_key_maintenance_service.dart` | One-time prekey replenishment with failed-upload rollback. |
| `POST /api/v1/prekeys/upload` | COVERED | `flutter_securechat/lib/src/auth/auth_api.dart` | Initial Signal V3 bundle upload. |
| `POST /api/v1/users/directory-token` | COVERED | `flutter_securechat/lib/src/contacts/private_contact_discovery.dart` | Authenticated account owner directory-key migration. |
| `POST /api/v1/users/register` | COVERED | `flutter_securechat/lib/src/auth/auth_api.dart` | OTP-bound hash-only registration; no reversible phone envelope. |
| `WS /ws` | COVERED | `flutter_securechat/lib/src/services/signaling_service.dart` | Bearer-authenticated signaling, reconnect, size limit and codec path. |

## Signal codec

- Kotlin discriminator: 33
- Flutter discriminator: 33
- Flutter eksigi: yok
- Flutter fazlasi: yok

## Sonuc

- Route: 22/22 kararli esleme
- Codec: 33/33 birebir discriminator

## Gizlilik nedeniyle kasitli wire daraltmalari

- `group_notification`, `group_directory_sync_v2` ve `group_message_fanout` production server tarafindan reddedilir.
- Grup kontrolu ve grup mesaji her aliciya ayri ordinary `encrypted_message` Signal zarfi olarak gider; sabit grup tokeni dis zarfta bulunmaz.
- Grup cagrisi group ID yerine cagri-basina 256-bit routing nonce kullanir; client `participants` listesini bos gonderir ve server state yalniz RAM'de ust sure siniriyla tutulur.
- Receipt, edit/delete/reaction/pin, typing ve disappearing timer typed frame'leri server tarafindan plaintext kabul edilmez; sabit 16 KiB `CHATCTRL:v2` payload'i ordinary direct Signal `encrypted_message` icinde tasir.
- Admin audit outer `eventType` yalniz `PRIVATE_EVENT` olabilir; gercek olay turu recipient-specific E2EE payload icindedir.
