# Elçim'in Teknik İşleyişi

Elçim, Android ve iOS platformları için geliştirilmiş bir mesajlaşma uygulamasıdır. Mesajlar cihazdan çıkmadan önce şifrelenmekte; sunucu tarafından yalnızca iletilmekte, içerikleri ise okunamamaktadır.

# Elçim'in Teknik İşleyişi

Elçim, Android ve iOS platformları için geliştirilmiş bir mesajlaşma uygulamasıdır. Mesajlar cihazdan çıkmadan önce şifrelenmekte; sunucu tarafından yalnızca iletilmekte, içerikleri ise okunamamaktadır.

## Kullanılan Teknolojiler

- Flutter ve Dart: Android ve iOS sürümlerinde ortak olarak kullanılan arayüz ve uygulama mantığı
- Kotlin ve Swift: Cihazın bildirim, arama ve ses özelliklerine erişim
- Kotlin ve Ktor: Hesap işlemlerinin ve cihazlar arası iletişimin yönetildiği sunucu
- Signal Protocol: Mesajların uçtan uca şifrelenmesi
- SQLCipher: Cihazda saklanan sohbet verilerinin şifrelenmesi
- PostgreSQL: Hesap ve oturum bilgilerinin kalıcı olarak kaydedilmesi
- Redis: Teslim edilmemiş şifreli mesajların kısa süreli olarak saklanması
- Firebase FCM: Yeni bir mesaj ya da arama alındığında cihazın uyandırılması
- WebRTC: Sesli ve görüntülü görüşmelerin gerçekleştirilmesi

## Sistem Mimarisi

Elçim'in mimarisi genel olarak üç ana bileşenden oluşmaktadır: kullanıcı cihazlarında çalışan istemci uygulama, Ktor tabanlı sunucu ve bu sunucunun kullandığı veri depoları ile harici servisler. Bileşenler arasındaki tüm iletişim TLS ile şifrelenmiş bağlantılar üzerinden yürütülmektedir.

### İstemci Uygulama

İstemci uygulama iki katmandan oluşmaktadır. Arayüz ve uygulama mantığı Flutter ve Dart ile geliştirilmiş olup Android ve iOS sürümlerinde ortak olarak kullanılmaktadır. Bildirim, arama ve ses gibi platforma özgü işlevlere ise Android'de Kotlin, iOS'ta Swift ile yazılmış yerel katman üzerinden erişilmektedir.

Mesajların şifrelenmesi ve şifrelerinin çözülmesi yalnızca istemci tarafında, Signal Protocol ile gerçekleştirilmektedir. Sohbet geçmişi cihazda SQLCipher ile şifrelenmiş bir veritabanında saklanmakta; henüz iletilemeyen mesajlar da şifreli hâlde bir gönderim kuyruğunda tutulmaktadır. Bu yapı sayesinde mesaj içeriğinin açık hâli yalnızca gönderen ve alıcı cihazlarda bulunmaktadır.

### Sunucu

Sunucu, Kotlin ve Ktor ile geliştirilmiştir ve hesap işlemleri ile cihazlar arası iletişimin yönetilmesinden sorumludur. Sunucu mesajları yalnızca yönlendirmekte, içeriklerine erişememektedir. Sunucu tarafında iki veri deposu kullanılmaktadır:

- PostgreSQL: Hesap ve oturum bilgileri gibi kalıcı kayıtların tutulduğu veritabanıdır. Kullanıcıların telefon numaraları bu kayıtlarda açık hâlde değil, UUID olarak bulunmaktadır.
- Redis: Alıcısı çevrimdışı olan mesajları taşıyan paketlerin şifreli olarak kısa süreli bekletildiği depodur. Kayıtlar, teslim teyidi alındığında ya da bekleme süresi dolduğunda silinmektedir.

## Mesaj İletim Süreci

