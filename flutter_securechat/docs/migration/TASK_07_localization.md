# 07 — Çevrilmemiş stringler

**Durum: Almanca TAMAM · Arapça ertelendi** · **Bağımlılık:** yok

## Yapıldı

`de` tamamlandı: 432 eksik anahtar çevrildi, toplam **640/640**. Mevcut 208
çevirinin register'ına uyuldu — gayri resmî "du", `Fingerabdruck`,
`Lesebestätigungen`, `Sitzung`. Birleştirme sırasında her ICU placeholder'ı
(`{arg1}`, `{chatName}`, `{duration}`, `{sender}`) İngilizce kaynakla
karşılaştırılarak doğrulandı; `\n` ve `\"` kaçışları korundu.

## Arapça — bilinçli erteleme

`ar` 208/640'ta kaldı. Kullanıcı önceliklendirmedi.

Dili tamamen kaldırmak ilk bakışta kolay görünüyor ama değil:
`AppLanguagePreference.ar` enum'u Arapça'yı ayarlardaki dil seçicisinde
kullanıcı seçeneği yapıyor (`lib/src/app.dart:351`), ve beş test dosyası
`'ar'`'a referans veriyor (`service_strings_test`, `recovery_screen_test`,
`settings_module_test`, `full_screen_stress_audit_test`,
`chat_bubble_padding_layout_test`). Kozmetik bir hedef için enum + ayarlar
UI + testlere dokunmak gereksiz risk.

Kısmi çevirinin maliyeti yalnızca şu: Arapça seçen kullanıcı 432 stringde
İngilizce görüyor (Flutter template'e düşüyor). Mağaza tarafında bu bir
kalite riski ama ret gerekçesi olacak kadar değil — dil beyan edilmiş ve
çalışıyor, sadece eksik.

## Kalan iki seçenek

**A — tamamla.** 432 Arapça çeviri. Arapça RTL; proje RTL destekliyor ama
432 stringin RTL düzende gözden geçirilmesi gerekir.

**B — kaldır.** `lib/l10n/app_ar.arb`'ı `lib/l10n/` dışına taşı,
`AppLanguagePreference`'tan `ar`'ı çıkar, ayarlardaki seçiciyi güncelle, beş
test dosyasını uyarla, `Info.plist`'teki `CFBundleLocalizations`'tan `ar`'ı
sil.

## CI durumu

`flutter-ci.yml` içindeki çevrilmemiş-string kapısı `ar`'ı **gerekçesiyle
muaf tutuyor**; başka bir dilde eksik çıkarsa iş düşer. A veya B yapılınca
muafiyet kaldırılacak.

## Doğrulama

```bash
flutter gen-l10n --untranslated-messages-file=untranslated.json
# yalnizca "ar" gorunmeli, "de" gorunmemeli
flutter analyze --no-pub
flutter test --no-pub
```
