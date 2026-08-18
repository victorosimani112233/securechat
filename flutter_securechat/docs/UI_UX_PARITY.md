# Flutter UI/UX parity çalışma defteri

Bu belge Kotlin/Compose arayüzünün Flutter hedefindeki görsel ve davranışsal
taşımasını yönetir. `MIGRATION_TRACKER.md` özellik/altyapı kapanışını izler;
buradaki bir satır kapanmadan yalnızca ilgili servisin çalışması UI paritesi
sayılmaz.

Son güncelleme: 2026-08-18

## Kapanış ölçütü

Her ekran veya ortak bileşen için aşağıdaki kanıtların tamamı aranır:

1. Compose kaynağındaki hiyerarşi, durumlar, aksiyonlar ve motion davranışı
   çıkarılmış olmalı.
2. Flutter üretim route'u demo/mock olmayan gerçek servis grafiğine bağlı
   olmalı.
3. Light/dark, küçük telefon, büyük yazı, RTL ve erişilebilirlik durumu widget
   testinde doğrulanmalı.
4. Android fiziksel cihazda kritik gesture ve görünüm kanıtı alınmalı.
5. iOS'a özel safe-area, Cupertino geçişi, izin ve platform davranışı kaynak
   auditinden geçmeli; nihai DEVICE VERIFIED yalnız macOS/iPhone kanıtıyla
   verilir.

Durumlar:

- `DEVICE VERIFIED`: kaynak, test ve fiziksel Android kanıtı var.
- `TEST VERIFIED`: kaynak ve otomatik test var; fiziksel ekran turu bekliyor.
- `IMPLEMENTED / VISUAL AUDIT`: işlev bağlı, Compose görsel ayrıntı kontrolü
  sürüyor.
- `OPEN`: eksik görsel/etkileşim karşılığı var.
- `DEPLOY BLOCKED`: UI doğru hata durumunu gösteriyor fakat harici servis
  deployment'ı tamamlanmamış.

## Değiştirilemez tasarım sözleşmesi

| Alan | Compose kaynağı | Flutter karşılığı | Durum |
|---|---|---|---|
| Azure renkleri | `ui/theme/AzureTokens.kt` | `lib/src/theme/secure_chat_theme.dart` | TEST VERIFIED |
| Başlık/yazı/etiket fontları | Space Grotesk / Inter / JetBrains Mono | Aynı üç aile `assets/fonts` ve theme içinde | TEST VERIFIED |
| Doodle zemin | `DoodleBackdrop.kt` içindeki tekrar eden 13 motif | `AzureDoodlePainter` tiled painter | DEVICE VERIFIED |
| Glass yüzey | `Glass.kt`, `GlassComponents.kt` | `AzureGlassPanel`, theme card/input yüzeyleri | DEVICE VERIFIED; varyant audit'i sürüyor |
| Radius/spacing | Azure token ve 12/16/24 dp ritmi | `AzureTokens` spacing/radius sabitleri | TEST VERIFIED |
| Ana sekmeler | `HorizontalPager`, 4 tab, nav senkron | `PageView` + raw gesture fallback + `NavigationBar` | DEVICE VERIFIED |
| Sayfa geçişi | 300 ms yatay Compose navigation | Android 300 ms slide; iOS Cupertino transition | TEST VERIFIED; iOS device bekliyor |
| Root back davranışı | Ana tablarda geri oku/ikinci root yok | Tek initial route + embedded AppBar politikası | DEVICE VERIFIED |

## Ekran parite matrisi

