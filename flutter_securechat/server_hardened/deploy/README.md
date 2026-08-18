# Hardened privacy deployment

Bu dizin kok `infra/` compose dosyasinin yerine production icin kullanilir.
Kok compose eski server'i, AOF acik Redis volume'unu ve kalici backend log
volume'unu tasidigi icin hardened privacy release'inde kesinlikle kullanilmaz.

## Guvenlik ozellikleri

- Uygulama, Redis ve base JRE image'lari mutable tag degil `image@sha256`
  digest olmak zorundadir.
- Uygulama image'lari non-root, read-only filesystem, `cap_drop=ALL`,
  `no-new-privileges`, core dump kapali ve sinirli PID ile calisir.
- JVM heap/core/error dump ve attach mekanizmasi kapali; tek yazilabilir uygulama
  alani boyutu sinirli tmpfs'tir.
- Redis AOF/RDB kullanmaz, volume tasimaz ve `/data` dahil yalniz tmpfs'tir.
  Startup'ta iki JVM process'i de Redis `CONFIG GET` sonucunu ayrica dogrular.
- Container log driver'i `none`'dir. Health ve bearer-korumali identity-free
  aggregate metricler kullanilir; request/message/call zaman cizelgesi log
  collector'a aktarilmaz.
- Secret degerleri compose environment veya image'a girmez. Yalniz
  `/run/secrets/*` read-only dosyalari ve `NAME_FILE` degiskenleri kullanilir.
- PostgreSQL bu compose'a bilincli olarak dahil degildir. Encrypted disk,
  private network, V1-V14 migration ve retention/backup politikasini kanitlayan
  ayri managed/self-hosted hedef verilmelidir.
- Ayni sinirlar compose'a guvenmez: signaling ve bot binary'leri production
  mode, verify-full DB TLS ve legacy queue reddini listener'dan once tekrar
  dogrular; signaling ayrica PKCS#11 OPRF ile guvenli SMTP/Janus ister.

## Ag topolojisi ve kontrollu egress

Iki ag vardir:

- `securechat-internal` (`internal: true`) — servisler arasi trafik, disari
  cikisi yoktur. Redis **yalniz** bu agdadir: kisa TTL'li ciphertext tutan
  process'in disari cikan bir yolu olmamalidir.
- `securechat-egress` — yalniz signaling ve bot baglanir.

Egress'e cikan hedefler tam olarak sunlardir:

| Servis | Hedef | Neden |
|---|---|---|
| signaling | PostgreSQL | sema, hesap ve prekey materyali |
| signaling | SMTP (TLS) | kayit OTP'si |
| signaling | Firebase / APNs | generic wake-up push |
| signaling | Janus kontrol WebSocket'i | grup cagri odasi yonetimi |
| bot-api | PostgreSQL | bot identity, session ve policy |

**Host firewall bu listenin disina cikisi reddetmelidir.** Compose tek basina
allow-list saglayamaz; ag ayrimi yalniz "kim disari cikabilir" sorusunu
cozer, "nereye cikabilir" sorusunu deployment katmani cozer.

## Bot Unix socket dizini

Bot public ve admin yuzu ag uzerinde yayinlanmaz; erisim yalniz Unix domain
socket iledir. `BOT_SOCKET_DIR` host dizini onceden hazirlanmalidir:

```bash
install -d -o 10002 -g 10002 -m 0700 /srv/securechat/bot-sockets
```

Bot socket dosyalarini 0600 ile acar. Deploy preflight dizinin varligini,
0700 modunu ve 10002:10002 sahipligini dogrular.

## Guvenilen proxy

`TRUSTED_PROXIES` reverse proxy'nin adresini veya CIDR'ini tasir
(or. `127.0.0.1` veya `10.0.0.0/8`). Rate limit ve audit kararlarinda gercek
istemci adresi yalniz bu kaynaklardan gelen `X-Forwarded-For` ile belirlenir.

- Liste bos birakilirsa header hic okunmaz: butun kullanicilar proxy adresi
  uzerinden tek kimlik gibi sayilir ve IP basina limitler anlamini yitirir.
