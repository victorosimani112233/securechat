#!/bin/bash
# Iki tag arasindaki commit'lerden CHANGELOG.md uretir.
# Kullanim:
#   ./scripts/generate-changelog.sh                 # son tag'den HEAD'e
#   ./scripts/generate-changelog.sh v1.0.40         # v1.0.40'tan HEAD'e
#   ./scripts/generate-changelog.sh v1.0.40 v1.0.50 # iki tag arasi
set -euo pipefail
cd "$(dirname "$0")/.."

FROM="${1:-}"
TO="${2:-HEAD}"

if [ -z "$FROM" ]; then
  FROM=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
  if [ -z "$FROM" ]; then
    echo "Hicbir tag bulunamadi; tum history kullanilacak." >&2
    FROM=$(git rev-list --max-parents=0 HEAD | head -1)
  fi
fi

echo "Range: $FROM..$TO"
echo ""

# Conventional commits'i kategorize et
declare -A CATEGORIES=(
  ["feat"]="✨ Yeni Özellikler"
  ["fix"]="🐛 Hata Düzeltmeleri"
  ["refactor"]="♻️  Yeniden Düzenleme"
  ["docs"]="📚 Dökümantasyon"
  ["test"]="🧪 Testler"
  ["build"]="🔧 Build / Dependency"
  ["chore"]="🧹 Diğer"
)

# Yeni section'i CHANGELOG.md'nin tepesine ekle
TMPFILE=$(mktemp)
{
  echo "## [$TO] — $(date +%Y-%m-%d)"
  echo ""

  for prefix in feat fix refactor docs test build chore; do
    section_header="${CATEGORIES[$prefix]}"
    # Conventional format: "prefix(scope): mesaj" veya "prefix: mesaj"
    commits=$(git log "$FROM..$TO" --pretty=format:"- %s ([%h](commit/%H))" --no-merges \
              | grep -iE "^- ${prefix}(\(|:)" || true)
    if [ -n "$commits" ]; then
      echo "### $section_header"
      echo "$commits"
      echo ""
    fi
  done

  # Conventional formata uymayan commit'ler
  other=$(git log "$FROM..$TO" --pretty=format:"- %s ([%h](commit/%H))" --no-merges \
          | grep -ivE "^- (feat|fix|refactor|docs|test|build|chore)(\(|:)" || true)
  if [ -n "$other" ]; then
    echo "### 📝 Sınıflandırılmamış"
    echo "$other"
    echo ""
  fi
} > "$TMPFILE"

# Mevcut CHANGELOG.md varsa yeni section'i tepesine ekle
if [ -f CHANGELOG.md ]; then
  # "# Changelog" başlığını koru, sonrasına yeni section ekle
  HEAD_LINES=$(grep -n "^## " CHANGELOG.md | head -1 | cut -d: -f1 || echo "")
  if [ -n "$HEAD_LINES" ]; then
    HEAD_LINES=$((HEAD_LINES - 1))
    head -n "$HEAD_LINES" CHANGELOG.md > CHANGELOG.tmp
    cat "$TMPFILE" >> CHANGELOG.tmp
    tail -n +$((HEAD_LINES + 1)) CHANGELOG.md >> CHANGELOG.tmp
    mv CHANGELOG.tmp CHANGELOG.md
  else
    # İlk kez section ekleniyor
    cat "$TMPFILE" >> CHANGELOG.md
  fi
else
  # Yeni CHANGELOG.md
  {
    echo "# Changelog"
    echo ""
    echo "Tüm dikkate değer değişiklikler bu dosyada listelenir."
    echo "Format: [Keep a Changelog](https://keepachangelog.com/tr/), [Semantic Versioning](https://semver.org/lang/tr/)."
    echo ""
    cat "$TMPFILE"
  } > CHANGELOG.md
fi

rm "$TMPFILE"
echo "✓ CHANGELOG.md güncellendi (range $FROM..$TO)."