| Compose ekranı/akışı | Flutter dosyası | Durum | Kalan görsel/cihaz kanıtı |
|---|---|---|---|
| Splash | `features/onboarding/launch_flow.dart` | IMPLEMENTED / VISUAL AUDIT | Logo ölçüsü, pulse eğrisi ve kısa ekran fiziksel kayıtla kıyaslanacak. |
| Onboarding | `features/onboarding/launch_flow.dart` | DEVICE VERIFIED | CTA ve indicator ayri bottom safe-area tuketir; Samsung navigation alani, 320x568 ve %200 metin testi gecti. |
| Permission walkthrough | aynı dosya | TEST VERIFIED | Dort izin karti ve safe-area testli; temiz cihazdaki denied/permanently-denied sistem dialog turu bekliyor. |
| Phone + email OTP | `features/auth/auth_screen.dart` | DEVICE VERIFIED | Canli email OTP ile lokal negatif OTP/rate-limit/refresh/logout turu ve keyboard-safe layout gecti. |
| Conversations | `features/conversations/conversations_screen.dart` | DEVICE VERIFIED | Brand/top bar, disconnected state, animated global search, dört filtre, empty state ve dört işlemlik menü fiziksel cihazda; populated kart, global sonuç, arşiv/swipe/long-press durumları widget ve encrypted-DAO testlerinde doğrulandı. Gerçek cihaz veritabanı boş olduğu için populated görünümün ekran görüntüsü sonraki çoklu-cihaz turuna bırakıldı. |
| Calls history | `features/calls/call_history_screen.dart` | IMPLEMENTED / VISUAL AUDIT | Empty/populated/missed/group/video durumları ve Compose kart ölçüleri kıyaslanacak. |
| Contacts | `features/contacts/contacts_screen.dart` | DEVICE VERIFIED + DEPLOY BLOCKED | Search/group/error glass kartı cihazda doğrulandı. Populated kişi/avatar akışı için hardened directory deploy'u gerekli. |
| Settings | `features/settings/settings_screen.dart` | IMPLEMENTED / VISUAL AUDIT | Fiziksel swipe ile route doğrulandı; bölüm başlıkları, profil yüzeyi, toggle ve destructive sheet görsel turu bekliyor. |
| Chat | `features/chat/chat_screen.dart` ve part dosyaları | IMPLEMENTED / VISUAL AUDIT | Input yuzeyi ve ayri mic/send aksiyonu fiziksel klavye ile gecti; bubble/reply/reaction/status/typing tam fiziksel matrisi suruyor. |
| Chat info | `features/chat/chat_info_screen.dart` | IMPLEMENTED / VISUAL AUDIT | Media grid, lock/mute/timer ve destructive actions cihaz turu bekliyor. |
| Group create/add member/info | contacts dialog + `features/groups/group_info_screen.dart` | IMPLEMENTED / VISUAL AUDIT | Compose ayrı sayfa düzeniyle birebir flow ve 256 üyeli performans/scroll kanıtı bekliyor. |
| Media preview/viewer | `features/chat/media_preview_screen.dart`, `media_viewer_screen.dart` | IMPLEMENTED / VISUAL AUDIT | Swipe, view-once, video overlay ve iOS sandbox open/share görünümü bekliyor. |
| Call screen/PiP | `features/calls/call_screen.dart` | IMPLEMENTED / VISUAL AUDIT | Renderer, controls, reconnect/quality, PiP ve sistem çağrı yüzeyi fiziksel medya testi bekliyor. |
| Call readiness | `features/calls/call_readiness_screen.dart` | IMPLEMENTED / VISUAL AUDIT | Samsung/stock Android ayar dönüşleri ve iOS açıklama farkı cihaz turu bekliyor. |
| Scheduled messages | `features/scheduled/scheduled_messages_screen.dart` | IMPLEMENTED / VISUAL AUDIT | Empty/list/edit/cancel durumları bekliyor. |
| Bulk message | `features/bulk/bulk_message_screen.dart` | IMPLEMENTED / VISUAL AUDIT | Recipient selection/progress/failure summary görsel kıyası bekliyor. |
| Auto-download | `features/settings/auto_download_screen.dart` | IMPLEMENTED / VISUAL AUDIT | Wi‑Fi/mobile kart ve switch durumları bekliyor. |
| Storage usage | `features/settings/storage_usage_screen.dart` | IMPLEMENTED / VISUAL AUDIT | Usage bars, category cards ve cleanup confirmation bekliyor. |
| Export history | `features/export/export_history_screen.dart` | IMPLEMENTED / VISUAL AUDIT | Empty/list/share/failure durumları bekliyor. |
| Backup/restore | `features/backup/backup_screen.dart` | IMPLEMENTED / VISUAL AUDIT | Password strength, progress ve destructive restore açıklaması bekliyor. |

## Ortak bileşen matrisi

| Compose bileşeni | Flutter karşılığı | Durum |
|---|---|---|
| `AvatarGenerator` | `widgets/avatar.dart` | TEST VERIFIED |
| `GlassComponents` | `AzureGlassPanel` + themed cards/dialogs | DEVICE VERIFIED; `Material/Ink` ripple katmanı ve %200 metin testi tamam |
| `EmptyStateView` | ekran içi feature-local empty state'ler | MERGED / TEST VERIFIED; gereksiz ortak widget karari alinmadi |
| `Shimmer` | konuşma yükleme durumu | TEST VERIFIED |
| `ConnectionStatusIndicator` | clean UI adapter + signaling state sunumu | DEVICE VERIFIED (disconnected); diğer state renkleri testli |
| `SecureChatActionSheet` | feature-local modal bottom sheets | MERGED / TEST VERIFIED |
| `SecurityBadge` | onboarding/chat/contacts E2EE-shield yüzeyleri | MERGED / TEST VERIFIED |
| `MessageDateDivider` | chat date sections | IMPLEMENTED / VISUAL AUDIT |
| `TypingIndicator` | incoming typing state | IMPLEMENTED / VISUAL AUDIT |
| `OngoingCallBar` | `features/calls/ongoing_call_bar.dart` global route banner | TEST VERIFIED; 320x568/%200 semantics ve native open route testli |
| `CallControls` / `CallQualityIndicator` | calls widgets | IMPLEMENTED / VISUAL AUDIT |
| `VideoRenderer` / `PipCallContent` | `video_stream_view.dart`, call screen | DEVICE MEDIA VERIFIED; PiP tam gorsel turu acik |
| Haptic feedback | `widgets/haptics.dart` + chat/swipe/call controls | TEST VERIFIED |

