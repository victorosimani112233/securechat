#!/usr/bin/env bash
set -euo pipefail

tool_dir="${CRYPTO_AUDIT_TOOL_DIR:?Set CRYPTO_AUDIT_TOOL_DIR to the verified CogniCrypt directory}"
scanner="$tool_dir/HeadlessJavaScanner-5.0.1-jar-with-dependencies.jar"
rules="$tool_dir/JavaCryptographicArchitecture.zip"

test "$(sha256sum "$scanner" | awk '{print $1}')" = \
  177cefb7939c558837051f96705e240df9c43b44a037e4bf8e0da266f406a1b9
test "$(sha256sum "$rules" | awk '{print $1}')" = \
  d6dce41385627bdcb7c57a9a578636f7a945b327c52ed1433e5733981e6333ff

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
./gradlew :signaling-server:jar :bot-api:jar --offline --no-daemon

report_root="$repo_root/build/reports/cognicrypt"
for module in signaling-server bot-api; do
  mkdir -p "$report_root/$module"
  java -jar "$scanner" \
    --appPath="$repo_root/$module/build/libs/$module.jar" \
    --rulesDir="$rules" \
    --reportFormat=SARIF,CSV_SUMMARY \
    --reportPath="$report_root/$module" \
    --timeout=10000
done

echo "CogniCrypt advisory reports: $report_root"
