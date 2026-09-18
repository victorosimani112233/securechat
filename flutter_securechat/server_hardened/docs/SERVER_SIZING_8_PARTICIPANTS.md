# SecureChat Sunucu Boyutlandirmasi - 8 Katilimci

Tarih: 2026-09-17

Bu belge; signaling, bot API, PostgreSQL, gecici Redis, Janus SFU, coturn ve
reverse proxy'nin ayni fiziksel sunucuda calistigi ilk production kurulumu
icin kapasite varsayimlarini kaydeder. Kayitli hesap sayisindan cok ayni anda
bagli kullanici, aktif medya odasi ve TURN'a dusen arama sayisi belirleyicidir.

## Kisa karar

`6 fiziksel cekirdek / 12 thread, 2.4 GHz, 32 GB RAM, 960 GB SSD` makine,
asagidaki kosullarla ilk production ve orta duzey eszamanlilik icin yeterlidir:

- CPU paylasimsiz/dedicated ve modern bir nesil olmalidir.
- Ag en az garantili simetrik 1 Gbit/s, yuksek trafik kotali olmalidir.
- Tek 960 GB disk yerine tercihen `2 x 960 GB NVMe RAID1` kullanilmalidir.
- PostgreSQL yedegi ayni sunucuda tutulmamalidir.
- Eszamanli tam dolu 8 kisilik video odasi hedefi, yuk testi yapilana kadar
  8-12 oda ile sinirlanmalidir.

Bu makine yuksek erisilebilirlik saglamaz. Tek host arizasi mesajlasma,
kimlik dogrulama, TURN ve SFU'yu birlikte durdurur. Buyume asamasinda ilk
ayrilacak roller PostgreSQL ile Janus/coturn medya dugumudur.

## Uygulamadaki kesin sinirlar

- Grup aramasi mutlak tavani arayan dahil 8 kisidir.
- SFU yoksa video mesh tavani 6, ses mesh tavani 8 kisidir.
- Janus odasi en fazla 8 publisher ile acilir ve kayit kapali tutulur.
- Janus video publisher bitrate tavani kaynak kodda 512 kbit/s'dir.
- Tek signaling process'i en fazla 6000 WebSocket baglantisi kabul eder.
- PostgreSQL Hikari havuzu signaling icin 20 baglantidir.
- Bloklayan PostgreSQL/Redis isi `BLOCKING_IO_THREADS` havuzunda calisir
  (varsayilan cekirdek x 8, alt sinir 32). Netty event-loop'lari yalniz ag
  olaylarini surer; eszamanlilik artik cekirdek sayisiyla sinirli degildir.
- Redis `noeviction` ile calisir. Bellek dolunca sessizce key atilmaz; yazma
  reddedilir, rate limiter fail-closed olur ve gonderen 503 alip yeniden
  dener. `REDIS_MAXMEMORY` varsayilani 2 GB'dir.

  Bu, bilincli bir takastir: sessiz mesaj kaybi yerine gorunur ve yeniden
  denenebilir bir ret. Bedeli, Redis'in dolmasinin kendi basina bir kesinti
  olmasidir; bu yuzden `maxmemory` cimri ayarlanmamali ve bellek kullanimi
  izlenmelidir. Kaba hesap:

  ```text
  Redis ihtiyaci ~= eszamanli cevrimdisi kullanici x ortalama kuyruk boyutu
                    + rate limit/presence/cagri state'i (~100-200 MB)
  ```

  Kuyruk TTL'i varsayilan 15 dakikadir, bu yuzden kuyruklar hizli bosalir.
  Kullanici basina mutlak tavan 50 MB'dir; tavana yakin birkac kullanici tek
  basina 2 GB'i doldurabilir, dolayisiyla `alerting` bu metrik uzerinden
  kurulmalidir.
- Alici basina teslim kuyrugu en fazla 1000 mesaj ve 50 MB'dir. Sinira
  ulasildiginda bekleyen mesajlar korunur, yeni mesaj reddedilir.
- Privacy compose varsayilan olarak her servisi 1 CPU/1 GB ile sinirlar.
  Sunucu buyuk olsa bile bu limitler production kapasite testine gore acikca
  ayarlanmalidir.

## PostgreSQL buyume hesabi

Olculen degerler (PostgreSQL 16, 500 hesap, hesap basina 200 tek kullanimlik
prekey, `VACUUM ANALYZE` sonrasi):

| Tablo | 500 hesap | Hesap basina |
|---|---:|---:|
| `modern_one_time_prekeys` | 200 MB | ~410 KB |
| `one_time_prekeys` (legacy, bot yolu) | 17 MB | ~35 KB |
| Diger butun tablolar toplami | < 2 MB | ~3.5 KB |

Veritabaninin neredeyse tamami post-quantum tek kullanimlik prekey havuzudur:
bir Kyber1024 public key 1568 byte, klasik X25519 prekey 33 byte'tir. Bu,
PQXDH'nin dogal maliyetidir ve mesaj verisi degildir.

```text
Kabaca disk = hesap_sayisi x 0.45 MB   (havuz 200 prekey ile dolu iken)
5.000 hesap  -> ~2.3 GB
20.000 hesap -> ~9 GB
```

