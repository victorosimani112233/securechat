# Gelen Arama Sorunları — Detaylı Teknik Dokuman

## Mevcut Durum (30 Nisan 2026)

Oppo A16 ve Galaxy arasında arama yapıldığında birden fazla sorun yaşanıyor. Bu doküman tüm sorunları, kök nedenlerini ve yapılan/yapılması gereken düzeltmeleri detaylandırır.

---

## Sorun 1: Uygulama Kapalıyken Telefon Çalmıyor (Sadece Bildirim Geliyor)

### Belirtiler
- Uygulama kapalıyken arama geldiğinde telefon çalmıyor
- Sadece sessiz bir bildirim geliyor ("Yeni bir mesajınız var")
- Kullanıcı uygulamayı manuel açtığında çalmaya başlıyor

### Kök Neden
**ICE candidate, SDP Offer'den önce sunucuya ulaşıyor ve yanlış tipte FCM push gönderiyor.**

Arama başlatma akışı:
1. Arayan `createOffer()` sırasında ICE candidate'lar eş zamanlı üretiliyor
2. ICE candidate sunucuya SDP Offer'den **önce** ulaşabiliyor
3. Alıcı çevrimdışı → `ConnectionManager.queueAndNotify()` çağrılıyor
4. `FcmPushSender.extractMessageType()` → `"ice_candidate"` döner
5. `"ice_candidate"` `isCallSignal` setinde **YOK** → notification payload ekleniyor
6. FCM push "Yeni mesaj - Yeni bir mesajınız var" olarak gönderiliyor
7. Android notification payload'lı push'ı otomatik gösteriyor, `onMessageReceived()` **ÇAĞRILMIYOR**
8. SDP Offer 3 saniye içinde geldiğinde **rate-limit** (3000ms) devreye giriyor → FCM push hiç gönderilmiyor

### Düzeltme (SERVER — Yapıldı)
**Dosya:** `signaling-server/.../FcmPushSender.kt`

ICE candidate ve SDP answer için FCM push tamamen atlanıyor:
```kotlin
// sendWakeUpPush() metodunda, transientTypes kontrolünden sonra eklendi:
if (messageType in setOf("ice_candidate", "sdp_answer")) return false
```

**Neden:** Bu sinyaller Redis offline kuyruğuna eklenir ve WebSocket reconnect'te teslim edilir. Kendi FCM push'larına ihtiyaç duymazlar. SDP Offer push'ı cihazı uyandırmak için yeterlidir.

**Deploy:** `./gradlew :signaling-server:fatJar` → `signaling-server/build/libs/signaling-server-all.jar` → Docker container'a kopyala ve restart et.

---

## Sorun 2: Arama Ekranı Yerine Bildirim Geliyor (Telefon Açık/Kilitsizken)

### Belirtiler
- Telefon açık ve kilitsizken arama geldiğinde tam ekran arama ekranı yerine yukarıdan bildirim düşüyor
- "Gelen Arama" yazılı bildirime tıklamak gerekiyor

### Kök Neden
**Android 10+ tasarım kararı + `.setSilent(true)` sorunu**

1. Android 10+: Telefon kilitsizken `setFullScreenIntent()` çalışmıyor, heads-up notification'a düşürülüyor
2. `.setSilent(true)` ayarı heads-up notification'ın bile görünmesini engelliyor (bazı cihazlarda)
3. `startActivity()` FCM handler'dan çağrıldığında Android 12+ bunu engelliyor (arka plan activity başlatma kısıtı)

### Düzeltme (CLIENT — Yapıldı)
1. **`.setSilent(true)` kaldırıldı** — `IncomingCallHandler.kt`: Bildirim artık heads-up olarak görünecek
2. **`contentIntent` eklendi** — Bildirime tıklanınca arama ekranı açılır
3. **`SYSTEM_ALERT_WINDOW` izni eklendi** — `AndroidManifest.xml`: Bu izin verildiğinde arka plandan Activity başlatma çalışır
4. **Ayarlar ekranına "Gelen arama ekranı" seçeneği eklendi** — `SettingsScreen.kt`: Kullanıcı overlay iznini buradan verebilir