- Liste fazla genis tutulursa (or. `0.0.0.0/0`) her istemci kendi adresini
  uydurup limitleri tamamen atlayabilir. Yalniz kendi proxy'nizi yazin.

## Reverse proxy

`reverse-proxy.conf` referans konfigurasyonudur ve uc davranisi zorunlu
kilar: access log kapali, WebSocket upgrade isteginde `Authorization`
header'inin korunmasi, ve `token=` query parametresi tasiyan isteklerin
reddi. Container log driver'i `none` olsa da host proxy'si kendi logunu
tutar; bu dosya o sinirin parcasidir.

## Image build

Once approved JRE image'inin immutable digest'ini ve yerel cikti tag'lerini
verin. Gradle resolve islemi offline ve verification metadata fail-closed
calisir:

```bash
JRE_IMAGE='registry.example/jre@sha256:<64-hex>' \
SIGNALING_IMAGE_TAG='securechat-signaling:candidate' \
BOT_API_IMAGE_TAG='securechat-bot-api:candidate' \
./build_privacy_images.sh
```

Image'lari private registry'ye push edin, registry'nin verdigi digestleri
`SIGNALING_IMAGE` ve `BOT_API_IMAGE` olarak kullanin. Local tag production
deployment girdisi degildir.

## Zorunlu deployment preflight

Production compose dogrudan cagrilmaz. `deploy_privacy_stack.sh` varsayilan
olarak salt-okunur preflight calistirir; Redis, signaling ve bot image'larinin
ucunu de immutable digest olarak, PostgreSQL URL'sini
`sslmode=verify-full` ile ve tum host secret dosyalarini mutlak/regular,
en fazla 64 KiB ve group/world izni kapali olarak dogrular:
Secret materyalinin iki farkli amac icin tekrar kullanilmasi ve password'un
JDBC URL icine gomulmesi de preflight'ta reddedilir; secret degeri ciktiya
yazilmaz.

```bash
REDIS_IMAGE='registry.example/redis@sha256:<64-hex>' \
SIGNALING_IMAGE='registry.example/securechat-signaling@sha256:<64-hex>' \
BOT_API_IMAGE='registry.example/securechat-bot-api@sha256:<64-hex>' \
DATABASE_URL='jdbc:postgresql://db.internal/securechat?sslmode=verify-full' \
# Diger config ve *_FILE girdileri secret manager tarafindan saglanir. \
./deploy_privacy_stack.sh --check-only
```

Bu komut container olusturmaz veya degistirmez. Gercek uygulama yalniz tum
image'lar lokalde digest ile mevcutken, ayni preflight gectikten ve operator
acik onay verdikten sonra yapilir:

```bash
SECURECHAT_DEPLOY_CONFIRMATION='deploy-hardened-privacy-stack' \
./deploy_privacy_stack.sh --apply
```

Root `infra/docker-compose.yml` bu kapinin hicbir yolundan cagrilmaz.

## Secret dosyalari

Tum dosyalar root veya container UID'si tarafindan okunabilir, diger
kullanicilara kapali (`0400`) ve backup disi bir tmpfs/secret-manager mount'unda
olmalidir. Base64 anahtarlari decode sonrasi 32 byte ve birbirinden farkli
olmalidir. Direct `NAME` ile `NAME_FILE` birlikte verilirse process fail-closed
durur.

PKCS#11 provider ve vendor library image/host sinirinda ayrica kurulmalidir.
OPRF private key export edilmez; compose yalniz alias ve secret-file PIN tasir.
Fiziksel HSM tatbikati tracker'da harici release kapisidir.

## Yasaklar

- Kok `infra/docker-compose.yml` ile production baslatmak.
- Redis volume, AOF, RDB snapshot, host swap veya memory/core dump.
- Docker `json-file`/journald/cloud log collector ile request loglamak.
- Secret dosyalarini source tree, image layer, `.env`, PostgreSQL backup veya
  air-gapped mobil bundle'a kopyalamak.
- PostgreSQL backup'i canli tablodaki retention'dan uzun tutmak veya silinmis
  hesabi eski backup'tan production'a geri yuklemek.
