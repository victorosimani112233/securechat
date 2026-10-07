# 07 — 432 çevrilmemiş string

**Bağımlılık:** yok · **Tahmin:** 1 gün

## Amaç

Beyan edilen dil desteğiyle gerçek çeviri durumunu uyumlu hale getirmek.

## Mevcut durum

Build çıktısı her seferinde uyarıyor:

```
"ar": 432 untranslated message(s).
"de": 432 untranslated message(s).
```

`ios/Runner/Info.plist` içindeki `CFBundleLocalizations` dört dil beyan
ediyor: `tr`, `en`, `de`, `ar`. Arapça ve Almanca'nın **tamamı** eksik.
Beyan edilen dilde boş/İngilizce fallback göstermek mağaza kalite reddi
riski.

## İki seçenek

**A — dilleri beyandan çıkar (1 saat).** `CFBundleLocalizations`'ı
`tr` + `en` ile sınırla, `lib/l10n` altındaki `app_ar.arb` ve `app_de.arb`
dosyalarını kaldır, `l10n.yaml` ve `app_localizations*.dart` üretimini
güncelle. Risk sıfırlanır.

**B — çevirileri tamamla (1 gün + gözden geçirme).** 432 × 2 string.
Makine çevirisi + insan gözden geçirmesi. Arapça ayrıca **RTL** demek;
proje RTL'i destekliyor (`supportsRtl`, `MaterialApp` yönü) ama 432 stringin
RTL düzende test edilmesi gerekir.

Öneri: şimdilik **A**, sonra talep gelirse B. Mağazaya dört dil beyan edip
ikisini boş bırakmaktansa iki dilde iyi olmak yeterli.

## Doğrulama

```bash
flutter build apk --release --target-platform=android-arm64 2>&1 | grep untranslated
# cikti olmamali
dart tool/audit_ios_readiness.dart   # PASS kalmali
```

`test/accessibility_responsive_test.dart` ve l10n ile ilgili testlerin
geçmeye devam ettiğini doğrula.

---

## Ortak zemin

Önce [INDEX.md](INDEX.md) oku — mimari kararlar ve herkesi ilgilendiren
tuzaklar orada. Özellikle: vodozemac base64'ü padding'siz üretir, one-time
key'ler Account pickle'ının içinde durur, her encrypt/decrypt sonrası
yeniden pickle gerekir, ve Famedly'nin AGPL Dart binding'ine bakılmaz.

## Bitirme ölçütü

```bash
cd /home/user497/securechat/flutter_securechat
export PATH="/home/user497/flutter/bin:$PATH"
flutter analyze --no-pub     # temiz olmali
flutter test --no-pub        # tamami gecmeli
```
