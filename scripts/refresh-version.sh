#!/bin/bash
# Online makinede son git commit'inden VERSION dosyasini guncelle.
# USB ile offline makineye projeyi kopyalamadan ONCE bu script'i calistir.
# Olusan VERSION dosyasini repo'ya commit etmek tavsiye edilir (offline tutarlilik).
set -euo pipefail
cd "$(dirname "$0")/.."
VC=$(git rev-list --count HEAD)
SHA=$(git rev-parse --short HEAD)
cat > VERSION <<INNER
# Bu dosya online makinede ./scripts/refresh-version.sh ile guncellenir.
# Offline build (git veya .git yok) bu dosyadan okur.
# Manuel override: ./gradlew assembleDevRelease -PversionCode=NN -PversionName=...
versionCode=$VC
versionName=1.0.$VC-$SHA
INNER
echo "VERSION guncellendi: versionCode=$VC versionName=1.0.$VC-$SHA"
