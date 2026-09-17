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
- Privacy compose varsayilan olarak her servisi 1 CPU/1 GB ile, Redis'i
  ayrica 512 MB `maxmemory` ile sinirlar. Sunucu buyuk olsa bile bu limitler
  production kapasite testine gore acikca ayarlanmalidir.

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
| Redis ephemeral | 1 GB |
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
