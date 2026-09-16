#!/usr/bin/env bash
# Ucretsiz Apple ID ("Personal Team") ile cihaza kurulum icin YEREL ayar.
#
# Iki sey gerekiyor ve ikisi de depodaki degerlerle celisiyor:
#
# 1. Push yetkisi kaldirilmali. Xcode'un kendi hata metni:
#      "Personal development teams do not support the Push Notifications
#       capability."
#    Ucretsiz hesap `aps-environment` saglayamiyor; entitlement dosyasinda
#    durdugu surece profil URETILEMIYOR ve imzalama hic baslamiyor.
#
# 2. Bundle ID benzersiz olmali. `com.securechat.app` baska bir takima
#    kayitli; kisisel takim onu alamaz.
#
# Bu degisiklikler YALNIZ SENIN MAKINENDE kalmali — COMMIT ETME. `git pull`
# her seferinde depodaki degerleri geri getirir, betigi tekrar calistir.
#
# Kullanim:
#   ./tool/ios_personal_signing.sh grj        # uygula (ek: .grj)
#   ./tool/ios_personal_signing.sh --restore  # depodaki haline dondur
set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_directory="$(cd "$script_directory/.." && pwd)"
cd "$project_directory"

readonly entitlements="ios/Runner/Runner.entitlements"
readonly project_file="ios/Runner.xcodeproj/project.pbxproj"
readonly base_id="com.securechat.app"

if [[ "${1:-}" == "--restore" ]]; then
  git checkout -- "$entitlements" "$project_file"
  echo "Depodaki haline donduruldu."
  echo "UYARI: Xcode'un yazdigi DEVELOPMENT_TEAM ayari da silindi;"
  echo "       tekrar kurulum yapacaksan Xcode'da takimi yeniden sec."
  exit 0
fi

suffix="${1:-}"
[[ -n "$suffix" ]] || {
  echo "Kullanim: $0 <ek>        ornek: $0 grj" >&2
  echo "          $0 --restore" >&2
  exit 2
}
[[ "$suffix" =~ ^[A-Za-z0-9]+$ ]] || {
  echo "Ek yalniz harf ve rakam icerebilir: $suffix" >&2
  exit 2
}

# --- 1. Push yetkisini kaldir ------------------------------------------------
# Dosya tamamen bosaltilmiyor, gecerli bir bos plist yaziliyor: pbxproj
# CODE_SIGN_ENTITLEMENTS ile bu dosyayi isaret ettigi icin var olmasi gerek.
cat > "$entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
</dict>
</plist>
PLIST

# --- 2. Bundle ID'lere ek koy ------------------------------------------------
# Yalniz EKSIZ degerler eslesiyor; betik iki kez calistirilirsa ikinci kosum
# hicbir seyi degistirmez.
temporary="$(mktemp)"
sed \
  -e "s/PRODUCT_BUNDLE_IDENTIFIER = $base_id;/PRODUCT_BUNDLE_IDENTIFIER = $base_id.$suffix;/g" \
  -e "s/PRODUCT_BUNDLE_IDENTIFIER = $base_id\.RunnerTests;/PRODUCT_BUNDLE_IDENTIFIER = $base_id.$suffix.RunnerTests;/g" \
  "$project_file" > "$temporary"
mv "$temporary" "$project_file"

applied="$(grep -c "PRODUCT_BUNDLE_IDENTIFIER = $base_id\.$suffix" "$project_file" || true)"
if [[ "$applied" != "6" ]]; then
  echo "Beklenen 6 bundle ID satiri yerine $applied bulundu." >&2
  echo "Baska bir ek zaten uygulanmis olabilir: --restore ile sifirlayin." >&2
  exit 1
fi

cat <<INFO

Hazir.
  bundle ID : $base_id.$suffix   (RunnerTests dahil 6 satir)
  push      : entitlement kaldirildi

Xcode aciksa KAPAT ve tekrar ac; yoksa eski degerleri hafizada tutar:

  open ios/Runner.xcworkspace

Signing & Capabilities sekmesinde:
  - Team = Personal Team secili olmali
  - "Push Notifications" kutusu duruyorsa x ile kaldirin
    (durdugu surece Xcode entitlement'i dosyaya geri yazar)

Sonra cihaza kurun. Bildirimler CALISMAZ ve imza 7 gunde duser;
ucretsiz hesabin siniri.

Bu degisiklikleri COMMIT ETMEYIN:
  git status --short $entitlements $project_file
INFO