## 2026-08-17 fiziksel Android kanıtı

- Cihaz: Samsung SM-S921B, Android 14 / API 34.
- Güncel debug APK cold start: 2.039 s.
- Azure dark doodle zemin, search, filter chips, four-destination navigation ve
  selected icon durumu görüntülendi.
- Rehberde canlı config 404, ham exception yerine gizlilik açıklamalı glass
  status kartı olarak görüntülendi; UI tree dört tabı ve seçili `Rehber 3/4`
  durumunu doğruladı.
- Fiziksel soldan swipe ile `Rehber 3/4` → `Ayarlar 4/4` geçişi doğrulandı.
- Root stack'teki gereksiz geri oku tek initial route ve embedded AppBar
  kuralıyla düzeltildi; yeni APK/UI ağacında ana sekmede geri oku olmadığı
  doğrulandı.
- Compose sohbet top bar'ı `elçim.` markası, disconnected göstergesi, global
  arama ve dört işlemlik menüyle yeniden kuruldu. Arama alanının focus/keyboard
  durumu ve `Yeni Sohbet`, `Yeni Grup`, `Toplu Mesaj`, `Planlı Mesajlar`
  menüsü fiziksel cihazda doğrulandı.
- Fiziksel sağdan-sola swipe sonrasında UI ağacı `Arama / Sekme 2 / 4` için
  `selected=true` verdi. Conversation kartı içindeki kısa Dismissible hareketin
  sekmeyi değiştirmediği widget testinde ayrıca sabitlendi.
- Cam kartlar `Material/Ink` hiyerarşisine alındı; ripple'ın dekorasyon altında
  kaybolması giderildi. İçeriğe göre büyüyen konuşma satırı 320x568 ve %200
  metin ölçeğinde overflow vermeden doğrulandı.
- Güncel Flutter kapısı: temiz analyze ve 209/209 test.
- Ekran yakalama yalnız debug manifest metadata'sıyla açıldı. Release
  `FLAG_SECURE` fail-closed kalır.

## 2026-08-18 fiziksel Android ve responsive kanıtı

- Onboarding ve izin akisinin bottom CTA/indicator yerlesimi system navigation
  inset'ine alindi; kucuk ekran ve `%200` metinde overflow testi gecti.
- Sohbet composer'i tek sikisik kapsayici yerine ayri input glass yuzeyi ve
  baglamsal mic/send butonu olarak kuruldu. Fiziksel klavye acikken input
  yaklasik `194 dp` kullanilabilir genislikte kaldi ve alt navigation'a tasmadi.
- View-once kontrolunun gorseli `34 dp`, dokunma/semantics hedefi `48 dp` olarak
  sabitlendi. Record/send gecisi input genisligini degistirmiyor.
- Global devam-eden-arama bandi connecting/active/reconnecting durumlarini
  route disinda gosterir; tap/native open cagrisi call route'una doner. Dar
  ekran ve buyuk metinde label yerine semantics'li chevron kalir.
- Android 14 sistem tarafinda incoming ve ongoing `CallStyle`, ayni bildirim
  kimligi, privacy-redacted metin ve `phoneCall` foreground service ile gercek
  cihazda dogrulandi.
- Kotlin Haptic yardimcisinin dort kullanimi Flutter'a tasindi: mesaj gonderme,
  mesaj uzun basma, conversation swipe `%50` esigi ve aktif cagri kontrolleri.
- Guncel hedef UI testleri haptic eklemesiyle gecti; tam paket sonucu
  `MIGRATION_TRACKER.md` icinde tek kaynak olarak tutulur.

## Sıradaki çalışma sırası

1. Chat: bubble/banners/status/reaction/reply/typing tam fiziksel görsel matrisi.
2. Calls ve media: empty/populated history, call controls, renderer, PiP ve
   quality/reconnect durumları.
3. Contacts/group: hardened server deploy sonrası populated discovery, ayrı
   create/add-member akışı ve group info.
4. Settings ve tüm alt ekranlar: section/card/toggle/dialog tutarlılığı.
5. Splash/onboarding/auth temiz-kurulum fiziksel turu.
6. Küçük telefon, tablet, %200 font, TalkBack semantics, Arabic RTL ve klavye
   snapshot testleri.
7. macOS erişildiğinde Xcode simulator + fiziksel iPhone safe-area, CallKit,
   Contacts, picker ve screenshot/app-switcher privacy turu.

Bu sıra, işlevsel veya güvenlik kaynaklı bir hata çıkarsa durdurulabilir; hata
önce fail-closed biçimde kapatılır, ardından görsel pariteye dönülür.