`MAX_STORED_ONE_TIME_PREKEYS` tavani 1000'dir; istemciler havuzu tavana kadar
doldurursa bu rakam bese katlanir. Havuz boyutu, disk butcesinin tek gercek
degiskenidir.

## Ag hesabi

Sekiz kisinin de goruntu yayinladigi ve herkesin diger yedi yayini aldigi en
agir SFU odasi icin yalniz video hesabi:

```text
Janus giris  = 8 x 0.512                  = 4.096 Mbit/s
Janus cikis  = 8 x 7 x 0.512              = 28.672 Mbit/s
Toplam       = 32.768 Mbit/s
%25 ses/protokol/RTCP payi ile planlama   = yaklasik 41 Mbit/s / oda
```

Bu nedenle 10 tam dolu oda yaklasik 410 Mbit/s NIC trafigi uretebilir.
1 Gbit/s portta TURN, API, yedekleme ve ani bitrate yukselmeleri icin pay
birakilarak 8-12 tam oda temkinli ilk isletim siniridir. Gercek limit sentetik
WebRTC yuk testi ve packet-loss/CPU softirq olcumleriyle belirlenmelidir.

Bire bir aramalar once dogrudan WebRTC P2P kurulur. Dogrudan ICE yolu
kurulamazsa coturn medyanin tamamini relay eder. 720p bir relayed arama icin
iki yon toplam NIC tuketimi pratikte birkac Mbit/s olabilir; cok sayida TURN
aramasi, grup odalarindan once 1 Gbit/s portu doldurabilir. coturn relay UDP
port araligi ve provider'in UDP/PPS limiti de kapasitenin parcasidir.

## 32 GB RAM icin baslangic butcesi

| Rol | Baslangic butcesi |
|---|---:|
| PostgreSQL | 8 GB |
| Signaling JVM | 4-6 GB |
| Bot API JVM | 2 GB |
| Redis ephemeral | 1-2 GB (`REDIS_MAXMEMORY` + overhead) |
| Janus | 2-4 GB |
| coturn | 1-2 GB |
| Reverse proxy, HSM agent ve OS | 3-4 GB |
| Bos/OOM payi | en az 5 GB |

CPU frekansi tek basina yeterlilik gostergesi degildir. Islemci modeli,
tek-cekirdek performansi, sanallastirma overcommit'i ve ag softirq yuku
olculmelidir. Medya trafigi icin paylasimli vCPU yerine dedicated CPU veya
fiziksel sunucu tercih edilmelidir.

## Disk ve veri guvenligi

960 GB kapasite uygulama icin genellikle fazlasiyla yeterlidir; Janus kayit
yapmaz ve mesaj/dosya kuyruklari kalici medya arsivi degildir. Kritik konu
kapasite degil PostgreSQL WAL gecikmesi ve disk arizasidir.

- Tercih: guc kaybi korumali `2 x 960 GB NVMe RAID1`.
- Zorunlu: sifreli, ayri lokasyonda PostgreSQL yedegi ve geri donus testi.
- Tek SSD kullanilacaksa disk arizasinda hizmet/veri kaybi riski kabul
  edilmis olur; ayni diskteki snapshot yedek sayilmaz.

PostgreSQL, donanim ve disk cache katmanlarinin kalici yazma garantisini
saglamasini operator sorumlulugu olarak tanimlar:
https://www.postgresql.org/docs/current/wal-reliability.html

## Satin alma alt siniri

- Dedicated bare metal veya garantili dedicated-vCPU VDS
- 6 fiziksel cekirdek / 12 thread, modern x86-64 CPU
- 32 GB ECC RAM tercih edilir
- 2 x 960 GB NVMe RAID1
- Garantili simetrik 1 Gbit/s; en az 20 TB/ay veya unmetered trafik
- Statik public IPv4; UDP kisitlamasi/PPS darbogazi olmamali
- DDoS korumasi ve uzak konsol
- 443/TCP, TURN 3478 UDP/TCP, TURN TLS 5349 TCP/UDP ve kontrollu relay UDP
  port araligi
- Harici yedek hedefi ve izleme/uyari sistemi
- Production private-directory anahtari icin desteklenen PKCS#11 HSM

Janus VideoRoom bir SFU'dur; medyayi transcode etmek yerine publisher'dan
subscriber'lara yonlendirir:
https://janus.conf.meetecho.com/docs/videoroom

coturn varsayilan relay araligi ve port kapasitesi:
https://github.com/coturn/coturn/blob/master/docs/multiplex-peer.md

## Ne zaman ikinci sunucu gerekir?

Asagidakilerden biri gorulmeden once Janus/coturn ayri medya dugumune
alinmalidir:

- Surekli NIC kullanimi 500-600 Mbit/s'yi geciyor.
- Paket kaybi, jitter veya CPU softirq kullanimi yuk altinda artiyor.
- Ayni anda 8-12 tam dolu video odasi duzenli hale geliyor.
- TURN relay orani veya relayed bire bir arama sayisi beklenenden yuksek.
- Bakimda tum servisin durmasi kabul edilemez hale geliyor.

6000'den fazla eszamanli WebSocket icin yalniz daha buyuk makine yeterli
degildir. Presence ve aktif grup cagri state'inin process-local kisimlari
yatay olcekleme icin yeniden ele alinmali, sonra birden fazla signaling
instance'i ve load balancer kullanilmalidir.
