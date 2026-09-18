#!/usr/bin/env python3
"""Offline SBOM uretimi ve bilinen-zafiyet kapisi (P2-13).

Surum kaydinda hangi ucuncu parti baytlarin calistigina dair kanit yoktu.
`gradle/verification-metadata.xml` zaten her artefaktin sha256'sini tasir.
Bu betik o dosyayi CycloneDX 1.5 SBOM'una cevirir ve bilinen zafiyet
listesine karsi kontrol eder.

Manifest butun konfigurasyonlari kapsadigi icin test bagimliliklarini da
icerir. `--runtime` verildiginde yalniz release'e giren runtime classpath
listelenir; test-only bir bilesende cikan CVE release'i durdurmaz.

Ag erisimi gerektirmez: hem uretim hem kontrol yerel dosyalardan calisir.
Zafiyet listesinin (`deploy/known_vulnerable.txt`) guncel tutulmasi
operatorun isidir; agi olan bir makinede SCA beslemesinden yenilenir.

Kullanim:
    sbom.py --metadata gradle/verification-metadata.xml \
            --advisories deploy/known_vulnerable.txt \
            --runtime signaling-server/build/runtime-artifacts.txt \
            --runtime bot-api/build/runtime-artifacts.txt \
            --commit <40-hex> --output build/sbom.json
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

NAMESPACE = {"dv": "https://schema.gradle.org/dependency-verification"}
COMMIT_PATTERN = re.compile(r"^[0-9a-f]{40}$")
# group:name:version — version "*" tum surumleri kapsar.
ADVISORY_PATTERN = re.compile(
    r"^(?P<group>[^:\s]+):(?P<name>[^:\s]+):(?P<version>[^\s]+)(?:\s+(?P<note>.*))?$"
)


class SbomError(RuntimeError):
    pass


def parse_components(metadata_path: Path) -> list[dict]:
    """Dogrulama manifestindeki her bileseni okur.

    Yalniz `.jar` artefakti olan bilesenler SBOM'a girer: `.pom` ve `.module`
    dosyalari calisma zamaninda kod tasimaz.
    """
    root = ET.parse(metadata_path).getroot()
    components: list[dict] = []
    for component in root.iter(f"{{{NAMESPACE['dv']}}}component"):
        group = component.get("group")
        name = component.get("name")
        version = component.get("version")
        if not group or not name or not version:
            raise SbomError("Manifestte eksik bilesen koordinati var")
        jar_hash = None
        for artifact in component:
            artifact_name = artifact.get("name") or ""
            if not artifact_name.endswith(".jar"):
                continue
            for entry in artifact:
                if entry.tag.endswith("sha256"):
                    jar_hash = entry.get("value")
                    break
        if jar_hash is None:
            continue
        components.append(
            {
                "type": "library",
                "bom-ref": f"pkg:maven/{group}/{name}@{version}",
                "group": group,
                "name": name,
                "version": version,
                "purl": f"pkg:maven/{group}/{name}@{version}",
                "hashes": [{"alg": "SHA-256", "content": jar_hash}],
            }
        )
    if not components:
        raise SbomError("Manifestten hicbir bilesen okunamadi")
    components.sort(key=lambda item: item["bom-ref"])
    return components


def parse_advisories(path: Path) -> list[dict]:
    if not path.exists():
        raise SbomError(f"Zafiyet listesi yok: {path}")
    advisories: list[dict] = []
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        match = ADVISORY_PATTERN.match(line)
        if match is None:
            raise SbomError(f"{path}:{number} bicimi gecersiz")
        advisories.append(match.groupdict())
    return advisories


def find_matches(components: list[dict], advisories: list[dict]) -> list[str]:
    matches: list[str] = []
    for advisory in advisories:
        for component in components:
            if component["group"] != advisory["group"]:
                continue
            if component["name"] != advisory["name"]:
                continue
            if advisory["version"] not in ("*", component["version"]):
                continue
            note = advisory.get("note") or "bilinen zafiyet"
            matches.append(
                f"{component['group']}:{component['name']}:{component['version']} — {note}"
            )
    return matches


def parse_runtime(paths: list[Path]) -> set[str]:
    """Release'e giren `group:name:version` kumesi."""
    shipped: set[str] = set()
    for path in paths:
        if not path.exists():
            raise SbomError(f"Runtime listesi yok: {path}")
        for raw in path.read_text(encoding="utf-8").splitlines():
            line = raw.strip()
            if line and not line.startswith("#"):
                shipped.add(line)
    if not shipped:
        raise SbomError("Runtime listesi bos")
    return shipped