**Kullanıcı aksiyonu:** Her iki telefonda Ayarlar → Arama → "Gelen arama ekranı" → "Diğer uygulamaların üzerinde göster" iznini aç

---

## Sorun 3: Galaxy'de Uygulama Sürekli Crash Ediyor

### Belirtiler
- Oppo'dan Galaxy'yi arayınca Galaxy'de "Elçim sürekli duruyor" hatası
- Logda PID sürekli değişiyor (crash loop)
- Arama ekranı açılacak gibi olup hemen kapanıyor

### Kök Neden
**`CallForegroundService.start()` FCM handler'dan çağrılıyordu.**

Android 12+ arka plandan foreground service başlatmayı kısıtlıyor. `CallForegroundService` Hilt dependency injection kullanıyor (`@AndroidEntryPoint`, `@Inject CallManager`), cold start'ta injection başarısız olabiliyor → crash → restart → SDP offline queue'dan tekrar gelir → tekrar crash → sonsuz döngü.

### Düzeltme (CLIENT — Yapıldı)
`CallForegroundService.start()` FCM handler'dan kaldırıldı, `IncomingCallActivity.onCreate()`'e taşındı:

```kotlin
// SecureChatFcmService.kt — KALDIRILDI:
// CallForegroundService.start(this)  // CRASH NEDEN

// IncomingCallActivity.kt — EKLENDİ:
override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    try {
        CallForegroundService.start(this) // Activity foreground'da, güvenli
    } catch (e: Exception) { ... }
    ...
}
```

---

## Sorun 4: Stale SDP Offer — Sonradan Uygulamaya Girince Arama Başlıyor

### Belirtiler
- Arama yapılıp cevaplanmadığında, aranan kişi sonradan uygulamayı açınca telefonları çalmaya başlıyor
- Arayan çoktan vazgeçmiş olmasına rağmen arama tetikleniyor

### Kök Neden
**SDP Offer Redis offline kuyruğunda süresiz kalıyor.**

1. Arayan SDP Offer gönderir → alıcı çevrimdışı → Redis'e kuyruklanır
2. Arayan 30 saniye bekler, vazgeçer → ama SDP Offer Redis'te 14 gün kalır
3. Alıcı saatler/günler sonra uygulamayı açar → WebSocket bağlanır → offline mesajlar teslim edilir
4. Eski SDP Offer `handleIncomingCall()` tarafından işlenir → telefon çalmaya başlar

### Düzeltme (CLIENT — Yapıldı)
**Dosya:** `app/.../IncomingMessageHandler.kt`

60 saniyeden eski SDP Offer'ler ignore ediliyor:
```kotlin
private suspend fun handleIncomingCall(signal: SignalMessage.SdpOffer) {
    val ageMs = System.currentTimeMillis() - signal.timestamp
    if (ageMs > 60_000) {
        Log.w("IncomingHandler", "Stale SDP Offer ignore edildi: age=${ageMs}ms")
        return
    }
    // ... normal arama akışı
}
```

### Potansiyel Server-Side İyileştirme (Yapılmadı)
Redis'te SDP Offer için ayrı TTL uygulanabilir:
- `queueOfflineMessage()` içinde `sdp_offer` tipindeki mesajlar için TTL: 60 saniye
- Böylece eski SDP'ler Redis'ten otomatik silinir ve client'a hiç ulaşmaz

---

## Sorun 5: Sistem Mesajları Bildirim Olarak Görünüyor

### Belirtiler
- "Sesli Arama · Bağlanılamadı" gibi arama kayıtları bildirim olarak geliyor
- Konuşma listesinde raw format görünüyor: `CALL|OUTGOING|VOICE|FAILED|0|...`