1. Mesaj yazıldığı sırada metin yalnızca gönderenin cihazında bulunur. Karşı tarafa "yazıyor" bilgisi iletilebilir; ancak yazılan içerik iletilmez.
2. Gönderim komutu verildiğinde mesaj cihaza kaydedilir ve Signal Protocol ile şifrelenir. Bağlantının kesilmesi durumunda yeniden denenebilmesi amacıyla şifreli hâliyle gönderim kuyruğunda tutulur.
3. Signal Protocol ile şifrelenmiş mesaj bir veri paketine yerleştirilir ve bu paket, sunucuya aktarımı sırasında TLS ile ikinci bir şifreleme katmanı altında korunur. Bu yapıda mesaj içeriği uçtan uca şifreleme ile, mesajı taşıyan paket ise aktarım katmanında şifrelenmiş olur. TLS katmanı sunucuda çözülür; ancak mesaj içeriği Signal şifrelemesi altında kalmaya devam ettiğinden sunucu tarafından okunamaz. Alıcı çevrimiçi ise mesaj, alıcı cihazla kurulan TLS bağlantısı üzerinden doğrudan iletilir. Alıcının çevrimdışı olması durumunda mesajı taşıyan paket, Redis'te şifreli olarak geçici bir süre bekletilir (varsayılan olarak 15 dakika, en fazla bir saat). Bu süre boyunca hem mesaj içeriği Signal şifrelemesi altında hem de paketin kendisi şifreli hâlde tutulur. Aynı anda Firebase aracılığıyla alıcının cihazına bir uyandırma sinyali gönderilir. Söz konusu sinyal mesaj içeriğini taşımaz.
4. Alıcı cihazda mesaj doğrulanır, şifresi çözülür ve cihazdaki şifreli depoya kaydedilir; ardından gönderene teslim bilgisi iletilir. Bu teyidin sunucuya ulaşmasıyla birlikte bekleyen kayıt silinir; mesajın okunması beklenmez.
5. Alıcının ilgili sohbet ekranında bulunması hâlinde mesaj doğrudan görüntülenir. Aksi durumda bildirim ayarlarına bağlı olarak bilgilendirme yapılır.
6. Sohbet açıldığında alıcı uygulama tarafından okundu bilgisi gönderilir ve bu bilginin gönderene ulaşmasıyla mesajın durumu güncellenir. Okundu bilgisi yalnızca sohbetin açıldığını gösterir; mesajın tamamının okunduğuna dair bir ölçüm niteliği taşımaz.

## Sesli ve Görüntülü Aramalar

Sesli ve görüntülü görüşmeler WebRTC ile doğrudan cihazlar arasında P2P olarak gerçekleştirilmektedir. Grup aramalarında en fazla sekiz katılımcı desteklenmektedir.

## Verilerin Saklanması

Sohbet geçmişi yalnızca cihazlarda ve şifreli olarak saklanmaktadır.Sunucuda kalıcı bir sohbet arşivi tutulmamakta; yalnızca hesap bilgileri ile teslim için gerekli geçici kayıtlar yönetilmektedir. Kullanıcıların telefon numaraları sunucuda açık hâlde değil, UUID olarak bulunmaktadır. Teslim bekleyen şifreli mesajlar sunucuda varsayılan olarak 15 gün süreyle tutulmaktadır. Sürenin dolmasının ardından gönderen cihazdaki kayıt yeniden gönderilebilmekle birlikte, teslimin süresiz olarak denenmesi garanti edilmemektedir.

## Chat-in ile Karşılaştırma

Chat-in tarafından uçtan uca şifreleme, cihazda şifreli veri saklama ve güvenli bağlantı kullanıldığı açıklanmaktadır. Elçim'de de aynı temel korumalar uygulanmaktadır: Mesajlar Signal Protocol ile, cihazdaki veriler SQLCipher ile şifrelenmekte; bağlantılar ise TLS ile korunmaktadır.

İki uygulama arasında iki temel farklılık tespit edilmiştir:

- Sunucuda bekleme süresi: Chat-in gizlilik politikasına göre teslim edilemeyen şifreli mesajlar 60 güne kadar saklanabilmektedir. Elçim'de bu süre varsayılan olarak 15 gün olarak belirlenmiştir. Bu sayede sunucuda daha az veri tutulmaktadır.

- Telefon numarasının paylaşımı: Chat-in gizlilik politikasında telefon numarasının iletişim kurulan kullanıcılara açık olduğu belirtilmektedir. Elçim'de numaranın otomatik olarak paylaşılması devre dışı bırakılabilmekte; bu özellik etkin olduğunda numara yalnızca birebir sohbetteki alıcıya şifreli olarak iletilmektedir.

Elçim'de bunlara ek olarak parolalı sohbet kilidi, süreli mesajlar, tek gösterimlik medya, planlı mesajlar ve parola korumalı yedekleme özellikleri sunulmaktadır.

Elçim'in güvenlik yaklaşımında yalnızca mesajların şifrelenmesi değil, cihazdaki verilerin korunması ve sunucuda tutulan bilginin en aza indirilmesi de esas alınmaktadır.