def filter_shipped(components: list[dict], shipped: set[str]) -> list[dict]:
    """Test-only bilesenler SBOM'a girmez.

    Dogrulama manifesti butun konfigurasyonlari kapsar; calisan artefakti
    anlatan belge yalniz dagitilan bilesenleri icermelidir. Aksi halde test
    bagimliliginda cikan bir CVE release'i gereksiz yere durdururdu.
    """
    filtered = [
        component
        for component in components
        if f"{component['group']}:{component['name']}:{component['version']}" in shipped
    ]
    if not filtered:
        raise SbomError("Runtime filtresi hicbir bileseni birakmadi")
    return filtered


def build_document(components: list[dict], commit: str) -> dict:
    """CycloneDX 1.5 belgesi.

    `serialNumber` commit'ten deterministik turer: ayni commit her zaman ayni
    SBOM'u uretir, dolayisiyla yayinlanan belge yeniden uretilebilir.
    """
    digest = hashlib.sha256(f"securechat-server-sbom:{commit}".encode()).hexdigest()
    serial = (
        f"urn:uuid:{digest[0:8]}-{digest[8:12]}-{digest[12:16]}-"
        f"{digest[16:20]}-{digest[20:32]}"
    )
    return {
        "bomFormat": "CycloneDX",
        "specVersion": "1.5",
        "serialNumber": serial,
        "version": 1,
        "metadata": {
            "component": {
                "type": "application",
                "bom-ref": f"securechat-server@{commit}",
                "name": "securechat-server",
                "version": commit,
            },
        },
        "components": components,
    }


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Offline SBOM + SCA gate")
    parser.add_argument("--metadata", required=True, type=Path)
    parser.add_argument("--advisories", required=True, type=Path)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument(
        "--runtime",
        type=Path,
        action="append",
        default=None,
        help="Yalniz bu dosyalardaki group:name:version bilesenlerini dahil et "
             "(release'e giren runtime classpath). Verilmezse manifestin tamami.",
    )
    arguments = parser.parse_args(argv)

    if not COMMIT_PATTERN.match(arguments.commit):
        print("commit must be a full 40-hex id", file=sys.stderr)
        return 2

    try:
        components = parse_components(arguments.metadata)
        advisories = parse_advisories(arguments.advisories)
        if arguments.runtime:
            shipped = parse_runtime(arguments.runtime)
            components = filter_shipped(components, shipped)
    except (SbomError, ET.ParseError, OSError) as error:
        print(f"SBOM uretilemedi: {error}", file=sys.stderr)
        return 2

    document = build_document(components, arguments.commit)
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    # Deterministik cikti: ayni girdi ayni bayti uretir.
    serialized = json.dumps(document, indent=2, sort_keys=True, ensure_ascii=False)
    arguments.output.write_text(serialized + "\n", encoding="utf-8")

    matches = find_matches(components, advisories)
    digest = hashlib.sha256(serialized.encode("utf-8")).hexdigest()
    print(f"SBOM: {arguments.output} ({len(components)} bilesen) sha256={digest}")
    if matches:
        print("Bilinen zafiyetli bagimlilik bulundu:", file=sys.stderr)
        for match in matches:
            print(f"  - {match}", file=sys.stderr)
        return 1
    print("SCA gate: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