### Kök Neden
`saveCallSystemMessage()` → `messageRepository.saveMessage()` çağrısı:
1. `lastMessage` alanına raw "CALL|..." formatı yazılıyordu
2. `unreadCount` SYSTEM mesajları için de artıyordu
3. Unread count artınca konuşma listesinde badge görünüyordu

### Düzeltme (CLIENT — Yapıldı)
**Dosya:** `storage/.../MessageRepositoryImpl.kt`

```kotlin
val lastMessagePreview = when (message.contentType) {
    MessageContentType.POLL -> "📊 Anket"
    MessageContentType.SYSTEM -> {
        val parts = message.content.split("|")
        if (parts.size >= 6 && parts[0] == "CALL") "📞 ${parts[5]}" else message.content
    }
    else -> message.content
}
val shouldIncrementUnread = !message.isOutgoing && message.contentType != MessageContentType.SYSTEM
```

---

## Çift Çalma Sorunu (Daha Önce Düzeltildi)

### Belirtiler
- Arama geldiğinde hem uygulama içinden hem bildirimden çalıyordu

### Düzeltme
- `IncomingCallHandler.kt`: Notification channel `setSound(null, null)`, `enableVibration(false)`
- Notification builder: `.setSilent(true)` (sonra kaldırıldı — Sorun 2 ile çelişiyordu)
- Kanal `setSound(null, null)` zaten ses çalmayı engelliyor
- Tüm ses/titreşim sadece `RingtonePlayer` tarafından yönetiliyor

---

## Arama Reddedilince Ekran Kapanmıyor (Daha Önce Düzeltildi)

### Düzeltme
**Dosya:** `app/.../CallScreen.kt`
```kotlin
if (state == CallState.ENDED || state == CallState.FAILED || state == CallState.REJECTED) {
    delay(1500)
    onCallEnded()
}
```
`CallState.REJECTED` eklendi.

---

## Genel Arama Akışı (Referans)

### Arayan Taraf
```
initiateCall() → PeerConnection → createOffer() → SDP Offer gönder (WebSocket)
                                                 → ICE candidate'lar gönder (WebSocket)
                                                 → Ringback tone başlat
```

### Alıcı Taraf (Online)
```
WebSocket mesaj → IncomingMessageHandler.handleIncomingCall()
               → CallManager.handleIncomingCall() → RINGING state
               → RingtonePlayer.startRinging()
               → IncomingCallActivity göster
```

### Alıcı Taraf (Offline)
```
Server: SDP Offer → Redis offline queue + FCM data-only push (type=incoming_call)
Client: FCM onMessageReceived() → ringtonePlayer.startRinging()
                                → IncomingCallHandler notification (full-screen intent)
                                → startActivity(IncomingCallActivity)
                                → WebSocketDrainWorker → SDP Offer teslim
                                → CallManager.handleIncomingCall() → session oluştur
```

---

## Server Deploy Notları

- Signaling server: `./gradlew :signaling-server:fatJar`
- JAR: `signaling-server/build/libs/signaling-server-all.jar`
- Docker: JAR'ı container'a kopyala, restart et
- Sunucu: `185.48.182.124:9090`
- FCM: `FIREBASE_SERVICE_ACCOUNT_PATH` env variable gerekli

---

## Hala Devam Eden / İzlenmesi Gereken Sorunlar

1. **Oppo A16'dan Galaxy'yi arayınca arama hemen kapanıyor** — Crash düzeltildikten sonra test edilmeli. Crash loop sorunu çözüldüyse normal çalışması bekleniyor.
2. **Galaxy'den Oppo'yu arayınca hiçbir şey olmuyor** — Logda detay yok, server loglarının kontrol edilmesi gerekiyor. FCM push gidiyor mu? SDP Offer kuyruğa ekleniyor mu?
3. **Overlay izni** — Her iki telefonda "Diğer uygulamaların üzerinde göster" izni verilmeli. Ayarlar → Arama → "Gelen arama ekranı" seçeneğinden açılabilir.
