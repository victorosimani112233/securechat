#!/usr/bin/env python3
"""Rust kripto cekirdeginin (native/securechat_crypto) mobil hedeflerde
gercekten linklenen bagimliliklarinin lisans metinlerini tek bir asset'e
toplar. Uygulamanin lisans ekrani (lib/main.dart) bu dosyayi okur.

Kullanim:
    python3 tool/generate_native_licenses.py

Cikti: assets/licenses/native_rust_crates.txt

Kapsam: yalnizca `normal` bagimliliklar, yalnizca mobil hedefler.
Proc-macro crate'leri derleme zamaninda calisir, binary'e girmez; dahil
edilmez. Lisans dosyasi bulunamayan crate varsa script hata verir; sessizce
eksik bildirim uretmez.
"""

from __future__ import annotations

import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CRATE_DIR = ROOT / "native" / "securechat_crypto"
OUTPUT = ROOT / "assets" / "licenses" / "native_rust_crates.txt"
TARGETS = [
    "aarch64-linux-android",
    "armv7-linux-androideabi",
    "x86_64-linux-android",
    "aarch64-apple-ios",
]
# Kendi kodumuz; ucuncu taraf bildirimi gerekmez.
SELF_CRATES = {"securechat_crypto"}
# Lisans dosyasini paketlemeyen crate'ler icin SPDX kimligine gore standart
# metin. Apache-2.0 metni lisansa ozgu degildir; mevcut asset yeniden kullanilir.
FALLBACK_TEXTS = {
    "Apache-2.0": ROOT / "assets" / "licenses" / "audioswitch_APACHE-2.0.txt",
}
LICENSE_FILE = re.compile(r"^(LICEN[CS]E|COPYING|UNLICENSE|NOTICE)", re.I)
SECTION_MARKER = "=== "


def shipped_crates() -> dict[tuple[str, str], tuple[str, pathlib.Path]]:
    crates: dict[tuple[str, str], tuple[str, pathlib.Path]] = {}
    for target in TARGETS:
        out = subprocess.run(
            [
                "cargo", "tree", "-e", "normal,no-proc-macro", "--target", target,
                "--prefix", "none", "--locked", "--offline",
                "-f", "{p}|{l}|{r}",
            ],
            cwd=CRATE_DIR, check=True, capture_output=True, text=True,
        ).stdout
        for line in out.splitlines():
            line = line.replace(" (*)", "")
            if "(proc-macro)" in line:
                continue
            spec, license_expr, _ = (line.split("|") + ["", ""])[:3]
            parts = spec.split()
            name, version = parts[0], parts[1].lstrip("v")
            if name in SELF_CRATES:
                continue
            crates[(name, version)] = (license_expr, registry_dir(name, version))
    return crates


def registry_dir(name: str, version: str) -> pathlib.Path:
    registry = pathlib.Path.home() / ".cargo" / "registry" / "src"
    for index in registry.iterdir():
        candidate = index / f"{name}-{version}"
        if candidate.is_dir():
            return candidate
    sys.exit(f"crate kaynagi bulunamadi: {name} {version} (once `cargo fetch`)")


def license_texts(license_expr: str, src: pathlib.Path) -> list[str]:
    files = sorted(p for p in src.iterdir() if p.is_file() and LICENSE_FILE.match(p.name))
    if not files:
        fallback = FALLBACK_TEXTS.get(license_expr)
        if fallback is None:
            sys.exit(f"lisans dosyasi yok: {src.name} ({license_expr})")
        return [fallback.read_text(encoding="utf-8").strip()]
    # "MIT OR ..." secimli crate'lerde MIT'i secip yalnizca onu ekleriz;
    # bildirim yukumlulugu tek lisans icin yeterli. "AND" iceren ifadelerde
    # tum lisanslar birlikte gecerli oldugu icin hicbiri elenmez.
    is_choice = " OR " in license_expr or "/" in license_expr
    if is_choice and " AND " not in license_expr and re.search(r"\bMIT\b", license_expr):
        mit = [p for p in files if re.search(r"MIT", p.name, re.I)]
        if mit:
            files = mit
    return [p.read_text(encoding="utf-8", errors="replace").strip() for p in files]


def main() -> None:
    crates = shipped_crates()
    sections = []
    for (name, version), (license_expr, src) in sorted(crates.items()):
        body = "\n\n".join(license_texts(license_expr, src))
        sections.append(f"{SECTION_MARKER}{name} {version} ({license_expr})\n{body}\n")
    OUTPUT.write_text("\n".join(sections), encoding="utf-8")
    print(f"{len(sections)} crate -> {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
